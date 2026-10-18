// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/data/ai/api_client.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/card_source.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/ui/pages/import_page.dart';
import 'package:word_flashcards/src/ui/pages/settings_page.dart';

import 'support/test_harness.dart';

/// 两段就能入库的 JSON，字段和 card_parser 认的一致。
const String kCardsJson = '{"cards":['
    '{"word":"abandon","definition":"v. 放弃；抛弃",'
    '"distractors":["v. 遵守；坚持","v. 维持；供养","v. 增加；扩大","v. 分配；指派"],'
    '"phonetic":"/əˈbændən/","example":"He abandoned the plan."},'
    '{"word":"meticulous","definition":"adj. 一丝不苟的",'
    '"distractors":["adj. 漫不经心的","adj. 慷慨的","adj. 沉默的","adj. 固执的"],'
    '"phonetic":"/məˈtɪkjələs/","example":"She is meticulous about details."}'
    ']}';

/// 固定的 API 配置：地址是内置的 DeepSeek 预设，所以设置页里那个 chip 会被选中。
const AppSettings kConfigured = AppSettings(
  apiBaseUrl: 'https://api.deepseek.com/v1',
  apiKey: 'sk-test',
  apiModel: 'deepseek-chat',
  apiTimeoutSeconds: 30,
  apiCacheHours: 24,
);

/// 假的 API 客户端：想看「调了几次」「最后一次请求长什么样」都靠它。
class FakeClient implements AiApiClient {
  FakeClient(this.reply);

  final AiCompletion Function(AiRequest request) reply;

  int calls = 0;
  AiRequest? lastRequest;

  @override
  Future<AiCompletion> complete(AiRequest request) async {
    calls++;
    lastRequest = request;
    return reply(request);
  }

  @override
  void close() {}
}

AiCompletion completionOf(String content, {int promptTokens = 100, int completionTokens = 50}) =>
    AiCompletion(
      content: content,
      model: 'deepseek-chat',
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );

