import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/data/ai/api_client.dart';
import 'package:word_cards/src/data/ai/generation_service.dart';
import 'package:word_cards/src/data/ai/prompt_templates.dart';
import 'package:word_cards/src/domain/models/app_settings.dart';
import 'package:word_cards/src/domain/models/card_language.dart';
import 'package:word_cards/src/domain/models/cached_generation.dart';

import 'support/fake_api_cache.dart';

/// 示例 JSON：字段和 card_parser 认的完全一致。
const String kCardsJson = '{"cards":['
    '{"word":"abandon","definition":"v. 放弃；抛弃",'
    '"distractors":["v. 遵守；坚持","v. 维持；供养","v. 增加；扩大","v. 分配；指派"],'
    '"phonetic":"/əˈbændən/","example":"He abandoned the plan."},'
    '{"word":"meticulous","definition":"adj. 一丝不苟的",'
    '"distractors":["adj. 漫不经心的","adj. 慷慨的","adj. 沉默的","adj. 固执的"],'
    '"phonetic":"/məˈtɪkjələs/","example":"She is meticulous about details."}'
    ']}';

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

AiCompletion completionOf(
  String content, {
  int promptTokens = 100,
  int completionTokens = 50,
}) =>
    AiCompletion(
      content: content,
      model: 'test-model',
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );

const AppSettings configured = AppSettings(
  apiBaseUrl: 'https://api.example.com/v1',
  apiKey: 'sk-test',
  apiModel: 'test-model',
  apiTimeoutSeconds: 30,
  apiCacheHours: 24,
);

GenerationService serviceWith(
  FakeClient client,
  FakeApiCacheRepository cache, {
  DateTime Function()? clock,
}) =>
    GenerationService(
      client: client,
      cache: cache,
      clock: clock ?? () => DateTime(2026, 3, 1, 12),
    );

Future<GenerationOutcome> run(
  GenerationService service, {
  String words = 'abandon\nmeticulous',
  AppSettings settings = configured,
  PromptTemplate? template,
}) =>
    service.generate(
      words: words,
      template: template ?? kPromptTemplates.first,
      language: CardLanguage.english,
      settings: settings,
    );

