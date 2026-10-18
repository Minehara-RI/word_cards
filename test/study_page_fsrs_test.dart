// 「作答」页要能直接调本轮参数，并且能切换复习算法（原有算法 / FSRS-6）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/ui/pages/study_page.dart';

import 'support/test_harness.dart';

void main() {
  Future<TestHarness> boot(
    WidgetTester tester, {
    SchedulerMode mode = SchedulerMode.legacy,
  }) async {
    tester.view.physicalSize = const Size(1400, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final TestHarness harness = TestHarness.fake();
    await harness.settings.save(AppSettings(schedulerMode: mode));
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

  testWidgets('本轮参数直接在作答页改（每轮题数 / 限时 / 正误显示）', (tester) async {
    final TestHarness harness = await boot(tester);

    // 限时是输入框，不再是档位按钮
    expect(find.byKey(const Key('time-limit-field')), findsOneWidget);
    expect(find.text('自定义'), findsNothing);
    expect(find.textContaining('秒'), findsWidgets);

    await tester.enterText(find.byKey(const Key('time-limit-field')), '25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).questionTimeLimitSeconds, 25);

    await tester.tap(find.widgetWithText(ChoiceChip, '20 题'));
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).quizQuestionCount, 20);
  });

  testWidgets('默认是原有算法，界面上不出现 FSRS 的那些设置', (tester) async {
    await boot(tester);
    expect(find.text('原有算法'), findsOneWidget);
    expect(find.text('FSRS-6'), findsOneWidget);
    expect(find.textContaining('目标保留率'), findsNothing);
    expect(find.textContaining('复习今天到期的词'), findsNothing);
  });

  testWidgets('打开 FSRS-6 后出现目标保留率与到期复习入口', (tester) async {
    final TestHarness harness = await boot(tester, mode: SchedulerMode.fsrs);
    expect(find.textContaining('目标保留率'), findsOneWidget);
    expect(find.textContaining('复习今天到期的词'), findsOneWidget);

    // 保留率可以调，并且写进设置
    await tester.tap(find.widgetWithText(ChoiceChip, '80%'));
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).fsrsDesiredRetention, 0.8);

    // 切回原有算法：设置存下来，FSRS 面板消失
    await tester.tap(find.text('原有算法'));
    await tester.pumpAndSettle();
    expect((await harness.settings.load()).schedulerMode, SchedulerMode.legacy);
    expect(find.textContaining('目标保留率'), findsNothing);
  });
}