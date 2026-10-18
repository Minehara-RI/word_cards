// 「这一场演示放哪些词」的纯逻辑：先按卡组圈定范围，再按标签缩小。
//
// 演示和「作答」各记一份选择。老师备课时常常要放别的班刚学的那一组，
// 不该顺手把作答页的卡组也改掉，所以这里不去读 selectedDeck 的持久化值，
// 当前卡组只作为「跟随」这一档的输入。

import '../domain/models/app_settings.dart';
import '../domain/models/word_card.dart';
import 'study_pool.dart';

/// 演示的词汇来源解析结果。
class ProjectionScope {
  const ProjectionScope({
    required this.deckId,
    required this.deckCards,
    required this.cards,
    required this.tags,
  });

  /// 圈定的卡组；null 表示整个词库。
  final String? deckId;

  /// 这个卡组里的全部词（还没按标签筛）。
  final List<WordCard> deckCards;

  /// 最终出题池：卡组范围再按标签筛过一遍。
  final List<WordCard> cards;

  /// 这个卡组里出现过的标签（筛选面板的候选）。
  final List<String> tags;
}

/// 按设置算出这一场演示的出题池。
///
/// [chosenDeckId] 只在 [ProjectionSource.deck] 下有意义；它指向一个已经不存在的
/// 卡组时按「还没挑」处理，退回当前卡组，不至于当场放空。
ProjectionScope resolveProjectionScope({
  required List<WordCard> cards,
  required ProjectionSource source,
  required String? currentDeckId,
  required String? chosenDeckId,
  required Iterable<String> tags,
}) {
  final String? deckId = switch (source) {
    ProjectionSource.all => null,
    ProjectionSource.currentDeck => currentDeckId,
    ProjectionSource.deck => chosenDeckId ?? currentDeckId,
  };

  final List<WordCard> deckCards = deckId == null
      ? List<WordCard>.unmodifiable(cards)
      : cards
          .where((WordCard card) => card.deckId == deckId)
          .toList(growable: false);

  return ProjectionScope(
    deckId: deckId,
    deckCards: deckCards,
    cards: filterCardsByTags(deckCards, tags),
    tags: deckTags(deckCards),
  );
}
