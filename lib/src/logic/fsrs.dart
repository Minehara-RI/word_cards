// 算法本身直接用官方包 dart-fsrs（pub.dev 上的 fsrs）：
// open-spaced-repetition/dart-fsrs，21 个参数就是 FSRS-6。
//
// 这个文件只做本应用特有的三件事：
// 1. 把卡片上的 FsrsMemory 和官方包里的 Card 互相映射（含落库字段）；
// 2. 把一次作答映射成 Again / Hard / Good / Easy；
// 3. 按到期时间与可提取度排复习队列。
// 公式一行都不在这里重写，升级算法只要换 fsrs 包的版本。
// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:fsrs/fsrs.dart' as fsrs;

import '../domain/models/fsrs_memory.dart';
import '../domain/models/word_card.dart';

/// 官方包的默认参数（21 个 = FSRS-6）。
const List<double> kFsrs6DefaultParameters = fsrs.defaultParameters;

/// Anki 25.09 内置 fsrs-rs v5.1.0 的 FSRS-6 参数。
///
/// 和官方包的默认值不同（那是另一套训练出来的参数），
/// 想和 Anki 完全对齐时把 [FsrsConfig.parameters] 换成这一组即可。
const List<double> kFsrs6AnkiParameters = <double>[
  0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666,
  0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658,
  0.1542,
];

/// 一套 FSRS 配置。
///
/// 学习步长刻意留空：本应用一轮测验里一个词只答一次，
/// 不需要「1 分钟 / 10 分钟」这种当天内的学习步骤，
/// 首次作答之后直接按 FSRS 的稳定性给天数间隔（和 Anki 关闭学习步骤时一致）。
class FsrsConfig {
  const FsrsConfig({
    List<double>? parameters,
    this.desiredRetention = 0.9,
    this.maximumInterval = 36500,
    this.enableFuzzing = true,
  }) : parameters = parameters ?? kFsrs6DefaultParameters;

  final List<double> parameters;

  /// 目标保留率：想在这个概率上还记得的时候安排复习。
  final double desiredRetention;

  final int maximumInterval;

  /// 官方包默认会加一点随机扰动，避免同一天堆积大量卡片。
  final bool enableFuzzing;

  static const FsrsConfig defaults = FsrsConfig();

  /// 参数不是 21 个时退回官方默认值，避免把非法参数传给官方包。
  static List<double> normalizeParameters(List<double> input) =>
      input.length == 21 ? input : kFsrs6DefaultParameters;

  fsrs.Scheduler build() => fsrs.Scheduler(
        parameters: normalizeParameters(parameters),
        desiredRetention: desiredRetention,
        learningSteps: const <Duration>[],
        relearningSteps: const <Duration>[],
        maximumInterval: maximumInterval,
        enableFuzzing: enableFuzzing,
      );

  FsrsConfig copyWith({
    List<double>? parameters,
    double? desiredRetention,
    int? maximumInterval,
    bool? enableFuzzing,
  }) =>
      FsrsConfig(
        parameters: parameters ?? this.parameters,
        desiredRetention: desiredRetention ?? this.desiredRetention,
        maximumInterval: maximumInterval ?? this.maximumInterval,
        enableFuzzing: enableFuzzing ?? this.enableFuzzing,
      );
}

/// 把一次作答映射成 FSRS 的 1–4 分（Again / Hard / Good / Easy）。
///
/// 规则简单直白，用户能预期：
/// - 超时或答错 -> 1（Again）
/// - 答对但用时超过限时的 75% -> 2（Hard）
/// - 正常答对 -> 3（Good）
/// - 用时不到限时的 40% -> 4（Easy）
int fsrsRatingForAnswer({
  required bool correct,
  required bool timedOut,
  required int reactionMs,
  required int timeLimitMs,
}) {
  if (timedOut || !correct) return 1;
  if (timeLimitMs <= 0) return 3;
  final double ratio = reactionMs / timeLimitMs;
  if (ratio <= 0.4) return 4;
  if (ratio <= 0.75) return 3;
  return 2;
}

