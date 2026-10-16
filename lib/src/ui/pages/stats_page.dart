// 这些文件里的字符串用 + 拼是刻意的（拼 SQL、拼路径），关掉这条纯风格 lint。
// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/answer_record.dart';
import '../../domain/models/word_card.dart';
import '../../logic/stats.dart';
import '../../logic/stats_breakdown.dart';
import '../../state/providers.dart';
import '../widgets/section_card.dart';

/// 「统计」页：掌握度分布、最近七天的量、最需要加强的词、最近答题。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StudyStats stats = ref.watch(statsProvider).value ?? StudyStats.empty;
    final StatsBreakdown breakdown =
        ref.watch(statsBreakdownProvider).value ?? StatsBreakdown.empty;
    final List<WordCard> cards = ref.watch(allCardsProvider).value ?? const <WordCard>[];
    final ThemeData theme = Theme.of(context);

    if (breakdown.totalCards == 0) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          const SectionCard(
            title: '统计',
            child: Text('还没有卡片，加入几张再回来看统计。'),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        SectionCard(
          title: '总览',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 28,
                runSpacing: 16,
                children: <Widget>[
                  StatTile(label: '卡片总数', value: stats.totalCards.toString()),
                  StatTile(label: '已掌握', value: stats.masteredCards.toString()),
                  StatTile(label: '今日答题', value: stats.todayAnswers.toString()),
                  StatTile(
                    label: '总正确率',
                    value: (stats.accuracy * 100).round().toString() + '%',
                  ),
                  StatTile(
                    label: '平均反应',
                    value: breakdown.averageReactionMs == 0
                        ? '--'
                        : (breakdown.averageReactionMs / 1000)
                                .toStringAsFixed(1) +
                            ' 秒',
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
            ],
          ),
        ),
        SectionCard(
          title: '掌握度分布',
          subtitle: '掌握度 = 答对次数 / 作答次数，达到 80% 记为已掌握。',
          child: Column(
            children: <Widget>[
              _DistributionBar(
                label: '还没学过',
                count: breakdown.untouched,
                ratio: breakdown.untouchedRatio,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 10),
              _DistributionBar(
                label: '学习中',
                count: breakdown.learning,
                ratio: breakdown.learningRatio,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(height: 10),
              _DistributionBar(
                label: '已掌握',
                count: breakdown.mastered,
                ratio: breakdown.masteredRatio,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
        SectionCard(
          title: '最近七天',
          subtitle: '每天答了多少题，深色部分是答对的。',
          child: _WeeklyChart(daily: breakdown.daily),
        ),
        SectionCard(
          title: '最需要加强的词',
          subtitle: '按正确率从低到高排，只列做过题的。',
          child: breakdown.weakest.isEmpty
              ? const Text('还没有答题记录。')
              : Column(
                  children: <Widget>[
                    for (final CardAccuracy item in breakdown.weakest)
                      _WeakRow(item: item),
                  ],
                ),
        ),
        SectionCard(
          title: '最近答题',
          child: breakdown.recent.isEmpty
              ? const Text('还没有答题记录。')
              : Column(
                  children: <Widget>[
                    for (final AnswerRecord record in breakdown.recent)
                      _RecentRow(record: record, cards: cards),
                  ],
                ),
        ),
      ],
    );
  }
}

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({
    required this.label,
    required this.count,
    required this.ratio,
    required this.color,
  });

  final String label;
  final int count;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        SizedBox(width: 84, child: Text(label, style: theme.textTheme.bodyMedium)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 12,
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 96,
          child: Text(
            count.toString() +
                ' 张 · ' +
                (ratio * 100).round().toString() +
                '%',
            textAlign: TextAlign.right,
            style: theme.textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.daily});

  final List<DailyAnswers> daily;

  static const List<String> _weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) return const Text('还没有数据。');
    final ThemeData theme = Theme.of(context);
    int maxTotal = 1;
    for (final DailyAnswers day in daily) {
      if (day.total > maxTotal) maxTotal = day.total;
    }

    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final DailyAnswers day in daily)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Text(
                    day.total == 0 ? '' : day.total.toString(),
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 90,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: day.total == 0
                            ? 0.02
                            : (day.total / maxTotal).clamp(0.05, 1.0),
                        child: Container(
                          width: 22,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _weekdays[day.day.weekday - 1],
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(
                    (day.day.month).toString() + '/' + (day.day.day).toString(),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WeakRow extends StatelessWidget {
  const _WeakRow({required this.item});

  final CardAccuracy item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int percent = (item.accuracy * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              item.card.word,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              item.card.definition,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          Text(
            percent.toString() + '%（' +
                item.correct.toString() + '/' + item.attempts.toString() + '）',
            style: theme.textTheme.labelMedium?.copyWith(
              color: percent < 60 ? theme.colorScheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.record, required this.cards});

  final AnswerRecord record;
  final List<WordCard> cards;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    String word = record.cardId;
    for (final WordCard card in cards) {
      if (card.id == record.cardId) {
        word = card.word;
        break;
      }
    }
    String time = record.answeredAt.month.toString() +
        '/' +
        record.answeredAt.day.toString() +
        ' ' +
        record.answeredAt.hour.toString().padLeft(2, '0') +
        ':' +
        record.answeredAt.minute.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(
            record.correct ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 18,
            color: record.correct
                ? const Color(0xFF16A34A)
                : theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              word,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (record.timedOut)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('超时', style: theme.textTheme.labelSmall),
            ),
          Text(
            (record.mode == QuizMode.projection ? '' : '') + time,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
