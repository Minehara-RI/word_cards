// 主界面入口两端一致：五个（加入 / 作答 / 演示 / 统计 / 导出）。
// 桌面端的「演示」另开独立窗口，手机端是应用内全屏，所以手机端不再藏这一页。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/ui/pages/home_shell.dart';
import 'package:word_flashcards/src/ui/pages/projection_page.dart';
import 'package:word_flashcards/src/ui/pages/settings_page.dart';
import 'package:word_flashcards/src/ui/platform_target.dart';

import 'support/test_harness.dart';

void main() {
  Future<TestHarness> pump(
    WidgetTester tester,
    Widget home, {
    AppSettings? saved,
  }) async {
    tester.view.physicalSize = const Size(1120, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final TestHarness harness = TestHarness.fake();
    if (saved != null) {
      await harness.settings.save(saved);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWithValue(harness.cards),
          answerRecordRepositoryProvider.overrideWithValue(harness.records),
          deckRepositoryProvider.overrideWithValue(harness.decks),
          settingsRepositoryProvider.overrideWithValue(harness.settings),
          apiCacheRepositoryProvider.overrideWithValue(harness.cache),
          currentSettingsProvider.overrideWithValue(
            const AppSettings(quizQuestionCount: 5),
          ),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  group('主界面入口按平台给', () {
    test('两端都是五个，都含「演示」', () {
      expect(visibleHomeTabs(PlatformTarget.desktop), AppSettings.homeTabs);
      expect(visibleHomeTabs(PlatformTarget.mobile), AppSettings.homeTabs);
      expect(visibleHomeTabs(PlatformTarget.mobile), hasLength(5));
      expect(
        visibleHomeTabs(PlatformTarget.mobile).contains(AppSettings.demoHomeTab),
        isTrue,
      );
    });

    testWidgets('手机端也画五个入口，能进演示页', (WidgetTester tester) async {
      await pump(tester, const HomeShell(target: PlatformTarget.mobile));

      for (final String label in <String>['加入', '作答', '演示', '统计', '导出']) {
        expect(find.text(label), findsOneWidget, reason: '缺少入口：$label');
      }
      // 默认还是停在作答页
      expect(find.text('开始测验'), findsOneWidget);

      await tester.tap(find.text('演示'));
      await tester.pumpAndSettle();
      expect(find.text('课堂演示（投影）'), findsOneWidget);
      expect(find.text('词汇来源'), findsOneWidget);
    });

    testWidgets('手机端切页与记忆照旧', (WidgetTester tester) async {
      final TestHarness harness = await pump(
        tester,
        const HomeShell(target: PlatformTarget.mobile),
      );

      await tester.tap(find.text('加入'));
      await tester.pumpAndSettle();
      expect(find.text('手动添加一张卡片'), findsOneWidget);
      expect((await harness.settings.load()).homeTab, 'add');

      await tester.tap(find.text('统计'));
      await tester.pumpAndSettle();
      expect((await harness.settings.load()).homeTab, 'stats');
    });

    testWidgets('上次停在「演示」：手机端也照样落回演示页', (WidgetTester tester) async {
      final TestHarness harness = await pump(
        tester,
        const HomeShell(target: PlatformTarget.mobile),
        saved: const AppSettings(homeTab: AppSettings.demoHomeTab),
      );

      expect(find.text('词汇来源'), findsOneWidget);
      expect(find.text('开始测验'), findsNothing);
      expect((await harness.settings.load()).homeTab, 'demo');
    });

    testWidgets('桌面端五个入口，能切到演示页', (WidgetTester tester) async {
      await pump(tester, const HomeShell(target: PlatformTarget.desktop));

      expect(find.text('演示'), findsOneWidget);
      await tester.tap(find.text('演示'));
      await tester.pumpAndSettle();
      expect(find.text('课堂演示（投影）'), findsOneWidget);
      expect(find.text('开始演示'), findsOneWidget);
    });
  });

  group('演示页的桌面专属控件', () {
    testWidgets('手机端不画「选择目录…」', (WidgetTester tester) async {
      await pump(
        tester,
        ProjectionPage(target: PlatformTarget.mobile, onGoToAdd: () {}),
      );
      await tester.dragUntilVisible(
        find.text('演示答案文件'),
        find.byType(Scrollable).first,
        const Offset(0, -320),
      );
      await tester.pumpAndSettle();
      expect(find.text('演示答案文件'), findsOneWidget);
      expect(find.text('选择目录…'), findsNothing);
    });

    testWidgets('桌面端照旧有「选择目录…」', (WidgetTester tester) async {
      await pump(
        tester,
        ProjectionPage(target: PlatformTarget.desktop, onGoToAdd: () {}),
      );
      await tester.dragUntilVisible(
        find.text('演示答案文件'),
        find.byType(Scrollable).first,
        const Offset(0, -320),
      );
      await tester.pumpAndSettle();
      expect(find.text('选择目录…'), findsOneWidget);
    });
  });

  group('设置页里的演示外观', () {
    testWidgets('两端都画：手机端的演示也有自己的深浅色', (WidgetTester tester) async {
      await pump(tester, const SettingsPage());

      expect(find.text('主界面'), findsOneWidget);
      expect(find.text('演示模式（全屏投影）'), findsOneWidget);
    });
  });
}