/// 评分对应的中文名，界面上用来解释「这次算 Easy 还是 Good」。
String fsrsRatingLabel(int rating) {
  switch (rating.clamp(1, 4)) {
    case 1:
      return 'Again 忘了';
    case 2:
      return 'Hard 勉强想起';
    case 4:
      return 'Easy 很轻松';
    default:
      return 'Good 想起来了';
  }
}

/// 一次复习算出来的结果。
class FsrsReviewResult {
  const FsrsReviewResult({
    required this.memory,
    required this.rating,
    required this.retrievability,
    required this.elapsedDays,
    required this.intervalDays,
  });

  final FsrsMemory memory;

  /// 这次给的评分 1–4。
  final int rating;

  /// 复习前的可提取度（新卡为 0）。
  final double retrievability;

  /// 距上次复习的整天数（新卡为 0）。
  final int elapsedDays;

  /// 这次算出的下次间隔（天，至少 1）。
  final int intervalDays;
}

/// 本应用对 FSRS 的封装：状态映射 + 复习 + 队列。
class FsrsScheduler {
  FsrsScheduler(this.config) : _scheduler = config.build();

  final FsrsConfig config;
  final fsrs.Scheduler _scheduler;

  /// 卡片上的记忆状态 -> 官方包的 Card。
  static fsrs.Card toFsrsCard(
    FsrsMemory memory, {
    int cardId = 0,
    DateTime? fallbackDue,
  }) {
    if (memory.isNew) {
      // 没学过的卡：官方包用 learning + 空 stability 表示「新卡」。
      return fsrs.Card(
        cardId: cardId,
        state: fsrs.State.learning,
        step: 0,
        due: (fallbackDue ?? DateTime.now()).toUtc(),
      );
    }
    return fsrs.Card(
      cardId: cardId,
      state: _toFsrsState(memory.state),
      step: null,
      stability: memory.stability,
      difficulty: memory.difficulty,
      due: (memory.dueAt ?? fallbackDue ?? DateTime.now()).toUtc(),
      lastReview: memory.lastReviewAt?.toUtc(),
    );
  }

  /// 官方包算完的 Card -> 卡片上的记忆状态。
  ///
  /// 遗忘次数由评分决定：还是新卡时评 Again 只是没学会，不算遗忘。
  static FsrsMemory fromFsrsCard(
    fsrs.Card card,
    FsrsMemory prior, {
    required int rating,
  }) {
    final int extraLapse = prior.hasMemory && rating == 1 ? 1 : 0;
    return FsrsMemory(
      stability: card.stability ?? 0,
      difficulty: card.difficulty ?? 0,
      reps: prior.reps + 1,
      lapses: prior.lapses + extraLapse,
      state: _fromFsrsState(card.state),
      lastReviewAt: card.lastReview?.toLocal(),
      dueAt: card.due.toLocal(),
    );
  }

  /// 复习一次，返回新的记忆状态与下次间隔。
  FsrsReviewResult review({
    FsrsMemory? previous,
    required int rating,
    required DateTime reviewedAt,
  }) {
    final FsrsMemory prior = previous ?? const FsrsMemory();
    final fsrs.Card before = toFsrsCard(prior, fallbackDue: reviewedAt);
    final double retrievability = prior.isNew
        ? 0
        : _scheduler.getCardRetrievability(before,
            currentDateTime: reviewedAt.toUtc());

    final fsrs.Rating fsrsRating = fsrs.Rating.fromValue(rating.clamp(1, 4));
    final ({fsrs.Card card, fsrs.ReviewLog reviewLog}) outcome =
        _scheduler.reviewCard(
      before,
      fsrsRating,
      reviewDateTime: reviewedAt.toUtc(),
    );

    final fsrs.Card after = outcome.card;
    final int intervalDays = after.due
        .difference(reviewedAt.toUtc())
        .inDays
        .clamp(1, config.maximumInterval);

    return FsrsReviewResult(
      memory: fromFsrsCard(after, prior, rating: fsrsRating.value),
      rating: fsrsRating.value,
      retrievability: retrievability,
      elapsedDays: elapsedDaysBetween(prior.lastReviewAt, reviewedAt),
      intervalDays: intervalDays,
    );
  }

