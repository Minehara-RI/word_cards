/// 词库：一组卡片的集合，例如“考研词汇”“雅思词汇”。
class Deck {
  const Deck({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  /// 默认词库的固定 id，兼容没有词库概念时导入的卡片。
  static const String defaultDeckId = 'default';
  static const String defaultDeckName = '默认词库';

  final String id;
  final String name;
  final DateTime createdAt;

  factory Deck.fallback() => Deck(
        id: defaultDeckId,
        name: defaultDeckName,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  Deck copyWith({String? name}) => Deck(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  static Deck fromMap(Map<String, Object?> map) => Deck(
        id: map['id']! as String,
        name: (map['name'] as String?) ?? defaultDeckName,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as num?)?.toInt() ?? 0,
        ),
      );

  @override
  String toString() => 'Deck($id, $name)';
}
