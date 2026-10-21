// 「本轮到底考哪些词」这件事的纯逻辑：先按卡组圈定范围（多选并集），
// 再按标签缩小（并集或交集）。
//
// 卡组筛选与标签筛选对两套算法都生效：FSRS-6 也是先筛出候选词，
// 再按记忆状态排序 —— 「这一轮只考第四单元」在哪套算法下都得算数。

import '../domain/models/app_settings.dart';
import '../domain/models/card_language.dart';
import '../domain/models/deck.dart';
import '../domain/models/word_card.dart';

/// 当前范围里出现过的标签，出现次数多的排前面；同次数按名称排。
///
/// 语言标签（lang::en 这种）不算用户标签，不进候选。
List<String> deckTags(List<WordCard> cards, {int limit = 40}) {
  final Map<String, int> counts = <String, int>{};
  final Map<String, String> labels = <String, String>{};

  for (final WordCard card in cards) {
    for (final String raw in card.displayTags) {
      if (CardLanguage.isLanguageTag(raw)) continue;
      final String key = raw.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
      labels.putIfAbsent(key, () => raw);
    }
  }

  final List<String> keys = counts.keys.toList(growable: false)
    ..sort((String a, String b) {
      final int byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });

  return keys.take(limit).map((String key) => labels[key]!).toList(growable: false);
}

Set<String> _normalize(Iterable<String> tags) => tags
    .map((String tag) => tag.trim().toLowerCase())
    .where((String tag) => tag.isNotEmpty)
    .toSet();

/// [tags] 里每个标签这张卡是不是都带着。大小写不敏感，空集合恒为 true。
bool cardHasAllTags(WordCard card, Iterable<String> tags) {
  final Set<String> need = _normalize(tags);
  if (need.isEmpty) return true;
  final Set<String> have = card.displayTags
      .map((String tag) => tag.trim().toLowerCase())
      .toSet();
  return need.every(have.contains);
}

/// [tags] 里任意一个标签这张卡是不是带着。空集合恒为 true。
bool cardHasAnyTag(WordCard card, Iterable<String> tags) {
  final Set<String> need = _normalize(tags);
  if (need.isEmpty) return true;
  final Set<String> have = card.displayTags
      .map((String tag) => tag.trim().toLowerCase())
      .toSet();
  return need.any(have.contains);
}

/// 按标签筛词。
///
/// [match] 决定多个标签之间取「并集」（任一命中）还是「交集」（全部命中）。
/// 默认取交集，保持老调用点的行为；界面上传的是设置里那一档。
///
/// [tags] 为空（或全是空白）时原样返回整个列表，也就是「不筛」。
List<WordCard> filterCardsByTags(
  List<WordCard> cards,
  Iterable<String> tags, {
  TagMatchMode match = TagMatchMode.all,
}) {
  if (_normalize(tags).isEmpty) return cards;
  final bool any = match == TagMatchMode.any;
  return cards
      .where((WordCard card) =>
          any ? cardHasAnyTag(card, tags) : cardHasAllTags(card, tags))
      .toList(growable: false);
}

/// 这些卡组里的全部词（并集）。[deckIds] 为空时不筛，原样返回。
List<WordCard> cardsInDecks(List<WordCard> cards, Iterable<String> deckIds) {
  final Set<String> ids = deckIds.toSet();
  if (ids.isEmpty) return cards;
  return cards
      .where((WordCard card) => ids.contains(card.deckId))
      .toList(growable: false);
}

/// 一轮作答的选题范围。
class StudyScope {
  const StudyScope({
    required this.deckIds,
    required this.deckCards,
    required this.cards,
    required this.tags,
    required this.followedCurrentDeck,
    required this.suspendedDeckCount,
    required this.selectedDeckSuspended,
  });

  /// 实际参与出题的卡组（并集）。空列表表示一个词都选不出来。
  final List<String> deckIds;

  /// 这些卡组里的全部词（还没按标签筛）。
  final List<WordCard> deckCards;

  /// 最终出题池：卡组范围再按标签筛过一遍。
  final List<WordCard> cards;

  /// 这些卡组里出现过的标签（筛选面板的候选）。
  final List<String> tags;

  /// 没手动勾卡组、跟着「当前卡组」走。
  final bool followedCurrentDeck;

  /// 词库里一共有多少个卡组被挂起（界面上提一句就够了）。
  final int suspendedDeckCount;

  /// 跟着走下去的那个当前卡组自己就被挂起了 —— 这时候池子必然是空的，
  /// 界面要说法不一样（不是「没有词」，而是「这个卡组被挂起了」）。
  final bool selectedDeckSuspended;
}

/// 按设置算出这一轮作答的出题范围。
///
/// 规则：
/// - [selectedDeckIds] 非空：这些卡组的并集，已挂起的、已经被删掉的自动剔除；
/// - 为空：跟随 [currentDeckId]（null 表示「全部词库」）；
/// - 「全部词库」也只算**没挂起**的卡组 —— 挂起的卡组就是「这阵子不学它」。
StudyScope resolveStudyScope({
  required List<WordCard> allCards,
  required List<Deck> decks,
  required List<String> selectedDeckIds,
  required String? currentDeckId,
  required Iterable<String> tags,
  required TagMatchMode match,
}) {
  final Set<String> known = decks.map((Deck deck) => deck.id).toSet();
  final Set<String> suspended = <String>{
    for (final Deck deck in decks)
      if (deck.suspended) deck.id,
  };

  // 卡组列表里没有的 deckId 也要算：Anki 侧新建的牌组还没被认领时，
  // 里面的词不该因为「卡组不存在」就从「全部词库」里消失。
  final List<String> orphanDeckIds = <String>[
    for (final WordCard card in allCards)
      if (!known.contains(card.deckId) && !suspended.contains(card.deckId))
        card.deckId,
  ];

  bool followedCurrentDeck = false;
  bool selectedDeckSuspended = false;
  List<String> deckIds;

  if (selectedDeckIds.isNotEmpty) {
    deckIds = <String>[
      for (final String id in selectedDeckIds)
        if (!suspended.contains(id) && (known.contains(id) || _hasDeck(allCards, id)))
          id,
    ];
  } else if (currentDeckId != null) {
    followedCurrentDeck = true;
    selectedDeckSuspended = suspended.contains(currentDeckId);
    deckIds = selectedDeckSuspended ? <String>[] : <String>[currentDeckId];
  } else {
    deckIds = <String>[
      for (final Deck deck in decks)
        if (!deck.suspended) deck.id,
      ...orphanDeckIds,
    ];
  }

  final Set<String> uniqueDeckIds = <String>{...deckIds};
  // 空集合是「一个卡组都不算」，不是「不筛」——cardsInDecks 把空集合当成
  // 不筛（给「全部词库」用），这里的空必须显式处理。
  final List<WordCard> deckCards = uniqueDeckIds.isEmpty
      ? const <WordCard>[]
      : cardsInDecks(allCards, uniqueDeckIds);

  return StudyScope(
    deckIds: uniqueDeckIds.toList(growable: false),
    deckCards: deckCards,
    cards: filterCardsByTags(deckCards, tags, match: match),
    tags: deckTags(deckCards),
    followedCurrentDeck: followedCurrentDeck,
    suspendedDeckCount: suspended.length,
    selectedDeckSuspended: selectedDeckSuspended,
  );
}

bool _hasDeck(List<WordCard> cards, String deckId) =>
    cards.any((WordCard card) => card.deckId == deckId);
