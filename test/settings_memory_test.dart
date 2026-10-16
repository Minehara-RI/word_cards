// 「所有的设定都要记得住」：模型能存能读、写进真实库能读回来、
// 界面上的选择会写回设置并在下次打开时恢复。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/domain/models/app_settings.dart';
import 'package:word_cards/src/domain/models/card_language.dart';
import 'package:word_cards/src/domain/models/quiz_direction.dart';
import 'package:word_cards/src/state/providers.dart';
import 'package:word_cards/src/ui/pages/home_shell.dart';
import 'package:word_cards/src/ui/pages/import_page.dart';

import 'support/test_harness.dart';

void main() {
  group('配置模型', () {
    test('所有设定都能原样走一遍 Map', () {
      const AppSettings original = AppSettings(
        apiBaseUrl: 'https://example.com/v1',
        apiKey: 'sk-test',
        apiModel: 'gpt-x',
        quizQuestionCount: 20,
        studyTagFilter: <String>['第四单元', 'E2E'],
        questionTimeLimitSeconds: 25,
        answerRevealMode: AnswerRevealMode.deferred,
        quizDirection: QuizDirection.mixed,
        schedulerMode: SchedulerMode.fsrs,
        fsrsDesiredRetention: 0.85,
        promptTemplateId: 'batch',
        homeTab: 'demo',
        activeDeckId: 'deck-1',
        language: CardLanguage.korean,
        themeMode: AppThemeMode.light,
        projectionThemeMode: AppThemeMode.dark,
        fontScale: 1.2,
        projectionIntervalSeconds: 8,
        projectionShuffle: true,
        projectionLoop: false,
        projectionOptionLabelStyle: OptionLabelStyle.letter,
        projectionReshuffleEachRound: false,
        projectionAnswerMode: AnswerSheetMode.optionOnly,
        projectionAnswerDir: 'D:/answers',
        projectionBeepEnabled: false,
        projectionBeepHz: 4400,
        projectionBeepMs: 300,
        projectionSoundSource: PageTurnSoundSource.custom,
        projectionSoundPath: 'D:/ping.wav',
      );

      final AppSettings back = AppSettings.fromMap(original.toMap());
      expect(back.apiBaseUrl, 'https://example.com/v1');
      expect(back.apiKey, 'sk-test');
      expect(back.apiModel, 'gpt-x');
      expect(back.quizQuestionCount, 20);
      expect(back.studyTagFilter, <String>['第四单元', 'E2E']);
      expect(back.questionTimeLimitSeconds, 25);
      expect(back.answerRevealMode, AnswerRevealMode.deferred);
      expect(back.quizDirection, QuizDirection.mixed);
      expect(back.schedulerMode, SchedulerMode.fsrs);
      expect(back.usesFsrs, isTrue);
      expect(back.fsrsDesiredRetention, 0.85);
      expect(back.retention, 0.85);
      expect(back.promptTemplateId, 'batch');
      expect(back.homeTab, 'demo');
      expect(back.activeDeckId, 'deck-1');
      expect(back.language, CardLanguage.korean);
      expect(back.themeMode, AppThemeMode.light);
      expect(back.projectionThemeMode, AppThemeMode.dark);
      expect(back.fontScale, 1.2);
      expect(back.projectionIntervalSeconds, 8);
      expect(back.projectionShuffle, isTrue);
      expect(back.projectionLoop, isFalse);
      expect(back.projectionOptionLabelStyle, OptionLabelStyle.letter);
      expect(back.projectionReshuffleEachRound, isFalse);
      expect(back.projectionAnswerMode, AnswerSheetMode.optionOnly);
      expect(back.projectionAnswerDir, 'D:/answers');
      expect(back.projectionBeepEnabled, isFalse);
      expect(back.projectionBeepHz, 4400);
      expect(back.projectionBeepMs, 300);
      expect(back.projectionSoundSource, PageTurnSoundSource.custom);
      expect(back.projectionSoundPath, 'D:/ping.wav');
    });

    test('主页面的 id 稳定，未知值回默认（作答）', () {
      // 这几个 id 是存在设置里的值，只能加不能改。
      expect(AppSettings.addHomeTab, 'add');
      expect(AppSettings.studyHomeTab, 'study');
      expect(AppSettings.demoHomeTab, 'demo');
      expect(AppSettings.statsHomeTab, 'stats');
      expect(AppSettings.exportHomeTab, 'export');
      expect(AppSettings.homeTabs, <String>['add', 'study', 'demo', 'stats', 'export']);
      expect(AppSettings.defaultHomeTab, AppSettings.studyHomeTab);
      expect(
        AppSettings.fromMap(<String, Object?>{'home_tab': '???有关'}).homeTab,
        AppSettings.defaultHomeTab,
      );
    });

    test('题目数量的默认是「全部」，标签筛选默认不筛', () {
      const AppSettings defaults = AppSettings();
      expect(defaults.quizQuestionCount, AppSettings.allQuestions);
      expect(defaults.quizAllQuestions, isTrue);
      expect(defaults.studyTagFilter, isEmpty);

      // 老库里主动选过的具体题数照旧尊重
      expect(
        AppSettings.fromMap(<String, Object?>{'quiz_question_count': 5})
            .quizAllQuestions,
        isFalse,
      );
      expect(
        AppSettings.fromMap(<String, Object?>{'quiz_question_count': 20})
            .quizQuestionCount,
        20,
      );

      // 老库（还没有 study_tag_filter 这个键）里那个旧的默认值 10 当「全部」
      expect(
        AppSettings.fromMap(<String, Object?>{'quiz_question_count': 10})
            .quizAllQuestions,
        isTrue,
      );
      // 一旦保存过设置（新键在了），存什么就是什么，包括用户主动选的 10
      expect(
        AppSettings.fromMap(<String, Object?>{
          'quiz_question_count': 10,
          'study_tag_filter': <Object?>[],
        }).quizQuestionCount,
        10,
      );

      // 存下来的标签会去空白、去重
      expect(
        AppSettings.fromMap(<String, Object?>{
          'study_tag_filter': <Object?>[' 第四单元 ', '第四单元', '', null],
        }).studyTagFilter,
        <String>['第四单元'],
      );
    });

    test('目标保留率越界会夹回去', () {
      expect(const AppSettings(fsrsDesiredRetention: 2).retention,
          AppSettings.maxRetention);
      expect(const AppSettings(fsrsDesiredRetention: 0.1).retention,
          AppSettings.minRetention);
    });
  });

  group('写进真实库', () {
    test('存下去再读出来，设定一个都不少', () async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      const AppSettings saved = AppSettings(
        promptTemplateId: 'strict',
        homeTab: 'export',
        language: CardLanguage.russian,
        schedulerMode: SchedulerMode.fsrs,
        projectionThemeMode: AppThemeMode.light,
      );
      await harness.settings.save(saved);
      final AppSettings loaded = await harness.settings.load();
      expect(loaded.promptTemplateId, 'strict');
      expect(loaded.homeTab, 'export');
      expect(loaded.language, CardLanguage.russian);
      expect(loaded.schedulerMode, SchedulerMode.fsrs);
      expect(loaded.projectionThemeMode, AppThemeMode.light);
    });
  });

  group('界面上的选择会写回设置', () {
    testWidgets('主界面记住停在哪一页，也会把新的选择存下来', (tester) async {
      final TestHarness harness = TestHarness.fake();
      await harness.settings.save(const AppSettings(homeTab: 'demo'));

      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardRepositoryProvider.overrideWithValue(harness.cards),
            answerRecordRepositoryProvider.overrideWithValue(harness.records),
            deckRepositoryProvider.overrideWithValue(harness.decks),
            settingsRepositoryProvider.overrideWithValue(harness.settings),
          ],
          child: const MaterialApp(home: HomeShell()),
        ),
      );
      await tester.pumpAndSettle();

      // 上次停在演示页：打开就应该是演示页
      expect(find.text('课堂演示（投影）'), findsOneWidget);

      await tester.tap(find.text('统计'));
      await tester.pumpAndSettle();
      expect((await harness.settings.load()).homeTab, 'stats');
    });

    testWidgets('导入页记住上次选的 Prompt 模板', (tester) async {
      final TestHarness harness = TestHarness.fake();
      await harness.settings.save(const AppSettings(promptTemplateId: 'batch'));

      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardRepositoryProvider.overrideWithValue(harness.cards),
            answerRecordRepositoryProvider.overrideWithValue(harness.records),
            deckRepositoryProvider.overrideWithValue(harness.decks),
            settingsRepositoryProvider.overrideWithValue(harness.settings),
          ],
          child: const MaterialApp(home: ImportPage()),
        ),
      );
      await tester.pumpAndSettle();

      ChoiceChip chip(String label) =>
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
      expect(chip('批量模板').selected, isTrue);

      await tester.tap(find.widgetWithText(ChoiceChip, '严格精简模板'));
      await tester.pumpAndSettle();
      expect((await harness.settings.load()).promptTemplateId, 'strict');
      expect(chip('严格精简模板').selected, isTrue);
    });
  });
}