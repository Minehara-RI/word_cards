// 加入页的「AI 补全」：必填项没填时按钮是灰的、点了要提示；补全只动空格子。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/data/ai/api_client.dart';
import 'package:word_flashcards/src/data/ai/card_completion.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/ui/pages/add_page.dart';

import 'support/fake_api_cache.dart';
import 'support/test_harness.dart';

class _FakeClient implements AiApiClient {
  _FakeClient(this.content);

  final String content;
  int calls = 0;
  AiRequest? lastRequest;

  @override
  Future<AiCompletion> complete(AiRequest request) async {
    calls++;
    lastRequest = request;
    return AiCompletion(
      content: content,
      model: 'test-model',
      promptTokens: 120,
      completionTokens: 80,
    );
  }

  @override
  void close() {}
}

const String _reply =
    '{"phonetic":"/əˈbændən/","partOfSpeech":"verb",'
    '"example":"He abandoned the plan.","note":"a-band-on 记法",'
    '"distractors":["v. 遵守；坚持","v. 维持；供养","v. 增加；扩大","v. 分配；指派"]}';

const AppSettings _configured = AppSettings(
  apiBaseUrl: 'https://api.example.com/v1',
  apiKey: 'sk-test',
  apiModel: 'test-model',
  apiCacheHours: 24,
);

void main() {
  Future<TestHarness> boot(
    WidgetTester tester, {
    required AppSettings settings,
    AiApiClient? client,
  }) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final TestHarness harness = TestHarness.fake();
    await harness.settings.save(settings);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWithValue(harness.cards),
          answerRecordRepositoryProvider.overrideWithValue(harness.records),
          deckRepositoryProvider.overrideWithValue(harness.decks),
          settingsRepositoryProvider.overrideWithValue(harness.settings),
          apiCacheRepositoryProvider.overrideWithValue(harness.cache),
          if (client != null)
            cardCompletionServiceProvider.overrideWithValue(
              CardCompletionService(
                client: client,
                cache: FakeApiCacheRepository(),
                clock: () => DateTime(2026, 3, 1, 12),
              ),
            ),
        ],
        child: const MaterialApp(home: Scaffold(body: AddPage())),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  Finder fieldWithLabel(String label) => find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );

  String fieldText(WidgetTester tester, String label) =>
      tester.widget<TextField>(fieldWithLabel(label)).controller!.text;

  OutlinedButton aiButton(WidgetTester tester) =>
      tester.widget<OutlinedButton>(find.byKey(const Key('add-ai-complete')));

  testWidgets('必填项没填：按钮是灰的，点了告诉用户差什么', (tester) async {
    final _FakeClient client = _FakeClient(_reply);
    await boot(tester, settings: _configured, client: client);

    // 灰是「看起来不能用」，但仍然可点（点了要有反馈）。
    expect(aiButton(tester).onPressed, isNotNull);
    expect(aiButton(tester).style, isNotNull);

    await tester.tap(find.byKey(const Key('add-ai-complete')));
    await tester.pumpAndSettle();

    expect(find.textContaining('先填好单词和释义'), findsOneWidget);
    expect(client.calls, 0);
  });

  testWidgets('填好必填项就能补全：只补空格子，记一次用量', (tester) async {
    final _FakeClient client = _FakeClient(_reply);
    final TestHarness harness =
        await boot(tester, settings: _configured, client: client);

    await tester.enterText(fieldWithLabel('单词 *'), 'abandon');
    await tester.enterText(fieldWithLabel('释义 *'), 'v. 放弃；抛弃');
    await tester.pumpAndSettle();
    // 必填项齐了，按钮不再是灰的
    expect(aiButton(tester).style, isNull);

    await tester.tap(find.byKey(const Key('add-ai-complete')));
    await tester.pumpAndSettle();

    expect(client.calls, 1);
    expect(client.lastRequest!.prompt, contains('abandon'));
    expect(client.lastRequest!.prompt, contains('混淆'));

    expect(fieldText(tester, '音标'), '/əˈbændən/');
    expect(fieldText(tester, '词性'), 'verb');
    expect(fieldText(tester, '例句'), contains('abandoned'));
    expect(fieldText(tester, '备注'), contains('记法'));
    expect(fieldText(tester, '干扰项（每行一个，可留空）').split('\n'), hasLength(4));
    expect(find.textContaining('AI 补全完成'), findsOneWidget);

    final AppSettings saved = await harness.settings.load();
    expect(saved.apiCallCount, 1);
    expect(saved.apiPromptTokens, 120);
    expect(saved.apiCompletionTokens, 80);
  });

  testWidgets('已经填过的格子不会被覆盖', (tester) async {
    final _FakeClient client = _FakeClient(_reply);
    await boot(tester, settings: _configured, client: client);

    await tester.enterText(fieldWithLabel('单词 *'), 'abandon');
    await tester.enterText(fieldWithLabel('释义 *'), 'v. 放弃；抛弃');
    await tester.enterText(fieldWithLabel('音标'), '/我自己写的/');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-ai-complete')));
    await tester.pumpAndSettle();

    expect(fieldText(tester, '音标'), '/我自己写的/');
    expect(fieldText(tester, '例句'), contains('abandoned'));
  });

  testWidgets('没配 API：不偷偷改成复制 Prompt，直接说去哪配', (tester) async {
    final _FakeClient client = _FakeClient(_reply);
    await boot(tester, settings: const AppSettings(), client: client);

    await tester.enterText(fieldWithLabel('单词 *'), 'abandon');
    await tester.enterText(fieldWithLabel('释义 *'), 'v. 放弃；抛弃');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-ai-complete')));
    await tester.pumpAndSettle();

    expect(find.textContaining('这个功能只走 API'), findsOneWidget);
    expect(client.calls, 0);
    expect(fieldText(tester, '音标'), isEmpty);
  });
}
