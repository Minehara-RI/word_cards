// 「所有新词都进当前卡组，只有用户主动换组/开新组才重开卡组」这条规则。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/domain/models/card_language.dart';
import 'package:word_cards/src/domain/models/deck.dart';
import 'package:word_cards/src/domain/models/word_card.dart';
import 'package:word_cards/src/state/providers.dart';
import 'package:word_cards/src/ui/pages/add_page.dart';

import 'support/test_harness.dart';

void main() {
  Future<TestHarness> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final TestHarness harness = TestHarness.fake();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWithValue(harness.cards),
          answerRecordRepositoryProvider.overrideWithValue(harness.records),
          deckRepositoryProvider.overrideWithValue(harness.decks),
          settingsRepositoryProvider.overrideWithValue(harness.settings),
        ],
        child: const MaterialApp(home: Scaffold(body: AddPage())),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  Future<void> fillWord(WidgetTester tester, String word, String meaning) async {
    await tester.enterText(
      find.widgetWithText(TextField, '单词 *'),
      word,
    );
    await tester.enterText(
      find.widgetWithText(TextField, '释义 *'),
      meaning,
    );
  }

  Future<void> createDeck(WidgetTester tester, String name) async {
    await tester.tap(find.text('开启新卡组'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-deck-name')), name);
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
  }

  testWidgets('默认是全部词库，新词进默认卡组', (tester) async {
    final TestHarness harness = await boot(tester);
    expect(find.text('当前卡组'), findsOneWidget);
    expect(find.textContaining('全部词库'), findsWidgets);

    await fillWord(tester, 'abandon', 'v. 放弃；抛弃');
    await tester.tap(find.textContaining('加入「'));
    await tester.pumpAndSettle();

    final List<WordCard> cards = await harness.cards.getAll();
    expect(cards, hasLength(1));
    expect(cards.single.deckId, Deck.defaultDeckId);
  });

  testWidgets('开启新卡组后，之后加的单词都进新卡组', (tester) async {
    final TestHarness harness = await boot(tester);

    await createDeck(tester, '日语 N2');
    final List<Deck> decks = await harness.decks.getAll();
    expect(decks.map((Deck deck) => deck.name), contains('日语 N2'));
    final String deckId = (await harness.settings.load()).activeDeckId!;
    expect(deckId, isNot(Deck.defaultDeckId));
    expect(find.text('日语 N2'), findsWidgets);

    // 现在填一张卡：应该落到新卡组里，标签和语言也要带上
    await fillWord(tester, 'すいえい', 'n. 游泳');
    await tester.enterText(find.byKey(const Key('add-tags-field')), 'N2，第1课');
    await tester.tap(find.widgetWithText(ChoiceChip, '日语'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入卡片'));
    await tester.pumpAndSettle();

    final List<WordCard> cards = await harness.cards.getAll();
    expect(cards, hasLength(1));
    expect(cards.single.word, 'すいえい');
    expect(cards.single.deckId, deckId);
    expect(cards.single.language, CardLanguage.japanese);
    expect(cards.single.tags, <String>['N2', '第1课']);
  });

  testWidgets('更换卡组：能选回默认卡组，也能选全部词库', (tester) async {
    final TestHarness harness = await boot(tester);
    await createDeck(tester, '法语 A1');

    await tester.tap(find.text('更换卡组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('默认词库'));
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).activeDeckId, Deck.defaultDeckId);

    await tester.tap(find.text('更换卡组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部词库'));
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).activeDeckId, isNull);
  });
}