import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ids.dart';
import '../data/audio/beep_player.dart';
import '../data/export/answer_sheet_service.dart';
import '../domain/models/app_settings.dart';
import '../domain/models/word_card.dart';
import '../logic/quiz.dart';
import 'providers.dart';

enum ProjectionStatus {
  /// 还没开始
  idle,

  /// 正在演示
  running,

  /// 演示结束了（不循环时放完最后一张，或者中途退出）
  finished,

  /// 没有可演示的卡片
  empty,
}

/// 演示模式的状态。
///
/// 演示是**用来答题的**：和测验一样是「一个单词 + 五个选项」，
/// 区别只是放大到全屏、而且屏幕上点不了（学生口头作答，讲的人控制节奏）。
/// **全程不显示答案** —— 答案在结束后写进一个 txt 文件。
class ProjectionState {
  const ProjectionState({
    this.status = ProjectionStatus.idle,
    this.questions = const <QuizQuestion>[],
    this.index = 0,
    this.remainingMs = 0,
    this.intervalMs = 0,
    this.paused = false,
    this.loops = 0,
    this.deckName = '',
    this.sessionId,
  });

  final ProjectionStatus status;
  final List<QuizQuestion> questions;
  final int index;

  /// 当前这道题还剩多少毫秒。
  final int remainingMs;

  /// 每道题的限时总长（毫秒）。
  final int intervalMs;

  final bool paused;

  /// 循环了几轮。
  final int loops;

  /// 这一轮用的卡组名，写答案文件时用。
  final String deckName;

  /// 本轮演示的 id，用来保证答案文件只写一次。
  final String? sessionId;

  QuizQuestion? get current =>
      index >= 0 && index < questions.length ? questions[index] : null;

  /// 当前题的卡片。
  WordCard? get card => current?.card;

  /// 当前题的五个选项。
  List<String> get options => current?.options ?? const <String>[];

  /// 正确选项在这五个里的下标。
  int get correctIndex => current?.correctIndex ?? -1;

  int get total => questions.length;
  int get position => total == 0 ? 0 : index + 1;
  bool get isRunning => status == ProjectionStatus.running;
  bool get isLast => index >= questions.length - 1;

  double get remainingRatio {
    if (intervalMs <= 0) return 0;
    return (remainingMs / intervalMs).clamp(0.0, 1.0);
  }

  int get remainingSeconds =>
      remainingMs <= 0 ? 0 : ((remainingMs + 999) ~/ 1000);

  ProjectionState copyWith({
    ProjectionStatus? status,
    List<QuizQuestion>? questions,
    int? index,
    int? remainingMs,
    int? intervalMs,
    bool? paused,
    int? loops,
    String? deckName,
    String? sessionId,
  }) {
    return ProjectionState(
      status: status ?? this.status,
      questions: questions ?? this.questions,
      index: index ?? this.index,
      remainingMs: remainingMs ?? this.remainingMs,
      intervalMs: intervalMs ?? this.intervalMs,
      paused: paused ?? this.paused,
      loops: loops ?? this.loops,
      deckName: deckName ?? this.deckName,
      sessionId: sessionId ?? this.sessionId,
    );
  }
}

/// 课堂演示（投影）的流程控制。
///
/// 铁律和测验一致：**每道题都有停留限时，到点直接换下一题**，没有「不限时」。
/// 这里是纯展示：没有作答动作、不给看答案、不写任何答题记录；
/// 一轮演示结束时把出过的题和正确答案写成一份 txt（时间 + 卡组名）。
///
/// 计时用累加 tick 而不是 DateTime.now()，这样 widget 测试里的假时钟也能驱动。
class ProjectionController extends Notifier<ProjectionState> {
  static const Duration _tick = Duration(seconds: 1);

  Timer? _timer;
  int _elapsedMs = 0;

  bool _loop = true;
  bool _shuffle = false;
  bool _reshuffleEachRound = true;
  List<WordCard> _cards = const <WordCard>[];
  String _deckName = '';
  int _intervalSeconds = 5;

  PageTurnSound _sound = const SilentPageTurnSound();

  /// 已经写过答案文件的 session，保证一次演示只写一份。
  final Set<String> _writtenSessions = <String>{};

