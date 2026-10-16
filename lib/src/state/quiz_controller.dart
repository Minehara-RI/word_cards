import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ids.dart';
import '../domain/models/answer_record.dart';
import '../domain/models/app_settings.dart';
import '../domain/models/word_card.dart';
import '../logic/fsrs.dart';
import '../logic/quiz.dart';
import 'providers.dart';

/// 结束后的逐题回顾条目（「统一显示」模式用）。
class QuizReviewItem {
  const QuizReviewItem({required this.question, required this.record});

  final QuizQuestion question;
  final AnswerRecord record;

  bool get correct => record.correct;
  String get word => question.card.word;
}

enum QuizStatus {
  /// 还没开始
  idle,

  /// 答题中
  running,

  /// 答完了
  finished,

  /// 题库是空的
  empty,
}

/// 测验的完整状态。不可变，每次变化整体替换，方便 UI 做声明式渲染。
class QuizState {
  const QuizState({
    this.status = QuizStatus.idle,
    this.questions = const <QuizQuestion>[],
    this.index = 0,
    this.selectedIndex,
    this.timedOut = false,
    this.records = const <AnswerRecord>[],
    this.questionShownAt,
    this.sessionId,
    this.remainingMs = 0,
    this.timeLimitMs = 0,
    this.revealMode = AnswerRevealMode.immediate,
  });

  final QuizStatus status;
  final List<QuizQuestion> questions;
  final int index;

  /// 当前题已选的选项下标；超时或未作答为 null。
  final int? selectedIndex;

  /// 当前题是否因为超时被判为未作答。
  final bool timedOut;

  final List<AnswerRecord> records;
  final DateTime? questionShownAt;
  final String? sessionId;

  /// 当前题还剩多少毫秒。
  final int remainingMs;

  /// 当前题的限时总长（毫秒）。
  final int timeLimitMs;

  /// 本轮的正误显示时机。
  final AnswerRevealMode revealMode;

  /// 要不要**现在**就把对错和正确答案亮出来。
  ///
  /// false 时（统一显示 / 不显示）作答后只做中性标记，不泄露答案。
  bool get showCorrectness => isAnswered && revealMode.isImmediate;

  /// 只要出了结果（作答或超时）就算已结束。
  bool get isAnswered => selectedIndex != null || timedOut;

  QuizQuestion? get current =>
      index >= 0 && index < questions.length ? questions[index] : null;

  int get total => questions.length;
  int get position => total == 0 ? 0 : index + 1;

  int get correctCount => records.where((record) => record.correct).length;

  bool get isLastQuestion => index >= questions.length - 1;

  /// 倒计时进度 1.0 -> 0.0。
  double get remainingRatio {
    if (timeLimitMs <= 0) return 0;
    return (remainingMs / timeLimitMs).clamp(0.0, 1.0);
  }

  /// 剩余整秒数（向上取整，避免显示 0 秒但其实还有 300ms）。
  int get remainingSeconds =>
      remainingMs <= 0 ? 0 : ((remainingMs + 999) ~/ 1000);

  /// 剩余时间是否已经不多了（用于把倒计时染成警示色）。
  bool get isRunningOut => remainingRatio <= 0.3;

  /// 当前题是否答对了。超时记 false。
  bool? get currentCorrect {
    final question = current;
    if (!isAnswered || question == null) return null;
    return selectedIndex == question.correctIndex && selectedIndex != null;
  }

  QuizSummary get summary => QuizSummary(
        total: records.length,
        correct: correctCount,
        totalReactionMs: records.fold<int>(
          0,
          (sum, record) => sum + record.reactionMs,
        ),
      );

  List<AnswerRecord> get wrongRecords =>
      records.where((record) => !record.correct).toList(growable: false);

  int get timedOutCount =>
      records.where((record) => record.timedOut).length;

  /// 逐题回顾。作答与题目一一对应，所以直接按下标配对。
  List<QuizReviewItem> get reviewItems {
    final items = <QuizReviewItem>[];
    final count = records.length < questions.length ? records.length : questions.length;
    for (var i = 0; i < count; i++) {
      items.add(QuizReviewItem(question: questions[i], record: records[i]));
    }
    return items;
  }

