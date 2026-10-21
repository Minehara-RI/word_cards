// 作答页的筛选：卡组多选并集、标签并集/交集、自定义题数。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/deck.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/ui/pages/study_page.dart';

import 'support/test_harness.dart';

List<WordCard> taggedCards() => <WordCard>[
      makeCard(id: 'c1', word: 'abandon', tags: const <String>['第四单元']),
      makeCard(
        id: 'c2',
        word: 'meticulous',
        definition: 'adj. 一丝不苟的',
        tags: const <String>['第四单元'],
      ),
      makeCard(
        id: 'c3',
        word: 'resilient',
        definition: 'adj. 有韧性的',
        tags: const <String>['E2E'],
      ),
    ];

void main() {
  Future<TestHarness> boot(
    WidgetTester tester, {
    AppSettings? settings,
    List<WordCard>? cards,
    List<Deck>? decks,
  }) async {
    tester.view.physicalSize = const Size(1400, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final TestHarness harness = TestHarness.fake();
    if (decks != null) {
      for (final Deck deck in decks) {
        await harness.decks.upsert(deck);
      }
    }
    await harness.settings.save(settings ?? const AppSettings());
    await harness.cards.upsertAll(cards ?? taggedCards());
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

  ChoiceChip choiceChip(WidgetTester tester, String label) =>
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

  testWidgets('默认选「全部」，5 / 10 / 20 与自定义题数并存', (tester) async {
    final TestHarness harness = await boot(tester);

    expect((await harness.settings.load()).quizAllQuestions, isTrue);
    expect(choiceChip(tester, '全部（3）').selected, isTrue);
    expect(choiceChip(tester, '10 题').selected, isFalse);
    expect(find.textContaining('默认全出'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '10 题'));
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).quizQuestionCount, 10);
    expect(choiceChip(tester, '10 题').selected, isTrue);

    // 档位之外的题数也能填：37 题
    await tester.enterText(find.byKey(const Key('quiz-count-field')), '37');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).quizQuestionCount, 37);
    expect(choiceChip(tester, '10 题').selected, isFalse);
    expect(choiceChip(tester, '全部（3）').selected, isFalse);

    // 填 0 = 全部
    await tester.enterText(find.byKey(const Key('quiz-count-field')), '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).quizAllQuestions, isTrue);
  });

  testWidgets('第一次勾标签先问并集还是交集，选并集后两个标签取并集', (tester) async {
    final TestHarness harness = await boot(tester);

    await tester.tap(find.widgetWithText(FilterChip, '第四单元'));
    await tester.pumpAndSettle();
    expect(find.text('同时选多个标签时'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tag-match-any')));
    await tester.pumpAndSettle();

    AppSettings saved = await harness.settings.load();
    expect(saved.studyTagFilter, <String>['第四单元']);
    expect(saved.tagMatchMode, TagMatchMode.any);
    expect(saved.tagMatchAsked, isTrue);
    expect(choiceChip(tester, '全部（2）').selected, isTrue);

    // 并集：再加上 E2E，三个词全入选（不再是 0）
    await tester.tap(find.widgetWithText(FilterChip, 'E2E'));
    await tester.pumpAndSettle();
    saved = await harness.settings.load();
    expect(saved.studyTagFilter, <String>['第四单元', 'E2E']);
    expect(choiceChip(tester, '全部（3）').selected, isTrue);
    // 问过一次之后不再弹
    expect(find.text('同时选多个标签时'), findsNothing);

    await tester.tap(find.text('清空筛选'));
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).studyTagFilter, isEmpty);
    expect(choiceChip(tester, '全部（3）').selected, isTrue);
  });

  testWidgets('交集：两个标签要同时带上，筛成 0 个时开始按钮禁用', (tester) async {
    await boot(
      tester,
      settings: const AppSettings(
        tagMatchAsked: true,
        tagMatchMode: TagMatchMode.all,
      ),
    );

    await tester.tap(find.widgetWithText(FilterChip, '第四单元'));
    await tester.pumpAndSettle();
    expect(choiceChip(tester, '全部（2）').selected, isTrue);

    await tester.tap(find.widgetWithText(FilterChip, 'E2E'));
    await tester.pumpAndSettle();
    expect(choiceChip(tester, '全部（0）').selected, isTrue);
    expect(find.textContaining('一个词都不剩'), findsOneWidget);
    final FilledButton start =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '开始测验'));
    expect(start.onPressed, isNull);

    await tester.tap(find.text('清空筛选'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '开始测验'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('卡组多选取并集，已挂起的卡组不出现在作答页', (tester) async {
    final List<WordCard> cards = <WordCard>[
      makeCard(id: 'c1', word: 'abandon'),
      makeCard(id: 'c2', word: 'meticulous', deckId: 'd1'),
      makeCard(id: 'c3', word: 'resilient', deckId: 'd2'),
      makeCard(id: 'c4', word: 'loyal', deckId: 'd3'),
    ];
    final List<Deck> decks = <Deck>[
      Deck(id: 'd1', name: '第一册', createdAt: DateTime(2026, 1, 1)),
      Deck(id: 'd2', name: '第二册', createdAt: DateTime(2026, 1, 1)),
      Deck(
        id: 'd3',
        name: '第三册',
        createdAt: DateTime(2026, 1, 1),
        suspended: true,
      ),
    ];
    final TestHarness harness = await boot(tester, cards: cards, decks: decks);

    // 默认跟随当前卡组（这里是「全部词库」），挂起的第三册不算
    expect(choiceChip(tester, '全部（3）').selected, isTrue);
    expect(find.byKey(const Key('quiz-deck-d3')), findsNothing);

    await tester.tap(find.byKey(const Key('quiz-deck-d1')));
    await tester.pumpAndSettle();
    expect(
      (await harness.settings.load()).quizDeckIds,
      <String>['d1'],
    );
    expect(choiceChip(tester, '全部（1）').selected, isTrue);

    // 多选：并集
    await tester.tap(find.byKey(const Key('quiz-deck-d2')));
    await tester.pumpAndSettle();
    expect(
      (await harness.settings.load()).quizDeckIds,
      <String>['d1', 'd2'],
    );
    expect(choiceChip(tester, '全部（2）').selected, isTrue);

    // 回到跟随当前卡组
    await tester.tap(find.text('回到跟随当前卡组'));
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).quizDeckIds, isEmpty);
    expect(choiceChip(tester, '全部（3）').selected, isTrue);
  });

  testWidgets('FSRS 也按卡组与标签筛选：候选池跟着筛', (tester) async {
    final TestHarness harness = await boot(
      tester,
      settings: const AppSettings(schedulerMode: SchedulerMode.fsrs),
    );
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(StudyPage)),
    );

    List<String> poolWords() => container
        .read(studyPoolProvider)
        .map((WordCard card) => card.word)
        .toList(growable: false);

    expect(poolWords(), <String>['abandon', 'meticulous', 'resilient']);

    await harness.settings.save(
      const AppSettings(
        schedulerMode: SchedulerMode.fsrs,
        studyTagFilter: <String>['第四单元'],
        tagMatchAsked: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(poolWords(), <String>['abandon', 'meticulous']);

    // 筛选控件在 FSRS 下照样摆着（以前是整块藏起来）
    expect(find.widgetWithText(FilterChip, '第四单元'), findsOneWidget);
    expect(find.textContaining('FSRS-6 按最可能忘的顺序安排'), findsOneWidget);
  });
}
