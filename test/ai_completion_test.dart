// 「AI 补全」：解析、缓存、失败口径。不发真实请求。
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/data/ai/api_client.dart';
import 'package:word_flashcards/src/data/ai/card_completion.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/card_language.dart';

import 'support/fake_api_cache.dart';

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

const String kReply = '''```json
{
  "phonetic": "/əˈbændən/",
  "partOfSpeech": "verb",
  "example": "He abandoned the plan without a word.",
  "note": "a-band-on：丢下 band（乐队）自己走了",
  "distractors": ["v. 遵守；坚持", "v. 维持；供养", "v. 增加；扩大", "v. 分配；指派",],
}
```''';

const AppSettings configured = AppSettings(
  apiBaseUrl: 'https://api.example.com/v1',
  apiKey: 'sk-test',
  apiModel: 'test-model',
  apiCacheHours: 24,
);

void main() {
  group('解析模型返回', () {
    test('代码块 + 尾随逗号都能修', () {
      final CardCompletion? parsed = CardCompletion.parse(kReply);
      expect(parsed, isNotNull);
      expect(parsed!.phonetic, '/əˈbændən/');
      expect(parsed.partOfSpeech, 'verb');
      expect(parsed.example, contains('abandoned'));
      expect(parsed.note, contains('乐队'));
      expect(parsed.distractors, hasLength(4));
      expect(parsed.filledLabels, <String>['音标', '词性', '例句', '备注', '干扰项']);
    });

    test('字段名换个写法也认', () {
      final CardCompletion? parsed = CardCompletion.parse(
        '{"ipa":"/x/","pos":"noun","sentence":"An example.","distractors":"甲，乙"}',
      );
      expect(parsed?.phonetic, '/x/');
      expect(parsed?.partOfSpeech, 'noun');
      expect(parsed?.example, 'An example.');
      expect(parsed?.distractors, <String>['甲', '乙']);
    });

    test('什么都没有就返回 null', () {
      expect(CardCompletion.parse('抱歉，我不能帮忙。'), isNull);
      expect(CardCompletion.parse('{}'), isNull);
    });
  });

  group('补全服务', () {
    test('成功：发请求、解析、写缓存、带 token', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client = FakeClient(
        (_) => const AiCompletion(
          content: kReply,
          model: 'test-model',
          promptTokens: 120,
          completionTokens: 80,
        ),
      );
      final CardCompletionService service = CardCompletionService(
        client: client,
        cache: cache,
        clock: () => DateTime(2026, 3, 1, 12),
      );

      final CardCompletionOutcome outcome = await service.complete(
        word: 'abandon',
        definition: 'v. 放弃；抛弃',
        language: CardLanguage.english,
        settings: configured,
      );

      expect(outcome.ok, isTrue);
      expect(outcome.fromCache, isFalse);
      expect(outcome.completion!.distractors, hasLength(4));
      expect(outcome.promptTokens, 120);
      expect(outcome.completionTokens, 80);
      expect(cache.writeCount, 1);

      final AiRequest sent = client.lastRequest!;
      expect(sent.baseUrl, configured.apiBaseUrl);
      expect(sent.apiKey, 'sk-test');
      expect(sent.prompt, contains('abandon'));
      expect(sent.prompt, contains('v. 放弃；抛弃'));
      // 要求给「容易混淆」的干扰项，这是这一功能的重点
      expect(sent.prompt, contains('混淆'));
    });

    test('同一个词第二次走缓存，不再请求', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client = FakeClient(
        (_) => const AiCompletion(content: kReply, promptTokens: 10),
      );
      final CardCompletionService service = CardCompletionService(
        client: client,
        cache: cache,
        clock: () => DateTime(2026, 3, 1, 12),
      );

      await service.complete(
        word: 'abandon',
        definition: 'v. 放弃',
        language: CardLanguage.english,
        settings: configured,
      );
      final CardCompletionOutcome again = await service.complete(
        word: 'abandon',
        definition: 'v. 放弃',
        language: CardLanguage.english,
        settings: configured,
      );

      expect(client.calls, 1);
      expect(again.fromCache, isTrue);
      expect(again.ok, isTrue);
    });

    test('没配 API：给出 notConfigured 与明确的下一步', () async {
      final FakeClient client = FakeClient(
        (_) => const AiCompletion(content: kReply),
      );
      final CardCompletionService service = CardCompletionService(
        client: client,
        cache: FakeApiCacheRepository(),
      );

      final CardCompletionOutcome outcome = await service.complete(
        word: 'abandon',
        definition: 'v. 放弃',
        language: CardLanguage.english,
        settings: const AppSettings(),
      );

      expect(outcome.ok, isFalse);
      expect(outcome.failure!.kind, AiFailureKind.notConfigured);
      expect(outcome.failure!.hint, contains('设置页'));
      expect(client.calls, 0);
    });

    test('必填项没填：emptyInput，连请求都不发', () async {
      final FakeClient client = FakeClient(
        (_) => const AiCompletion(content: kReply),
      );
      final CardCompletionService service = CardCompletionService(
        client: client,
        cache: FakeApiCacheRepository(),
      );

      final CardCompletionOutcome outcome = await service.complete(
        word: '  ',
        definition: 'v. 放弃',
        language: CardLanguage.english,
        settings: configured,
      );

      expect(outcome.failure!.kind, AiFailureKind.emptyInput);
      expect(client.calls, 0);
    });

    test('模型胡说八道：unparsable，原文留着，不写缓存', () async {
      final FakeApiCacheRepository cache = FakeApiCacheRepository();
      final FakeClient client = FakeClient(
        (_) => const AiCompletion(content: '这个单词很好，但我就不给 JSON。'),
      );
      final CardCompletionService service = CardCompletionService(
        client: client,
        cache: cache,
        clock: () => DateTime(2026, 3, 1, 12),
      );

      final CardCompletionOutcome outcome = await service.complete(
        word: 'abandon',
        definition: 'v. 放弃',
        language: CardLanguage.english,
        settings: configured,
      );

      expect(outcome.ok, isFalse);
      expect(outcome.failure!.kind, AiFailureKind.unparsable);
      expect(outcome.response, isNotEmpty);
      expect(cache.writeCount, 0);
    });
  });
}
