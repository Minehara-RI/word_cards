import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/answer_record.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/logic/stats_breakdown.dart';

import 'support/test_harness.dart';

void main() {
  WordCard card(
    String id,
    String word, {
    int reviewCount = 0,
    double mastery = 0,
  }) =>
      makeCard(id: id, word: word)
          .copyWith(reviewCount: reviewCount, mastery: mastery);

  AnswerRecord record(
    String cardId,
    DateTime at, {
    bool correct = true,
    int reactionMs = 1000,
    QuizMode mode = QuizMode.practice,
  }) =>
      AnswerRecord(
        id: cardId + at.microsecondsSinceEpoch.toString(),
        cardId: cardId,
        selected: 'x',
        expected: 'x',
        correct: correct,
        reactionMs: reactionMs,
        answeredAt: at,
        mode: mode,
      );

  final DateTime now = DateTime(2026, 3, 10, 12);

  test('掌握度分布：没学过 / 学习中 / 已掌握', () {
    final StatsBreakdown breakdown = computeBreakdown(
      cards: <WordCard>[
        card('a', 'alpha'),
        card('b', 'beta', reviewCount: 3, mastery: 0.9),
        card('c', 'gamma', reviewCount: 2, mastery: 0.4),
      ],
      records: const <AnswerRecord>[],
      now: now,
    );
    expect(breakdown.totalCards, 3);
    expect(breakdown.untouched, 1);
    expect(breakdown.mastered, 1);
    expect(breakdown.learning, 1);
    expect(breakdown.masteredRatio, closeTo(1 / 3, 0.0001));
  });

  test('最近七天按天分桶，从早到晚', () {
    final StatsBreakdown breakdown = computeBreakdown(
      cards: <WordCard>[card('a', 'alpha')],
      records: <AnswerRecord>[
        record('a', DateTime(2026, 3, 10, 9)),
        record('a', DateTime(2026, 3, 10, 10), correct: false),
        record('a', DateTime(2026, 3, 8, 9)),
        record('a', DateTime(2026, 2, 1, 9)),
      ],
      now: now,
      dayCount: 7,
    );

    expect(breakdown.daily.length, 7);
    expect(breakdown.daily.first.day, DateTime(2026, 3, 4));
    expect(breakdown.daily.last.day, DateTime(2026, 3, 10));
    expect(breakdown.daily.last.total, 2);
    expect(breakdown.daily.last.correct, 1);
    expect(breakdown.daily[4].day, DateTime(2026, 3, 8));
    expect(breakdown.daily[4].total, 1);
  });

  test('最需要加强的词按正确率升序，没做过的词不出现', () {
    final StatsBreakdown breakdown = computeBreakdown(
      cards: <WordCard>[
        card('a', 'alpha'),
        card('b', 'beta'),
        card('c', 'gamma'),
      ],
      records: <AnswerRecord>[
        record('a', DateTime(2026, 3, 10, 9)),
        record('a', DateTime(2026, 3, 10, 9, 1)),
        record('b', DateTime(2026, 3, 10, 9, 2)),
        record('b', DateTime(2026, 3, 10, 9, 3), correct: false),
        record('b', DateTime(2026, 3, 10, 9, 4), correct: false),
      ],
      now: now,
    );

    expect(breakdown.weakest.map((CardAccuracy e) => e.card.word).toList(),
        <String>['beta', 'alpha']);
    expect(breakdown.weakest.first.accuracy, closeTo(1 / 3, 0.0001));
    expect(breakdown.weakest.first.attempts, 3);
  });

  test('投影模式的记录完全不计入统计', () {
    final StatsBreakdown breakdown = computeBreakdown(
      cards: <WordCard>[card('a', 'alpha')],
      records: <AnswerRecord>[
        record('a', DateTime(2026, 3, 10, 9), mode: QuizMode.projection),
        record('a', DateTime(2026, 3, 10, 10)),
      ],
      now: now,
    );
    expect(breakdown.daily.last.total, 1);
    expect(breakdown.weakest.single.attempts, 1);
    expect(breakdown.recent.length, 1);
  });

  test('平均反应时间按毫秒算', () {
    final StatsBreakdown breakdown = computeBreakdown(
      cards: <WordCard>[card('a', 'alpha')],
      records: <AnswerRecord>[
        record('a', DateTime(2026, 3, 10, 9), reactionMs: 1000),
        record('a', DateTime(2026, 3, 10, 10), reactionMs: 3000),
      ],
      now: now,
    );
    expect(breakdown.averageReactionMs, 2000);
  });

  test('最近答题取最新的若干条', () {
    final StatsBreakdown breakdown = computeBreakdown(
      cards: <WordCard>[card('a', 'alpha')],
      records: <AnswerRecord>[
        record('a', DateTime(2026, 3, 10, 12)),
        record('a', DateTime(2026, 3, 10, 11)),
        record('a', DateTime(2026, 3, 10, 10)),
      ],
      now: now,
      recentLimit: 2,
    );
    expect(breakdown.recent.length, 2);
    expect(breakdown.recent.first.answeredAt.hour, 12);
  });
}
