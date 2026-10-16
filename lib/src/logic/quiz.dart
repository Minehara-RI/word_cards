import 'dart:math';

import '../domain/models/word_card.dart';

/// 一道已经出好的题：选项顺序固定，正确项有明确下标。
class QuizQuestion {
  const QuizQuestion({
    required this.card,
    required this.options,
    required this.correctIndex,
  });

  final WordCard card;
  final List<String> options;
  final int correctIndex;

  String get correctOption => options[correctIndex];

  bool isCorrect(int? index) => index != null && index == correctIndex;
}

/// 一次测验的成绩单。
class QuizSummary {
  const QuizSummary({
    required this.total,
    required this.correct,
    required this.totalReactionMs,
  });

  final int total;
  final int correct;
  final int totalReactionMs;

  double get accuracy => total == 0 ? 0 : correct / total;

  int get averageReactionMs => total == 0 ? 0 : (totalReactionMs / total).round();
}

/// 根据卡片列表出题。
///
/// [optionCount] 默认 5（1 个正确释义 + 4 个干扰项）。当某张卡片自己带的
/// 干扰项不够时，会从 [cards] 里其他卡片的释义中借，保证每题都有 5 个选项。
List<QuizQuestion> buildQuizQuestions(
  List<WordCard> cards, {
  int? limit,
  Random? random,
  int optionCount = WordCard.targetOptionCount,
  bool shuffleCards = true,
}) {
  if (cards.isEmpty) return const <QuizQuestion>[];
  final rng = random ?? Random();

  final ordered = List<WordCard>.of(cards);
  if (shuffleCards) ordered.shuffle(rng);

  final selected = limit == null || limit <= 0 || limit >= ordered.length
      ? ordered
      : ordered.sublist(0, limit);

  final pool = _borrowPool(ordered);

  return selected
      .map((card) => _buildQuestion(card, pool, rng, optionCount))
      .toList(growable: false);
}

QuizQuestion _buildQuestion(
  WordCard card,
  List<String> pool,
  Random rng,
  int optionCount,
) {
  final correct = card.definition.trim();
  final seen = <String>{correct.toLowerCase()};
  final options = <String>[correct];

  for (final distractor in card.distractors) {
    if (options.length >= optionCount) break;
    final value = distractor.trim();
    if (value.isEmpty) continue;
    if (seen.add(value.toLowerCase())) options.add(value);
  }

  if (options.length < optionCount) {
    final candidates = <String>[];
    for (final item in pool) {
      final value = item.trim();
      if (value.isEmpty) continue;
      if (seen.add(value.toLowerCase())) candidates.add(value);
    }
    candidates.shuffle(rng);
    for (final candidate in candidates) {
      if (options.length >= optionCount) break;
      options.add(candidate);
    }
  }

  options.shuffle(rng);
  return QuizQuestion(
    card: card,
    options: options,
    correctIndex: options.indexOf(correct),
  );
}

/// 借释义用的池子：所有卡片的正确释义与干扰项。
List<String> _borrowPool(List<WordCard> cards) {
  final pool = <String>[];
  for (final card in cards) {
    pool.add(card.definition);
    pool.addAll(card.distractors);
  }
  return pool;
}

/// 依据答题结果更新卡片的学习状态（阶段五会换成完整的 SM-2）。
WordCard applyAnswer(
  WordCard card, {
  required bool correct,
  required int reactionMs,
  required DateTime answeredAt,
}) {
  final reviewCount = card.reviewCount + 1;
  final correctCount = card.correctCount + (correct ? 1 : 0);
  final wrongCount = card.wrongCount + (correct ? 0 : 1);
  final accuracy = correctCount / reviewCount;

  // 掌握度：正确率为主，反应速度做小幅修正。
  final speedBonus = reactionMs <= 2500 ? 0.1 : (reactionMs >= 8000 ? -0.1 : 0.0);
  final mastery = (accuracy + (correct ? speedBonus : -0.1)).clamp(0.0, 1.0);

  return card.copyWith(
    reviewCount: reviewCount,
    correctCount: correctCount,
    wrongCount: wrongCount,
    totalReactionMs: card.totalReactionMs + reactionMs,
    mastery: mastery,
    lastReviewedAt: answeredAt,
  );
}
