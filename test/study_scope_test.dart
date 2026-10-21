// 作答范围：卡组并集、挂起排除、标签并集/交集。
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/deck.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/logic/study_pool.dart';

import 'support/test_harness.dart';

void main() {
  final List<Deck> decks = <Deck>[
    Deck(id: 'default', name: '默认词库', createdAt: DateTime(2026, 1, 1)),
    Deck(id: 'd1', name: '第一册', createdAt: DateTime(2026, 1, 1)),
    Deck(id: 'd2', name: '第二册', createdAt: DateTime(2026, 1, 1)),
    Deck(
      id: 'd3',
      name: '第三册',
      createdAt: DateTime(2026, 1, 1),
      suspended: true,
    ),
  ];

  final List<WordCard> cards = <WordCard>[
    makeCard(id: 'a', word: 'abandon', tags: const <String>['第四单元']),
    makeCard(
      id: 'b',
      word: 'meticulous',
      deckId: 'd1',
      tags: const <String>['第四单元', '高频'],
    ),
    makeCard(id: 'c', word: 'resilient', deckId: 'd2', tags: const <String>['高频']),
    makeCard(id: 'd', word: 'loyal', deckId: 'd3', tags: const <String>['第四单元']),
  ];

  List<String> ids(StudyScope scope) =>
      scope.cards.map((WordCard card) => card.id).toList(growable: false);

  StudyScope resolve({
    List<String> selectedDeckIds = const <String>[],
    String? currentDeckId,
    List<String> tags = const <String>[],
    TagMatchMode match = TagMatchMode.all,
    List<WordCard>? allCards,
    List<Deck>? allDecks,
  }) =>
      resolveStudyScope(
        allCards: allCards ?? cards,
        decks: allDecks ?? decks,
        selectedDeckIds: selectedDeckIds,
        currentDeckId: currentDeckId,
        tags: tags,
        match: match,
      );

  test('没勾卡组时跟随当前卡组', () {
    final StudyScope scope = resolve(currentDeckId: 'd1');
    expect(scope.followedCurrentDeck, isTrue);
    expect(scope.deckIds, <String>['d1']);
    expect(ids(scope), <String>['b']);
  });

  test('当前是「全部词库」：挂起的卡组不参与', () {
    final StudyScope scope = resolve();
    expect(scope.deckIds, containsAll(<String>['default', 'd1', 'd2']));
    expect(scope.deckIds, isNot(contains('d3')));
    expect(ids(scope), <String>['a', 'b', 'c']);
    expect(scope.suspendedDeckCount, 1);
  });

  test('手动勾卡组：取并集，挂起的不算', () {
    final StudyScope scope = resolve(selectedDeckIds: <String>['d1', 'd2']);
    expect(scope.followedCurrentDeck, isFalse);
    expect(ids(scope), <String>['b', 'c']);

    // 勾了挂起的卡组：直接剔除，不静默把它的词放进来
    final StudyScope withSuspended =
        resolve(selectedDeckIds: <String>['d1', 'd3']);
    expect(ids(withSuspended), <String>['b']);
  });

  test('当前卡组自己被挂起：池子空，界面要说清楚', () {
    final StudyScope scope = resolve(currentDeckId: 'd3');
    expect(scope.cards, isEmpty);
    expect(scope.selectedDeckSuspended, isTrue);
  });

  test('标签取并集', () {
    final StudyScope scope = resolve(
      tags: <String>['第四单元', '高频'],
      match: TagMatchMode.any,
    );
    expect(ids(scope), <String>['a', 'b', 'c']);
  });

  test('标签取交集', () {
    final StudyScope scope = resolve(
      tags: <String>['第四单元', '高频'],
      match: TagMatchMode.all,
    );
    expect(ids(scope), <String>['b']);
  });

  test('卡组列表里还没有的 deckId 也算进「全部词库」', () {
    final List<WordCard> extra = <WordCard>[
      ...cards,
      makeCard(id: 'x', word: 'orphan', deckId: 'not-yet-adopted'),
    ];
    final StudyScope scope = resolve(allCards: extra);
    expect(ids(scope), contains('x'));
  });

  test('标签候选只来自筛完的范围，且不受已选标签影响', () {
    final StudyScope scope = resolve(
      selectedDeckIds: <String>['d2'],
      tags: <String>['高频'],
    );
    expect(scope.tags, <String>['高频']);
    expect(scope.deckCards, hasLength(1));
    expect(ids(scope), <String>['c']);
  });

  test('被删掉的卡组 id 不会造成空范围', () {
    final StudyScope scope = resolve(
      selectedDeckIds: <String>['gone'],
      currentDeckId: 'd1',
    );
    expect(scope.cards, isEmpty);
    expect(scope.followedCurrentDeck, isFalse);
  });
}
