// 卡组管理：「重置」只清学习进度，「删除」连词一起删。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/domain/models/answer_record.dart';
import 'package:word_cards/src/domain/models/deck.dart';
import 'package:word_cards/src/domain/models/word_card.dart';
import 'package:word_cards/src/ui/pages/settings_page.dart';
import 'package:word_cards/src/ui/platform_target.dart';

import 'support/test_harness.dart';

void main() {
  group('仓储层', () {
    late TestHarness harness;

    setUp(() async {
      harness = await TestHarness.create();
    });

    tearDown(() async {
      await harness.dispose();
    });

    Future<void> seed() async {
      await harness.decks.upsert(Deck(
        id: 'd1',
        name: '新必修一',
        createdAt: DateTime(2026, 1, 1),
      ));
      await harness.decks.upsert(Deck(
        id: 'd2',
        name: '新必修二',
        createdAt: DateTime(2026, 1, 1),
      ));
      await harness.cards.upsert(makeCard(
        id: 'c1',
        word: 'abandon',
        deckId: 'd1',
        reviewCount: 3,
        correctCount: 2,
        mastery: 0.7,
      ));
      await harness.cards.upsert(makeCard(
        id: 'c2',
        word: 'meticulous',
        deckId: 'd2',
        reviewCount: 5,
        correctCount: 5,
        mastery: 1,
      ));
      for (final String id in <String>['c1', 'c2']) {
        await harness.records.add(AnswerRecord(
          id: 'r-$id',
          cardId: id,
          selected: 'x',
          expected: 'y',
          correct: true,
          reactionMs: 1000,
          answeredAt: DateTime(2026, 3, 1),
          sessionId: 's1',
          deckId: id == 'c1' ? 'd1' : 'd2',
        ));
      }
    }

    test('重置一个卡组：词还在，进度清零，别的卡组不动', () async {
      await seed();
      await harness.cards.resetProgress(deckId: 'd1');

      final WordCard d1 = (await harness.cards.getAll(deckId: 'd1')).single;
      expect(d1.reviewCount, 0);
      expect(d1.correctCount, 0);
      expect(d1.mastery, 0);
      expect(d1.lastReviewedAt, isNull);

      final WordCard d2 = (await harness.cards.getAll(deckId: 'd2')).single;
      expect(d2.reviewCount, 5);
      expect(d2.mastery, 1);

      final List<AnswerRecord> records = await harness.records.getAll();
      expect(records.map((AnswerRecord r) => r.cardId).toList(), <String>['c2']);
    });

    test('重置整个词库', () async {
      await seed();
      await harness.cards.resetProgress();
      final List<WordCard> cards = await harness.cards.getAll();
      expect(cards, hasLength(2));
      expect(cards.every((WordCard c) => c.reviewCount == 0), isTrue);
      expect(await harness.records.getAll(), isEmpty);
    });

    test('删除卡组会把里面的词一起删掉', () async {
      await seed();
      await harness.cards.deleteAll(deckId: 'd2');
      await harness.decks.delete('d2');

      expect(
        (await harness.decks.getAll()).map((Deck d) => d.id),
        isNot(contains('d2')),
      );
      expect(await harness.cards.getAll(deckId: 'd2'), isEmpty);
      expect(await harness.cards.getAll(deckId: 'd1'), hasLength(1));
    });

    test('默认卡组删不掉', () async {
      final TestHarness h = await TestHarness.create();
      addTearDown(h.dispose);
      await h.decks.delete(Deck.defaultDeckId);
      expect(
        (await h.decks.getAll()).map((Deck d) => d.id),
        contains(Deck.defaultDeckId),
      );
    });
  });

  group('设置页', () {
    testWidgets('列出卡组与词数，删除要过一次确认', (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final TestHarness harness = TestHarness.fake();
      await harness.decks.upsert(Deck(
        id: 'd2',
        name: '新必修一',
        createdAt: DateTime(2026, 1, 1),
      ));
      await harness.cards.upsert(makeCard(id: 'c1', word: 'abandon', deckId: 'd2'));

      await tester.pumpWidget(harness.wrap(MaterialApp(
        home: SettingsPage(target: PlatformTarget.mobile),
      )));
      await tester.pumpAndSettle();

      expect(find.text('管理卡组'), findsOneWidget);
      expect(find.byKey(const Key('deck-row-d2')), findsOneWidget);
      expect(find.text('1 个词'), findsOneWidget);

      final Finder deleteButton = find.byKey(const Key('deck-delete-d2'));
      await tester.scrollUntilVisible(
        deleteButton,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      expect(find.text('删除卡组「新必修一」？'), findsOneWidget);

      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deck-row-d2')), findsNothing);
      expect(await harness.cards.getAll(), isEmpty);
      expect(
        (await harness.decks.getAll()).map((Deck d) => d.id),
        isNot(contains('d2')),
      );
    });
  });
}
