import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ai/api_client.dart';
import '../data/ai/generation_service.dart';
import '../data/anki/anki_collection.dart';
import '../data/audio/beep_player.dart';
import '../data/export/answer_sheet_service.dart';
import '../data/export/export_service.dart';
import '../data/import/import_service.dart';
import '../domain/models/answer_record.dart';
import '../domain/models/app_settings.dart';
import '../domain/models/deck.dart';
import '../domain/models/word_card.dart';
import '../domain/repositories.dart';
import '../logic/fsrs.dart';
import '../logic/projection_pool.dart';
import '../logic/stats.dart';
import '../logic/stats_breakdown.dart';
import '../logic/study_pool.dart';

// ------------------------------------------------------------------ 仓库装配
//
// 具体实现（sembast / 以后换别的）在 main() 里 override 进来，
// 这样测试可以直接塞内存库或假仓库。

final cardRepositoryProvider = Provider<CardRepository>(
  (ref) => throw UnimplementedError('cardRepositoryProvider 需要在 ProviderScope 里 override'),
);

final answerRecordRepositoryProvider = Provider<AnswerRecordRepository>(
  (ref) => throw UnimplementedError('answerRecordRepositoryProvider 需要在 ProviderScope 里 override'),
);

final deckRepositoryProvider = Provider<DeckRepository>(
  (ref) => throw UnimplementedError('deckRepositoryProvider 需要在 ProviderScope 里 override'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('settingsRepositoryProvider 需要在 ProviderScope 里 override'),
);

final importServiceProvider = Provider<ImportService>(
  (ref) => ImportService(
    cards: ref.watch(cardRepositoryProvider),
    decks: ref.watch(deckRepositoryProvider),
  ),
);

// ------------------------------------------------------------------ 模式 B：API 直连

/// 生成缓存的存储；main() 里换成 Anki 实现，测试里换成内存实现。
final apiCacheRepositoryProvider = Provider<ApiCacheRepository>(
  (ref) => throw UnimplementedError(
    'apiCacheRepositoryProvider 需要在 ProviderScope 里 override',
  ),
);

/// HTTP 客户端：整个应用共用一个连接池。
final aiApiClientProvider = Provider<AiApiClient>((ref) {
  final HttpAiApiClient client = HttpAiApiClient();
  ref.onDispose(client.close);
  return client;
});

/// 模式 B 的编排（Prompt → 缓存 → 请求 → 解析 → 写缓存）。
final generationServiceProvider = Provider<GenerationService>(
  (ref) => GenerationService(
    client: ref.watch(aiApiClientProvider),
    cache: ref.watch(apiCacheRepositoryProvider),
  ),
);

// ------------------------------------------------------------------ 配置

final settingsProvider = StreamProvider<AppSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).watch(),
);

/// 已经拿到值（或还没拿到时用默认值）的配置，UI 直接用这个。
final currentSettingsProvider = Provider<AppSettings>((ref) {
  return ref.watch(settingsProvider).value ?? const AppSettings();
});

// ------------------------------------------------------------------ 词库

final decksProvider = StreamProvider<List<Deck>>(
  (ref) => ref.watch(deckRepositoryProvider).watch(),
);

/// 当前卡组；null 表示「全部词库」。
///
/// 这是全应用唯一的「当前卡组」：新加入的词都进它，
/// 只有用户主动更换卡组或新建卡组时它才会变，并且会写回设置里（下次打开还是它）。
class SelectedDeck extends Notifier<String?> {
  @override
  String? build() {
    final AppSettings settings = ref.watch(currentSettingsProvider);
    final String? id = settings.activeDeckId;
    if (id == null) return null;
    final List<Deck>? decks = ref.watch(decksProvider).value;
    if (decks != null && decks.isNotEmpty && !decks.any((Deck deck) => deck.id == id)) {
      // 卡组被删掉了，退回「全部词库」。
      return null;
    }
    return id;
  }

  /// 切换当前卡组。
  void select(String? deckId) {
    state = deckId;
    _persist(deckId);
  }

  Future<void> _persist(String? deckId) async {
    final AppSettings settings = ref.read(currentSettingsProvider);
    await ref.read(settingsRepositoryProvider).save(
      settings.copyWith(
        activeDeckId: deckId,
        clearActiveDeckId: deckId == null,
      ),
    );
  }
}

final selectedDeckProvider =
    NotifierProvider<SelectedDeck, String?>(SelectedDeck.new);

/// 新卡片该进哪个卡组：当前卡组；选了「全部词库」时进默认卡组。
final activeDeckIdProvider = Provider<String>((ref) {
  return ref.watch(selectedDeckProvider) ?? Deck.defaultDeckId;
});

/// 当前卡组对象。
final activeDeckProvider = Provider<Deck?>((ref) {
  final String id = ref.watch(activeDeckIdProvider);
  final List<Deck> decks = ref.watch(decksProvider).value ?? const <Deck>[];
  for (final Deck deck in decks) {
    if (deck.id == id) return deck;
  }
  return null;
});

/// FSRS 配置：默认的 FSRS-6 参数 + 用户设定的目标保留率。
final fsrsConfigProvider = Provider<FsrsConfig>((ref) {
  final AppSettings settings = ref.watch(currentSettingsProvider);
  return FsrsConfig(desiredRetention: settings.retention);
});

/// 当前卡片列表（跟随当前卡组与数据变化自动更新）。
final deckCardsProvider = Provider<List<WordCard>>((ref) {
  return ref.watch(cardsProvider).value ?? const <WordCard>[];
});

/// 当前卡组里出现过的标签（标签筛选面板的候选）。
final deckTagsProvider = Provider<List<String>>((ref) {
  return deckTags(ref.watch(deckCardsProvider));
});