/// 把某个页面装进 ProviderScope；[client] 不传就用默认的 HTTP 客户端（测试里不会真发请求）。
Future<TestHarness> pumpPage(
  WidgetTester tester,
  Widget page, {
  required TestHarness harness,
  AiApiClient? client,
  AppSettings? saved,
}) async {
  if (saved != null) await harness.settings.save(saved);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cardRepositoryProvider.overrideWithValue(harness.cards),
        answerRecordRepositoryProvider.overrideWithValue(harness.records),
        deckRepositoryProvider.overrideWithValue(harness.decks),
        settingsRepositoryProvider.overrideWithValue(harness.settings),
        apiCacheRepositoryProvider.overrideWithValue(harness.cache),
        if (client != null) aiApiClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  setUp(() {
    // 设置页 + 加入页都很长，给一块够高的画布，省得按钮在屏幕外点不到。
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('加入页：模式 B 生成', () {
    testWidgets('切到 API 直连 → 生成 → 原文进粘贴框 → 入库标成「API 生成」',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final TestHarness harness = TestHarness.fake();
      final FakeClient client = FakeClient((_) => completionOf(kCardsJson));
      await pumpPage(
        tester,
        const ImportPage(),
        harness: harness,
        client: client,
        saved: kConfigured,
      );

      // 默认应该落在「API 直连」（因为配好了 API、也没说过要优先手动）。
      expect(find.text('直接生成卡片'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('import-words-field')),
        'abandon\nmeticulous',
      );
      await tester.tap(find.text('生成卡片'));
      await tester.pumpAndSettle();

      expect(client.calls, 1);
      expect(client.lastRequest!.baseUrl, kConfigured.apiBaseUrl);
      expect(client.lastRequest!.model, 'deepseek-chat');
      expect(find.text('生成成功'), findsOneWidget);

      // 原文被填进了粘贴框，后面走的是和模式 A 一模一样的解析入库。
      final TextField jsonField = tester.widget<TextField>(
        find.byKey(const Key('import-json-field')),
      );
      expect(jsonField.controller!.text, contains('meticulous'));
      expect(find.textContaining('解析成功'), findsOneWidget);

      await tester.tap(find.textContaining('合并到当前卡组'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续导入'));
      await tester.pumpAndSettle();

      final cards = await harness.cards.getAll();
      expect(cards.length, 2);
      expect(cards.every((c) => c.source == CardSource.api), isTrue);
    });

    testWidgets('用量写回设置：调用 1 次、输入 100 / 输出 50', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final TestHarness harness = TestHarness.fake();
      final FakeClient client = FakeClient((_) => completionOf(kCardsJson));
      await pumpPage(
        tester,
        const ImportPage(),
        harness: harness,
        client: client,
        saved: kConfigured,
      );

      await tester.enterText(find.byKey(const Key('import-words-field')), 'abandon');
      await tester.tap(find.text('生成卡片'));
      await tester.pumpAndSettle();

      final AppSettings after = await harness.settings.load();
      expect(after.apiCallCount, 1);
      expect(after.apiPromptTokens, 100);
      expect(after.apiCompletionTokens, 50);
    });

    testWidgets('缓存命中：第二次不再请求、不再计费', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final TestHarness harness = TestHarness.fake();
      final FakeClient client = FakeClient((_) => completionOf(kCardsJson));
      await pumpPage(
        tester,
        const ImportPage(),
        harness: harness,
        client: client,
        saved: kConfigured,
      );

      await tester.enterText(find.byKey(const Key('import-words-field')), 'abandon');
      await tester.tap(find.text('生成卡片'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成卡片'));
      await tester.pumpAndSettle();

      expect(client.calls, 1);
      expect(find.textContaining('命中缓存'), findsWidgets);
      final AppSettings after = await harness.settings.load();
      expect(after.apiCallCount, 1, reason: '缓存命中不该算调用次数');
    });

    testWidgets('失败 → 有原因和下一步，能一键降级回网页聊天导入', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final TestHarness harness = TestHarness.fake();
      final FakeClient client = FakeClient(
        (_) => throw const AiApiFailure(
          AiFailureKind.network,
          '连不上 API：connection refused',
          hint: '检查网络或代理；本地模型要确认服务已经启动',
        ),
      );
      await pumpPage(
        tester,
        const ImportPage(),
        harness: harness,
        client: client,
        saved: kConfigured,
      );

      await tester.enterText(find.byKey(const Key('import-words-field')), 'abandon');
      await tester.tap(find.text('生成卡片'));
      await tester.pumpAndSettle();

      expect(find.textContaining('连不上 API'), findsOneWidget);
      expect(find.textContaining('检查网络或代理'), findsOneWidget);

      // 降级：切回模式 A，并且把选择记进设置。
      await tester.tap(find.text('改用网页聊天导入'));
      await tester.pumpAndSettle();
      expect(find.text('复制 Prompt'), findsOneWidget);
      expect((await harness.settings.load()).preferManualMode, isTrue);
    });

    testWidgets('模型答非所问：原文照样进粘贴框，用户能自己修', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final TestHarness harness = TestHarness.fake();
      final FakeClient client =
          FakeClient((_) => completionOf('抱歉，我不能帮你写题目。'));
      await pumpPage(
        tester,
        const ImportPage(),
        harness: harness,
        client: client,
        saved: kConfigured,
      );

      await tester.enterText(find.byKey(const Key('import-words-field')), 'abandon');
      await tester.tap(find.text('生成卡片'));
      await tester.pumpAndSettle();

      final TextField jsonField = tester.widget<TextField>(
        find.byKey(const Key('import-json-field')),
      );
      expect(jsonField.controller!.text, contains('我不能帮你写题目'));
      expect(find.text('改用网页聊天导入'), findsOneWidget);
    });

    testWidgets('没配 API 时切过去：先提示去设置页，不真发请求', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final TestHarness harness = TestHarness.fake();
      final FakeClient client = FakeClient((_) => completionOf(kCardsJson));
      await pumpPage(tester, const ImportPage(), harness: harness, client: client);

      // 没凭据时默认是网页聊天导入。
      expect(find.text('复制 Prompt'), findsOneWidget);
      await tester.tap(find.text('API 直连'));
      await tester.pumpAndSettle();
      expect(find.textContaining('还没有配好 API'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('import-words-field')), 'abandon');
      await tester.tap(find.text('生成卡片'));
      await tester.pumpAndSettle();
      expect(client.calls, 0);
      expect(find.textContaining('还没有配好 API'), findsWidgets);
    });

    testWidgets('模式记在设置里：手动模式不会被「有凭据」顶掉', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final TestHarness harness = TestHarness.fake();
      final FakeClient client = FakeClient((_) => completionOf(kCardsJson));
      await pumpPage(
        tester,
        const ImportPage(),
        harness: harness,
        client: client,
        saved: kConfigured.copyWith(preferManualMode: true),
      );

      expect(find.text('复制 Prompt'), findsOneWidget);
      await tester.tap(find.text('API 直连'));
      await tester.pumpAndSettle();
      expect((await harness.settings.load()).preferManualMode, isFalse);
    });
  });

  group('设置页：模式 B 表单', () {
    testWidgets('点提供商会把地址和模型填好，并存进设置', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final TestHarness harness = TestHarness.fake();
      await pumpPage(tester, const SettingsPage(), harness: harness);

      await tester.tap(find.widgetWithText(ChoiceChip, 'DeepSeek'));
      await tester.pumpAndSettle();

      final AppSettings after = await harness.settings.load();
      expect(after.apiBaseUrl, 'https://api.deepseek.com/v1');
      expect(after.apiModel, 'deepseek-chat');
      expect(after.hasApiCredentials, isFalse, reason: '还差一个 Key');
    });

    testWidgets('测试连接成功：显示毫秒数与模型回复，并累计用量',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final TestHarness harness = TestHarness.fake();
      final FakeClient client = FakeClient(
        (_) => completionOf('正常', promptTokens: 7, completionTokens: 2),
      );
      await pumpPage(
        tester,
        const SettingsPage(),
        harness: harness,
        client: client,
        saved: kConfigured,
      );

      await tester.ensureVisible(find.text('测试连接'));
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();

      expect(find.textContaining('连接正常'), findsOneWidget);
      expect(find.textContaining('正常'), findsWidgets);
      final AppSettings after = await harness.settings.load();
      expect(after.apiCallCount, 1);
      expect(after.apiPromptTokens, 7);
      expect(after.apiCompletionTokens, 2);
    });

    testWidgets('测试连接失败：显示原因与下一步', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final TestHarness harness = TestHarness.fake();
      final FakeClient client = FakeClient(
        (_) => throw const AiApiFailure(
          AiFailureKind.unauthorized,
          '密钥无效或没有权限（401）',
          hint: '检查 API Key 是否过期、有没有多余空格',
        ),
      );
      await pumpPage(
        tester,
        const SettingsPage(),
        harness: harness,
        client: client,
        saved: kConfigured,
      );

      await tester.ensureVisible(find.text('测试连接'));
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();

      expect(find.textContaining('密钥无效或没有权限'), findsOneWidget);
      expect(find.textContaining('检查 API Key'), findsOneWidget);
      expect((await harness.settings.load()).apiCallCount, 0);
    });
  });
}
