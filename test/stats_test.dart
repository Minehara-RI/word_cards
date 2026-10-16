// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/domain/models/answer_record.dart';
import 'package:word_cards/src/domain/models/word_card.dart';
import 'package:word_cards/src/logic/stats.dart';

import 'support/test_harness.dart';

AnswerRecord record({
  required bool correct,
  required DateTime at,
  int reactionMs = 2000,
  QuizMode mode = QuizMode.practice,
}) {
  return AnswerRecord(
    id: 'r-' + at.microsecondsSinceEpoch.toString(),
    cardId: 'c1',
    selected: correct ? '甲' : '乙',
    expected: '甲',
    correct: correct,
    reactionMs: reactionMs,
    answeredAt: at,
    mode: mode,
  );
}

void main() {
  final now = DateTime(2026, 6, 1, 20);

  test('空数据', () {
    final stats = computeStats(cards: const [], records: const [], now: now);
    expect(stats.totalCards, 0);
    expect(stats.accuracy, 0);
    expect(stats.todayAnswers, 0);
  });

  test('卡片按掌握度分类', () {
    final cards = <WordCard>[
      makeCard(id: 'a'),
      makeCard(id: 'b', reviewCount: 3, correctCount: 2, mastery: 0.6),
      makeCard(id: 'c', reviewCount: 5, correctCount: 5, mastery: 0.95),
    ];
    final stats = computeStats(cards: cards, records: const [], now: now);
    expect(stats.totalCards, 3);
    expect(stats.newCards, 1);
    expect(stats.learningCards, 1);
    expect(stats.masteredCards, 1);
  });

  test('只统计今天的答题，且投影模式不计入', () {
    final records = <AnswerRecord>[
      record(correct: true, at: DateTime(2026, 6, 1, 9), reactionMs: 1000),
      record(correct: false, at: DateTime(2026, 6, 1, 10), reactionMs: 3000),
      record(correct: true, at: DateTime(2026, 5, 31, 23)),
      record(
        correct: true,
        at: DateTime(2026, 6, 1, 11),
        mode: QuizMode.projection,
      ),
    ];
    final stats = computeStats(
      cards: <WordCard>[makeCard()],
      records: records,
      now: now,
    );
    expect(stats.todayAnswers, 2);
    expect(stats.todayCorrect, 1);
    expect(stats.todayReactionMs, 4000);
    expect(stats.todayAverageReactionMs, 2000);
    expect(stats.totalAnswers, 3, reason: '投影模式那一条不算个人成绩');
    expect(stats.totalCorrect, 2);
  });
}
