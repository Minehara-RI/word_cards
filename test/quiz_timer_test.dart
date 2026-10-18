import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/state/quiz_controller.dart';
import 'package:word_flashcards/src/ui/pages/quiz_page.dart';

import 'support/test_harness.dart';

/// 限时是硬规则：到点没作答就必须判超时、记错题、自动下一题。
void main() {
  Future<ProviderContainer> boot(
    WidgetTester tester,
    TestHarness harness, {
    required int limitSeconds,
  }) async {
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

    // 直接把限时 override 成固定值，避免受设置流的异步时序影响
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWithValue(harness.cards),
          answerRecordRepositoryProvider.overrideWithValue(harness.records),
          deckRepositoryProvider.overrideWithValue(harness.decks),
          settingsRepositoryProvider.overrideWithValue(harness.settings),
          currentSettingsProvider.overrideWithValue(
            AppSettings(questionTimeLimitSeconds: limitSeconds),
          ),
        ],
        child: const MaterialApp(home: QuizPage()),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(QuizPage)),
    );
    expect(
      container.read(currentSettingsProvider).questionTimeLimitSeconds,
      limitSeconds,
    );
    return container;
  }

  testWidgets('倒计时到点会判超时、记错题并强制下一题', (tester) async {
    final harness = TestHarness.fake();
    final container = await boot(tester, harness, limitSeconds: 2);

    await container
        .read(quizControllerProvider.notifier)
        .start(questionCount: 2, shuffle: false);
    await tester.pumpAndSettle();

    // 第 1 题正在进行，界面上有倒计时
    var state = container.read(quizControllerProvider);
    expect(state.status, QuizStatus.running);
    expect(state.current!.card.word, 'abandon');
    expect(state.timeLimitMs, 2000);
    expect(state.remainingMs, 2000);
    expect(find.textContaining('剩余'), findsOneWidget);
    expect(find.textContaining('超时自动下一题'), findsOneWidget);

    // 过 1 秒：还在倒计时，没判超时
    await tester.pump(const Duration(seconds: 1));
    state = container.read(quizControllerProvider);
    expect(state.timedOut, isFalse);
    expect(state.isAnswered, isFalse);
    expect(state.remainingMs, 1000);
    expect(state.remainingSeconds, 1);

    // 再过 1 秒：到点，判超时
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    state = container.read(quizControllerProvider);
    expect(state.timedOut, isTrue);
    expect(state.isAnswered, isTrue);
    expect(state.currentCorrect, isFalse);
    expect(state.remainingMs, 0);
    expect(find.textContaining('超时了'), findsOneWidget);
    expect(find.textContaining('已超时'), findsOneWidget);

    // 题 1 的错题记录已经落库，reactionMs 就是限时
    await tester.pumpAndSettle();
    final records = await harness.records.getAll();
    expect(records, hasLength(1));
    expect(records.single.timedOut, isTrue);
    expect(records.single.correct, isFalse);
    expect(records.single.selected, isEmpty);
    expect(records.single.expected, 'v. 放弃；抛弃');
    expect(records.single.reactionMs, 2000);

    // 超时停留一会儿后自动翻到第 2 题，倒计时重新开始
    await tester.pump(
      QuizController.timeoutFeedbackDelay + const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    state = container.read(quizControllerProvider);
    expect(state.index, 1);
    expect(state.timedOut, isFalse);
    expect(state.isAnswered, isFalse);
    expect(state.current!.card.word, 'meticulous');
    expect(state.remainingMs, 2000, reason: '新题要重新开始计时');

    // 卡片也被记了一次错误练习
    final card = await harness.cards.getById('c1');
    expect(card!.reviewCount, 1);
    expect(card.wrongCount, 1);
  });

  testWidgets('超时之后再点选项不再生效', (tester) async {
    final harness = TestHarness.fake();
    final container = await boot(tester, harness, limitSeconds: 2);

    await container.read(quizControllerProvider.notifier).start(questionCount: 2);
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(container.read(quizControllerProvider).timedOut, isTrue);

    // 超时后点正确选项也不应该被当成答对
    container.read(quizControllerProvider.notifier).answer(0);
    await tester.pump();
    final state = container.read(quizControllerProvider);
    expect(state.timedOut, isTrue);
    expect(state.correctCount, 0);
    expect(state.records, hasLength(1));
  });

  testWidgets('作答会立刻停掉倒计时，同一题不会被重复判超时', (tester) async {
    final harness = TestHarness.fake();
    final container = await boot(tester, harness, limitSeconds: 3);

    await container
        .read(quizControllerProvider.notifier)
        .start(questionCount: 2, shuffle: false);
    await tester.pumpAndSettle();

    final notifier = container.read(quizControllerProvider.notifier);
    final correctIndex =
        container.read(quizControllerProvider).current!.correctIndex;
    notifier.answer(correctIndex);
    await tester.pump();

    // 作答后倒计时立刻停掉
    expect(container.read(quizControllerProvider).timedOut, isFalse);
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(quizControllerProvider).timedOut, isFalse);

    // 一路把时间推过原来的限时（以及自动翻页）：第 1 题只该有一条“答对”的记录
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    final recordsForFirst = (await harness.records.getAll())
        .where((record) => record.cardId == 'c1')
        .toList();
    expect(recordsForFirst, hasLength(1), reason: '同一题只能落一条记录');
    expect(recordsForFirst.single.correct, isTrue);
    expect(recordsForFirst.single.timedOut, isFalse);
  });
}
