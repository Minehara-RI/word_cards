import 'dart:math';

import '../domain/models/quiz_direction.dart';
import '../domain/models/word_card.dart';

/// 一道已经出好的题：选项顺序固定，正确项有明确下标。
class QuizQuestion {
  const QuizQuestion({
    required this.card,
    required this.options,
    required this.correctIndex,
    this.direction = QuizDirection.wordToMeaning,
  });

  final WordCard card;
  final List<String> options;
  final int correctIndex;

  /// 这一题具体考哪边。**不会是 [QuizDirection.mixed]** ——
  /// 混合是设置里的东西，出题时已经掷成具体方向了。
  final QuizDirection direction;

  /// 题面上的内容：正方向是单词，反方向是中文释义。
  String get promptText => direction.isReverse ? card.definition : card.word;

  /// 题面要不要连音标一起显示。
  ///
  /// 反方向必须藏着：音标就是答案那个词的读音，摆出来等于把答案写在题面上。
  bool get showsPhonetic => !direction.isReverse;

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
/// [optionCount] 默认 5（1 个正确项 + 4 个干扰项）。当某张卡片自己带的
/// 干扰项不够时，会从 [cards] 里其他卡片的释义中借，保证每题都有 5 个选项。
///
/// [direction] 决定题面给什么、选项选什么；[QuizDirection.mixed] 时每道题
/// 单独掷一次，所以同一轮里两种方向都会出现。
List<QuizQuestion> buildQuizQuestions(
  List<WordCard> cards, {
  int? limit,
  Random? random,
  int optionCount = WordCard.targetOptionCount,
  bool shuffleCards = true,
  QuizDirection direction = QuizDirection.wordToMeaning,
}) {
  if (cards.isEmpty) return const <QuizQuestion>[];
  final rng = random ?? Random();

  final ordered = List<WordCard>.of(cards);
  if (shuffleCards) ordered.shuffle(rng);

  final selected = limit == null || limit <= 0 || limit >= ordered.length
      ? ordered
      : ordered.sublist(0, limit);

  final pool = _borrowPool(ordered);
  final wordPool = _borrowWordPool(ordered);

  return selected.map((card) {
    if (direction.pick(rng) == QuizDirection.meaningToWord) {
      final reverse = _buildReverseQuestion(card, wordPool, rng, optionCount);
      // 反方向借不到别的词（整个卡组就一个词）时返回 null，
      // 这时宁可退回正方向，也不出「只有一个选项」的假题。
      if (reverse != null) return reverse;
    }
    return _buildQuestion(card, pool, rng, optionCount);
  }).toList(growable: false);
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

/// 反方向（看中文选英文）：题面是中文释义，选项是单词。
///
/// 单词没有现成的干扰项字段（卡片里存的干扰项是释义那一侧的），
/// 所以干扰项一律从同批其它卡片的单词里借；借不到第二个词就返回 null，
/// 让调用方退回正方向。
QuizQuestion? _buildReverseQuestion(
  WordCard card,
  List<String> wordPool,
  Random rng,
  int optionCount,
) {
  final correct = card.word.trim();
  if (correct.isEmpty) return null;

  final seen = <String>{correct.toLowerCase()};
  final candidates = <String>[];
  for (final item in wordPool) {
    final value = item.trim();
    if (value.isEmpty) continue;
    if (seen.add(value.toLowerCase())) candidates.add(value);
  }
  candidates.shuffle(rng);

  final options = <String>[correct];
  for (final candidate in candidates) {
    if (options.length >= optionCount) break;
    options.add(candidate);
  }
  if (options.length < 2) return null;

  options.shuffle(rng);
  return QuizQuestion(
    card: card,
    options: options,
    correctIndex: options.indexOf(correct),
    direction: QuizDirection.meaningToWord,
  );
}

/// 借单词用的池子：所有卡片的单词（反方向的干扰项从这里出）。
List<String> _borrowWordPool(List<WordCard> cards) =>
    cards.map((WordCard card) => card.word).toList(growable: false);

/// 借释义用的池子：所有卡片的正确释义与干扰项。
List<String> _borrowPool(List<WordCard> cards) {
  final pool = <String>[];
  for (final card in cards) {
    pool.add(card.definition);
    pool.addAll(card.distractors);
  }
  return pool;
}

/// 依据答题结果更新卡片的学习状态（掌握度与各项统计字段）。
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
