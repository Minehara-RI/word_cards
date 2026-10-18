import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/ui/pages/home_shell.dart';

import 'support/test_harness.dart';

/// 主界面是 Anki 式的：上面一排入口，下面是当前页。
///
/// 这里测的是桌面端的样子（flutter test 跑在宿主上，detectPlatformTarget()
/// 给的就是 desktop）；手机端只有四个入口，见 home_tabs_platform_test.dart。
void main() {
  Future<TestHarness> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
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
          currentSettingsProvider.overrideWithValue(
            const AppSettings(quizQuestionCount: 5),
          ),
        ],
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('五个入口都在，默认停在作答', (tester) async {
    await boot(tester);
    for (final String label in <String>['加入', '作答', '演示', '统计', '导出']) {
      expect(find.text(label), findsOneWidget, reason: '缺少入口：$label');
    }
    expect(find.text('开始测验'), findsOneWidget);
  });

  testWidgets('能切到加入页，手动加卡表单在', (tester) async {
    await boot(tester);
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    expect(find.text('手动添加一张卡片'), findsOneWidget);
    expect(find.text('单词 *'), findsOneWidget);
    expect(find.text('释义 *'), findsOneWidget);
    // 按钮文案带上了当前卡组名：加入「默认词库」
    expect(find.textContaining('加入'), findsWidgets);
    expect(find.text('当前卡组'), findsOneWidget);
  });

  testWidgets('能切到演示页，看得到限时与提示音设置', (tester) async {
    await boot(tester);
    await tester.tap(find.text('演示'));
    await tester.pumpAndSettle();

    expect(find.text('课堂演示（投影）'), findsOneWidget);
    expect(find.byKey(const Key('projection-interval-field')), findsOneWidget);
    // 频率不再有档位按钮，改成输入框里的当前值
    expect(find.text('3000'), findsOneWidget);
    expect(find.text('演示外观'), findsOneWidget);
    expect(find.text('开启提示音'), findsOneWidget);
    expect(find.text('开始演示'), findsOneWidget);
  });

  testWidgets('能切到统计页与导出页', (tester) async {
    await boot(tester);

    await tester.tap(find.text('统计'));
    await tester.pumpAndSettle();
    expect(find.text('统计'), findsWidgets);

    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    expect(find.text('导出卡片 JSON（0）'), findsOneWidget);
    expect(find.text('关于数据库'), findsOneWidget);
    expect(find.textContaining('collection.anki2'), findsWidgets);
  });
}
