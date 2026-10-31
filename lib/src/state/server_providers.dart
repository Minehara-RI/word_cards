import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/server_ports.dart';
import '../data/ai/card_completion.dart';
import '../data/api/anki_connect_service.dart';
import '../data/api/anki_connect_server.dart';
import '../data/sync/sync_client.dart';
import '../data/sync/sync_server.dart';
import '../data/sync/sync_service.dart';
import '../data/sync/sync_url.dart';
import '../domain/models/app_settings.dart';
import '../domain/models/sync_snapshot.dart';
import '../domain/models/word_card.dart';
import '../domain/repositories.dart';
import 'providers.dart';

/// 同步状态的存储（设备 id + 删除记录）。main() 里换成 Anki 实现。
final syncRepositoryProvider = Provider<SyncRepository>(
  (ref) => throw UnimplementedError(
    'syncRepositoryProvider 需要在 ProviderScope 里 override',
  ),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(
    cards: ref.watch(cardRepositoryProvider),
    decks: ref.watch(deckRepositoryProvider),
    records: ref.watch(answerRecordRepositoryProvider),
    sync: ref.watch(syncRepositoryProvider),
  ),
);

final syncClientProvider = Provider<SyncClient>((ref) {
  final SyncClient client = SyncClient();
  ref.onDispose(client.close);
  return client;
});