  @override
  ProjectionState build() {
    ref.onDispose(_cancelTimer);
    return const ProjectionState();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// 开始演示。
  ///
  /// [announcePageTurns] 打开时，每次翻页都会播提示音（内置正弦波或用户自选音频）。
  /// [reshuffleEachRound] 打开时，每循环一圈都重新打乱选项顺序。
  void start(
    List<WordCard> cards, {
    required int intervalSeconds,
    String deckName = '',
    bool shuffle = false,
    bool loop = true,
    bool reshuffleEachRound = true,
    bool announcePageTurns = true,
  }) {
    _cancelTimer();
    _loop = loop;
    _shuffle = shuffle;
    _reshuffleEachRound = reshuffleEachRound;
    _intervalSeconds = intervalSeconds.clamp(1, 600);
    _deckName = deckName.trim().isEmpty ? '默认词库' : deckName.trim();
    _cards = List<WordCard>.of(cards);
    _sound = announcePageTurns
        ? ref.read(pageTurnSoundProvider)
        : const SilentPageTurnSound();

    if (cards.isEmpty) {
      state = const ProjectionState(status: ProjectionStatus.empty);
      return;
    }

    final int intervalMs = _intervalSeconds * 1000;
    _elapsedMs = 0;
    state = ProjectionState(
      status: ProjectionStatus.running,
      questions: _buildQuestions(),
      index: 0,
      remainingMs: intervalMs,
      intervalMs: intervalMs,
      deckName: _deckName,
      sessionId: newId(),
    );
    _startTimer();
  }

  /// 演示要放完全部卡片，不受「每轮题数」限制。
  List<QuizQuestion> _buildQuestions() => buildQuizQuestions(
        _cards,
        limit: _cards.length,
        shuffleCards: _shuffle,
        random: Random(),
      );

  void _startTimer() {
    _timer?.cancel();
    _elapsedMs = 0;
    if (state.intervalMs <= 0) return;
    _timer = Timer.periodic(_tick, (Timer timer) {
      if (!state.isRunning || state.paused) return;
      _elapsedMs += _tick.inMilliseconds;
      final int remaining =
          (state.intervalMs - _elapsedMs).clamp(0, state.intervalMs);
      if (remaining <= 0) {
        _turn(1);
        return;
      }
      state = state.copyWith(remainingMs: remaining);
    });
  }

  /// 翻页。delta 为 +1 / -1；越界时按 loop 设置决定回到头尾还是结束。
  void _turn(int delta) {
    if (!state.isRunning) return;
    final int next = state.index + delta;

    if (next < 0) {
      if (!_loop) return;
      _goTo(state.questions.length - 1);
      return;
    }
    if (next >= state.questions.length) {
      if (!_loop) {
        _finish();
        return;
      }
      // 新的一轮：需要的话把选项重新打乱
      state = state.copyWith(
        loops: state.loops + 1,
        questions: _reshuffleEachRound ? _buildQuestions() : state.questions,
      );
      _goTo(0);
      return;
    }
    _goTo(next);
  }

  void _goTo(int index) {
    _elapsedMs = 0;
    state = state.copyWith(index: index, remainingMs: state.intervalMs);
    unawaited(_sound.playPageTurn());
  }

  /// 不循环时放完最后一题：结束并写答案文件。
  void _finish() {
    _cancelTimer();
    final ProjectionState snapshot =
        state.copyWith(status: ProjectionStatus.finished, remainingMs: 0);
    state = snapshot;
    unawaited(_writeAnswerSheet(snapshot));
  }

  /// 暂停 / 继续。
  void togglePause() {
    if (!state.isRunning) return;
    state = state.copyWith(paused: !state.paused);
  }

  void next() => _turn(1);

  void previous() => _turn(-1);

  /// 结束这一轮演示。中途退出也走这里，所以答案文件不会丢。
  void stop() {
    final ProjectionState snapshot = state;
    _cancelTimer();
    state = const ProjectionState();
    unawaited(_writeAnswerSheet(snapshot));
  }

  /// 把这一轮出过的题和正确答案写成 txt。同一个 session 只会写一次。
  Future<void> _writeAnswerSheet(ProjectionState snapshot) async {
    final String? session = snapshot.sessionId;
    if (session == null || session.isEmpty) return;
    if (snapshot.questions.isEmpty) return;
    if (!_writtenSessions.add(session)) return;

    try {
      final AppSettings settings = ref.read(currentSettingsProvider);
      final AnswerSheet sheet =
          await ref.read(answerSheetServiceProvider).write(
            questions: snapshot.questions,
            deckName: snapshot.deckName.isEmpty ? _deckName : snapshot.deckName,
            intervalSeconds: _intervalSeconds,
            labelStyle: settings.projectionOptionLabelStyle,
            mode: settings.projectionAnswerMode,
            customDirectory: settings.projectionAnswerDir,
          );
      ref.read(lastAnswerSheetProvider.notifier).remember(sheet);
    } catch (error) {
      // 写不出去不能影响演示的收尾，但要让用户看见原因。
      ref.read(lastAnswerSheetProvider.notifier).fail(error);
    }
  }
}

final projectionControllerProvider =
    NotifierProvider<ProjectionController, ProjectionState>(
        ProjectionController.new);
