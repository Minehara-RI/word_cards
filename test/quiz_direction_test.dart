// 出题方向：看词选义 / 看义选词 / 混合。逻辑层与界面各测一段。
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/domain/models/app_settings.dart';
import 'package:word_cards/src/domain/models/quiz_direction.dart';
import 'package:word_cards/src/domain/models/word_card.dart';
import 'package:word_cards/src/logic/quiz.dart';
import 'package:word_cards/src/state/providers.dart';
import 'package:word_cards/src/state/quiz_controller.dart';
import 'package:word_cards/src/ui/pages/quiz_page.dart';
import 'package:word_cards/src/ui/pages/study_page.dart';

import 'support/test_harness.dart';

/// 五张词形互不相同的卡：反方向的选项要凑够 5 个才测得出东西。
List<WordCard> fiveCards() => <WordCard>[
      makeCard(id: 'c1', word: 'abandon', definition: 'v. 放弃；抛弃'),
      makeCard(id: 'c2', word: 'meticulous', definition: 'adj. 一丝不苟的'),
      makeCard(id: 'c3', word: 'resilient', definition: 'adj. 有韧性的'),
      makeCard(id: 'c4', word: 'candid', definition: 'adj. 坦率的'),
      makeCard(id: 'c5', word: 'lucid', definition: 'adj. 清晰的'),
    ];

void bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 作答页自己不 watch 设置；真实应用里是外层的作答页在 watch。
/// 测试里补一层只负责 watch 的外壳，否则 settingsProvider 没人订阅，
/// 读出来的永远是默认值（看英文选中文）。
class _SettingsAwareHost extends ConsumerWidget {
  const _SettingsAwareHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(currentSettingsProvider);
    return const QuizPage();
  }
}

/// 挂起作答页、等设置到位之后再开一轮。
Future<ProviderContainer> bootQuiz(
  WidgetTester tester,
  TestHarness harness, {
  int? questionCount,
}) async {
  await tester.pumpWidget(
    harness.wrap(const MaterialApp(home: _SettingsAwareHost())),
  );
  await tester.pumpAndSettle();

  final ProviderContainer container = ProviderScope.containerOf(
    tester.element(find.byType(QuizPage)),
  );
  await container
      .read(quizControllerProvider.notifier)
      .start(questionCount: questionCount);
  await tester.pumpAndSettle();
  return container;
}

/// 答对当前这一题，然后等自动翻页把这一轮走完（顺手把倒计时停掉）。
Future<void> answerCorrect(WidgetTester tester, ProviderContainer container) async {
  final String correct =
      container.read(quizControllerProvider).current!.correctOption;
  await tester.tap(find.text(correct));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pumpAndSettle();
}

