import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/state/quiz_controller.dart';
import 'package:word_flashcards/src/ui/pages/quiz_page.dart';

import 'support/test_harness.dart';

/// 「正误显示时机」三档：立即显示 / 统一显示 / 不显示。
void main() {
  Future<ProviderContainer> boot(
    WidgetTester tester,
    TestHarness harness,
    AnswerRevealMode mode,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await harness.cards.upsertAll(<dynamic>[
      makeCard(id: 'c1', word: 'abandon'),
      makeCard(
        id: 'c2',
        word: 'meticulous',
        definition: 'adj. 一丝不苟的',
        distractors: <String>['adj. 漫不经心的', 'adj. 慷慨的', 'adj. 沉默的', 'adj. 固执的'],
      ),
    ].cast());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWithValue(harness.cards),
          answerRecordRepositoryProvider.overrideWithValue(harness.records),
          deckRepositoryProvider.overrideWithValue(harness.decks),
          settingsRepositoryProvider.overrideWithValue(harness.settings),
          currentSettingsProvider.overrideWithValue(
            AppSettings(questionTimeLimitSeconds: 30, answerRevealMode: mode),
          ),
        ],
        child: const MaterialApp(home: QuizPage()),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(QuizPage)),
    );
    await container
        .read(quizControllerProvider.notifier)
        .start(questionCount: 2, shuffle: false);
    await tester.pumpAndSettle();

    expect(container.read(quizControllerProvider).revealMode, mode);
    return container;
  }

  /// 一直作答到本轮结束。
  Future<void> answerAll(
    WidgetTester tester,
    ProviderContainer container, {
    required bool correct,
  }) async {
    var guard = 0;
    while (container.read(quizControllerProvider).status == QuizStatus.running) {
      if (guard++ > 10) fail('停不下来了');
      final question = container.read(quizControllerProvider).current!;
      final index = correct
          ? question.correctIndex
          : (question.correctIndex + 1) % question.options.length;
      container.read(quizControllerProvider.notifier).answer(index);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('立即显示：作答后马上标出对错', (tester) async {
    final harness = TestHarness.fake();
    final container = await boot(tester, harness, AnswerRevealMode.immediate);

    final question = container.read(quizControllerProvider).current!;
    await tester.tap(find.text(question.correctOption));
    await tester.pump();

    final state = container.read(quizControllerProvider);
    expect(state.showCorrectness, isTrue);
    expect(find.text('答对了'), findsOneWidget);
  });

  testWidgets('统一显示：过程不提示，结束后逐题回顾', (tester) async {
    final harness = TestHarness.fake();
    final container = await boot(tester, harness, AnswerRevealMode.deferred);

    // 作答前就不该有任何对错提示，实时比分也不能露
    // （「答对 N 题」会间接告诉你上一题做对没有）
    expect(find.textContaining('答对了'), findsNothing);
    expect(find.textContaining('答对 '), findsNothing);

    final question = container.read(quizControllerProvider).current!;
    await tester.tap(find.text(question.correctOption));
    await tester.pump();

    // 关键：作答后仍然不显示对错
    var state = container.read(quizControllerProvider);
    expect(state.isAnswered, isTrue);
    expect(state.showCorrectness, isFalse);
    expect(find.textContaining('答对了'), findsNothing);
    expect(find.textContaining('答错了'), findsNothing);
    expect(find.textContaining('已记录'), findsOneWidget);

    // 第一题答对、第二题答错，然后看结果
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final second = container.read(quizControllerProvider).current!;
    container.read(quizControllerProvider.notifier).answer(
          (second.correctIndex + 1) % second.options.length,
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    state = container.read(quizControllerProvider);
    expect(state.status, QuizStatus.finished);
    expect(state.correctCount, 1);
    expect(state.reviewItems, hasLength(2));

    // 结束后统一列出两道题
    expect(find.text('逐题回顾'), findsOneWidget);
    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('meticulous'), findsOneWidget);
    expect(find.textContaining('你选了：'), findsWidgets);
    expect(find.textContaining('正确答案：'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('不显示：全程不露对错，结果页只有分数', (tester) async {
    final harness = TestHarness.fake();
    final container = await boot(tester, harness, AnswerRevealMode.never);

    // 连右上角的「正确 N」都不显示
    expect(find.textContaining('答对 '), findsNothing);

    await answerAll(tester, container, correct: true);

    final state = container.read(quizControllerProvider);
    expect(state.status, QuizStatus.finished);
    expect(state.correctCount, 2);

    // 只给总分，不列题目与答案
    expect(find.text('100%'), findsOneWidget);
    expect(find.textContaining('不列出题目与答案'), findsOneWidget);
    expect(find.text('逐题回顾'), findsNothing);
    expect(find.text('需要复习的单词'), findsNothing);
    expect(find.text('abandon'), findsNothing);
  });

  testWidgets('不显示：答错也不会在过程中或结果里暴露答案', (tester) async {
    final harness = TestHarness.fake();
    final container = await boot(tester, harness, AnswerRevealMode.never);

    await answerAll(tester, container, correct: false);

    final state = container.read(quizControllerProvider);
    expect(state.status, QuizStatus.finished);
    expect(state.correctCount, 0);
    expect(find.text('0%'), findsOneWidget);
    // 错题的正确答案一个字都不出现
    expect(find.textContaining('v. 放弃；抛弃'), findsNothing);
    expect(find.textContaining('adj. 一丝不苟的'), findsNothing);
  });
}
