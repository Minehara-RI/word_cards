import 'dart:math';

import 'card_language.dart';
import 'card_source.dart';
import 'deck.dart';
import 'fsrs_memory.dart';

/// 单词卡片：AI 产出的学习内容 + 用户本地的学习状态。
///
/// 这个类是逻辑层与数据层共用的核心模型，**不依赖 Flutter**，
/// 因此可以在纯 Dart 单元测试里直接构造与断言。
class WordCard {
  const WordCard({
    required this.id,
    required this.word,
    required this.definition,
    required this.distractors,
    required this.createdAt,
    required this.updatedAt,
    this.phonetic,
    this.example,
    this.partOfSpeech,
    this.note,
    this.deckId = Deck.defaultDeckId,
    this.language = CardLanguage.english,
    this.tags = const <String>[],
    this.fsrs,
    this.source = CardSource.manualImport,
    this.reviewCount = 0,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.totalReactionMs = 0,
    this.mastery = 0,
    this.lastReviewedAt,
    this.nextReviewAt,
    this.intervalDays = 0,
    this.easeFactor = 2.5,
  });

  /// 一道题需要展示的选项总数（1 个正确释义 + 4 个干扰项）。
  static const int targetOptionCount = 5;

  /// 干扰项的标准数量。
  static const int targetDistractorCount = targetOptionCount - 1;

  final String id;
  final String word;
  final String definition;

  /// 干扰项集合，理论上 4 个。
  final List<String> distractors;

  final String? phonetic;
  final String? example;
  final String? partOfSpeech;
  final String? note;

  final String deckId;

  /// 这张卡记的是哪国语言的词。
  final CardLanguage language;

  /// 用户给这张卡打的标签（语言标签不算在内，它单独存在 [language] 里）。
  final List<String> tags;

  final CardSource source;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ---- 学习状态（掌握度与间隔重复都要读写这些字段）----
  final int reviewCount;
  final int correctCount;
  final int wrongCount;

  /// 累计反应时间，用来算平均反应时间。
  final int totalReactionMs;

  /// 掌握度 0.0–1.0。
  final double mastery;

  final DateTime? lastReviewedAt;
  final DateTime? nextReviewAt;
  final int intervalDays;
  final double easeFactor;

  /// FSRS 的记忆状态。为 null 表示这张卡还没进过 FSRS 调度。
  ///
  /// 和上面那组字段完全隔离：打开 FSRS 只写这里，关掉 FSRS 时
  /// 上面那组（掌握度、间隔、ease）一个字节都不会变。
  final FsrsMemory? fsrs;

  /// 只用于界面展示的标签（去掉空项与语言标签里的重复项）。
  List<String> get displayTags => tags
      .map((String tag) => tag.trim())
      .where((String tag) => tag.isNotEmpty)
      .toList(growable: false);

