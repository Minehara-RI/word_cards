// 「这一场演示放哪些词」的纯逻辑：先按卡组圈定范围（多选并集），再按标签缩小。
//
// 演示和「作答」各记一份选择。老师备课时常常要放别的班刚学的那一组，
// 不该顺手把作答页的卡组也改掉，所以这里不去读 selectedDeck 的持久化值，
// 当前卡组只作为「跟随」这一档的输入。
//
// 和作答页有一处**故意**的不同：演示不排除已挂起的卡组。
// 挂起是「这段时间不安排复习」，不是「不许出现在课堂上」。

import '../domain/models/app_settings.dart';
import '../domain/models/word_card.dart';
import 'study_pool.dart';

/// 演示的词汇来源解析结果。
class ProjectionScope {
  const ProjectionScope({
    required this.deckIds,
    required this.deckCards,
    required this.cards,
    required this.tags,
  });

  /// 圈定的卡组（并集）；null 表示整个词库。
  final List<String>? deckIds;

  /// 这些卡组里的全部词（还没按标签筛）。
  final List<WordCard> deckCards;

  /// 最终出题池：卡组范围再按标签筛过一遍。
  final List<WordCard> cards;

  /// 这些卡组里出现过的标签（筛选面板的候选）。
  final List<String> tags;

  /// 只圈了一个卡组时给出它的 id，否则为 null（写答案文件的抬头用）。
  String? get deckId {
    final List<String>? ids = deckIds;
    if (ids == null || ids.length != 1) return null;
    return ids.single;
  }

  /// 整个词库都算。
  bool get isWholeLibrary => deckIds == null;
}

/// 按设置算出这一场演示的出题池。
///
/// [chosenDeckIds] 只在 [ProjectionSource.deck] 下有意义；为空表示
/// 「还没挑」，退回当前卡组，不至于当场放空。指向已被删掉的卡组时
/// 那些 id 不会匹配到任何词，池子自然变小，不会报错。
ProjectionScope resolveProjectionScope({
  required List<WordCard> cards,
  required ProjectionSource source,
  required String? currentDeckId,
  required Iterable<String> chosenDeckIds,
  required Iterable<String> tags,
  TagMatchMode match = TagMatchMode.all,
}) {
  final List<String> chosen = chosenDeckIds.toList(growable: false);
  final List<String>? deckIds = switch (source) {
    ProjectionSource.all => null,
    ProjectionSource.currentDeck =>
      currentDeckId == null ? null : <String>[currentDeckId],
    ProjectionSource.deck => chosen.isEmpty
        ? (currentDeckId == null ? null : <String>[currentDeckId])
        : chosen,
  };

  final List<WordCard> deckCards =
      deckIds == null ? List<WordCard>.unmodifiable(cards) : cardsInDecks(cards, deckIds);

  return ProjectionScope(
    deckIds: deckIds,
    deckCards: deckCards,
    cards: filterCardsByTags(deckCards, tags, match: match),
    tags: deckTags(deckCards),
  );
}
