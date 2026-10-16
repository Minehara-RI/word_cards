// 演示窗口这一套：帧的编解码、主窗口到画面的换算，以及
// 「多窗口插件不可用时退回应用内全屏页」这条兜底路线。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/domain/models/app_settings.dart';
import 'package:word_cards/src/domain/models/quiz_direction.dart';
import 'package:word_cards/src/logic/quiz.dart';
import 'package:word_cards/src/state/projection_controller.dart';
import 'package:word_cards/src/state/providers.dart';
import 'package:word_cards/src/ui/pages/presentation_page.dart';
import 'package:word_cards/src/ui/pages/projection_page.dart';
import 'package:word_cards/src/ui/presentation/presentation_frame.dart';

import 'support/test_harness.dart';

void main() {
  final PresentationFrame frame = PresentationFrame(
    status: PresentationFrame.statusRunning,
    questions: const <PresentationQuestion>[
      PresentationQuestion(
        prompt: 'すいえい',
        phonetic: '【すいえい】',
        options: <String>['n. 游泳', 'n. 跑步'],
      ),
    ],
    index: 0,
    remainingMs: 2500,
    intervalMs: 5000,
    paused: false,
    loops: 1,
    labelStyle: OptionLabelStyle.letter,
  );

  group('演示窗口参数', () {
    test('一帧能原样编解码（中文、日文都不丢）', () {
      final PresentationWindowPayload payload = PresentationWindowPayload(
        frame: frame,
        themeMode: AppThemeMode.light,
      );
      final PresentationFrame back =
          PresentationWindowPayload.tryDecode(payload.encode())!.frame;
      expect(back.status, PresentationFrame.statusRunning);
      expect(back.questions.single.prompt, 'すいえい');
      expect(back.questions.single.phonetic, '【すいえい】');
      expect(back.questions.single.options, <String>['n. 游泳', 'n. 跑步']);
      expect(back.questions.single.direction, QuizDirection.wordToMeaning);
      expect(back.labelStyle, OptionLabelStyle.letter);
      expect(back.remainingSeconds, 3);
      expect(back.remainingRatio, closeTo(0.5, 1e-9));
      expect(back.position, 1);
      expect(back.total, 1);
    });

    test('只有带标记的窗口参数才会被当成演示窗口', () {
      expect(PresentationWindowPayload.tryDecode(frame.encode()), isNull);
      expect(PresentationWindowPayload.tryDecode(''), isNull);
      expect(PresentationWindowPayload.tryDecode('not json'), isNull);

      final PresentationWindowPayload payload = PresentationWindowPayload(
        frame: frame,
        themeMode: AppThemeMode.dark,
      );
      final PresentationWindowPayload? back =
          PresentationWindowPayload.tryDecode(payload.encode());
      expect(back, isNotNull);
      expect(back!.themeMode, AppThemeMode.dark);
      expect(back.frame.questions.single.prompt, 'すいえい');
    });

    test('反方向的题面是中文释义，音标不带过去', () {
      final PresentationWindowPayload payload = PresentationWindowPayload(
        frame: PresentationFrame(
          status: PresentationFrame.statusRunning,
          questions: const <PresentationQuestion>[
            PresentationQuestion(
              prompt: 'v. 放弃；抛弃',
              options: <String>['abandon', 'meticulous'],
              direction: QuizDirection.meaningToWord,
            ),
          ],
          index: 0,
          remainingMs: 1000,
          intervalMs: 5000,
          paused: false,
          loops: 0,
          labelStyle: OptionLabelStyle.number,
        ),
        themeMode: AppThemeMode.system,
      );
      final PresentationQuestion question =
          PresentationWindowPayload.tryDecode(payload.encode())!
              .frame
              .questions
              .single;
      expect(question.prompt, 'v. 放弃；抛弃');
      expect(question.phonetic, isNull);
      expect(question.direction, QuizDirection.meaningToWord);
    });
  });

  group('控制器状态换算成画面', () {
    final AppSettings settings = const AppSettings(
      projectionOptionLabelStyle: OptionLabelStyle.letter,
    );

    test('运行中：题目与倒计时都对得上', () {
      final ProjectionState state = ProjectionState(
        status: ProjectionStatus.running,
        questions: buildQuizQuestions(
          <dynamic>[makeCard(id: 'c1', word: 'abandon')].cast(),
          shuffleCards: false,
        ),
        intervalMs: 4000,
        remainingMs: 1000,
        loops: 2,
      );
      final ProjectionFrameData data = projectionFrameOf(state, settings);
      expect(data.frame.isRunning, isTrue);
      expect(data.frame.current!.prompt, 'abandon');
      expect(data.frame.remainingSeconds, 1);
      expect(data.frame.labelStyle, OptionLabelStyle.letter);
      expect(data.frame.loops, 2);
    });

    test('结束：会带上答案文件那句提示', () {
      const ProjectionState state = ProjectionState(
        status: ProjectionStatus.finished,
        intervalMs: 3000,
        loops: 1,
      );
      final ProjectionFrameData data = projectionFrameOf(state, settings);
      expect(data.frame.isRunning, isFalse);
      expect(data.frame.message, contains('答案已经写进 txt 文件'));
      expect(data.frame.message, contains('循环 1 轮'));
    });

    test('没有卡片：提示去加卡片', () {
      const ProjectionState state = ProjectionState(
        status: ProjectionStatus.empty,
      );
      final ProjectionFrameData data = projectionFrameOf(state, settings);
      expect(data.frame.status, PresentationFrame.statusEmpty);
      expect(data.frame.message, contains('没有可演示的卡片'));
    });
  });

  testWidgets('多窗口不可用时，退回应用内全屏演示页', (tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final TestHarness harness = TestHarness.fake();
    await harness.cards.upsertAll(sampleCards());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWithValue(harness.cards),
          answerRecordRepositoryProvider.overrideWithValue(harness.records),
          deckRepositoryProvider.overrideWithValue(harness.decks),
          settingsRepositoryProvider.overrideWithValue(harness.settings),
        ],
        child: MaterialApp(
          home: Scaffold(body: ProjectionPage(onGoToAdd: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('开始演示'),
      find
          .descendant(
            of: find.byType(ProjectionPage),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始演示'));
    await tester.pumpAndSettle();

    // 测试环境里没有多窗口插件 -> 走应用内全屏页
    expect(find.byType(PresentationPage), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PresentationPage)),
    );
    expect(
      container.read(projectionControllerProvider).status,
      ProjectionStatus.running,
    );
    expect(
      container.read(projectionControllerProvider).total,
      sampleCards().length,
    );

    // 退出后演示要停下来（退出动作由 ProjectionPage 在路由返回后做）
    await tester.tap(find.byTooltip('退出演示'));
    await tester.pumpAndSettle();
    expect(find.byType(PresentationPage), findsNothing);
    expect(
      container.read(projectionControllerProvider).status,
      isNot(ProjectionStatus.running),
    );
  });
}