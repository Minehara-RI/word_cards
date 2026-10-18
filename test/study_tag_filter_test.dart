// 非 FSRS 下默认出当前卡组的全部词，并且支持按标签筛（多标签取「与」）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/state/quiz_controller.dart';
import 'package:word_flashcards/src/ui/pages/quiz_page.dart';
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
    SchedulerMode mode = SchedulerMode.legacy,
    List<WordCard>? cards,
  }) async {
    tester.view.physicalSize = const Size(1400, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final TestHarness harness = TestHarness.fake();
    await harness.settings.save(AppSettings(schedulerMode: mode));
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

  testWidgets('非 FSRS 默认选「全部」，题数档位仍然可以手选', (tester) async {
    final TestHarness harness = await boot(tester);

    expect((await harness.settings.load()).quizAllQuestions, isTrue);
    expect(choiceChip(tester, '全部（3）').selected, isTrue);
    expect(choiceChip(tester, '10 题').selected, isFalse);
    expect(find.textContaining('默认全出'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '10 题'));
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).quizQuestionCount, 10);
    expect(choiceChip(tester, '10 题').selected, isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, '全部（3）'));
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).quizAllQuestions, isTrue);
    expect(choiceChip(tester, '全部（3）').selected, isTrue);
  });

  testWidgets('标签多选取「与」：筛成 0 个时开始按钮禁用，清空后恢复', (tester) async {
    final TestHarness harness = await boot(tester);

    expect(find.widgetWithText(FilterChip, '第四单元'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'E2E'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '第四单元'));
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).studyTagFilter, <String>['第四单元']);
    expect(choiceChip(tester, '全部（2）').selected, isTrue);
    expect(find.textContaining('已选 第四单元：2 / 3 个词'), findsOneWidget);

    // 两个标签没有词同时带上：池子空了，开始按钮点不动
    await tester.tap(find.widgetWithText(FilterChip, 'E2E'));
    await tester.pumpAndSettle();
    expect(
      (await harness.settings.load()).studyTagFilter,
      <String>['第四单元', 'E2E'],
    );
    expect(choiceChip(tester, '全部（0）').selected, isTrue);
    expect(find.textContaining('一个词都不剩'), findsOneWidget);
    final FilledButton start =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '开始测验'));
    expect(start.onPressed, isNull);

    await tester.tap(find.text('清空筛选'));
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).studyTagFilter, isEmpty);
    expect(choiceChip(tester, '全部（3）').selected, isTrue);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '开始测验'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('标签筛选只认非 FSRS：开着 FSRS 时整块藏起来，队列还是整个卡组', (tester) async {
    final TestHarness harness = await boot(tester);
    await harness.settings.save(
      const AppSettings(studyTagFilter: <String>['第四单元']),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, '第四单元'), findsOneWidget);

    // 切到 FSRS：控件整块不画，但选择留在设置里，切回来才生效
    await harness.settings.save(
      const AppSettings(
        schedulerMode: SchedulerMode.fsrs,
        studyTagFilter: <String>['第四单元'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('标签筛选'), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('清空筛选'), findsNothing);
    expect((await harness.settings.load()).studyTagFilter, <String>['第四单元']);
    // 出题范围还是整个卡组，说明行也换成 FSRS 那句
    expect(choiceChip(tester, '全部（3）').selected, isTrue);
    expect(find.textContaining('默认全出'), findsNothing);
    expect(find.textContaining('FSRS-6 按最可能忘的顺序安排'), findsOneWidget);

    // 切回原有算法：筛选立刻又摆出来，也立刻生效
    await harness.settings.save(
      const AppSettings(studyTagFilter: <String>['第四单元']),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, '第四单元'), findsOneWidget);
    expect(choiceChip(tester, '全部（2）').selected, isTrue);
  });

  testWidgets('点开始测验：默认把整卡组的词都出了', (tester) async {
    final TestHarness harness = await boot(tester);

    await tester.tap(find.widgetWithText(FilledButton, '开始测验'));
    await tester.pumpAndSettle();

    expect(find.text('第 1 / 3 题'), findsOneWidget);

    // 三题都答完，让倒计时停下来（留着定时器测试结束会报 pending timer）
    for (int i = 0; i < 3; i++) {
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(QuizPage)),
      );
      final String answer =
          container.read(quizControllerProvider).current!.card.definition;
      await tester.tap(find.text(answer));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
    }

    expect(find.text('正确率'), findsOneWidget);
    expect(await harness.records.getAll(), hasLength(3));
  });

  testWidgets('候选池：非 FSRS 按标签筛，FSRS 原样用整个卡组', (tester) async {
    final TestHarness harness = await boot(tester);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(StudyPage)),
    );

    List<String> poolWords() => container
        .read(studyPoolProvider)
        .map((WordCard card) => card.word)
        .toList(growable: false);

    // 没筛：整个卡组
    expect(poolWords(), <String>['abandon', 'meticulous', 'resilient']);

    Future<void> saveAndSettle(AppSettings settings) async {
      await harness.settings.save(settings);
      await tester.pumpAndSettle();
    }

    await saveAndSettle(const AppSettings(studyTagFilter: <String>['第四单元']));
    expect(poolWords(), <String>['abandon', 'meticulous']);

    await saveAndSettle(
      const AppSettings(studyTagFilter: <String>['第四单元', 'E2E']),
    );
    expect(container.read(studyPoolProvider), isEmpty);

    // 切到 FSRS：标签筛选不参与，池子回到整个卡组
    await saveAndSettle(
      const AppSettings(
        schedulerMode: SchedulerMode.fsrs,
        studyTagFilter: <String>['第四单元'],
      ),
    );
    expect(poolWords(), <String>['abandon', 'meticulous', 'resilient']);
  });
}
