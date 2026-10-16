// 「本轮到底考哪些词」这件事的纯逻辑：默认整个卡组，需要时再按标签缩小。
//
// 标签筛选只在**原有算法**下生效；FSRS-6 有自己的复习队列，不参与这里的筛选。

import '../domain/models/card_language.dart';
import '../domain/models/word_card.dart';

/// 当前卡组里出现过的标签，出现次数多的排前面；同次数按名称排。
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

/// [tags] 里每个标签这张卡是不是都带着。大小写不敏感，空集合恒为 true。
bool cardHasAllTags(WordCard card, Iterable<String> tags) {
  final Set<String> need = _normalize(tags);
  if (need.isEmpty) return true;
  final Set<String> have = card.displayTags
      .map((String tag) => tag.trim().toLowerCase())
      .toSet();
  return need.every(have.contains);
}

/// 按标签筛词：多个标签取「与」（同时带上才会入选）。
///
/// [tags] 为空（或全是空白）时原样返回整个列表，也就是「不筛」。
List<WordCard> filterCardsByTags(List<WordCard> cards, Iterable<String> tags) {
  if (_normalize(tags).isEmpty) return cards;
  return cards
      .where((WordCard card) => cardHasAllTags(card, tags))
      .toList(growable: false);
}

Set<String> _normalize(Iterable<String> tags) => tags
    .map((String tag) => tag.trim().toLowerCase())
    .where((String tag) => tag.isNotEmpty)
    .toSet();
