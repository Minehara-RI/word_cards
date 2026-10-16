import '../domain/models/answer_record.dart';
import '../domain/models/word_card.dart';

/// 概览统计。纯函数计算，方便单测。
class StudyStats {
  const StudyStats({
    required this.totalCards,
    required this.masteredCards,
    required this.learningCards,
    required this.newCards,
    required this.totalAnswers,
    required this.totalCorrect,
    required this.todayAnswers,
    required this.todayCorrect,
    required this.todayReactionMs,
  });

  static const StudyStats empty = StudyStats(
    totalCards: 0,
    masteredCards: 0,
    learningCards: 0,
    newCards: 0,
    totalAnswers: 0,
    totalCorrect: 0,
    todayAnswers: 0,
    todayCorrect: 0,
    todayReactionMs: 0,
  );

  final int totalCards;

  /// 掌握度 >= 0.8
  final int masteredCards;

  /// 答过题但还没掌握
  final int learningCards;

  /// 一次都没答过
  final int newCards;

  final int totalAnswers;
  final int totalCorrect;
  final int todayAnswers;
  final int todayCorrect;
  final int todayReactionMs;

  double get accuracy => totalAnswers == 0 ? 0 : totalCorrect / totalAnswers;

  double get todayAccuracy =>
      todayAnswers == 0 ? 0 : todayCorrect / todayAnswers;

  int get todayAverageReactionMs =>
      todayAnswers == 0 ? 0 : (todayReactionMs / todayAnswers).round();

  /// 掌握度分布，用于概览页面。
  double get masteryRatio => totalCards == 0 ? 0 : masteredCards / totalCards;
}

/// 掌握度的分界线。
const double kMasteryThreshold = 0.8;

StudyStats computeStats({
  required List<WordCard> cards,
  required List<AnswerRecord> records,
  required DateTime now,
}) {
  final startOfDay = DateTime(now.year, now.month, now.day);

  var mastered = 0;
  var learning = 0;
  var fresh = 0;
  for (final card in cards) {
    if (card.reviewCount == 0) {
      fresh++;
    } else if (card.mastery >= kMasteryThreshold) {
      mastered++;
    } else {
      learning++;
    }
  }

  var todayAnswers = 0;
  var todayCorrect = 0;
  var todayReactionMs = 0;
  var totalCorrect = 0;

  for (final record in records) {
    // 投影模式是集体复习，完全不计入个人统计
    if (record.mode == QuizMode.projection) continue;
    if (record.correct) totalCorrect++;
    if (record.answeredAt.isBefore(startOfDay)) continue;
    todayAnswers++;
    if (record.correct) todayCorrect++;
    todayReactionMs += record.reactionMs;
  }

  return StudyStats(
    totalCards: cards.length,
    masteredCards: mastered,
    learningCards: learning,
    newCards: fresh,
    totalAnswers: records
        .where((record) => record.mode != QuizMode.projection)
        .length,
    totalCorrect: totalCorrect,
    todayAnswers: todayAnswers,
    todayCorrect: todayCorrect,
    todayReactionMs: todayReactionMs,
  );
}
