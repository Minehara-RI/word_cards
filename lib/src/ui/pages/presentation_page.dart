// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/app_settings.dart';
import '../../logic/quiz.dart';
import '../../state/projection_controller.dart';
import '../../state/providers.dart';
import '../presentation/presentation_frame.dart';
import '../presentation/presentation_view.dart';

/// 应用内全屏演示页。
///
/// 桌面端默认会另开一个最大化的演示窗口（见 presentation_window.dart），
/// 这个页面是**兜底**：多窗口插件开不出窗口时（比如在测试环境里）
/// 用它顶上去，演示功能不打折。手机端没有「演示」这个入口，
/// 也就没有这一路（见 home_shell.dart 的 visibleHomeTabs）。
class PresentationPage extends ConsumerStatefulWidget {
  const PresentationPage({super.key});

  @override
  ConsumerState<PresentationPage> createState() => _PresentationPageState();
}

class _PresentationPageState extends ConsumerState<PresentationPage> {
  late final ProjectionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(projectionControllerProvider.notifier);
  }

  @override
  void dispose() {
    // 注意：不能在 dispose 里改 provider（Riverpod 会断言）。
    // 停止演示交给 ProjectionPage 在路由返回之后做。
    super.dispose();
  }

  void _restart() {
    final ProjectionState current = ref.read(projectionControllerProvider);
    final AppSettings settings = ref.read(currentSettingsProvider);
    _controller.start(
      current.questions.map((QuizQuestion question) => question.card).toList(),
      intervalSeconds: settings.projectionIntervalSeconds,
      deckName: current.deckName,
      shuffle: settings.projectionShuffle,
      loop: settings.projectionLoop,
      reshuffleEachRound: settings.projectionReshuffleEachRound,
      announcePageTurns: settings.projectionBeepEnabled,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _controller.togglePause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyN) {
      _controller.next();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyP) {
      _controller.previous();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ProjectionState state = ref.watch(projectionControllerProvider);
    final AppSettings settings = ref.watch(currentSettingsProvider);
    final ProjectionFrameData data = projectionFrameOf(state, settings);

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: PresentationView(
        frame: data.frame,
        brightness: projectionBrightness(
          settings.projectionThemeMode,
          MediaQuery.platformBrightnessOf(context),
        ),
        onPrevious: _controller.previous,
        onNext: _controller.next,
        onTogglePause: _controller.togglePause,
        onExit: () => Navigator.of(context).maybePop(),
        onRestart: _restart,
      ),
    );
  }
}

/// 把投影控制器的状态换算成给画面用的一帧 + 结束提示。
class ProjectionFrameData {
  const ProjectionFrameData({required this.frame});

  final PresentationFrame frame;
}

/// 主窗口和应用内全屏页共用的一段转换逻辑。
ProjectionFrameData projectionFrameOf(
  ProjectionState state,
  AppSettings settings,
) {
  final List<PresentationQuestion> questions = state.questions
      .map(
        (QuizQuestion question) => PresentationQuestion(
          word: question.card.word,
          phonetic: question.card.phonetic,
          options: question.options,
        ),
      )
      .toList(growable: false);

  final String status = switch (state.status) {
    ProjectionStatus.running => PresentationFrame.statusRunning,
    ProjectionStatus.finished => PresentationFrame.statusFinished,
    ProjectionStatus.empty => PresentationFrame.statusEmpty,
    ProjectionStatus.idle => state.questions.isEmpty
        ? PresentationFrame.statusEmpty
        : PresentationFrame.statusFinished,
  };

  String? message;
  if (status == PresentationFrame.statusEmpty) {
    message = '没有可演示的卡片。';
  } else if (status == PresentationFrame.statusFinished) {
    message = '演示结束，共出过 ' +
        state.total.toString() +
        ' 道题' +
        (state.loops > 0 ? '，循环 ' + state.loops.toString() + ' 轮' : '') +
        '。\n答案已经写进 txt 文件，可以在「演示」页看到文件位置。';
  }

  return ProjectionFrameData(
    frame: PresentationFrame(
      status: status,
      questions: questions,
      index: state.index,
      remainingMs: state.remainingMs,
      intervalMs: state.intervalMs,
      paused: state.paused,
      loops: state.loops,
      labelStyle: settings.projectionOptionLabelStyle,
      message: message,
    ),
  );
}