  QuizState copyWith({
    QuizStatus? status,
    List<QuizQuestion>? questions,
    int? index,
    int? selectedIndex,
    bool clearSelectedIndex = false,
    bool? timedOut,
    List<AnswerRecord>? records,
    DateTime? questionShownAt,
    String? sessionId,
    int? remainingMs,
    int? timeLimitMs,
    AnswerRevealMode? revealMode,
  }) {
    return QuizState(
      status: status ?? this.status,
      questions: questions ?? this.questions,
      index: index ?? this.index,
      selectedIndex:
          clearSelectedIndex ? null : (selectedIndex ?? this.selectedIndex),
      timedOut: timedOut ?? this.timedOut,
      records: records ?? this.records,
      questionShownAt: questionShownAt ?? this.questionShownAt,
      sessionId: sessionId ?? this.sessionId,
      remainingMs: remainingMs ?? this.remainingMs,
      timeLimitMs: timeLimitMs ?? this.timeLimitMs,
      revealMode: revealMode ?? this.revealMode,
    );
  }
}

/// 测验流程控制：抽题、限时倒计时、判定、落库。
///
/// 两条硬规则：
/// 1. **每题都有作答限时**，到点没作答一律判超时（记一条 timedOut 的错题）并自动下一题；
/// 2. 作答或超时后都会自动翻页，用户也可以手动提前翻。
///
/// 这里是纯逻辑，不 import 任何 Flutter widget。
class QuizController extends Notifier<QuizState> {
  /// 倒计时刷新间隔。
  ///
  /// 刻意做成「一秒一跳」而不是每帧动画：高频重建会让 widget 测试与真机
  /// 集成测试里的 pumpAndSettle 永远等不到静止状态。界面上一秒一跳的倒计时
  /// 反而更好读。
  static const Duration _tick = Duration(seconds: 1);

  /// 答完一题后停留多久再翻页（够看清对错）。
  static const Duration answerFeedbackDelay = Duration(milliseconds: 850);

  /// 超时后停留久一点，让用户看清正确答案。
  static const Duration timeoutFeedbackDelay = Duration(milliseconds: 1600);

  /// 「统一显示 / 不显示」模式下没什么可看的，翻页要快。
  static const Duration quietAdvanceDelay = Duration(milliseconds: 260);

  Timer? _countdown;
  Timer? _advance;

  /// 用累加 tick 而不是 DateTime.now() 计时，这样 widget 测试里的假时钟也能驱动它。
  int _elapsedMs = 0;

  QuizMode _mode = QuizMode.practice;

  @override
  QuizState build() {
    ref.onDispose(_cancelTimers);
    return const QuizState();
  }

  void _cancelTimers() {
    _countdown?.cancel();
    _advance?.cancel();
    _countdown = null;
    _advance = null;
  }

  /// 开始一轮测验。
  Future<void> start({
    String? deckId,
    int? questionCount,
    bool shuffle = true,
    QuizMode mode = QuizMode.practice,
  }) async {
    final cards = await ref.read(cardRepositoryProvider).getAll(deckId: deckId);
    await startWithCards(
      cards,
      questionCount: questionCount,
      shuffle: shuffle,
      mode: mode,
    );
  }

  /// 用指定卡片开一轮（投影模式、错题重练等会直接用它）。
  Future<void> startWithCards(
    List<WordCard> cards, {
    int? questionCount,
    bool shuffle = true,
    QuizMode mode = QuizMode.practice,
  }) async {
    _cancelTimers();
    _mode = mode;

    if (cards.isEmpty) {
      state = const QuizState(status: QuizStatus.empty);
      return;
    }

    final settings = ref.read(currentSettingsProvider);
    final questions = buildQuizQuestions(
      cards,
      limit: questionCount ?? settings.quizQuestionCount,
      shuffleCards: shuffle,
    );

    // 限时是硬规则，所以下限给到 1 秒、上限 10 分钟，避免配置出「不限时」。
    final limitMs =
        settings.questionTimeLimitSeconds.clamp(1, 600) * 1000;

    state = QuizState(
      status: QuizStatus.running,
      questions: questions,
      index: 0,
      records: const <AnswerRecord>[],
      questionShownAt: DateTime.now(),
      sessionId: newId(),
      remainingMs: limitMs,
      timeLimitMs: limitMs,
      revealMode: settings.answerRevealMode,
    );
    _startCountdown();
  }

  void _startCountdown() {
    _countdown?.cancel();
    _elapsedMs = 0;

    final limitMs = state.timeLimitMs;
    if (limitMs <= 0) return;

    _countdown = Timer.periodic(_tick, (timer) {
      if (state.status != QuizStatus.running || state.isAnswered) {
        timer.cancel();
        return;
      }
      _elapsedMs += _tick.inMilliseconds;
      final remaining = (limitMs - _elapsedMs).clamp(0, limitMs);
      if (remaining <= 0) {
        timer.cancel();
        _countdown = null;
        _timeoutCurrentQuestion();
        return;
      }
      state = state.copyWith(remainingMs: remaining);
    });
  }

