import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ai/api_client.dart';
import '../data/ai/card_completion.dart';
import '../data/ai/generation_service.dart';
import '../data/anki/anki_collection.dart';
import '../data/audio/beep_player.dart';
import '../data/export/answer_sheet_service.dart';
import '../data/export/export_service.dart';
import '../data/import/anki_import.dart';
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

/// Anki 的 .anki2 导入（读取 + 入库）。
final ankiImportServiceProvider = Provider<AnkiImportService>(
  (ref) => AnkiImportService(
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

/// 「AI 补全」：只补齐非必填项，只走 API（没有复制 Prompt 那条退路）。
final cardCompletionServiceProvider = Provider<CardCompletionService>(
  (ref) => CardCompletionService(
    client: ref.watch(aiApiClientProvider),
    cache: ref.watch(apiCacheRepositoryProvider),
  ),
);

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

/// 当前卡组里出现过的标签（加入页的标签候选）。
final deckTagsProvider = Provider<List<String>>((ref) {
  return deckTags(ref.watch(deckCardsProvider));
});

/// 已挂起的卡组 id。
///
/// 挂起 = 不作答、不进学习概览，但演示照样能选（见 projection_pool.dart）。
final suspendedDeckIdsProvider = Provider<Set<String>>((ref) {
  final List<Deck> decks = ref.watch(decksProvider).value ?? const <Deck>[];
  return <String>{
    for (final Deck deck in decks)
      if (deck.suspended) deck.id,
  };
});

/// 本轮作答的出题范围：卡组并集 + 标签筛选，已挂起的卡组自动排除。
final studyScopeProvider = Provider<StudyScope>((ref) {
  final AppSettings settings = ref.watch(currentSettingsProvider);
  return resolveStudyScope(
    allCards: ref.watch(allCardsProvider).value ?? const <WordCard>[],
    decks: ref.watch(decksProvider).value ?? const <Deck>[],
    selectedDeckIds: settings.quizDeckIds,
    currentDeckId: ref.watch(selectedDeckProvider),
    tags: settings.studyTagFilter,
    match: settings.tagMatchMode,
  );
});

/// 本轮出题的候选池（已经按卡组与标签筛过）。
///
/// 两套算法都用它：FSRS-6 只是把这份候选池按记忆状态排序，
/// 不再自己另看一份「整个卡组」。
final studyPoolProvider = Provider<List<WordCard>>(
  (ref) => ref.watch(studyScopeProvider).cards,
);

/// 筛选范围内出现过的标签（作答页的标签候选）。
final studyTagsProvider = Provider<List<String>>(
  (ref) => ref.watch(studyScopeProvider).tags,
);

/// 演示这一场从哪些词里出题（卡组范围 + 标签筛选）。
///
/// 刻意不复用 studyPoolProvider：两边各有一份选择，老师上课放哪个卡组
/// 不应该顺手改掉作答页的卡组。演示也不排除已挂起的卡组。
final projectionScopeProvider = Provider<ProjectionScope>((ref) {
  final AppSettings settings = ref.watch(currentSettingsProvider);
  // 挑中的卡组可能已经被删掉：只保留还存在的，全没了就当「还没挑」，
  // 由 resolveProjectionScope 退回当前卡组（课上不至于当场放空）。
  final Set<String> known = <String>{
    for (final Deck deck in ref.watch(decksProvider).value ?? const <Deck>[])
      deck.id,
  };
  return resolveProjectionScope(
    cards: ref.watch(allCardsProvider).value ?? const <WordCard>[],
    source: settings.projectionSource,
    currentDeckId: ref.watch(selectedDeckProvider),
    chosenDeckIds: settings.projectionDeckIds
        .where((String id) => known.contains(id))
        .toList(growable: false),
    tags: settings.projectionTagFilter,
    match: settings.tagMatchMode,
  );
});

/// 按 FSRS 排好的复习队列：最可能忘的词排在前面。
final fsrsQueueProvider = Provider<List<FsrsQueueItem>>((ref) {
  return buildFsrsQueue(
    ref.watch(studyPoolProvider),
    now: DateTime.now(),
    config: ref.watch(fsrsConfigProvider),
  );
});

/// 今天到期（含从未学过的新词）的卡片数。
final fsrsDueCountProvider = Provider<int>((ref) {
  return countFsrsDue(
    ref.watch(studyPoolProvider),
    now: DateTime.now(),
    config: ref.watch(fsrsConfigProvider),
  );
});

/// 「学习概览」要显示的数据：范围内的卡片 + 统计。
class OverviewSummary {
  const OverviewSummary({
    required this.cards,
    required this.stats,
    required this.label,
    required this.scope,
  });

  static const OverviewSummary empty = OverviewSummary(
    cards: <WordCard>[],
    stats: StudyStats.empty,
    label: '总概览',
    scope: OverviewScope.all,
  );

  final List<WordCard> cards;
  final StudyStats stats;

  /// 范围名字：总概览 / 全部词库 / 某个卡组的名字。
  final String label;

  final OverviewScope scope;
}

/// 学习概览的统计。
///
/// 总概览排除已挂起的卡组；当前卡组只看自己。答题记录也按卡片范围筛一遍，
/// 否则「当前卡组」的今日答题数会把别的卡组的也算进来。
///
/// 这里 watch 了一下 statsProvider：清空答题记录只会 invalidate 它，
/// 卡片流不会变，不挂上这层依赖的话概览数字会停在旧值。
final overviewSummaryProvider = FutureProvider<OverviewSummary>((ref) async {
  ref.watch(statsProvider);
  final List<WordCard> cards = await ref.watch(allCardsProvider.future);
  final List<Deck> decks = await ref.watch(decksProvider.future);
  final AppSettings settings = ref.watch(currentSettingsProvider);
  final String? currentDeckId = ref.watch(selectedDeckProvider);

  final Set<String> suspended = <String>{
    for (final Deck deck in decks)
      if (deck.suspended) deck.id,
  };

  final bool currentOnly = settings.overviewScope == OverviewScope.currentDeck &&
      currentDeckId != null;

  // 当前卡组自己也被挂起时，「当前卡组」这一档同样是空的：
  // 挂起的意思是「这段时间不算它」，换个口径看统计也不该把它算进来。
  final List<WordCard> scoped = currentOnly
      ? (suspended.contains(currentDeckId)
          ? const <WordCard>[]
          : cards
              .where((WordCard card) => card.deckId == currentDeckId)
              .toList(growable: false))
      : cards
          .where((WordCard card) => !suspended.contains(card.deckId))
          .toList(growable: false);

  String label;
  if (currentOnly) {
    label = '当前卡组';
    for (final Deck deck in decks) {
      if (deck.id == currentDeckId) label = deck.name;
    }
  } else {
    label = settings.overviewScope == OverviewScope.currentDeck
        ? '全部词库'
        : '总概览';
  }

  final Set<String> ids =
      scoped.map((WordCard card) => card.id).toSet();
  final List<AnswerRecord> records =
      await ref.watch(answerRecordRepositoryProvider).getAll();
  final List<AnswerRecord> scopedRecords = records
      .where((AnswerRecord record) => ids.contains(record.cardId))
      .toList(growable: false);

  return OverviewSummary(
    cards: scoped,
    stats: computeStats(
      cards: scoped,
      records: scopedRecords,
      now: DateTime.now(),
    ),
    label: label,
    scope: settings.overviewScope,
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