void main() {
  group('生成成功', () {
    test('解析出卡片，并写进缓存', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client = FakeClient((_) => completionOf(kCardsJson));
      final GenerationOutcome outcome =
          await run(serviceWith(client, cache));

      expect(outcome.ok, isTrue);
      expect(outcome.cardCount, 2);
      expect(outcome.fromCache, isFalse);
      expect(client.calls, 1);
      expect(cache.writeCount, 1);
      expect(await cache.count(), 1);
      expect(outcome.promptTokens, 100);
      expect(outcome.completionTokens, 50);
      expect(outcome.response, kCardsJson);
    });

    test('请求里带的是配置里的地址/密钥/模型与超时', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client = FakeClient((_) => completionOf(kCardsJson));
      await run(serviceWith(client, cache));

      final AiRequest sent = client.lastRequest!;
      expect(sent.baseUrl, configured.apiBaseUrl);
      expect(sent.apiKey, 'sk-test');
      expect(sent.model, 'test-model');
      expect(sent.timeoutSeconds, 30);
      expect(sent.prompt, contains('abandon'));
    });

    test('Prompt 里带上语言（日语模板会说日语）', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client = FakeClient((_) => completionOf(kCardsJson));
      final GenerationService service = serviceWith(client, cache);
      await service.generate(
        words: 'abandon',
        template: kPromptTemplates.first,
        language: CardLanguage.japanese,
        settings: configured,
      );
      expect(client.lastRequest!.prompt, contains(CardLanguage.japanese.label));
    });
  });

  group('缓存', () {
    test('同一个 Prompt 第二次直接命中，不再请求、不再计费', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client = FakeClient((_) => completionOf(kCardsJson));
      final GenerationService service = serviceWith(client, cache);

      final GenerationOutcome first = await run(service);
      final GenerationOutcome second = await run(service);

      expect(first.fromCache, isFalse);
      expect(second.fromCache, isTrue);
      expect(second.cardCount, 2);
      expect(second.totalTokens, 0);
      expect(client.calls, 1);
      expect(cache.writeCount, 1);
    });

    test('缓存过期（超过 apiCacheHours）会重新请求', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client = FakeClient((_) => completionOf(kCardsJson));
      DateTime now = DateTime(2026, 3, 1, 12);
      final GenerationService service =
          serviceWith(client, cache, clock: () => now);

      await run(service);
      now = now.add(const Duration(hours: 23));
      expect((await run(service)).fromCache, isTrue);
      now = now.add(const Duration(hours: 2));
      final GenerationOutcome later = await run(service);
      expect(later.fromCache, isFalse);
      expect(client.calls, 2);
    });

    test('apiCacheHours = 0 表示不缓存：每次都请求，也不写表', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client = FakeClient((_) => completionOf(kCardsJson));
      final GenerationService service = serviceWith(client, cache);
      const AppSettings noCache = AppSettings(
        apiBaseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-test',
        apiModel: 'test-model',
        apiCacheHours: 0,
      );

      expect((await run(service, settings: noCache)).fromCache, isFalse);
      expect((await run(service, settings: noCache)).fromCache, isFalse);
      expect(client.calls, 2);
      expect(cache.writeCount, 0);
    });

    test('换模型 / 换地址 / 改模板都会换 key，不会拿旧答案糊弄', () {
      final String base = GenerationService.cacheKeyFor(
        baseUrl: 'https://a.com/v1/',
        model: 'm1',
        prompt: 'hello',
      );
      expect(
        base,
        GenerationService.cacheKeyFor(
          baseUrl: 'https://a.com/v1',
          model: ' m1 ',
          prompt: 'hello',
        ),
        reason: '只差空白和结尾斜杠时应该算同一个 key',
      );
      expect(
        base,
        isNot(GenerationService.cacheKeyFor(
          baseUrl: 'https://a.com/v1',
          model: 'm2',
          prompt: 'hello',
        )),
      );
      expect(
        base,
        isNot(GenerationService.cacheKeyFor(
          baseUrl: 'https://b.com/v1',
          model: 'm1',
          prompt: 'hello',
        )),
      );
      expect(
        base,
        isNot(GenerationService.cacheKeyFor(
          baseUrl: 'https://a.com/v1',
          model: 'm1',
          prompt: 'hello!',
        )),
      );
    });

    test('预置的缓存条目能被直接命中', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client = FakeClient((_) => completionOf('不该被调用'));
      final GenerationService service = serviceWith(client, cache);
      final String key = GenerationService.cacheKeyFor(
        baseUrl: configured.apiBaseUrl!,
        model: configured.apiModel!,
        prompt: kPromptTemplates.first.build('abandon\nmeticulous'),
      );
      cache.seed(
        CachedGeneration(
          key: key,
          response: kCardsJson,
          createdAt: DateTime(2026, 3, 1, 11),
        ),
      );

      final GenerationOutcome outcome = await run(service);
      expect(outcome.fromCache, isTrue);
      expect(outcome.cardCount, 2);
      expect(client.calls, 0);
    });
  });

  group('失败与降级', () {
    test('解析不出卡片 → unparsable，保留原文，且不写缓存', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client =
          FakeClient((_) => completionOf('抱歉，我不能帮你写题目。'));
      final GenerationOutcome outcome = await run(serviceWith(client, cache));

      expect(outcome.ok, isFalse);
      expect(outcome.failure!.kind, AiFailureKind.unparsable);
      expect(outcome.hasRawResponse, isTrue, reason: '要让用户能把原文贴回模式 A 手改');
      expect(cache.writeCount, 0);
    });

    test('客户端报错原样带出来（比如密钥无效）', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client = FakeClient(
        (_) => throw const AiApiFailure(
          AiFailureKind.unauthorized,
          '密钥无效',
          hint: '换一个 Key',
        ),
      );
      final GenerationOutcome outcome = await run(serviceWith(client, cache));
      expect(outcome.failure!.kind, AiFailureKind.unauthorized);
      expect(outcome.failure!.hint, '换一个 Key');
      expect(outcome.failure!.isRetryable, isFalse);
    });

    test('客户端抛别的异常也会被包成 network，不让界面崩', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client =
          FakeClient((_) => throw StateError('boom'));
      final GenerationOutcome outcome = await run(serviceWith(client, cache));
      expect(outcome.failure!.kind, AiFailureKind.network);
      expect(outcome.failure!.message, contains('boom'));
    });

    test('没输入单词 → emptyInput，且一次请求都不发', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client = FakeClient((_) => completionOf(kCardsJson));
      final GenerationOutcome outcome =
          await run(serviceWith(client, cache), words: '   ');
      expect(outcome.failure!.kind, AiFailureKind.emptyInput);
      expect(client.calls, 0);
    });

    test('没配好 API → notConfigured，引导去设置页或回模式 A', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client = FakeClient((_) => completionOf(kCardsJson));
      final GenerationOutcome outcome = await run(
        serviceWith(client, cache),
        settings: const AppSettings(),
      );
      expect(outcome.failure!.kind, AiFailureKind.notConfigured);
      expect(outcome.failure!.hint, contains('设置页'));
      expect(client.calls, 0);
    });
  });
}
