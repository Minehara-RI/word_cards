import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/logic/quiz.dart';

import 'support/test_harness.dart';

void main() {
  group('出题', () {
    test('每题 5 个选项，correctIndex 指向正确释义', () {
      final questions = buildQuizQuestions(
        sampleCards(),
        random: Random(7),
        shuffleCards: false,
      );
      expect(questions, hasLength(3));
      for (final question in questions) {
        expect(question.options, hasLength(5));
        expect(question.options.toSet(), hasLength(5), reason: '选项不能重复');
        expect(
          question.options[question.correctIndex],
          question.card.definition,
        );
      }
    });

    test('limit 生效', () {
      final questions = buildQuizQuestions(
        sampleCards(),
        limit: 2,
        random: Random(1),
      );
      expect(questions, hasLength(2));
    });

    test('干扰项不足时从其他卡片借，凑够 5 个', () {
      final cards = <WordCard>[
        makeCard(
          id: 'solo',
          word: 'solo',
          definition: 'adj. 单独的',
          distractors: <String>['adj. 共同的'],
        ),
        ...sampleCards(),
      ];
      final questions = buildQuizQuestions(
        cards,
        random: Random(3),
        shuffleCards: false,
      );
      final first = questions.first;
      expect(first.card.word, 'solo');
      expect(first.options, hasLength(5));
      expect(first.options[first.correctIndex], 'adj. 单独的');
    });

    test('同一份种子出题结果可复现', () {
      final a = buildQuizQuestions(sampleCards(), random: Random(42));
      final b = buildQuizQuestions(sampleCards(), random: Random(42));
      expect(
        a.map((q) => q.options.join('|')),
        b.map((q) => q.options.join('|')),
      );
      expect(a.map((q) => q.correctIndex), b.map((q) => q.correctIndex));
    });

    test('空列表返回空', () {
      expect(buildQuizQuestions(const []), isEmpty);
    });
  });

  group('答题后更新学习状态', () {
    test('答对会累加次数并提升掌握度', () {
      final card = makeCard();
      final updated = applyAnswer(
        card,
        correct: true,
        reactionMs: 1500,
        answeredAt: DateTime(2026, 5, 1),
      );
      expect(updated.reviewCount, 1);
      expect(updated.correctCount, 1);
      expect(updated.wrongCount, 0);
      expect(updated.totalReactionMs, 1500);
      expect(updated.mastery, greaterThan(0));
      expect(updated.lastReviewedAt, DateTime(2026, 5, 1));
    });

    test('答错会拉低掌握度', () {
      final card = makeCard(reviewCount: 3, correctCount: 3, mastery: 1);
      final updated = applyAnswer(
        card,
        correct: false,
        reactionMs: 9000,
        answeredAt: DateTime(2026, 5, 1),
      );
      expect(updated.reviewCount, 4);
      expect(updated.wrongCount, 1);
      expect(updated.mastery, lessThan(1));
    });

    test('掌握度被夹在 0..1', () {
      var card = makeCard();
      for (var i = 0; i < 20; i++) {
        card = applyAnswer(
          card,
          correct: true,
          reactionMs: 500,
          answeredAt: DateTime(2026, 5, 1),
        );
      }
      expect(card.mastery, lessThanOrEqualTo(1.0));
      expect(card.mastery, greaterThanOrEqualTo(0.0));
    });
  });
}
