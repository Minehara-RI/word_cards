// 应用内「说明」：手机端每个页面底部一个按钮，设置页只在 Anki 接口那一节。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/ui/help/help_content.dart';
import 'package:word_flashcards/src/ui/pages/settings_page.dart';
import 'package:word_flashcards/src/ui/platform_target.dart';
import 'package:word_flashcards/src/ui/widgets/help_button.dart';

import 'support/test_harness.dart';

void main() {
  group('说明文案', () {
    test('每个页面都有词条，且至少有一节', () {
      for (final String key in <String>['add', 'study', 'stats', 'export', 'anki']) {
        final HelpTopic? topic = helpTopicFor(key);
        expect(topic, isNotNull, reason: '缺少说明：$key');
        expect(topic!.sections, isNotEmpty, reason: '$key 没有内容');
        expect(topic.title.trim(), isNotEmpty);
        for (final HelpSection section in topic.sections) {
          expect(section.heading.trim(), isNotEmpty);
          expect(section.body.trim(), isNotEmpty);
        }
      }
    });

    test('内容覆盖几个关键说法（不是空壳）', () {
      final HelpTopic add = helpTopicFor('add')!;
      final String addText = add.sections.map((HelpSection s) => s.heading + s.body).join();
      expect(addText, contains('AI 补全'));
      expect(addText, contains('干扰项'));

      final HelpTopic study = helpTopicFor('study')!;
      final String studyText =
          study.sections.map((HelpSection s) => s.heading + s.body).join();
      expect(studyText, contains('限时'));
      expect(studyText, contains('FSRS'));

      final HelpTopic anki = helpTopicFor('anki')!;
      final String ankiText = anki.sections.map((HelpSection s) => s.heading + s.body).join();
      expect(ankiText, contains('8766'));
      expect(ankiText, contains('unsupported action'));

      final HelpTopic export = helpTopicFor('export')!;
      final String exportText =
          export.sections.map((HelpSection s) => s.heading + s.body).join();
      expect(exportText, contains('5033'));
      expect(exportText, contains('同步'));
    });

    test('没有词条的 key 返回 null，弹窗不会开一个空框', () {
      expect(helpTopicFor('不存在'), isNull);
    });
  });

  group('说明按钮', () {
    testWidgets('电脑端不画', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HelpButton(topic: 'add', target: PlatformTarget.desktop),
          ),
        ),
      );
      expect(find.text('说明'), findsNothing);
    });

    testWidgets('手机端在底部，点开是这个页面的说明', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HelpButton(topic: 'add', target: PlatformTarget.mobile),
          ),
        ),
      );
      expect(find.text('说明'), findsOneWidget);

      await tester.tap(find.byKey(const Key('help-button-add')));
      await tester.pumpAndSettle();

      expect(find.text('加入：把词放进词库'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);

      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text('加入：把词放进词库'), findsNothing);
    });
  });

  group('设置页', () {
    testWidgets('手机端只在 Anki 接口那一节有「说明」', (WidgetTester tester) async {
      final TestHarness harness = TestHarness.fake();
      await tester.pumpWidget(
        harness.wrap(
          const MaterialApp(
            home: SettingsPage(target: PlatformTarget.mobile),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 设置页很长，「外部写入」在折叠线以下；ListView 只构建可见子项，
      // 所以先滚到它出现为止。
      final Finder button = find.byKey(const Key('help-button-anki'));
      await tester.scrollUntilVisible(
        button,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);
      // 别的分类没有按钮：设置页只给「外部写入」配说明。
      expect(find.text('说明'), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('外部写入：AnkiConnect 兼容接口'), findsOneWidget);
    });

    testWidgets('电脑端一个都不画', (WidgetTester tester) async {
      final TestHarness harness = TestHarness.fake();
      await tester.pumpWidget(
        harness.wrap(
          const MaterialApp(
            home: SettingsPage(target: PlatformTarget.desktop),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 滚到「外部写入」那一节，确认电脑端同位置没有按钮。
      await tester.scrollUntilVisible(
        find.text('外部写入（AnkiConnect 兼容）'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('说明'), findsNothing);
      expect(find.byKey(const Key('help-button-anki')), findsNothing);
    });
  });
}
