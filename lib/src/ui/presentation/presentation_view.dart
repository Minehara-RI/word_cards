// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';

import '../../domain/models/app_settings.dart';
import '../fonts.dart';
import '../theme.dart';
import 'presentation_frame.dart';

/// 演示画面本体：一个单词 + 五个选项 + 倒计时。
///
/// 主窗口（应用内全屏）和独立的演示窗口都用这一个组件，
/// 区别只在于数据是本地算出来的还是从主窗口推过来的。
/// 画面自带「演示模式深浅色」那一套主题，所以演示窗口也会跟着设置走。
class PresentationView extends StatelessWidget {
  const PresentationView({
    super.key,
    required this.frame,
    required this.brightness,
    this.onPrevious,
    this.onNext,
    this.onTogglePause,
    this.onExit,
    this.onRestart,
  });

  final PresentationFrame frame;

  /// 演示模式用深色还是浅色底。
  final Brightness brightness;

  /// 为 null 表示这个画面不接受操作（纯展示）。
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onTogglePause;
  final VoidCallback? onExit;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    final ThemeData projection = buildProjectionTheme(brightness);

    return Theme(
      data: projection,
      child: Scaffold(
        backgroundColor: projection.scaffoldBackgroundColor,
        body: SafeArea(
          child: frame.isRunning
              ? _RunningView(
                  frame: frame,
                  onPrevious: onPrevious,
                  onNext: onNext,
                  onTogglePause: onTogglePause,
                  onExit: onExit,
                )
              : _MessageView(
                  message: frame.message ?? '没有可演示的卡片。',
                  onRestart: onRestart,
                  onExit: onExit,
                ),
        ),
      ),
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({
    required this.frame,
    this.onPrevious,
    this.onNext,
    this.onTogglePause,
    this.onExit,
  });

  final PresentationFrame frame;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onTogglePause;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PresentationQuestion? card = frame.current;
    if (card == null) return const SizedBox.shrink();

    final int position = frame.position;
    final int total = frame.total;
    final int seconds = frame.remainingSeconds;
    final bool showControls = onPrevious != null || onNext != null ||
        onTogglePause != null || onExit != null;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '第 ' + position.toString() + ' / ' + total.toString() + ' 题',
                    style: projectionStyle(context,
                        size: ProjectionText.meta, weight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (frame.loops > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        '第 ' + (frame.loops + 1).toString() + ' 轮',
                        style: projectionStyle(context,
                            size: 20, weight: FontWeight.w600),
                      ),
                    ),
                  Text(
                    frame.paused ? '已暂停' : seconds.toString() + ' 秒',
                    style: projectionStyle(
                      context,
                      size: ProjectionText.countdown,
                      weight: FontWeight.w800,
                      color: frame.remainingRatio <= 0.3
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                  ),
                  if (onExit != null) ...<Widget>[
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: '退出演示',
                      onPressed: onExit,
                      icon: const Icon(Icons.close_fullscreen_outlined),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: frame.remainingRatio,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(48, 16, 48, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      card.word,
                      textAlign: TextAlign.center,
                      style: projectionStyle(
                        context,
                        size: ProjectionText.word,
                        weight: FontWeight.w800,
                        letterSpacing: 1,
                        height: 1.15,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (card.phonetic != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        card.phonetic!,
                        style: projectionStyle(
                          context,
                          size: 30,
                          weight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  for (int i = 0; i < card.options.length; i++)
                    _OptionRow(
                      label: frame.labelStyle.labelFor(i),
                      text: card.options[i],
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      '屏幕上不能点选，学生口头作答；倒计时结束自动换下一题',
                      style: projectionStyle(
                        context,
                        size: ProjectionText.hint,
                        weight: FontWeight.w400,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showControls)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton.filledTonal(
                  tooltip: '上一题（左方向键）',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  tooltip: frame.paused ? '继续（空格）' : '暂停（空格）',
                  onPressed: onTogglePause,
                  icon: Icon(
                    frame.paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  tooltip: '下一题（右方向键）',
                  onPressed: onNext,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 一个不能点的选项。全程不显示对错。
class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.label, required this.text});

  /// 选项前面的编号：1/2/3 或者 A/B/C。
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              label,
              style: projectionStyle(
                context,
                size: 26,
                weight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              text,
              style: projectionStyle(
                context,
                size: ProjectionText.option,
                weight: FontWeight.w600,
                height: 1.3,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.message,
    required this.onExit,
    this.onRestart,
  });

  final String message;
  final VoidCallback? onExit;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (onRestart != null)
                FilledButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('再来一遍'),
                ),
              if (onRestart != null) const SizedBox(width: 12),
              if (onExit != null)
                OutlinedButton.icon(
                  onPressed: onExit,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('退出'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 把 ApplicationThemeMode 换成真的 Brightness。
Brightness projectionBrightness(
  AppThemeMode mode,
  Brightness platformBrightness,
) {
  return switch (mode) {
    AppThemeMode.light => Brightness.light,
    AppThemeMode.dark => Brightness.dark,
    AppThemeMode.system => platformBrightness,
  };
}
