// 非 FSRS 下的选题范围：默认整个卡组，需要时再按标签缩小（多标签取「与」）。
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/logic/study_pool.dart';

import 'support/test_harness.dart';

void main() {
  group('卡组里的标签', () {
    test('出现次数多的排前面，同名不同大小写算一个', () {
      final List<WordCard> cards = <WordCard>[
        makeCard(id: 'c1', word: 'abandon', tags: const <String>['第四单元']),
        makeCard(id: 'c2', word: 'meticulous', tags: const <String>['第四单元']),
        makeCard(id: 'c3', word: 'resilient', tags: const <String>['E2E']),
        makeCard(id: 'c4', word: 'loyal', tags: const <String>['e2e']),
      ];

      // 两个标签都是 2 次，按名称排；大小写只用来判重，展示第一次见到的写法
      expect(deckTags(cards), <String>['E2E', '第四单元']);
    });

    test('语言标签不算用户标签', () {
      final List<WordCard> cards = <WordCard>[
        makeCard(id: 'c1', word: 'abandon', tags: const <String>['lang::ja', '第四单元']),
        makeCard(id: 'c2', word: 'meticulous', tags: const <String>['lang::en']),
      ];
      expect(deckTags(cards), <String>['第四单元']);
    });

    test('空标签不会被当成候选', () {
      final List<WordCard> cards = <WordCard>[
        makeCard(id: 'c1', word: 'abandon', tags: const <String>['  ', '']),
      ];
      expect(deckTags(cards), isEmpty);
    });
  });

  group('按标签筛词', () {
    final List<WordCard> cards = <WordCard>[
      makeCard(id: 'c1', word: 'abandon', tags: const <String>['第四单元']),
      makeCard(id: 'c2', word: 'meticulous', tags: const <String>['第四单元', 'E2E']),
      makeCard(id: 'c3', word: 'resilient', tags: const <String>['E2E']),
      makeCard(id: 'c4', word: 'loyal'),
    ];

    List<String> words(List<WordCard> list) =>
        list.map((WordCard card) => card.word).toList();

    test('不选标签就是整个卡组', () {
      expect(filterCardsByTags(cards, const <String>[]), same(cards));
      expect(filterCardsByTags(cards, const <String>['   ']), same(cards));
    });

    test('选一个标签只出带这个标签的词', () {
      expect(words(filterCardsByTags(cards, const <String>['第四单元'])),
          <String>['abandon', 'meticulous']);
    });

    test('选多个标签要同时带上（与）', () {
      expect(words(filterCardsByTags(cards, const <String>['第四单元', 'E2E'])),
          <String>['meticulous']);
      expect(
        filterCardsByTags(cards, const <String>['第四单元', 'E2E', '没有这个标签']),
        isEmpty,
      );
    });

    test('标签比对不区分大小写', () {
      expect(words(filterCardsByTags(cards, const <String>['e2e'])),
          <String>['meticulous', 'resilient']);
    });

    test('cardHasAllTags：空集合恒为真', () {
      expect(cardHasAllTags(cards.first, const <String>[]), isTrue);
      expect(cardHasAllTags(cards.first, const <String>['第四单元']), isTrue);
      expect(cardHasAllTags(cards.first, const <String>['E2E']), isFalse);
    });
  });
}
