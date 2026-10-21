/// 词库：一组卡片的集合，例如“考研词汇”“雅思词汇”。
class Deck {
  const Deck({
    required this.id,
    required this.name,
    required this.createdAt,
    this.suspended = false,
  });

  /// 默认词库的固定 id，兼容没有词库概念时导入的卡片。
  static const String defaultDeckId = 'default';
  static const String defaultDeckName = '默认词库';

  final String id;
  final String name;
  final DateTime createdAt;

  /// 卡组被「挂起」：不作答、不进学习概览，但演示照样能选。
  ///
  /// 挂起是**学习范围**上的开关，不是删除：词、进度、设置全都原地不动，
  /// 点一下「恢复」就回来。暑假想暂时搁置某个学期的词表时用它。
  final bool suspended;

  factory Deck.fallback() => Deck(
        id: defaultDeckId,
        name: defaultDeckName,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  Deck copyWith({String? name, bool? suspended}) => Deck(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        suspended: suspended ?? this.suspended,
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'name': name,
        'created_at': createdAt.millisecondsSinceEpoch,
        'suspended': suspended ? 1 : 0,
      };

  static Deck fromMap(Map<String, Object?> map) => Deck(
        id: map['id']! as String,
        name: (map['name'] as String?) ?? defaultDeckName,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as num?)?.toInt() ?? 0,
        ),
        suspended: (map['suspended'] as num?)?.toInt() == 1,
      );

  @override
  String toString() => 'Deck($id, $name, suspended: $suspended)';
}
