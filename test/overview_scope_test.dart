// 学习概览：总概览（排除挂起卡组）与当前卡组两种口径。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/answer_record.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/deck.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/ui/pages/study_page.dart';
import 'package:word_flashcards/src/ui/widgets/section_card.dart';

import 'support/test_harness.dart';

void main() {
  Future<TestHarness> boot(WidgetTester tester, AppSettings settings) async {
    tester.view.physicalSize = const Size(1400, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final TestHarness harness = TestHarness.fake();
    await harness.decks.upsert(Deck(
      id: 'd1',
      name: '第一册',
      createdAt: DateTime(2026, 1, 1),
    ));
    await harness.decks.upsert(Deck(
      id: 'd2',
      name: '第二册',
      createdAt: DateTime(2026, 1, 1),
      suspended: true,
    ));
    await harness.cards.upsertAll(<WordCard>[
      makeCard(id: 'c1', word: 'abandon', mastery: 1, reviewCount: 1),
      makeCard(id: 'c2', word: 'meticulous', deckId: 'd1'),
      makeCard(id: 'c3', word: 'resilient', deckId: 'd2'),
    ]);
    final DateTime now = DateTime.now();
    await harness.records.addAll(<AnswerRecord>[
      AnswerRecord(
        id: 'r1',
        cardId: 'c1',
        selected: 'v. 放弃；抛弃',
        expected: 'v. 放弃；抛弃',
        correct: true,
        reactionMs: 1200,
        answeredAt: now,
        sessionId: 's1',
        deckId: 'default',
      ),
      AnswerRecord(
        id: 'r3',
        cardId: 'c3',
        selected: 'x',
        expected: 'y',
        correct: true,
        reactionMs: 900,
        answeredAt: now,
        sessionId: 's1',
        deckId: 'd2',
      ),
    ]);
    await harness.settings.save(settings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWithValue(harness.cards),
          answerRecordRepositoryProvider.overrideWithValue(harness.records),
          deckRepositoryProvider.overrideWithValue(harness.decks),
          settingsRepositoryProvider.overrideWithValue(harness.settings),
        ],
        child: MaterialApp(
          home: Scaffold(body: StudyPage(onGoToAdd: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  String tile(WidgetTester tester, String label) =>
      tester.widget<StatTile>(find.widgetWithText(StatTile, label)).value;

  testWidgets('总概览：挂起的卡组不算卡片，也不算答题', (tester) async {
    await boot(tester, const AppSettings());

    expect(tile(tester, '卡片总数'), '2');
    expect(tile(tester, '已掌握'), '1');
    expect(tile(tester, '今日答题'), '1');
    expect(find.textContaining('不含已挂起的卡组'), findsWidgets);
  });

  testWidgets('当前卡组：只算这个卡组自己的词与答题', (tester) async {
    final TestHarness harness = await boot(
      tester,
      const AppSettings(activeDeckId: 'd1'),
    );

    expect(tile(tester, '卡片总数'), '2');

    await tester.tap(find.text('当前卡组'));
    await tester.pumpAndSettle();

    expect((await harness.settings.load()).overviewScope, OverviewScope.currentDeck);
    expect(tile(tester, '卡片总数'), '1');
    expect(tile(tester, '今日答题'), '0');
    expect(find.textContaining('范围：第一册'), findsOneWidget);
  });
}
