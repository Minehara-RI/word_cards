import 'answer_record.dart';
import 'deck.dart';
import 'word_card.dart';

/// 一条「删除记录」。
///
/// 为什么需要它：卡片在两边都有自己的整数 note id（Anki 的主键是设备本地的），
/// 所以「这台机器上删了」没法让对方知道该删哪一条。按 uid 记一条墓碑，
/// 合并时才能把删除这件事也同步过去，而不是被对方的数据原样复活。
class SyncTombstone {
  const SyncTombstone({
    required this.uid,
    required this.deletedAt,
    this.kind = kindCard,
    this.deckUid,
  });

  /// 删除的是卡片（按卡片 uid）。
  static const String kindCard = 'card';

  /// 删除的是整个卡组（按卡组 uid）。卡组里的卡会被挪回默认卡组。
  static const String kindDeck = 'deck';

  final String uid;
  final String kind;
  final String? deckUid;
  final DateTime deletedAt;

  bool get isDeck => kind == kindDeck;

  Map<String, Object?> toMap() => <String, Object?>{
        'uid': uid,
        'kind': kind,
        'deck_uid': deckUid,
        'deleted_at': deletedAt.millisecondsSinceEpoch,
      };

  factory SyncTombstone.fromMap(Map<String, Object?> map) => SyncTombstone(
        uid: (map['uid'] as String?) ?? '',
        kind: (map['kind'] as String?) ?? kindCard,
        deckUid: map['deck_uid'] as String?,
        deletedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['deleted_at'] as num?)?.toInt() ?? 0,
        ),
      );

  @override
  String toString() => 'SyncTombstone($kind $uid @ ${deletedAt.toIso8601String()})';
}

/// 一次同步交换的完整内容：一个设备上「全部有意义的」数据。
///
/// 这里刻意不做增量：整库现在只有几 MB，全量交换一次就能收敛，
/// 不用维护变更日志、也不用考虑日志被截断之后怎么补。
class SyncSnapshot {
  const SyncSnapshot({
    required this.deviceId,
    required this.deviceName,
    required this.generatedAt,
    this.decks = const <Deck>[],
    this.cards = const <WordCard>[],
    this.answers = const <AnswerRecord>[],
    this.tombstones = const <SyncTombstone>[],
  });

  /// 同步包的格式标记。以后改协议先看这个字段，不认就直接报错。
  static const String format = 'word_flashcards_sync';

  /// 协议版本。两端版本不一致时宁可拒绝，也不要写坏数据。
  static const int protocol = 1;

  final String deviceId;
  final String deviceName;
  final DateTime generatedAt;
  final List<Deck> decks;
  final List<WordCard> cards;
  final List<AnswerRecord> answers;
  final List<SyncTombstone> tombstones;

  int get size => cards.length + decks.length + answers.length;

  SyncSnapshot copyWith({
    String? deviceId,
    String? deviceName,
    DateTime? generatedAt,
    List<Deck>? decks,
    List<WordCard>? cards,
    List<AnswerRecord>? answers,
    List<SyncTombstone>? tombstones,
  }) =>
      SyncSnapshot(
        deviceId: deviceId ?? this.deviceId,
        deviceName: deviceName ?? this.deviceName,
        generatedAt: generatedAt ?? this.generatedAt,
        decks: decks ?? this.decks,
        cards: cards ?? this.cards,
        answers: answers ?? this.answers,
        tombstones: tombstones ?? this.tombstones,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'format': format,
        'protocol': protocol,
        'device_id': deviceId,
        'device_name': deviceName,
        'generated_at': generatedAt.millisecondsSinceEpoch,
        'decks': decks.map((Deck deck) => deck.toMap()).toList(growable: false),
        'cards': cards.map((WordCard card) => card.toMap()).toList(growable: false),
        'answers':
            answers.map((AnswerRecord record) => record.toMap()).toList(growable: false),
        'tombstones': tombstones
            .map((SyncTombstone stone) => stone.toMap())
            .toList(growable: false),
      };

  /// 解析对方发来的同步包。字段缺失按空处理，格式标记不对就抛
  /// [FormatException]（带一句人话，界面直接显示）。
  factory SyncSnapshot.fromJson(Map<String, Object?> json) {
    if (json['format'] != format) {
      throw const FormatException('这不是单词卡片的同步包');
    }
    final int protocol = (json['protocol'] as num?)?.toInt() ?? 1;
    if (protocol != SyncSnapshot.protocol) {
      throw FormatException(
        '对方的同步协议是第 $protocol 版，这个版本只认第 ${SyncSnapshot.protocol} 版；'
        '先把两台设备升级到同一个版本',
      );
    }
    return SyncSnapshot(
      deviceId: (json['device_id'] as String?) ?? '',
      deviceName: (json['device_name'] as String?) ?? '另一台设备',
      generatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['generated_at'] as num?)?.toInt() ?? 0,
      ),
      decks: _objects(json['decks'])
          .map((Map<String, Object?> map) => Deck.fromMap(map))
          .toList(growable: false),
      cards: _objects(json['cards'])
          .map((Map<String, Object?> map) => WordCard.fromMap(map))
          .toList(growable: false),
      answers: _objects(json['answers'])
          .map((Map<String, Object?> map) => AnswerRecord.fromMap(map))
          .toList(growable: false),
      tombstones: _objects(json['tombstones'])
          .map((Map<String, Object?> map) => SyncTombstone.fromMap(map))
          .toList(growable: false),
    );
  }

  static List<Map<String, Object?>> _objects(Object? value) {
    if (value is! List) return const <Map<String, Object?>>[];
    return value
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> map) => map.cast<String, Object?>())
        .toList(growable: false);
  }

  @override
  String toString() =>
      'SyncSnapshot($deviceName $deviceId, ${cards.length} 张卡, ${decks.length} 个卡组)';
}
