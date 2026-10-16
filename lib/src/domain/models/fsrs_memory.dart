// ignore_for_file: prefer_interpolation_to_compose_strings

/// FSRS 的卡片状态（Anki 里 card 的 learning / review / relearning 阶段）。
enum FsrsCardState {
  newCard('new'),
  learning('learning'),
  review('review'),
  relearning('relearning');

  const FsrsCardState(this.id);

  final String id;

  static FsrsCardState fromId(Object? value) {
    if (value is String) {
      for (final state in FsrsCardState.values) {
        if (state.id == value || state.name == value) return state;
      }
    }
    if (value is num) {
      final int index = value.toInt();
      if (index >= 0 && index < FsrsCardState.values.length) {
        return FsrsCardState.values[index];
      }
    }
    return FsrsCardState.newCard;
  }
}

/// 一张卡片的 FSRS 记忆状态。
///
/// 关键点：这份状态单独存在 wc_card_fsrs 表里，和原来那套
/// 掌握度 / 正确率 / interval_days / ease_factor **完全分开**。
/// 打开 FSRS 只写这张表，关掉 FSRS 这张表原样留着，
/// 原来的算法看不出任何变化。
class FsrsMemory {
  const FsrsMemory({
    this.stability = 0,
    this.difficulty = 0,
    this.reps = 0,
    this.lapses = 0,
    this.state = FsrsCardState.newCard,
    this.lastReviewAt,
    this.dueAt,
  });

  /// 稳定性（天）：可提取度从 100% 掉到 90% 需要的天数。
  final double stability;

  /// 难度（1–10）。
  final double difficulty;

  /// 累计复习次数。
  final int reps;

  /// 遗忘次数。
  final int lapses;

  final FsrsCardState state;

  final DateTime? lastReviewAt;

  /// 下次到期时间。
  final DateTime? dueAt;

  /// 完全没学过。
  bool get isNew => reps == 0 || stability <= 0;

  /// 学过的卡片才有稳定性可言。
  bool get hasMemory => !isNew;

  FsrsMemory copyWith({
    double? stability,
    double? difficulty,
    int? reps,
    int? lapses,
    FsrsCardState? state,
    DateTime? lastReviewAt,
    DateTime? dueAt,
  }) {
    return FsrsMemory(
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
      reps: reps ?? this.reps,
      lapses: lapses ?? this.lapses,
      state: state ?? this.state,
      lastReviewAt: lastReviewAt ?? this.lastReviewAt,
      dueAt: dueAt ?? this.dueAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'stability': stability,
        'difficulty': difficulty,
        'reps': reps,
        'lapses': lapses,
        'state': state.id,
        'last_review_at': lastReviewAt?.millisecondsSinceEpoch,
        'due_at': dueAt?.millisecondsSinceEpoch,
      };

  factory FsrsMemory.fromMap(Map<String, Object?> map) => FsrsMemory(
        stability: (map['stability'] as num?)?.toDouble() ?? 0,
        difficulty: (map['difficulty'] as num?)?.toDouble() ?? 0,
        reps: (map['reps'] as num?)?.toInt() ?? 0,
        lapses: (map['lapses'] as num?)?.toInt() ?? 0,
        state: FsrsCardState.fromId(map['state']),
        lastReviewAt: _date(map['last_review_at']),
        dueAt: _date(map['due_at']),
      );

  static DateTime? _date(Object? value) {
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  String toString() => 'FsrsMemory(S=' +
      stability.toStringAsFixed(2) +
      ', D=' +
      difficulty.toStringAsFixed(2) +
      ', reps=' +
      reps.toString() +
      ')';
}