void main() {
  group('看义选词（反方向）', () {
    test('题面是中文释义，选项都是单词，正确项就是这张卡的单词', () {
      final List<QuizQuestion> questions = buildQuizQuestions(
        fiveCards(),
        random: Random(1),
        shuffleCards: false,
        direction: QuizDirection.meaningToWord,
      );
      expect(questions, hasLength(5));
      for (final QuizQuestion question in questions) {
        expect(question.direction, QuizDirection.meaningToWord);
        expect(question.promptText, question.card.definition);
        expect(question.correctOption, question.card.word);
        expect(question.options, hasLength(5));
        expect(question.options.toSet(), hasLength(5), reason: '选项不能重复');
        // 选项全是单词：中文释义一个都不该混进来。
        expect(
          question.options.where((String option) => option.contains('的')),
          isEmpty,
        );
      }
    });

    test('反方向不显示音标 —— 那是答案的读音', () {
      final QuizQuestion question = buildQuizQuestions(
        fiveCards(),
        random: Random(2),
        shuffleCards: false,
        direction: QuizDirection.meaningToWord,
      ).first;
      expect(question.showsPhonetic, isFalse);
    });

    test('卡组只有一个词时退回正方向，不出只有一个选项的假题', () {
      final List<QuizQuestion> questions = buildQuizQuestions(
        <WordCard>[
          makeCard(id: 'solo', word: 'solo', definition: 'adj. 单独的'),
        ],
        random: Random(3),
        direction: QuizDirection.meaningToWord,
      );
      final QuizQuestion question = questions.single;
      expect(question.direction, QuizDirection.wordToMeaning);
      expect(question.options.length, greaterThan(1));
      expect(question.correctOption, 'adj. 单独的');
    });
  });

  group('混合方向', () {
    test('两种方向都会出现，每一题都是具体方向', () {
      final List<QuizQuestion> questions = buildQuizQuestions(
        fiveCards(),
        random: Random(7),
        shuffleCards: false,
        direction: QuizDirection.mixed,
      );
      final Set<QuizDirection> picked = questions
          .map((QuizQuestion question) => question.direction)
          .toSet();
      expect(
        picked,
        containsAll(<QuizDirection>[
          QuizDirection.wordToMeaning,
          QuizDirection.meaningToWord,
        ]),
      );
      for (final QuizQuestion question in questions) {
        expect(question.direction.isMixed, isFalse);
        expect(
          question.promptText,
          question.direction.isReverse
              ? question.card.definition
              : question.card.word,
        );
      }
    });

    test('同一份种子下方向的分配可复现', () {
      List<String> run() => buildQuizQuestions(
            fiveCards(),
            random: Random(9),
            shuffleCards: false,
            direction: QuizDirection.mixed,
          ).map((QuizQuestion question) => question.direction.id).toList();
      expect(run(), run());
    });
  });

  testWidgets('看中文选英文：题面是释义、选项是单词，音标藏起来', (tester) async {
    bigSurface(tester);
    final TestHarness harness = TestHarness.fake();
    await harness.cards.upsertAll(fiveCards());
    await harness.settings.save(
      const AppSettings(quizDirection: QuizDirection.meaningToWord),
    );

    final container = await bootQuiz(tester, harness, questionCount: 1);
    expect(
      container.read(currentSettingsProvider).quizDirection,
      QuizDirection.meaningToWord,
    );
    final QuizQuestion question =
        container.read(quizControllerProvider).current!;
    expect(question.direction, QuizDirection.meaningToWord);

    // 题面是中文释义，单词只出现在选项里，音标一个都不出现。
    expect(find.text(question.card.definition), findsOneWidget);
    expect(find.text(question.card.word), findsOneWidget);
    expect(find.text(question.card.phonetic!), findsNothing);

    await answerCorrect(tester, container);

    final records = await harness.records.getAll();
    expect(records.single.expected, question.card.word);
    expect(records.single.selected, question.card.word);
    expect(records.single.correct, isTrue);
  });

  testWidgets('看英文选中文：题面是单词 + 音标，选项是中文释义', (tester) async {
    bigSurface(tester);
    final TestHarness harness = TestHarness.fake();
    await harness.cards.upsertAll(fiveCards());

    final container = await bootQuiz(tester, harness, questionCount: 1);
    final QuizQuestion question =
        container.read(quizControllerProvider).current!;
    expect(question.direction, QuizDirection.wordToMeaning);
    expect(find.text(question.card.word), findsOneWidget);
    // 正方向照样显示音标，选项里有中文释义。
    expect(find.text(question.card.phonetic!), findsOneWidget);
    expect(find.text(question.card.definition), findsOneWidget);

    await answerCorrect(tester, container);
    expect(
      (await harness.records.getAll()).single.expected,
      question.card.definition,
    );
  });

  testWidgets('混合：题面上标出这一题考哪边', (tester) async {
    bigSurface(tester);
    final TestHarness harness = TestHarness.fake();
    await harness.cards.upsertAll(fiveCards());
    await harness.settings.save(
      const AppSettings(quizDirection: QuizDirection.mixed),
    );

    final container = await bootQuiz(tester, harness, questionCount: 1);
    final QuizState state = container.read(quizControllerProvider);
    expect(state.direction, QuizDirection.mixed);
    final QuizQuestion question = state.current!;
    expect(question.direction.isMixed, isFalse);
    expect(find.text(question.direction.shortLabel), findsOneWidget);

    await answerCorrect(tester, container);
  });

  testWidgets('作答页上的三个方向选项会写回设置', (tester) async {
    bigSurface(tester);
    final TestHarness harness = TestHarness.fake();
    await harness.cards.upsert(makeCard());

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

    ChoiceChip chip(String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

    // 默认是「看英文选中文」
    expect(chip('看英文选中文').selected, isTrue);
    expect(
      (await harness.settings.load()).quizDirection,
      QuizDirection.wordToMeaning,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, '看中文选英文'));
    await tester.pumpAndSettle();
    expect(
      (await harness.settings.load()).quizDirection,
      QuizDirection.meaningToWord,
    );
    expect(chip('看中文选英文').selected, isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, '混合'));
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).quizDirection, QuizDirection.mixed);
    expect(chip('混合').selected, isTrue);
  });
}
