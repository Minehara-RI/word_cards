import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:word_flashcards/main.dart' as app;
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/card_language.dart';
import 'package:word_flashcards/src/domain/models/deck.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/state/projection_controller.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/state/quiz_controller.dart';
import 'package:word_flashcards/src/ui/pages/add_page.dart';
import 'package:word_flashcards/src/ui/pages/home_shell.dart';
import 'package:word_flashcards/src/ui/pages/import_page.dart';
import 'package:word_flashcards/src/ui/pages/settings_page.dart';
import 'package:word_flashcards/src/ui/pages/study_page.dart';
import 'package:word_flashcards/src/ui/pages/projection_page.dart';
import 'package:word_flashcards/src/ui/pages/stats_page.dart';
import 'package:word_flashcards/src/ui/pages/quiz_page.dart';

/// 在真实的 Windows 桌面窗口上跑一遍端到端：
/// 清空数据 -> 作答页调参数（限时 / 正误 / FSRS）-> 选卡组 -> 导入带标签与语言的卡片
/// -> 限时测验（含一次超时）-> 成绩单 -> 统计 -> 演示模式（深色 + 限时自动翻页）。
///
/// 用的是真实 Anki（SQLite）库 + 真实 path_provider，所以顺带验证了持久化。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 这个测试的第一步是「清空全部卡片」，跑在真实数据目录上会把用户的词库清空
  //（2026-10-18 就这么清过一次）。所以必须用临时目录启动：
  //   pwsh -File scripts\verify.ps1
  //   flutter test integration_test/app_test.dart -d windows --dart-define=WORD_CARDS_DATA_DIR=<临时目录>
  const String dataDirOverride = String.fromEnvironment('WORD_CARDS_DATA_DIR');
  if (dataDirOverride.isEmpty) {
    throw StateError(
      '集成测试必须指定临时数据目录，否则会清掉真实词库。'
      '请跑 pwsh -File scripts\verify.ps1，或自己加 '
      '--dart-define=WORD_CARDS_DATA_DIR=<临时目录>。',
    );
  }

  /// 桌面窗口只有 720 高，很多控件在折叠线以下，点之前必须先把它们滚进可视区。
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 桌面窗口矮，长页面里的控件要先把页面滚到它那儿，find 才找得到。
  /// [up] 为 true 时往回滚（页面之前被滚下去过，要回到顶部附近）。
  Future<void> scrollTo(
    WidgetTester tester,
    Type page,
    Finder finder, {
    bool up = false,
  }) async {
    await tester.dragUntilVisible(
      finder,
      find
          .descendant(
            of: find.byType(page),
            matching: find.byType(Scrollable),
          )
          .first,
      up ? const Offset(0, 260) : const Offset(0, -260),
    );
    await tester.pumpAndSettle();
  }

  /// 等某个条件成立（真实时钟）。
  Future<void> waitFor(
    WidgetTester tester,
    bool Function() ready, {
    Duration timeout = const Duration(seconds: 25),
    String? reason,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    }
    fail(reason ?? '等待条件超时');
  }

  testWidgets('端到端：导入（标签/语言/卡组）-> 限时测验 -> 统计 -> FSRS -> 演示模式',
      (tester) async {
    await app.main(<String>[]);
    await tester.pumpAndSettle();

    // ---------- 1. 清空历史数据 ----------
    await tapVisible(tester, find.byTooltip('设置'));
    expect(find.text('设置'), findsWidgets);
    expect(find.text('演示模式（全屏投影）'), findsOneWidget);
    await scrollTo(tester, SettingsPage, find.text('当前卡组'));
    expect(find.text('当前卡组'), findsOneWidget);
    await scrollTo(tester, SettingsPage, find.text('清空全部卡片'));
    await tapVisible(tester, find.text('清空全部卡片'));
    await tapVisible(tester, find.widgetWithText(FilledButton, '确定'));
    await tapVisible(tester, find.byType(BackButton));

    // ---------- 2. 本轮参数在作答页直接改 ----------
    await tapVisible(tester, find.text('作答'));
    await scrollTo(tester, StudyPage, find.byKey(const Key('time-limit-field')));
    final limitField = find.byKey(const Key('time-limit-field'));
    await tester.ensureVisible(limitField);
    await tester.enterText(limitField, '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    // 正误显示时机要显式设回「立即显示」：应用会记住上一次的选择
    await scrollTo(tester, StudyPage, find.text('立即显示'));
    await tapVisible(tester, find.text('立即显示'));
    // 复习算法换成 FSRS-6（和原有算法互不干扰）
    await scrollTo(tester, StudyPage, find.text('FSRS-6'));
    await tapVisible(tester, find.text('FSRS-6'));
    expect(find.textContaining('目标保留率'), findsOneWidget);

    // ---------- 3. 选回默认卡组，再导入带标签与语言的卡片 ----------
    await tapVisible(tester, find.text('加入'));
    await tapVisible(tester, find.text('更换卡组'));
    // 卡组名可能和 DeckBar 上的文字撞车，所以在对话框里找
    final defaultDeckOption = find.descendant(
      of: find.byType(SimpleDialog),
      matching: find.text('默认词库'),
    );
    await tester.tap(defaultDeckOption.first);
    await tester.pumpAndSettle();
    expect(find.textContaining('默认词库'), findsWidgets);

    await scrollTo(tester, AddPage, find.text('粘贴 JSON 批量导入'));
    await tapVisible(tester, find.text('粘贴 JSON 批量导入'));
    await scrollTo(tester, ImportPage, find.text('填入示例数据'));
    await tapVisible(tester, find.text('填入示例数据'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.textContaining('解析成功：3 张卡片'), findsOneWidget);

    // 整批标签 + 语言
    await scrollTo(tester, ImportPage, find.byKey(const Key('import-tags-field')));
    await tester.enterText(find.byKey(const Key('import-tags-field')), 'E2E，第四单元');
    await tester.pumpAndSettle();
    await scrollTo(tester, ImportPage, find.widgetWithText(ChoiceChip, '日语'));
    await tapVisible(tester, find.widgetWithText(ChoiceChip, '日语'));

    await scrollTo(tester, ImportPage, find.text('合并到当前卡组（3 张）'));
    await tapVisible(tester, find.text('合并到当前卡组（3 张）'));
    expect(find.text('成功导入 3 张'), findsOneWidget);

    // 标签、语言、卡组都落到数据里了。
    // 注意：导入页盖在壳子上面，壳子那一层是 offstage 的，
    // 默认 finder 会跳过 offstage，所以要显式带上 skipOffstage: false。
    final importContainer = ProviderScope.containerOf(
      tester.element(find.byType(HomeShell, skipOffstage: false)),
    );
    final List<WordCard> imported =
        await importContainer.read(cardRepositoryProvider).getAll();
    expect(imported, hasLength(3));
    for (final WordCard card in imported) {
      expect(card.language, CardLanguage.japanese);
      expect(card.tags, <String>['E2E', '第四单元']);
      expect(card.deckId, Deck.defaultDeckId);
    }

    // ---------- 4. 开始测验 ----------
    await tapVisible(tester, find.text('立即测验'));
    expect(find.byType(QuizPage), findsOneWidget);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(QuizPage)));

    expect(container.read(quizControllerProvider).timeLimitMs, 5000);
    expect(find.textContaining('超时自动下一题'), findsOneWidget);

    // ---------- 5. 第 1 题故意不作答，等它超时 ----------
    final firstCard = container.read(quizControllerProvider).current!.card.word;
    expect(container.read(quizControllerProvider).timedOut, isFalse);

    await waitFor(
      tester,
      () => container.read(quizControllerProvider).timedOut,
      timeout: const Duration(seconds: 15),
      reason: '第 1 题应该在 5 秒限时后判超时',
    );
    expect(find.textContaining('已超时'), findsOneWidget);

    await waitFor(
      tester,
      () {
        final state = container.read(quizControllerProvider);
        return state.index == 1 && !state.timedOut;
      },
      timeout: const Duration(seconds: 10),
      reason: '超时后应该自动进入下一题',
    );
    expect(container.read(quizControllerProvider).current!.card.word,
        isNot(firstCard));

    // ---------- 6. 剩下两题全部答对 ----------
    for (var i = 0; i < 2; i++) {
      final question = container.read(quizControllerProvider).current!;
      expect(question.options, hasLength(5));

      await tester.ensureVisible(find.text(question.correctOption));
      await tester.pumpAndSettle();
      await tester.tap(find.text(question.correctOption));
      await tester.pump();

      final answered = container.read(quizControllerProvider);
      expect(answered.isAnswered, isTrue);
      expect(answered.currentCorrect, isTrue);
      expect(answered.timedOut, isFalse);

      await waitFor(
        tester,
        () => container.read(quizControllerProvider).isAnswered == false ||
            container.read(quizControllerProvider).status ==
                QuizStatus.finished,
        timeout: const Duration(seconds: 6),
        reason: '作答后应该自动进入下一题',
      );
    }

    // ---------- 7. 成绩单：2 对 1 超时 ----------
    final finished = container.read(quizControllerProvider);
    expect(finished.status, QuizStatus.finished);
    expect(finished.records, hasLength(3));
    expect(finished.records.where((r) => r.timedOut).length, 1);
    expect(finished.correctCount, 2);
    expect(find.text('67%'), findsOneWidget);
    expect(find.textContaining('答对 2 / 3 题'), findsOneWidget);
    expect(find.textContaining('其中 1 题超时未作答'), findsOneWidget);
    expect(find.textContaining('超时未作答  →'), findsOneWidget);

    // ---------- 8. 回首页：统计有内容，FSRS 记忆状态也写进去了 ----------
    await tapVisible(tester, find.text('返回首页'));
    await tapVisible(tester, find.text('作答'));
    // 这一页刚才被滚下去过，先回到顶部再看概览
    await scrollTo(tester, StudyPage, find.text('卡片总数'), up: true);
    expect(find.text('卡片总数'), findsOneWidget);
    expect(find.text('今日答题'), findsOneWidget);

    final List<WordCard> afterQuiz =
        await importContainer.read(cardRepositoryProvider).getAll();
    for (final WordCard card in afterQuiz) {
      expect(card.fsrs, isNotNull, reason: '开着 FSRS 答完题就该有记忆状态');
      expect(card.fsrs!.stability, greaterThan(0));
      expect(card.fsrs!.reps, greaterThan(0));
      // 老字段照旧在更新，两套数据互不覆盖
      expect(card.reviewCount, greaterThan(0));
    }

    await tapVisible(tester, find.text('统计'));
    expect(find.text('总览'), findsOneWidget);
    expect(find.text('掌握度分布'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('最需要加强的词'),
      find
          .descendant(
            of: find.byType(StatsPage),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('最需要加强的词'), findsOneWidget);

    // ---------- 9. 演示模式：深色外观 + 每词 1 秒自动翻页 ----------
    final shellContainer = ProviderScope.containerOf(
      tester.element(find.byType(HomeShell, skipOffstage: false)),
    );
    final recordsBefore = await shellContainer
        .read(answerRecordRepositoryProvider)
        .getAll();

    await tapVisible(tester, find.text('演示'));
    // 演示模式单独的深浅色：主界面是深色，这里显式选深色
    await scrollTo(tester, ProjectionPage, find.text('深色'));
    await tapVisible(tester, find.text('深色'));
    await waitFor(
      tester,
      () =>
          shellContainer.read(currentSettingsProvider).projectionThemeMode ==
          AppThemeMode.dark,
      timeout: const Duration(seconds: 6),
      reason: '演示外观应该能单独设置',
    );

    // 刚才是往下滚到「演示外观」的，这题停留输入框在上面，要往回滚
    await scrollTo(
      tester,
      ProjectionPage,
      find.byKey(const Key('projection-interval-field')),
      up: true,
    );
    final intervalField = find.byKey(const Key('projection-interval-field'));
    await tester.ensureVisible(intervalField);
    await tester.pumpAndSettle();
    await tester.enterText(intervalField, '1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await waitFor(
      tester,
      () =>
          shellContainer
              .read(currentSettingsProvider)
              .projectionIntervalSeconds ==
          1,
      timeout: const Duration(seconds: 6),
      reason: '演示限时也应该能直接输入',
    );

    await scrollTo(tester, ProjectionPage, find.text('开始演示'));
    await tapVisible(tester, find.text('开始演示'));

    // 桌面端会另开一个最大化的演示窗口；主窗口这边只显示状态 + 停止按钮。
    // （演示窗口是另一个引擎，测试里断言不到它的内容，所以这里验证主窗口这一侧：
    //  控制器在推进、每一帧推给了窗口、并且不产生任何答题记录。）
    await scrollTo(tester, ProjectionPage, find.text('演示已在另一个窗口播放'));
    expect(find.text('演示已在另一个窗口播放'), findsOneWidget);
    expect(
      shellContainer.read(projectionControllerProvider).status,
      ProjectionStatus.running,
    );
    expect(
      shellContainer.read(projectionControllerProvider).intervalMs,
      1000,
    );

    final firstWord = shellContainer
        .read(projectionControllerProvider)
        .current!
        .card
        .word;
    await waitFor(
      tester,
      () =>
          shellContainer
              .read(projectionControllerProvider)
              .current
              ?.card
              .word !=
          firstWord,
      timeout: const Duration(seconds: 8),
      reason: '每个词停留 1 秒后应该自动换到下一个',
    );

    // 演示是纯展示，不该产生任何答题记录
    final recordsAfter =
        await shellContainer.read(answerRecordRepositoryProvider).getAll();
    expect(recordsAfter.length, recordsBefore.length);

    // 停掉演示：窗口关掉、控制器结束、答案 txt 写出来
    await tapVisible(tester, find.text('停止演示'));
    await waitFor(
      tester,
      () =>
          shellContainer.read(projectionControllerProvider).status !=
          ProjectionStatus.running,
      timeout: const Duration(seconds: 10),
      reason: '停止演示后控制器应该结束',
    );
    await waitFor(
      tester,
      () => shellContainer.read(lastAnswerSheetProvider).sheet != null,
      timeout: const Duration(seconds: 10),
      reason: '演示结束后应该写出答案 txt',
    );
    await scrollTo(tester, ProjectionPage, find.text('开始演示'));
    expect(find.text('开始演示'), findsOneWidget);
  });
}