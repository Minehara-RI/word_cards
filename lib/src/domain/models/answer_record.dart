/// 一次答题的完整记录，用于统计正确率、平均反应时间与复习曲线。
class AnswerRecord {
  const AnswerRecord({
    required this.id,
    required this.cardId,
    required this.selected,
    required this.expected,
    required this.correct,
    required this.reactionMs,
    required this.answeredAt,
    this.sessionId,
    this.deckId,
    this.mode = QuizMode.practice,
    this.timedOut = false,
  });

  final String id;
  final String cardId;

  /// 用户点选/按键选择的选项文本。
  final String selected;

  /// 正确选项文本，冗余存储，便于卡片被删除后仍能回看。
  final String expected;

  final bool correct;

  /// 反应时间（毫秒），从题目出现到用户选择。
  final int reactionMs;

  final DateTime answeredAt;

  /// 同一次测验共用一个 sessionId。
  final String? sessionId;

  final String? deckId;
  final QuizMode mode;

  /// 是否因为超过限时被强制判为未作答。
  /// 超时的记录 [selected] 为空串、[correct] 为 false、[reactionMs] 等于限时。
  final bool timedOut;

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'card_id': cardId,
        'selected': selected,
        'expected': expected,
        'correct': correct ? 1 : 0,
        'reaction_ms': reactionMs,
        'answered_at': answeredAt.millisecondsSinceEpoch,
        'session_id': sessionId,
        'deck_id': deckId,
        'mode': mode.id,
        'timed_out': timedOut ? 1 : 0,
      };

  factory AnswerRecord.fromMap(Map<String, Object?> map) => AnswerRecord(
        id: map['id']! as String,
        cardId: (map['card_id'] as String?) ?? '',
        selected: (map['selected'] as String?) ?? '',
        expected: (map['expected'] as String?) ?? '',
        correct: (map['correct'] as num?)?.toInt() == 1,
        reactionMs: (map['reaction_ms'] as num?)?.toInt() ?? 0,
        answeredAt: DateTime.fromMillisecondsSinceEpoch(
          (map['answered_at'] as num?)?.toInt() ?? 0,
        ),
        sessionId: map['session_id'] as String?,
        deckId: map['deck_id'] as String?,
        mode: QuizMode.fromId(map['mode']),
        timedOut: (map['timed_out'] as num?)?.toInt() == 1,
      );

  @override
  String toString() =>
      'AnswerRecord($cardId correct=$correct ${reactionMs}ms timedOut=$timedOut)';
}

/// 答题的用途：个人自测 / 课堂投影 / 复习队列。
///
/// 投影模式是集体复习，默认不计入个人掌握度。
enum QuizMode {
  practice('practice', '快速测验'),
  review('review', '复习'),
  projection('projection', '课堂投影');

  const QuizMode(this.id, this.label);

  final String id;
  final String label;

  static QuizMode fromId(Object? value) {
    if (value is String) {
      for (final mode in QuizMode.values) {
        if (mode.id == value || mode.name == value) return mode;
      }
    }
    return QuizMode.practice;
  }
}