/// 本轮出题的候选池。
///
/// - 原有算法：当前卡组的全部词，再按标签筛一遍（标签筛选只在这里生效）；
/// - FSRS-6：原样返回整个卡组，复习哪些词由 FSRS 自己按记忆状态决定。
final studyPoolProvider = Provider<List<WordCard>>((ref) {
  final List<WordCard> cards = ref.watch(deckCardsProvider);
  final AppSettings settings = ref.watch(currentSettingsProvider);
  if (settings.usesFsrs) return cards;
  return filterCardsByTags(cards, settings.studyTagFilter);
});

/// 演示这一场从哪些词里出题（卡组范围 + 标签筛选）。
///
/// 刻意不复用 studyPoolProvider：两边各有一份选择，老师上课放哪个卡组
/// 不应该顺手改掉作答页的卡组。
final projectionScopeProvider = Provider<ProjectionScope>((ref) {
  final AppSettings settings = ref.watch(currentSettingsProvider);
  final List<Deck> decks = ref.watch(decksProvider).value ?? const <Deck>[];
  // 挑中的卡组被删掉了：当作「还没挑」，退回当前卡组。
  final String? chosen = decks.any(
    (Deck deck) => deck.id == settings.projectionDeckId,
  )
      ? settings.projectionDeckId
      : null;
  return resolveProjectionScope(
    cards: ref.watch(allCardsProvider).value ?? const <WordCard>[],
    source: settings.projectionSource,
    currentDeckId: ref.watch(selectedDeckProvider),
    chosenDeckId: chosen,
    tags: settings.projectionTagFilter,
  );
});

/// 按 FSRS 排好的复习队列：最可能忘的词排在前面。
final fsrsQueueProvider = Provider<List<FsrsQueueItem>>((ref) {
  return buildFsrsQueue(
    ref.watch(deckCardsProvider),
    now: DateTime.now(),
    config: ref.watch(fsrsConfigProvider),
  );
});

/// 今天到期（含从未学过的新词）的卡片数。
final fsrsDueCountProvider = Provider<int>((ref) {
  return countFsrsDue(
    ref.watch(deckCardsProvider),
    now: DateTime.now(),
    config: ref.watch(fsrsConfigProvider),
  );
});

// ------------------------------------------------------------------ 卡片

/// 当前词库下的卡片（随流自动更新）。
final cardsProvider = StreamProvider<List<WordCard>>((ref) {
  final repository = ref.watch(cardRepositoryProvider);
  final deckId = ref.watch(selectedDeckProvider);
  return repository.watch(deckId: deckId);
});

/// 全部卡片，忽略词库筛选。
final allCardsProvider = StreamProvider<List<WordCard>>(
  (ref) => ref.watch(cardRepositoryProvider).watch(),
);

// ------------------------------------------------------------------ 答题记录与统计

final recentRecordsProvider = StreamProvider<List<AnswerRecord>>(
  (ref) => ref.watch(answerRecordRepositoryProvider).watchRecent(limit: 500),
);

final statsProvider = FutureProvider<StudyStats>((ref) async {
  final cards = await ref.watch(cardRepositoryProvider).getAll();
  final records = await ref.watch(answerRecordRepositoryProvider).getAll();
  return computeStats(cards: cards, records: records, now: DateTime.now());
});

/// 统计页要用的更细的派生数据。
final statsBreakdownProvider = FutureProvider<StatsBreakdown>((ref) async {
  final cards = await ref.watch(cardRepositoryProvider).getAll();
  final records = await ref.watch(answerRecordRepositoryProvider).getAll();
  return computeBreakdown(cards: cards, records: records, now: DateTime.now());
});

// ------------------------------------------------------------------ Anki 库

/// 当前打开的 Anki 集合。只有真实运行时才有值，测试里是 null。
final ankiCollectionProvider = Provider<AnkiCollection?>((ref) => null);

// ------------------------------------------------------------------ 演示模式

/// 翻页提示音：默认是 3000 Hz、0.5 秒的内置正弦波，也可以换成用户自选的音频。
///
/// 会跟着设置走，所以改频率/时长/换文件之后下一轮演示就生效。
/// 测试里换成假的计数实现。
final pageTurnSoundProvider = Provider<PageTurnSound>((ref) {
  final AppSettings settings = ref.watch(currentSettingsProvider);
  final AudioPageTurnSound player = AudioPageTurnSound(
    frequencyHz: settings.projectionBeepHz,
    durationMs: settings.projectionBeepMs,
    customPath: settings.projectionSoundSource == PageTurnSoundSource.custom
        ? settings.projectionSoundPath
        : null,
  );
  ref.onDispose(player.dispose);
  return player;
});

// ------------------------------------------------------------------ 导出

final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(collection: ref.watch(ankiCollectionProvider)),
);

// ------------------------------------------------------------------ 演示答案

/// 演示结束后把答案写成 txt 的服务。
final answerSheetServiceProvider =
    Provider<AnswerSheetService>((ref) => AnswerSheetService());

/// 最近一次写答案文件的结果：成功就是文件，失败就是错误原因。
class AnswerSheetStatus {
  const AnswerSheetStatus({this.sheet, this.error});

  final AnswerSheet? sheet;
  final String? error;
}

class LastAnswerSheet extends Notifier<AnswerSheetStatus> {
  @override
  AnswerSheetStatus build() => const AnswerSheetStatus();

  void remember(AnswerSheet sheet) => state = AnswerSheetStatus(sheet: sheet);

  void fail(Object error) => state = AnswerSheetStatus(error: error.toString());
}

final lastAnswerSheetProvider =
    NotifierProvider<LastAnswerSheet, AnswerSheetStatus>(LastAnswerSheet.new);