  /// Anki 的标签不能含空格，这里统一把空白换成下划线。
  static String sanitizeTag(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), '_');

  /// 把用户输入的一串标签（逗号 / 分号 / 顿号分隔）整理成干净列表。
  static List<String> parseTags(String raw) {
    final List<String> result = <String>[];
    for (final String part in raw.split(RegExp(r'[,，;；、\n]+'))) {
      final String tag = sanitizeTag(part);
      if (tag.isEmpty) continue;
      if (CardLanguage.isLanguageTag(tag)) continue;
      if (!result.contains(tag)) result.add(tag);
    }
    return result;
  }

  double get accuracy => reviewCount == 0 ? 0 : correctCount / reviewCount;

  int get averageReactionMs =>
      reviewCount == 0 ? 0 : (totalReactionMs / reviewCount).round();

  /// 题目选项：正确释义 + 干扰项，去重后打乱顺序。
  ///
  /// 传入固定种子的 [random] 可以让测试可复现。
  List<String> shuffledOptions(Random random) {
    final unique = <String>{definition.trim()};
    for (final distractor in distractors) {
      unique.add(distractor.trim());
    }
    final options = unique.where((option) => option.isNotEmpty).toList();
    options.shuffle(random);
    return options;
  }

  WordCard copyWith({
    String? word,
    String? definition,
    List<String>? distractors,
    String? phonetic,
    String? example,
    String? partOfSpeech,
    String? note,
    String? deckId,
    CardLanguage? language,
    List<String>? tags,
    FsrsMemory? fsrs,
    bool clearFsrs = false,
    CardSource? source,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? reviewCount,
    int? correctCount,
    int? wrongCount,
    int? totalReactionMs,
    double? mastery,
    DateTime? lastReviewedAt,
    DateTime? nextReviewAt,
    int? intervalDays,
    double? easeFactor,
    bool clearPhonetic = false,
    bool clearExample = false,
    bool clearPartOfSpeech = false,
    bool clearNote = false,
    bool clearNextReviewAt = false,
  }) {
    return WordCard(
      id: id,
      word: word ?? this.word,
      definition: definition ?? this.definition,
      distractors: distractors ?? this.distractors,
      phonetic: clearPhonetic ? null : (phonetic ?? this.phonetic),
      example: clearExample ? null : (example ?? this.example),
      partOfSpeech: clearPartOfSpeech ? null : (partOfSpeech ?? this.partOfSpeech),
      note: clearNote ? null : (note ?? this.note),
      deckId: deckId ?? this.deckId,
      language: language ?? this.language,
      tags: tags ?? this.tags,
      fsrs: clearFsrs ? null : (fsrs ?? this.fsrs),
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reviewCount: reviewCount ?? this.reviewCount,
      correctCount: correctCount ?? this.correctCount,
      wrongCount: wrongCount ?? this.wrongCount,
      totalReactionMs: totalReactionMs ?? this.totalReactionMs,
      mastery: mastery ?? this.mastery,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      nextReviewAt: clearNextReviewAt ? null : (nextReviewAt ?? this.nextReviewAt),
      intervalDays: intervalDays ?? this.intervalDays,
      easeFactor: easeFactor ?? this.easeFactor,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'word': word,
        'phonetic': phonetic,
        'definition': definition,
        'distractors': distractors,
        'example': example,
        'part_of_speech': partOfSpeech,
        'note': note,
        'deck_id': deckId,
        'language': language.id,
        'tags': tags,
        'fsrs': fsrs?.toMap(),
        'source': source.id,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'review_count': reviewCount,
        'correct_count': correctCount,
        'wrong_count': wrongCount,
        'total_reaction_ms': totalReactionMs,
        'mastery': mastery,
        'last_reviewed_at': lastReviewedAt?.millisecondsSinceEpoch,
        'next_review_at': nextReviewAt?.millisecondsSinceEpoch,
        'interval_days': intervalDays,
        'ease_factor': easeFactor,
      };

  factory WordCard.fromMap(Map<String, Object?> map) {
    return WordCard(
      id: map['id']! as String,
      word: (map['word'] as String?) ?? '',
      definition: (map['definition'] as String?) ?? '',
      distractors: _stringList(map['distractors']),
      phonetic: _nonEmpty(map['phonetic']),
      example: _nonEmpty(map['example']),
      partOfSpeech: _nonEmpty(map['part_of_speech']),
      note: _nonEmpty(map['note']),
      deckId: (map['deck_id'] as String?) ?? Deck.defaultDeckId,
      language: CardLanguage.fromId(map['language']),
      tags: _stringList(map['tags']),
      fsrs: map['fsrs'] is Map
          ? FsrsMemory.fromMap((map['fsrs']! as Map).cast<String, Object?>())
          : null,
      source: CardSource.fromId(map['source']),
      createdAt: _dateTime(map['created_at']),
      updatedAt: _dateTime(map['updated_at'] ?? map['created_at']),
      reviewCount: (map['review_count'] as num?)?.toInt() ?? 0,
      correctCount: (map['correct_count'] as num?)?.toInt() ?? 0,
      wrongCount: (map['wrong_count'] as num?)?.toInt() ?? 0,
      totalReactionMs: (map['total_reaction_ms'] as num?)?.toInt() ?? 0,
      mastery: (map['mastery'] as num?)?.toDouble() ?? 0,
      lastReviewedAt: _dateTimeOrNull(map['last_reviewed_at']),
      nextReviewAt: _dateTimeOrNull(map['next_review_at']),
      intervalDays: (map['interval_days'] as num?)?.toInt() ?? 0,
      easeFactor: (map['ease_factor'] as num?)?.toDouble() ?? 2.5,
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    if (value is String && value.trim().isNotEmpty) {
      return <String>[value.trim()];
    }
    return const <String>[];
  }

  static String? _nonEmpty(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static DateTime _dateTime(Object? value) =>
      _dateTimeOrNull(value) ?? DateTime.fromMillisecondsSinceEpoch(0);

  static DateTime? _dateTimeOrNull(Object? value) {
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  String toString() =>
      'WordCard($word -> $definition, ${distractors.length} distractors)';
}
