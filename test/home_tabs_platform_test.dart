// 手机端只留四个界面：课堂投影（「演示」）是桌面端的事 —— 手机既开不了
// 独立的演示窗口，也没法把画面投给一屋子人。入口、页面、设置一起藏。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/domain/models/app_settings.dart';
import 'package:word_cards/src/state/providers.dart';
import 'package:word_cards/src/ui/pages/home_shell.dart';
import 'package:word_cards/src/ui/pages/settings_page.dart';
import 'package:word_cards/src/ui/platform_target.dart';

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
    test('桌面端五个，手机端四个（少的是「演示」）', () {
      expect(visibleHomeTabs(PlatformTarget.desktop), AppSettings.homeTabs);
      expect(visibleHomeTabs(PlatformTarget.desktop), hasLength(5));
      expect(
        visibleHomeTabs(PlatformTarget.mobile),
        <String>['add', 'study', 'stats', 'export'],
      );
      expect(
        visibleHomeTabs(PlatformTarget.mobile).contains(AppSettings.demoHomeTab),
        isFalse,
      );
    });

    testWidgets('手机端只画四个入口，找不到「演示」', (WidgetTester tester) async {
      await pump(tester, const HomeShell(target: PlatformTarget.mobile));

      for (final String label in <String>['加入', '作答', '统计', '导出']) {
        expect(find.text(label), findsOneWidget, reason: '缺少入口：$label');
      }
      expect(find.text('演示'), findsNothing);
      // 默认还是停在作答页
      expect(find.text('开始测验'), findsOneWidget);
    });

    testWidgets('手机端切页与记忆照旧，切不到演示', (WidgetTester tester) async {
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
      expect(find.text('演示'), findsNothing);
    });

    testWidgets('手机上上次停在「演示」：打开后落回答题页，也不写坏设置',
        (WidgetTester tester) async {
      final TestHarness harness = await pump(
        tester,
        const HomeShell(target: PlatformTarget.mobile),
        saved: const AppSettings(homeTab: AppSettings.demoHomeTab),
      );

      expect(find.text('开始测验'), findsOneWidget);
      expect(find.text('演示'), findsNothing);
      // 设置里那个值原样留着：换回桌面端还能停在演示页
      expect((await harness.settings.load()).homeTab, 'demo');
    });

    testWidgets('桌面端照旧五个入口，能切到演示页', (WidgetTester tester) async {
      await pump(tester, const HomeShell(target: PlatformTarget.desktop));

      expect(find.text('演示'), findsOneWidget);
      await tester.tap(find.text('演示'));
      await tester.pumpAndSettle();
      expect(find.text('课堂演示（投影）'), findsOneWidget);
      expect(find.text('开始演示'), findsOneWidget);
    });
  });

  group('设置页里的演示外观', () {
    testWidgets('手机端整块不画', (WidgetTester tester) async {
      await pump(tester, const SettingsPage(target: PlatformTarget.mobile));

      expect(find.text('主界面'), findsOneWidget);
      expect(find.text('演示模式（全屏投影）'), findsNothing);
    });

    testWidgets('桌面端还在', (WidgetTester tester) async {
      await pump(tester, const SettingsPage(target: PlatformTarget.desktop));

      expect(find.text('演示模式（全屏投影）'), findsOneWidget);
      expect(find.text('主界面'), findsOneWidget);
    });
  });
}
