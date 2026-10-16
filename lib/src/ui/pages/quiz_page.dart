// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/app_settings.dart';
import '../../domain/models/answer_record.dart';
import '../../domain/models/word_card.dart';
import '../../state/providers.dart';
import '../../state/quiz_controller.dart';
import '../platform_target.dart';
import '../theme.dart';
import '../quiz_keys.dart';

/// 快速测验页。
///
/// 三条规则都由 [QuizController] 保证，页面只负责画：
/// 1. 每题有限时，到点强制判超时并翻页；
/// 2. 作答/超时后自动翻页，也可手动提前翻；
/// 3. 正误什么时候显示，完全按 [AnswerRevealMode] 走。
class QuizPage extends ConsumerStatefulWidget {
  const QuizPage({super.key});

  @override
  ConsumerState<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends ConsumerState<QuizPage> {
  /// 只有桌面端接键盘：移动端不装监听，免得外接键盘上出现半套操作方式。
  bool get _keyboardEnabled => detectPlatformTarget().isDesktop;

  /// 作答页的快捷键：数字键 1-5 / A-E 选答、Enter 下一题、Esc 退出本轮。
  ///
  /// 只认「按下」这一次：按住 Enter 不放不该连着跳好几题。
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_keyboardEnabled) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final LogicalKeyboardKey key = event.logicalKey;
    final QuizController controller = ref.read(quizControllerProvider.notifier);

    // Esc 随时能退出：每题答完就已经落库了，退出只是不再往下答。
    if (isQuizExitKey(key)) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }

    final QuizState state = ref.read(quizControllerProvider);
    if (state.status != QuizStatus.running) return KeyEventResult.ignored;

    if (isQuizNextKey(key)) {
      // 还没选就按 Enter：什么都不做，别把手滑当成答错。
      if (!state.isAnswered) return KeyEventResult.handled;
      controller.next();
      return KeyEventResult.handled;
    }

    final int? option = quizOptionIndexForKey(key);
    if (option == null) return KeyEventResult.ignored;

    final question = state.current;
    if (question == null || option >= question.options.length) {
      // 本题选项比键盘上的键少：多出来的键吃掉，别漏给上层。
      return KeyEventResult.handled;
    }
    if (state.isAnswered) return KeyEventResult.handled;
    controller.answer(option);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(quizControllerProvider);
    final controller = ref.read(quizControllerProvider.notifier);

    // 只有「立即显示」才露实时比分：
    // 「统一显示」下答对计数会间接暴露上一题做对没有，「不显示」下更不该给。
    final showRunningScore =
        state.revealMode.isImmediate && state.status == QuizStatus.running;

    return Focus(
      // 桌面端进来就能直接用键盘，不用先点一下页面。
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(state.status == QuizStatus.finished ? '本轮结果' : '快速测验'),
          actions: <Widget>[
            if (showRunningScore)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '正确 ' + state.correctCount.toString(),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: switch (state.status) {
              // idle 用一个静态占位，不用 CircularProgressIndicator：
              // 无限动画会让 pumpAndSettle 永远等不到静止
              QuizStatus.idle => const SizedBox.shrink(),
              QuizStatus.empty => const _EmptyView(),
              QuizStatus.finished => _ResultView(
                  state: state,
                  onRestart: () {
                    final deckId = ref.read(selectedDeckProvider);
                    controller.start(deckId: deckId);
                  },
                ),
              _ => _QuestionView(
                  state: state,
                  onSelect: controller.answer,
                  onNext: controller.next,
                  keyboardEnabled: _keyboardEnabled,
                ),
            },
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.inbox_outlined, size: 56),
          SizedBox(height: 16),
          Text('没有可用的卡片，先去「导入卡片」吧。'),
        ],
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.state,
    required this.onSelect,
    required this.onNext,
    required this.keyboardEnabled,
  });

  final QuizState state;
  final ValueChanged<int> onSelect;
  final VoidCallback onNext;

  /// 只有桌面端才画下面那行键盘提示（移动端根本没接键盘）。
  final bool keyboardEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = state.current;
    if (question == null) return const SizedBox.shrink();

    final positionText =
        '第 ' + state.position.toString() + ' / ' + state.total.toString() + ' 题';
    final progress = state.total == 0 ? 0.0 : state.position / state.total;
    final showScore = state.revealMode.isImmediate;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(positionText, style: theme.textTheme.labelLarge),
            const Spacer(),
            if (showScore)
              Text(
                '答对 ' + state.correctCount.toString() + ' 题',
                style: theme.textTheme.labelMedium,
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 12),
        _CountdownBar(state: state),
        const SizedBox(height: 20),
        _WordHeader(card: question.card),
        const SizedBox(height: 24),
        ...List<Widget>.generate(question.options.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OptionTile(
              index: index,
              text: question.options[index],
              isCorrect: index == question.correctIndex,
              isSelected: state.selectedIndex == index,
              answered: state.isAnswered,
              showCorrectness: state.showCorrectness,
              onTap: () => onSelect(index),
            ),
          );
        }),
        const SizedBox(height: 8),
        _ActionBar(state: state, onNext: onNext),
        if (keyboardEnabled) ...<Widget>[
          const SizedBox(height: 18),
          _KeyboardHint(optionCount: question.options.length),
        ],
      ],
    );
  }
}

