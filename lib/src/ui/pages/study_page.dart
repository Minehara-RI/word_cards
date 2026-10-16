// 这些文件里的字符串用 + 拼是刻意的（拼 SQL、拼路径），关掉这条纯风格 lint。
// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/answer_record.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/word_card.dart';
import '../../logic/fsrs.dart';
import '../../logic/stats.dart';
import '../../logic/stats_breakdown.dart';
import '../../state/providers.dart';
import '../../state/quiz_controller.dart';
import '../widgets/number_field.dart';
import '../widgets/section_card.dart';
import 'quiz_page.dart';

/// 「作答」页：看一眼状态、直接把本轮参数调好，然后开始限时测验。
///
/// 每轮题数、每题限时、正误显示、复习算法都放在这里改（以前在设置页），
/// 因为它们只影响这一次答题，改完应该马上能开始，不该来回跳页面。
class StudyPage extends ConsumerWidget {
  const StudyPage({super.key, required this.onGoToAdd});

  final VoidCallback onGoToAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StudyStats stats =
        ref.watch(statsProvider).value ?? StudyStats.empty;
    final AppSettings settings = ref.watch(currentSettingsProvider);
    final int total = ref.watch(allCardsProvider).value?.length ?? 0;
    final int deckTotal = ref.watch(deckCardsProvider).length;
    final int dueCount = ref.watch(fsrsDueCountProvider);
    final int poolTotal = ref.watch(studyPoolProvider).length;
    final List<String> availableTags = ref.watch(deckTagsProvider);
    // 当前卡组一张牌都筛不出来时提前拦住（FSRS 不看标签筛选，不算这种）。
    final bool poolEmpty = !settings.usesFsrs && poolTotal == 0;
    final ThemeData theme = Theme.of(context);

