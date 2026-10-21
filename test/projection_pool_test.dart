// 演示的词汇来源：先按卡组圈定，再按标签缩小。
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/logic/projection_pool.dart';

import 'support/test_harness.dart';

void main() {
  final List<WordCard> cards = <WordCard>[
    makeCard(id: 'a1', word: 'abandon', deckId: 'd1'),
    makeCard(id: 'a2', word: 'meticulous', deckId: 'd1', tags: <String>['考研']),
    makeCard(id: 'b1', word: 'resilient', deckId: 'd2', tags: <String>['考研', '新词']),
    makeCard(id: 'b2', word: 'suisui', deckId: 'd2'),
  ];

  List<String> ids(ProjectionScope scope) =>
      scope.cards.map((WordCard card) => card.id).toList(growable: false);

  test('当前卡组：跟着作答页选的那个卡组', () {
    final ProjectionScope scope = resolveProjectionScope(
      cards: cards,
      source: ProjectionSource.currentDeck,
      currentDeckId: 'd2',
      chosenDeckIds: const <String>['d1'],
      tags: const <String>[],
    );
    expect(scope.deckId, 'd2');
    expect(ids(scope), <String>['b1', 'b2']);
    expect(scope.deckCards, hasLength(2));
  });

  test('当前卡组是「全部词库」时，整个词库都算', () {
    final ProjectionScope scope = resolveProjectionScope(
      cards: cards,
      source: ProjectionSource.currentDeck,
      currentDeckId: null,
      chosenDeckIds: const <String>['d1'],
      tags: const <String>[],
    );
    expect(scope.deckId, isNull);
    expect(scope.cards, hasLength(4));
  });

  test('全部词库：不管当前卡组与指定卡组', () {
    final ProjectionScope scope = resolveProjectionScope(
      cards: cards,
      source: ProjectionSource.all,
      currentDeckId: 'd1',
      chosenDeckIds: const <String>['d2'],
      tags: const <String>[],
    );
    expect(scope.deckId, isNull);
    expect(scope.cards, hasLength(4));
  });

  test('指定卡组：用它，不用当前卡组', () {
    final ProjectionScope scope = resolveProjectionScope(
      cards: cards,
      source: ProjectionSource.deck,
      currentDeckId: 'd2',
      chosenDeckIds: const <String>['d1'],
      tags: const <String>[],
    );
    expect(scope.deckId, 'd1');
    expect(ids(scope), <String>['a1', 'a2']);
  });

  test('指定卡组还没挑：退回当前卡组，不至于当场放空', () {
    final ProjectionScope scope = resolveProjectionScope(
      cards: cards,
      source: ProjectionSource.deck,
      currentDeckId: 'd2',
      chosenDeckIds: const <String>[],
      tags: const <String>[],
    );
    expect(scope.deckId, 'd2');
    expect(ids(scope), <String>['b1', 'b2']);
  });

  test('标签筛选在卡组范围里生效，多个标签取「与」', () {
    final ProjectionScope scope = resolveProjectionScope(
      cards: cards,
      source: ProjectionSource.all,
      currentDeckId: null,
      chosenDeckIds: const <String>[],
      tags: <String>['考研', '新词'],
    );
    expect(ids(scope), <String>['b1']);
  });

  test('标签候选只来自圈定的卡组，且不受当前标签筛选影响', () {
    final ProjectionScope scope = resolveProjectionScope(
      cards: cards,
      source: ProjectionSource.deck,
      currentDeckId: null,
      chosenDeckIds: const <String>['d2'],
      tags: <String>['考研'],
    );
    // deckTags 按出现次数排，同次数按名称排（「新」在「考」前面）。
    expect(scope.tags, <String>['新词', '考研']);
    expect(ids(scope), <String>['b1']);
  });

  test('筛选到空也算正常结果，界面自己要给提示', () {
    final ProjectionScope scope = resolveProjectionScope(
      cards: cards,
      source: ProjectionSource.deck,
      currentDeckId: null,
      chosenDeckIds: const <String>['d1'],
      tags: <String>['新词'],
    );
    expect(scope.cards, isEmpty);
    expect(scope.deckCards, hasLength(2));
  });

  test('指定多个卡组：取并集', () {
    final ProjectionScope scope = resolveProjectionScope(
      cards: cards,
      source: ProjectionSource.deck,
      currentDeckId: null,
      chosenDeckIds: const <String>['d1', 'd2'],
      tags: const <String>[],
    );
    expect(scope.deckIds, <String>['d1', 'd2']);
    expect(scope.cards, hasLength(4));
    // 多个卡组时没有「单个卡组」可写进答案文件抬头。
    expect(scope.deckId, isNull);
  });

  test('老设置里的单个 projection_deck_id 会读成一个元素的列表', () {
    final AppSettings back = AppSettings.fromMap(<String, Object?>{
      'projection_source': 'deck',
      'projection_deck_id': 'd2',
    });
    expect(back.projectionDeckIds, <String>['d2']);
  });

  test('设置里的来源与标签会原样存下来', () {
    const AppSettings settings = AppSettings(
      projectionSource: ProjectionSource.deck,
      projectionDeckIds: <String>['d2', 'd3'],
      projectionTagFilter: <String>['考研', '新词'],
    );
    final AppSettings back = AppSettings.fromMap(settings.toMap());
    expect(back.projectionSource, ProjectionSource.deck);
    expect(back.projectionDeckIds, <String>['d2', 'd3']);
    expect(back.projectionTagFilter, <String>['考研', '新词']);
  });

  test('老设置没有这几个键：默认跟随当前卡组、不筛标签', () {
    final AppSettings back = AppSettings.fromMap(<String, Object?>{
      'home_tab': 'study',
    });
    expect(back.projectionSource, ProjectionSource.currentDeck);
    expect(back.projectionDeckIds, isEmpty);
    expect(back.projectionTagFilter, isEmpty);
  });
}