/// 桌面端才画的一行键盘提示：选项左边的角标就是对应的键。
class _KeyboardHint extends StatelessWidget {
  const _KeyboardHint({required this.optionCount});

  final int optionCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    // 本题实际有几个选项就只报几个键，别把「1-5」这种空号也写出来。
    final choice = optionCount <= 1
        ? ''
        : '1-' +
            optionCount.toString() +
            ' 或 A-' +
            String.fromCharCode('A'.codeUnitAt(0) + optionCount - 1) +
            ' 选答，';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.keyboard_outlined, size: 16, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '键盘：' + choice + 'Enter 下一题，Esc 退出本轮',
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// 每题倒计时条：剩余秒数 + 逐渐缩短的进度条。
class _CountdownBar extends StatelessWidget {
  const _CountdownBar({required this.state});

  final QuizState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (state.isAnswered) {
      final timedOut = state.timedOut;
      final text = timedOut ? '已超时' : '已作答';
      final color = timedOut ? scheme.error : scheme.primary;
      return Row(
        children: <Widget>[
          Icon(
            timedOut ? Icons.timer_off_outlined : Icons.timer_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(text, style: theme.textTheme.labelLarge?.copyWith(color: color)),
        ],
      );
    }

    final runningOut = state.isRunningOut;
    final color = runningOut ? scheme.error : scheme.primary;
    final seconds = state.remainingSeconds.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.timer_outlined, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              '剩余 ' + seconds + ' 秒（超时自动下一题）',
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: runningOut ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: state.remainingRatio,
            minHeight: 6,
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _WordHeader extends StatelessWidget {
  const _WordHeader({required this.card});

  final WordCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phonetic = card.phonetic;
    final partOfSpeech = card.partOfSpeech;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        child: Column(
          children: <Widget>[
            Text(
              card.word,
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            if (phonetic != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                phonetic,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (partOfSpeech != null) ...<Widget>[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  partOfSpeech,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.index,
    required this.text,
    required this.isCorrect,
    required this.isSelected,
    required this.answered,
    required this.showCorrectness,
    required this.onTap,
  });

  final int index;
  final String text;
  final bool isCorrect;
  final bool isSelected;
  final bool answered;
  final bool showCorrectness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    const correctColor = Color(0xFF16A34A);

    var border = scheme.outlineVariant;
    var background = theme.cardTheme.color ?? scheme.surface;
    var keyColor = scheme.surfaceContainerHighest;
    var keyText = scheme.onSurfaceVariant;
    IconData? trailing;

    if (showCorrectness) {
      if (isCorrect) {
        border = correctColor;
        background = correctColor.withValues(alpha: 0.10);
        keyColor = correctColor;
        keyText = Colors.white;
        trailing = Icons.check_circle;
      } else if (isSelected) {
        border = scheme.error;
        background = scheme.error.withValues(alpha: 0.10);
        keyColor = scheme.error;
        keyText = Colors.white;
        trailing = Icons.cancel;
      }
    } else if (answered && isSelected) {
      // 「统一显示 / 不显示」时不能让颜色泄露对错，
      // 只中性标出「你选了这一项」。
      border = scheme.primary;
      background = scheme.primary.withValues(alpha: 0.10);
      keyColor = scheme.primary;
      keyText = scheme.onPrimary;
      trailing = Icons.radio_button_checked;
    }

    final keyLabel = (index + 1).toString();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kCardRadius),
        onTap: answered ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(kCardRadius),
            border: Border.all(
              color: border,
              width: (showCorrectness && (isCorrect || isSelected)) ||
                      (!showCorrectness && answered && isSelected)
                  ? 1.6
                  : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: keyColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  keyLabel,
                  style: TextStyle(
                    color: keyText,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
              if (trailing != null) Icon(trailing, size: 20, color: keyColor),
            ],
          ),
        ),
      ),
    );
  }
}

/// 题目下方的操作条：显示什么完全取决于「正误显示时机」。
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.state, required this.onNext});

  final QuizState state;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!state.isAnswered) {
      return Center(
        child: Text('选择一个释义', style: theme.textTheme.bodySmall),
      );
    }

    final nextLabel = state.isLastQuestion ? '看结果' : '下一题';
    final question = state.current;
    final correctAnswer = question?.correctOption ?? '';

    // 不揭晓答案的模式：只确认「已记录」
    if (!state.showCorrectness) {
      final label = state.revealMode.showsReview
          ? '已记录，结果在最后统一显示'
          : '已记录';
      return Row(
        children: <Widget>[
          Icon(Icons.bookmark_added_outlined, color: scheme.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(onPressed: onNext, child: Text(nextLabel)),
        ],
      );
    }

    IconData icon;
    Color color;
    String label;

    if (state.timedOut) {
      icon = Icons.timer_off_outlined;
      color = scheme.error;
      label = '超时了，正确释义：' + correctAnswer;
    } else if (state.currentCorrect ?? false) {
      icon = Icons.check_circle_outline;
      color = const Color(0xFF16A34A);
      label = '答对了';
    } else {
      icon = Icons.error_outline;
      color = scheme.error;
      label = '答错了，正确释义：' + correctAnswer;
    }

    return Row(
      children: <Widget>[
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        FilledButton(onPressed: onNext, child: Text(nextLabel)),
      ],
    );
  }
}