    Future<void> update(AppSettings next) =>
        ref.read(settingsRepositoryProvider).save(next);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        SectionCard(
          title: '学习概览',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 28,
                runSpacing: 16,
                children: <Widget>[
                  StatTile(label: '卡片总数', value: total.toString()),
                  StatTile(
                    label: '已掌握',
                    value: stats.masteredCards.toString(),
                    hint: '掌握度 ≥ 80%',
                  ),
                  StatTile(label: '今日答题', value: stats.todayAnswers.toString()),
                  StatTile(
                    label: '总正确率',
                    value: (stats.accuracy * 100).round().toString() + '%',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: stats.masteryRatio,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                total == 0
                    ? '还没有卡片，先去「加入」页加几张。'
                    : '掌握进度 ' +
                        (stats.masteryRatio * 100).round().toString() +
                        '%（答完题会自动更新掌握度）',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        SectionCard(
          title: '本轮设置',
          subtitle: '每道题都有倒计时，到点自动判超时并进入下一题。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('题目数量', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final int count in <int>[5, 10, 20])
                    ChoiceChip(
                      label: Text(count.toString() + ' 题'),
                      selected: !settings.quizAllQuestions &&
                          settings.quizQuestionCount == count,
                      onSelected: (_) =>
                          update(settings.copyWith(quizQuestionCount: count)),
                    ),
                  ChoiceChip(
                    label: Text('全部（' + poolTotal.toString() + '）'),
                    selected: settings.quizAllQuestions,
                    onSelected: (_) => update(
                      settings.copyWith(
                        quizQuestionCount: AppSettings.allQuestions,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _poolSummary(
                  settings: settings,
                  deckTotal: deckTotal,
                  poolTotal: poolTotal,
                  dueCount: dueCount,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: poolEmpty ? theme.colorScheme.error : null,
                ),
              ),
              // 标签筛选只在「原有算法」下有意义：开着 FSRS-6 就整块藏起来，
              // 免得摆一排点不动的控件。选择照旧存在设置里，切回来立刻生效。
              if (!settings.usesFsrs) ...<Widget>[
                const SizedBox(height: 16),
                _TagFilterPanel(
                  settings: settings,
                  tags: availableTags,
                  deckTotal: deckTotal,
                  poolTotal: poolTotal,
                  onChanged: (List<String> next) =>
                      update(settings.copyWith(studyTagFilter: next)),
                ),
              ],
              const SizedBox(height: 16),
              Text('每题限时', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                '到时间还没作答就判超时、记为错题，并自动进入下一题。'
                '可填 1–600 秒，没有「不限时」这个选项。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              NumberField(
                fieldKey: const Key('time-limit-field'),
                label: '每题限时',
                helper: '1 - 600 秒',
                suffix: '秒',
                width: 200,
                value: settings.questionTimeLimitSeconds,
                min: AppSettings.minTimeLimitSeconds,
                max: AppSettings.maxTimeLimitSeconds,
                onCommit: (int seconds) => update(
                  settings.copyWith(questionTimeLimitSeconds: seconds),
                ),
              ),
              const SizedBox(height: 18),
              Text('答完是否显示对错', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                settings.answerRevealMode.description,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              SegmentedButton<AnswerRevealMode>(
                segments: AnswerRevealMode.values
                    .map(
                      (AnswerRevealMode mode) =>
                          ButtonSegment<AnswerRevealMode>(
                        value: mode,
                        label: Text(mode.label),
                      ),
                    )
                    .toList(growable: false),
                selected: <AnswerRevealMode>{settings.answerRevealMode},
                onSelectionChanged: (Set<AnswerRevealMode> selection) => update(
                  settings.copyWith(answerRevealMode: selection.first),
                ),
              ),
              const SizedBox(height: 18),
              Text('复习算法', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                settings.schedulerMode.description,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              SegmentedButton<SchedulerMode>(
                segments: SchedulerMode.values
                    .map(
                      (SchedulerMode mode) => ButtonSegment<SchedulerMode>(
                        value: mode,
                        label: Text(mode.label),
                      ),
                    )
                    .toList(growable: false),
                selected: <SchedulerMode>{settings.schedulerMode},
                onSelectionChanged: (Set<SchedulerMode> selection) =>
                    update(settings.copyWith(schedulerMode: selection.first)),
              ),
              if (settings.usesFsrs) ...<Widget>[
                const SizedBox(height: 14),
                _FsrsPanel(
                  settings: settings,
                  deckTotal: deckTotal,
                  dueCount: dueCount,
                  onRetention: (double value) => update(
                    settings.copyWith(fsrsDesiredRetention: value),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                settings.usesFsrs
                    ? '两套算法互不干扰：FSRS 的记忆状态单独存，'
                        '换回「原有算法」时掌握度、正确率还是原来那份数据。'
                    : '当前用原有算法：按正确率与掌握度挑词。'
                        '切到 FSRS-6 会用记忆状态安排复习，原有数据不受影响。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        SectionCard(
          title: '开始',
          child: Column(
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: total == 0 || poolEmpty
                      ? null
                      : () => _startQuiz(context, ref),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(settings.usesFsrs ? '开始测验（FSRS 排序）' : '开始测验'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (total == 0 ||
                          poolEmpty ||
                          (settings.usesFsrs && dueCount == 0))
                      ? null
                      : () => settings.usesFsrs
                          ? _startDue(context, ref)
                          : _startWeakest(context, ref),
                  icon: Icon(
                    settings.usesFsrs
                        ? Icons.event_available_outlined
                        : Icons.replay_outlined,
                  ),
                  label: Text(
                    settings.usesFsrs
                        ? '复习今天到期的词（' + dueCount.toString() + '）'
                        : '只练做错过 / 正确率低的词',
                  ),
                ),
              ),
              if (settings.usesFsrs && total > 0) ...<Widget>[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () => _startWeakest(context, ref),
                  icon: const Icon(Icons.replay_outlined, size: 18),
                  label: const Text('只练做错过 / 正确率低的词'),
                ),
              ],
              if (total == 0) ...<Widget>[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: onGoToAdd,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('去加入卡片'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static Future<void> _startQuiz(BuildContext context, WidgetRef ref) async {
    final AppSettings settings = ref.read(currentSettingsProvider);

    if (settings.usesFsrs) {
      // FSRS 模式：按「最可能忘」的顺序出题，不再随机打乱。
      final List<WordCard> ordered =
          ref.read(fsrsQueueProvider).map((FsrsQueueItem item) => item.card).toList();
      if (ordered.isEmpty) {
        _toast(context, '当前卡组没有可复习的词。');
        return;
      }
      await ref.read(quizControllerProvider.notifier).startWithCards(
            ordered,
            questionCount: settings.quizQuestionCount,
            shuffle: false,
          );
    } else {
      // 原有算法：默认出当前卡组（有筛选就先按标签筛）的全部词。
      // 「题目数量」只负责截断，选「全部」时出的是整份词表。
      final List<WordCard> pool = ref.read(studyPoolProvider);
      if (pool.isEmpty) {
        _toast(
          context,
          settings.studyTagFilter.isEmpty
              ? '当前卡组没有可用的词。'
              : '当前标签筛选下没有词，换一组标签或者清空筛选。',
        );
        return;
      }
      await ref.read(quizControllerProvider.notifier).startWithCards(
            pool,
            questionCount: settings.quizQuestionCount,
            shuffle: true,
          );
    }

    if (!context.mounted) return;
    if (ref.read(quizControllerProvider).status == QuizStatus.empty) {
      _toast(context, '当前没有可用的卡片，请先导入。');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const QuizPage()),
    );
  }

  /// FSRS 模式：只做今天到期的（含从没学过的新词）。
  static Future<void> _startDue(BuildContext context, WidgetRef ref) async {
    final AppSettings settings = ref.read(currentSettingsProvider);
    final List<WordCard> due = ref
        .read(fsrsQueueProvider)
        .where((FsrsQueueItem item) => item.due)
        .map((FsrsQueueItem item) => item.card)
        .toList(growable: false);

    if (due.isEmpty) {
      _toast(context, '今天没有到期的词，休息一下或者直接开始测验。');
      return;
    }

    await ref.read(quizControllerProvider.notifier).startWithCards(
          due,
          questionCount: settings.quizQuestionCount,
          shuffle: false,
        );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const QuizPage()),
    );
  }

  /// 从答题记录里挑出正确率最低的词重练（原有算法那条路）。
  static Future<void> _startWeakest(BuildContext context, WidgetRef ref) async {
    // 用同一份候选池：标签筛选对「只练做错的词」也生效。
    final List<WordCard> cards = ref.read(studyPoolProvider);
    final List<AnswerRecord> records =
        await ref.read(answerRecordRepositoryProvider).getAll();
    final StatsBreakdown breakdown = computeBreakdown(
      cards: cards,
      records: records,
      now: DateTime.now(),
      weakestLimit: 20,
    );
    final List<WordCard> weak = breakdown.weakest
        .where((CardAccuracy item) => item.accuracy < 1.0)
        .map((CardAccuracy item) => item.card)
        .toList(growable: false);

    if (!context.mounted) return;
    if (weak.isEmpty) {
      _toast(context, '还没有做错的词，先随便测一轮吧。');
      return;
    }

    await ref.read(quizControllerProvider.notifier).startWithCards(
          weak,
          shuffle: false,
          mode: QuizMode.review,
        );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const QuizPage()),
    );
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 「题目数量」下面那行说明：这一轮到底会考哪些词、考多少个。
String _poolSummary({
  required AppSettings settings,
  required int deckTotal,
  required int poolTotal,
  required int dueCount,
}) {
  if (settings.usesFsrs) {
    return '当前卡组 ' +
        deckTotal.toString() +
        ' 个词，今天到期 ' +
        dueCount.toString() +
        ' 个；FSRS-6 按最可能忘的顺序安排。';
  }
  if (settings.studyTagFilter.isEmpty) {
    return '当前卡组 ' +
        deckTotal.toString() +
        ' 个词，默认全出；想少做可以选上面的题数，想缩小范围可以选标签。';
  }
  if (poolTotal == 0) {
    return '按标签筛完一个词都不剩了，换个标签或者点「清空筛选」。';
  }
  return '当前卡组 ' +
      deckTotal.toString() +
      ' 个词，按标签筛出 ' +
      poolTotal.toString() +
      ' 个，默认全出。';
}

/// 「本轮考哪些词」的标签筛选：多选，取「与」。
///
/// 只在「原有算法」下显示与生效。开着 FSRS-6 时整块不画
/// （复习队列按整个卡组排），选择照旧留在设置里，切回原有算法立刻生效。
class _TagFilterPanel extends StatelessWidget {
  const _TagFilterPanel({
    required this.settings,
    required this.tags,
    required this.deckTotal,
    required this.poolTotal,
    required this.onChanged,
  });

  final AppSettings settings;
  final List<String> tags;
  final int deckTotal;
  final int poolTotal;
  final ValueChanged<List<String>> onChanged;

  void _toggle(String tag) {
    final List<String> next = List<String>.of(settings.studyTagFilter);
    if (!next.remove(tag)) next.add(tag);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> selected = settings.studyTagFilter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('标签筛选', style: theme.textTheme.labelMedium),
            const SizedBox(width: 8),
            if (selected.isNotEmpty)
              TextButton(
                onPressed: () => onChanged(const <String>[]),
                child: const Text('清空筛选'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '只在原有算法下生效。选多个标签时，词要同时带上这些标签才会入选；'
          '一个都不选就是整个卡组。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (tags.isEmpty)
          Text(
            '当前卡组还没有标签。去「加入」页给词打标签，这里就会出现可选。',
            style: theme.textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final String tag in tags)
                FilterChip(
                  label: Text(tag),
                  selected: selected.contains(tag),
                  onSelected: (_) => _toggle(tag),
                ),
            ],
          ),
        if (selected.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '已选 ' +
                selected.join(' + ') +
                '：' +
                poolTotal.toString() +
                ' / ' +
                deckTotal.toString() +
                ' 个词',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// FSRS 打开时多出来的那一段：目标保留率 + 今天该复习多少。
class _FsrsPanel extends StatelessWidget {
  const _FsrsPanel({
    required this.settings,
    required this.deckTotal,
    required this.dueCount,
    required this.onRetention,
  });

  final AppSettings settings;
  final int deckTotal;
  final int dueCount;
  final ValueChanged<double> onRetention;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double retention = settings.retention;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.insights_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '当前卡组 ' +
                      deckTotal.toString() +
                      ' 个词，今天该复习 ' +
                      dueCount.toString() +
                      ' 个',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '目标保留率：' + (retention * 100).round().toString() + '%',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 2),
          Text(
            '想在某个时间点还记得的概率。调高 -> 复习更勤、间隔更短；'
            '调低 -> 复习更少、更省时间。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: AppSettings.retentionPresets
                .map(
                  (double value) => ChoiceChip(
                    label: Text((value * 100).round().toString() + '%'),
                    selected: (retention - value).abs() < 0.001,
                    onSelected: (_) => onRetention(value),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 12),
          Text(
            '算法：FSRS-6（直接用官方 dart-fsrs 包，参数就是它自带的默认值）；'
            '评分由作答结果映射——超时或答错记 Again，答对按用时记 Hard / Good / Easy。'
            '想和 Anki 完全对齐，可以在代码里换成 Anki 那套参数（kFsrs6AnkiParameters）。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
