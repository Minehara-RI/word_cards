import '../domain/models/answer_record.dart';
import '../domain/models/word_card.dart';
import 'stats.dart';

/// 一张卡片的正确率排行项。
class CardAccuracy {
  const CardAccuracy({
    required this.card,
    required this.attempts,
    required this.correct,
  });

  final WordCard card;
  final int attempts;
  final int correct;

  double get accuracy => attempts == 0 ? 0 : correct / attempts;
}

/// 某一天的答题量。
class DailyAnswers {
  const DailyAnswers({
    required this.day,
    required this.total,
    required this.correct,
  });

  /// 当天 0 点（本地时间）。
  final DateTime day;
  final int total;
  final int correct;

  double get accuracy => total == 0 ? 0 : correct / total;
}

/// 统计页要用的全部派生数据。
class StatsBreakdown {
  const StatsBreakdown({
    required this.untouched,
    required this.learning,
    required this.mastered,
    required this.daily,
    required this.weakest,
    required this.averageReactionMs,
    required this.recent,
  });

  /// 一次都没作答过的卡片。
  final int untouched;

  /// 做过题但还没到掌握线的卡片。
  final int learning;

  /// 掌握度达到阈值的卡片。
  final int mastered;

  /// 最近若干天，从早到晚。
  final List<DailyAnswers> daily;

  /// 正确率从低到高，只看做过题的卡片。
  final List<CardAccuracy> weakest;

  final int averageReactionMs;

  /// 最近若干条答题记录（新的在前）。
  final List<AnswerRecord> recent;

  int get totalCards => untouched + learning + mastered;

  double get untouchedRatio => totalCards == 0 ? 0 : untouched / totalCards;

  double get learningRatio => totalCards == 0 ? 0 : learning / totalCards;

  double get masteredRatio => totalCards == 0 ? 0 : mastered / totalCards;

  static const StatsBreakdown empty = StatsBreakdown(
    untouched: 0,
    learning: 0,
    mastered: 0,
    daily: <DailyAnswers>[],
    weakest: <CardAccuracy>[],
    averageReactionMs: 0,
    recent: <AnswerRecord>[],
  );
}

/// 从卡片与答题记录算出统计页需要的东西。
///
/// 投影模式的记录一律不计入，和 [computeStats] 保持一致。
StatsBreakdown computeBreakdown({
  required List<WordCard> cards,
  required List<AnswerRecord> records,
  required DateTime now,
  int dayCount = 7,
  int weakestLimit = 8,
  int recentLimit = 12,
}) {
  final List<AnswerRecord> studied = records
      .where((AnswerRecord record) => record.mode != QuizMode.projection)
      .toList(growable: false);

  int untouched = 0;
  int learning = 0;
  int mastered = 0;
  for (final WordCard card in cards) {
    if (card.reviewCount == 0) {
      untouched++;
    } else if (card.mastery >= kMasteryThreshold) {
      mastered++;
    } else {
      learning++;
    }
  }

  final DateTime today = DateTime(now.year, now.month, now.day);
  final List<DailyAnswers> daily = <DailyAnswers>[];
  for (int offset = dayCount - 1; offset >= 0; offset--) {
    final DateTime day = today.subtract(Duration(days: offset));
    int total = 0;
    int correct = 0;
    for (final AnswerRecord record in studied) {
      final DateTime answered = record.answeredAt;
      if (answered.year == day.year &&
          answered.month == day.month &&
          answered.day == day.day) {
        total++;
        if (record.correct) correct++;
      }
    }
    daily.add(DailyAnswers(day: day, total: total, correct: correct));
  }

  final Map<String, int> attempts = <String, int>{};
  final Map<String, int> corrects = <String, int>{};
  for (final AnswerRecord record in studied) {
    attempts[record.cardId] = (attempts[record.cardId] ?? 0) + 1;
    if (record.correct) {
      corrects[record.cardId] = (corrects[record.cardId] ?? 0) + 1;
    }
  }

  final List<CardAccuracy> ranked = <CardAccuracy>[];
  for (final WordCard card in cards) {
    final int count = attempts[card.id] ?? 0;
    if (count == 0) continue;
    ranked.add(CardAccuracy(
      card: card,
      attempts: count,
      correct: corrects[card.id] ?? 0,
    ));
  }
  ranked.sort((CardAccuracy a, CardAccuracy b) {
    final int byAccuracy = a.accuracy.compareTo(b.accuracy);
    if (byAccuracy != 0) return byAccuracy;
    return b.attempts.compareTo(a.attempts);
  });

  final int totalReaction =
      studied.fold<int>(0, (int sum, AnswerRecord r) => sum + r.reactionMs);

  return StatsBreakdown(
    untouched: untouched,
    learning: learning,
    mastered: mastered,
    daily: daily,
    weakest: ranked.take(weakestLimit).toList(growable: false),
    averageReactionMs:
        studied.isEmpty ? 0 : (totalReaction / studied.length).round(),
    recent: studied.take(recentLimit).toList(growable: false),
  );
}