  /// 这张卡现在该不该复习（新卡一律算「该学」）。
  bool isDue(FsrsMemory? memory, DateTime now) {
    if (memory == null || memory.isNew) return true;
    final DateTime? due = memory.dueAt;
    if (due == null) return true;
    return !due.isAfter(now);
  }

  /// 当前可提取度；新卡按 0 算（最该学）。
  double retrievabilityOf(FsrsMemory? memory, DateTime now) {
    if (memory == null || memory.isNew) return 0;
    return _scheduler.getCardRetrievability(
      toFsrsCard(memory),
      currentDateTime: now.toUtc(),
    );
  }

  /// 距上次复习的整天数（按自然日算，Anki 的 day cutoff 在这里做了简化）。
  static int elapsedDaysBetween(DateTime? from, DateTime to) {
    if (from == null) return 0;
    final int days = dayStart(to).difference(dayStart(from)).inDays;
    return days < 0 ? 0 : days;
  }

  static DateTime dayStart(DateTime time) =>
      DateTime(time.year, time.month, time.day);

  static fsrs.State _toFsrsState(FsrsCardState state) => switch (state) {
        FsrsCardState.learning => fsrs.State.learning,
        FsrsCardState.relearning => fsrs.State.relearning,
        FsrsCardState.newCard => fsrs.State.learning,
        FsrsCardState.review => fsrs.State.review,
      };

  static FsrsCardState _fromFsrsState(fsrs.State state) => switch (state) {
        fsrs.State.learning => FsrsCardState.learning,
        fsrs.State.relearning => FsrsCardState.relearning,
        fsrs.State.review => FsrsCardState.review,
      };
}

/// 复习队列里的一项。
class FsrsQueueItem {
  const FsrsQueueItem({
    required this.card,
    required this.memory,
    required this.retrievability,
    required this.due,
  });

  final WordCard card;
  final FsrsMemory? memory;

  /// 现在的可提取度（越低越该复习）。
  final double retrievability;

  /// 是不是已经到期。
  final bool due;
}

/// 按 FSRS 排出今天该复习什么。
///
/// 排序规则：先把该复习的排前面，再按可提取度从低到高——
/// 也就是「最可能已经忘了的词」先出现。新词排在到期词之后。
List<FsrsQueueItem> buildFsrsQueue(
  List<WordCard> cards, {
  DateTime? now,
  FsrsConfig config = FsrsConfig.defaults,
  bool includeNew = true,
}) {
  final FsrsScheduler scheduler = FsrsScheduler(config);
  final DateTime moment = now ?? DateTime.now();
  final List<FsrsQueueItem> items = <FsrsQueueItem>[];

  for (final WordCard card in cards) {
    final FsrsMemory? memory = card.fsrs;
    final bool isNew = memory == null || memory.isNew;
    if (isNew && !includeNew) continue;

    items.add(
      FsrsQueueItem(
        card: card,
        memory: memory,
        retrievability: scheduler.retrievabilityOf(memory, moment),
        due: scheduler.isDue(memory, moment),
      ),
    );
  }

  items.sort((FsrsQueueItem a, FsrsQueueItem b) {
    if (a.due != b.due) return a.due ? -1 : 1;
    final bool aNew = a.memory == null || a.memory!.isNew;
    final bool bNew = b.memory == null || b.memory!.isNew;
    if (aNew != bNew) return aNew ? 1 : -1;
    final int byRetrievability = a.retrievability.compareTo(b.retrievability);
    if (byRetrievability != 0) return byRetrievability;
    return a.card.word.toLowerCase().compareTo(b.card.word.toLowerCase());
  });

  return items;
}

/// 这段时间内到期（含新词）的卡片数量。
int countFsrsDue(
  List<WordCard> cards, {
  DateTime? now,
  FsrsConfig config = FsrsConfig.defaults,
}) {
  final FsrsScheduler scheduler = FsrsScheduler(config);
  final DateTime moment = now ?? DateTime.now();
  int count = 0;
  for (final WordCard card in cards) {
    if (scheduler.isDue(card.fsrs, moment)) count += 1;
  }
  return count;
}