/// 外部写入（AnkiConnect 兼容）的服务。只有真的开了监听才会被创建。
final ankiConnectServiceProvider = Provider<AnkiConnectService>((ref) {
  final collection = ref.watch(ankiCollectionProvider);
  if (collection == null) {
    throw StateError('没有打开的 Anki 库，外部写入服务不可用');
  }
  return AnkiConnectService(
    cards: ref.watch(cardRepositoryProvider),
    decks: ref.watch(deckRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    collection: collection,
    onCardAdded: (WordCard card) => _completeInboundCard(ref, card),
  );
});

/// 外部写进来、干扰项不够时的 AI 补全。
///
/// 失败一律安静吞掉：加卡已经成功了，补全只是个加分项，
/// 不能让用户看到一张卡「加了一半」。
Future<void> _completeInboundCard(Ref ref, WordCard card) async {
  try {
    final AppSettings settings = await ref.read(settingsRepositoryProvider).load();
    if (!settings.hasApiCredentials) return;
    final CardCompletionOutcome outcome =
        await ref.read(cardCompletionServiceProvider).complete(
              word: card.word,
              definition: card.definition,
              language: card.language,
              settings: settings,
              existingDistractors: card.distractors,
            );
    final CardCompletion? completion = outcome.completion;
    if (completion == null) return;

    final WordCard? current =
        await ref.read(cardRepositoryProvider).getById(card.id);
    if (current == null) return;

    WordCard next = current;
    if (completion.phonetic != null && (next.phonetic ?? '').isEmpty) {
      next = next.copyWith(phonetic: completion.phonetic);
    }
    if (completion.partOfSpeech != null && (next.partOfSpeech ?? '').isEmpty) {
      next = next.copyWith(partOfSpeech: completion.partOfSpeech);
    }
    if (completion.example != null && (next.example ?? '').isEmpty) {
      next = next.copyWith(example: completion.example);
    }
    if (completion.note != null && (next.note ?? '').isEmpty) {
      next = next.copyWith(note: completion.note);
    }
    final List<String> distractors = <String>[...next.distractors];
    for (final String item in completion.distractors) {
      if (distractors.length >= WordCard.targetDistractorCount) break;
      if (item == next.definition || distractors.contains(item)) continue;
      distractors.add(item);
    }
    final List<String> tags = <String>[...next.tags];
    if (distractors.length >= WordCard.targetDistractorCount) {
      tags.remove(WordCard.incompleteTag);
    }
    next = next.copyWith(
      distractors: distractors,
      tags: tags,
      updatedAt: DateTime.now(),
    );
    await ref.read(cardRepositoryProvider).upsert(next);
    await ref.read(settingsRepositoryProvider).save(
          settings.addApiUsage(
            calls: 1,
            promptTokens: outcome.promptTokens,
            completionTokens: outcome.completionTokens,
          ),
        );
  } on Object {
    // 补全失败不影响已经写进去的卡片。
  }
}

// ------------------------------------------------------------------ 监听状态

/// 一个监听端点的运行状态。
class ServerRuntime {
  const ServerRuntime({
    this.running = false,
    this.starting = false,
    this.port,
    this.error,
  });

  final bool running;
  final bool starting;
  final int? port;
  final String? error;

  static const ServerRuntime stopped = ServerRuntime();

  ServerRuntime copyWith({bool? running, bool? starting, int? port, String? error}) =>
      ServerRuntime(
        running: running ?? this.running,
        starting: starting ?? this.starting,
        port: port ?? this.port,
        error: error,
      );

  String describe() {
    if (error != null) return error!;
    if (starting) return '正在监听…';
    if (running) return '正在监听端口 ${port ?? 0}';
    return '没有在监听';
  }
}

/// AnkiConnect 兼容服务。跟着设置自动开关，改端口会重启。
class AnkiConnectServerController extends Notifier<ServerRuntime> {
  AnkiConnectHandle? _handle;
  String _signature = '';
  int _token = 0;

  @override
  ServerRuntime build() {
    // 用 listen 而不是 watch：watch 会让设置一变就重建这个 provider，
    // 而重建会先跑 onDispose（关掉监听）—— 用户在设置页拖一下字号、
    // 或者外部写词后记一次用量，都会顺手把端口重启一遍。
    // 这里只在「真的被销毁」时关，配置变化由 _apply 自己比较签名。
    ref.onDispose(() {
      _token++;
      unawaited(_close());
    });
    ref.listen<AppSettings>(
      currentSettingsProvider,
      (AppSettings? previous, AppSettings next) {
        unawaited(_apply(++_token, next));
      },
      fireImmediately: true,
    );
    return ServerRuntime.stopped;
  }

  Future<void> _apply(int token, AppSettings settings) async {
    final String signature = [
      settings.apiServerEnabled,
      settings.apiServerAllowLan,
    ].join('|');

    if (!settings.apiServerEnabled) {
      await _close();
      if (token == _token) state = ServerRuntime.stopped;
      return;
    }
    if (_handle != null && signature == _signature) return;

    final AnkiConnectService service = ref.read(ankiConnectServiceProvider);
    final SettingsRepository repository = ref.read(settingsRepositoryProvider);
    await _close();
    if (token != _token) return;

    try {
      final AnkiConnectHandle handle = await startAnkiConnectServer(
        service: service,
        settings: repository,
        port: kApiServerPort,
        allowLan: settings.apiServerAllowLan,
      );
      if (token != _token) {
        await handle.close();
        return;
      }
      _handle = handle;
      _signature = signature;
      state = ServerRuntime(running: true, port: handle.port);
    } on SocketException catch (error) {
      if (token != _token) return;
      state = ServerRuntime(error: _explain(error, kApiServerPort));
    } on Object catch (error) {
      if (token != _token) return;
      state = ServerRuntime(error: '外部写入没开起来：$error');
    }
  }

  Future<void> _close() async {
    final AnkiConnectHandle? handle = _handle;
    _handle = null;
    if (handle != null) await handle.close();
  }

  static String _explain(SocketException error, int port) {
    final String text = error.toString();
    if (text.contains('10048') ||
        text.contains('98') ||
        text.contains('address already in use')) {
      return '端口 $port 被占用了：先关掉占着它的程序（Anki 插件的默认端口是 8765，'
          '本应用固定用 8766，一般不会撞）。';
    }
    if (text.contains('10013') || text.contains('permission')) {
      return '系统不允许监听端口 $port，换一个 1024 以上的端口试试。';
    }
    return '监听端口 $port 失败：$error';
  }
}

final ankiConnectServerProvider =
    NotifierProvider<AnkiConnectServerController, ServerRuntime>(
  AnkiConnectServerController.new,
);

/// 设备同步服务。跟着设置自动开关。
class SyncServerController extends Notifier<ServerRuntime> {
  SyncServerHandle? _handle;
  String _signature = '';
  int _token = 0;

  @override
  ServerRuntime build() {
    // 同 AnkiConnectServerController：listen 而不是 watch，避免设置一变就重启端口。
    ref.onDispose(() {
      _token++;
      unawaited(_close());
    });
    ref.listen<AppSettings>(
      currentSettingsProvider,
      (AppSettings? previous, AppSettings next) {
        unawaited(_apply(++_token, next));
      },
      fireImmediately: true,
    );
    return ServerRuntime.stopped;
  }

  Future<void> _apply(int token, AppSettings settings) async {
    final String signature = [
      settings.syncEnabled,
      settings.syncPin ?? '',
      settings.syncDeviceName ?? '',
    ].join('|');

    if (!settings.syncEnabled) {
      await _close();
      if (token == _token) state = ServerRuntime.stopped;
      return;
    }
    if (_handle != null && signature == _signature) return;

    final SyncService service = ref.read(syncServiceProvider);
    final String deviceName = deviceDisplayName(settings);
    final String? pin = settings.syncPin;
    await _close();
    if (token != _token) return;

    try {
      final SyncServerHandle handle = await startSyncServer(
        service: service,
        port: kSyncPort,
        deviceName: () => deviceName,
        pin: () => pin,
      );
      if (token != _token) {
        await handle.close();
        return;
      }
      _handle = handle;
      _signature = signature;
      state = ServerRuntime(running: true, port: handle.port);
    } on SocketException catch (error) {
      if (token != _token) return;
      state = ServerRuntime(
        error: AnkiConnectServerController._explain(error, kSyncPort),
      );
    } on Object catch (error) {
      if (token != _token) return;
      state = ServerRuntime(error: '同步服务没开起来：$error');
    }
  }

  Future<void> _close() async {
    final SyncServerHandle? handle = _handle;
    _handle = null;
    if (handle != null) await handle.close();
  }
}

final syncServerProvider =
    NotifierProvider<SyncServerController, ServerRuntime>(
  SyncServerController.new,
);

/// 设备名。没填就用一个中性的默认值（不在这里判断平台）。
String deviceDisplayName(AppSettings settings) {
  final String? name = settings.syncDeviceName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return '单词卡片';
}

// ------------------------------------------------------------------ 一次同步

enum SyncStage { idle, connecting, exchanging, applying, done, failed }

class SyncRunState {
  const SyncRunState({
    this.stage = SyncStage.idle,
    this.message = '',
    this.peerName,
    this.applied,
  });

  final SyncStage stage;
  final String message;
  final String? peerName;
  final SyncApplyResult? applied;

  bool get busy =>
      stage == SyncStage.connecting ||
      stage == SyncStage.exchanging ||
      stage == SyncStage.applying;

  SyncRunState copyWith({
    SyncStage? stage,
    String? message,
    String? peerName,
    SyncApplyResult? applied,
  }) =>
      SyncRunState(
        stage: stage ?? this.stage,
        message: message ?? this.message,
        peerName: peerName ?? this.peerName,
        applied: applied ?? this.applied,
      );
}

/// 手动发起一次同步：连对方 → 交换整份数据 → 落库。
///
/// 只有「主动推」这一个方向：对方的监听可能没开（手机上更常见），
/// 但本机发起时总能连上对方的同步端口。
class SyncRunner extends Notifier<SyncRunState> {
  @override
  SyncRunState build() => const SyncRunState();

  Future<void> run(String address, {String? pin}) async {
    if (state.busy) return;
    final String? base = normalizeSyncBaseUrl(address);
    if (base == null) {
      state = SyncRunState(
        stage: SyncStage.failed,
        message: '地址看起来不对。填对方的 IP 就行，例如 192.168.1.5（端口固定是 $kSyncPort）。',
      );
      return;
    }

    state = const SyncRunState(stage: SyncStage.connecting, message: '正在找对方…');
    try {
      final SyncClient client = ref.read(syncClientProvider);
      final SyncPeerInfo peer = await client.ping(base);
      if (peer.protocol != SyncSnapshot.protocol) {
        throw const SyncFailure('对方的版本对不上，先把两台设备更新到同一个版本');
      }
      final String? myPin =
          (pin ?? ref.read(currentSettingsProvider).syncPin)?.trim();
      if (peer.requiresPin && (myPin == null || myPin.isEmpty)) {
        throw const SyncFailure('对方设了同步口令，先在下面填上和对方一样的口令');
      }

      state = SyncRunState(
        stage: SyncStage.exchanging,
        message: '正在和「${peer.deviceName}」交换数据…',
        peerName: peer.deviceName,
      );
      final SyncService service = ref.read(syncServiceProvider);
      final SyncSnapshot mine = await service.buildSnapshot(
        deviceName: deviceDisplayName(ref.read(currentSettingsProvider)),
      );
      final SyncSnapshot merged =
          await client.exchange(base, mine, pin: myPin);

      if (ref.mounted) {
        state = SyncRunState(
          stage: SyncStage.applying,
          message: '正在写入合并结果…',
          peerName: peer.deviceName,
        );
      }
      final SyncApplyResult applied = await service.applyMerged(merged);

      final AppSettings settings = ref.read(currentSettingsProvider);
      await ref.read(settingsRepositoryProvider).save(
            settings.copyWith(syncLastAt: DateTime.now().millisecondsSinceEpoch),
          );
      ref.invalidate(statsProvider);

      if (!ref.mounted) return;
      state = SyncRunState(
        stage: SyncStage.done,
        peerName: peer.deviceName,
        applied: applied,
        message: '和「${peer.deviceName}」同步完成：${applied.summary}',
      );
    } on SyncFailure catch (failure) {
      if (!ref.mounted) return;
      state = SyncRunState(stage: SyncStage.failed, message: failure.message);
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = SyncRunState(
        stage: SyncStage.failed,
        message: '同步失败：$error',
      );
    }
  }
}

final syncRunnerProvider =
    NotifierProvider<SyncRunner, SyncRunState>(SyncRunner.new);