  /// 超时：记一条 timedOut 的错题，然后自动下一题。
  void _timeoutCurrentQuestion() {
    final question = state.current;
    if (question == null || state.isAnswered) return;

    final limitMs = state.timeLimitMs;
    final record = AnswerRecord(
      id: newId(),
      cardId: question.card.id,
      selected: '',
      expected: question.correctOption,
      correct: false,
      reactionMs: limitMs,
      answeredAt: DateTime.now(),
      sessionId: state.sessionId,
      deckId: question.card.deckId,
      mode: _mode,
      timedOut: true,
    );

    state = state.copyWith(
      timedOut: true,
      remainingMs: 0,
      records: <AnswerRecord>[...state.records, record],
    );

    unawaited(_persist(question.card, record));
    _scheduleAdvance(
      state.showCorrectness ? timeoutFeedbackDelay : quietAdvanceDelay,
    );
  }

  /// 记录一次作答，立刻给 UI 反馈，落库放到后台。
  void answer(int optionIndex) {
    final question = state.current;
    if (question == null || state.isAnswered) return;
    if (optionIndex < 0 || optionIndex >= question.options.length) return;

    _countdown?.cancel();
    _countdown = null;

    final now = DateTime.now();
    final shownAt = state.questionShownAt ?? now;
    final reactionMs =
        now.difference(shownAt).inMilliseconds.clamp(0, 10 * 60 * 1000);
    final correct = optionIndex == question.correctIndex;

    final record = AnswerRecord(
      id: newId(),
      cardId: question.card.id,
      selected: question.options[optionIndex],
      expected: question.correctOption,
      correct: correct,
      reactionMs: reactionMs,
      answeredAt: now,
      sessionId: state.sessionId,
      deckId: question.card.deckId,
      mode: _mode,
    );

    state = state.copyWith(
      selectedIndex: optionIndex,
      records: <AnswerRecord>[...state.records, record],
    );

    unawaited(_persist(question.card, record));
    _scheduleAdvance(
      state.showCorrectness ? answerFeedbackDelay : quietAdvanceDelay,
    );
  }

  void _scheduleAdvance(Duration delay) {
    _advance?.cancel();
    _advance = Timer(delay, () {
      _advance = null;
      if (state.status == QuizStatus.running) next();
    });
  }

  /// 进入下一题（或者结束）。用户手动点「下一题」也会走这里。
  void next() {
    if (state.status != QuizStatus.running) return;
    _cancelTimers();

    if (state.isLastQuestion) {
      state = state.copyWith(status: QuizStatus.finished, remainingMs: 0);
      return;
    }

    state = state.copyWith(
      index: state.index + 1,
      clearSelectedIndex: true,
      timedOut: false,
      questionShownAt: DateTime.now(),
      remainingMs: state.timeLimitMs,
    );
    _startCountdown();
  }

  void reset() {
    _cancelTimers();
    state = const QuizState();
  }

  Future<void> _persist(WordCard card, AnswerRecord record) async {
    try {
      await ref.read(answerRecordRepositoryProvider).add(record);
      if (_mode != QuizMode.projection) {
        final AppSettings settings = ref.read(currentSettingsProvider);
        WordCard updated = applyAnswer(
          card,
          correct: record.correct,
          reactionMs: record.reactionMs,
          answeredAt: record.answeredAt,
        );

        // FSRS 打开时额外更新记忆状态。注意它只写 word.fsrs 那一份数据，
        // 掌握度 / 正确率 / 间隔这些老字段照旧由 applyAnswer 更新，
        // 两套状态各存一处，关掉 FSRS 也不会把对方的数抹掉。
        if (settings.usesFsrs) {
          final FsrsScheduler scheduler = FsrsScheduler(
            FsrsConfig(desiredRetention: settings.retention),
          );
          final FsrsReviewResult result = scheduler.review(
            previous: card.fsrs,
            rating: fsrsRatingForAnswer(
              correct: record.correct,
              timedOut: record.timedOut,
              reactionMs: record.reactionMs,
              timeLimitMs: state.timeLimitMs,
            ),
            reviewedAt: record.answeredAt,
          );
          updated = updated.copyWith(fsrs: result.memory);
        }

        await ref.read(cardRepositoryProvider).upsert(updated);
      }
      ref.invalidate(statsProvider);
    } catch (_) {
      // 落库失败不应该打断答题：用户屏幕上已经看到反馈了。
    }
  }
}

final quizControllerProvider =
    NotifierProvider<QuizController, QuizState>(QuizController.new);