class _ResultView extends ConsumerWidget {
  const _ResultView({required this.state, required this.onRestart});

  final QuizState state;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = state.summary;
    final percent = (summary.accuracy * 100).round();
    final averageSeconds = (summary.averageReactionMs / 1000).toStringAsFixed(1);
    final timedOutCount = state.timedOutCount;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: Column(
              children: <Widget>[
                Text('正确率', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Text(
                  '$percent%',
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: percent >= 80
                        ? const Color(0xFF16A34A)
                        : (percent >= 60
                            ? const Color(0xFFF59E0B)
                            : scheme.error),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '答对 ' +
                      summary.correct.toString() +
                      ' / ' +
                      summary.total.toString() +
                      ' 题　平均反应 ' +
                      averageSeconds +
                      ' 秒',
                  style: theme.textTheme.bodyMedium,
                ),
                if (timedOutCount > 0) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    '其中 ' + timedOutCount.toString() + ' 题超时未作答',
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        switch (state.revealMode) {
          AnswerRevealMode.never => const _AnswersHiddenCard(),
          AnswerRevealMode.deferred => _ReviewCard(items: state.reviewItems),
          AnswerRevealMode.immediate => state.wrongRecords.isEmpty
              ? const _AllCorrectCard()
              : _WrongCard(records: state.wrongRecords),
        },
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: onRestart,
                icon: const Icon(Icons.refresh),
                label: const Text('再来一轮'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                // 从导入页直接开测验时，只 pop 一层会退回导入页而不是首页
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('返回首页'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AllCorrectCard extends StatelessWidget {
  const _AllCorrectCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          children: <Widget>[
            Icon(Icons.emoji_events_outlined, color: Color(0xFF16A34A)),
            SizedBox(width: 12),
            Expanded(child: Text('全部答对，这一轮非常稳。')),
          ],
        ),
      ),
    );
  }
}

class _AnswersHiddenCard extends StatelessWidget {
  const _AnswersHiddenCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: <Widget>[
            Icon(Icons.visibility_off_outlined,
                color: theme.colorScheme.outline),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('当前设置是「不显示」：只看总分，不列出题目与答案。'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WrongCard extends StatelessWidget {
  const _WrongCard({required this.records});

  final List<AnswerRecord> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('需要复习的单词', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            ...records.map(
              (record) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      record.timedOut ? Icons.timer_off : Icons.close,
                      size: 16,
                      color: const Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        record.timedOut
                            ? '超时未作答  →  ' + record.expected
                            : record.selected + '  →  ' + record.expected,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「统一显示」模式的逐题回顾。
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.items});

  final List<QuizReviewItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const correctColor = Color(0xFF16A34A);
    final wrongColor = theme.colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('逐题回顾', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      item.record.timedOut
                          ? Icons.timer_off
                          : (item.correct ? Icons.check : Icons.close),
                      size: 16,
                      color: item.correct ? correctColor : wrongColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.word,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.record.timedOut
                                ? '超时未作答　正确答案：' + item.record.expected
                                : '你选了：' +
                                    item.record.selected +
                                    (item.correct
                                        ? ''
                                        : '　正确答案：' + item.record.expected),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
