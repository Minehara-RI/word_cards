// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:word_cards/src/data/ai/api_client.dart';

/// 把一次请求「录下来」，方便断言 URL / 头 / 请求体。
class Recorder {
  http.Request? request;
  String? body;
}

HttpAiApiClient clientReturning(
  Object? Function(http.Request request) respond, [
  Recorder? recorder,
]) {
  return HttpAiApiClient(
    client: MockClient((http.Request request) async {
      recorder?.request = request;
      recorder?.body = request.body;
      final Object? result = respond(request);
      if (result is http.Response) return result;
      if (result is Future<http.Response>) return result;
      throw result as Object;
    }),
  );
}

http.Response jsonResponse(Object? payload, {int status = 200}) =>
    http.Response.bytes(utf8.encode(jsonEncode(payload)), status);

AiRequest request({
  String baseUrl = 'https://api.example.com/v1',
  String apiKey = 'sk-test',
  String model = 'test-model',
  int timeoutSeconds = 15,
}) =>
    AiRequest(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      prompt: '生成卡片',
      timeoutSeconds: timeoutSeconds,
    );

Map<String, Object?> okPayload({
  String content = '{"word":"abandon"}',
  String? finishReason,
}) =>
    <String, Object?>{
      'model': 'test-model',
      'choices': <Object?>[
        <String, Object?>{
          'message': <String, Object?>{'role': 'assistant', 'content': content},
          'finish_reason': finishReason ?? 'stop',
        },
      ],
      'usage': <String, Object?>{
        'prompt_tokens': 120,
        'completion_tokens': 80,
      },
    };

void main() {
  group('成功请求', () {
    test('请求长什么样：地址、Bearer、JSON 体', () async {
      final Recorder recorder = Recorder();
      final HttpAiApiClient client = clientReturning(
        (_) => jsonResponse(okPayload()),
        recorder,
      );

      await client.complete(request());

      expect(
        recorder.request!.url.toString(),
        'https://api.example.com/v1/chat/completions',
      );
      expect(recorder.request!.method, 'POST');
      expect(recorder.request!.headers['authorization'], 'Bearer sk-test');
      expect(recorder.request!.headers['content-type'], contains('application/json'));

      final Map<String, Object?> body =
          jsonDecode(recorder.body!) as Map<String, Object?>;
      expect(body['model'], 'test-model');
      expect(body['stream'], false);
      expect(body.containsKey('max_tokens'), isFalse);
      final List<Object?> messages = body['messages']! as List<Object?>;
      final Map<Object?, Object?> first = messages.first! as Map<Object?, Object?>;
      expect(first['role'], 'user');
      expect(first['content'], '生成卡片');
    });

    test('取回正文、token 数和 finish_reason', () async {
      final HttpAiApiClient client =
          clientReturning((_) => jsonResponse(okPayload(content: '你好')));
      final AiCompletion completion = await client.complete(request());
      expect(completion.content, '你好');
      expect(completion.promptTokens, 120);
      expect(completion.completionTokens, 80);
      expect(completion.truncated, isFalse);
    });

    test('中文不乱码：服务端没发 charset 也按 UTF-8 解', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => http.Response.bytes(
          utf8.encode(jsonEncode(okPayload(content: 'v. 放弃；抛弃'))),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        ),
      );
      final AiCompletion completion = await client.complete(request());
      expect(completion.content, 'v. 放弃；抛弃');
    });

    test('已经填了完整端点就不再拼一次', () async {
      final Recorder recorder = Recorder();
      final HttpAiApiClient client =
          clientReturning((_) => jsonResponse(okPayload()), recorder);
      await client.complete(
        request(baseUrl: 'https://api.example.com/v1/chat/completions'),
      );
      expect(
        recorder.request!.url.toString(),
        'https://api.example.com/v1/chat/completions',
      );
    });

    test('本地模型可以不填 Key：不发 authorization 头', () async {
      final Recorder recorder = Recorder();
      final HttpAiApiClient client =
          clientReturning((_) => jsonResponse(okPayload()), recorder);
      await client.complete(
        request(baseUrl: 'http://127.0.0.1:11434/v1', apiKey: ''),
      );
      expect(recorder.request!.headers.containsKey('authorization'), isFalse);
    });

    test('content 是分段数组时拼起来', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => jsonResponse(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{
                'content': <Object?>[
                  <String, Object?>{'type': 'text', 'text': 'ab'},
                  <String, Object?>{'type': 'text', 'text': 'cd'},
                ],
              },
              'finish_reason': 'stop',
            },
          ],
        }),
      );
      expect((await client.complete(request())).content, 'abcd');
    });

    test('被长度截断时会标出来', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => jsonResponse(okPayload(finishReason: 'length')),
      );
      expect((await client.complete(request())).truncated, isTrue);
    });
  });

  group('失败分类', () {
    test('401 → unauthorized，不可重试', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => jsonResponse(<String, Object?>{
          'error': <String, Object?>{'message': 'invalid api key'},
        }, status: 401),
      );
      await expectLater(
        client.complete(request()),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.kind, 'kind', AiFailureKind.unauthorized)
              .having((f) => f.statusCode, 'status', 401)
              .having((f) => f.isRetryable, 'retryable', isFalse)
              .having((f) => f.hint, 'hint', isNotNull),
        ),
      );
    });

    test('400 带出服务端自己的错误信息（比如模型名写错）', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => jsonResponse(<String, Object?>{
          'error': <String, Object?>{'message': 'Model not found: gpt-9'},
        }, status: 400),
      );
      await expectLater(
        client.complete(request()),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.kind, 'kind', AiFailureKind.badRequest)
              .having((f) => f.message, 'message', contains('Model not found')),
        ),
      );
    });

    test('400 但响应不是 JSON 时给出正文片段', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => http.Response('<html>bad gateway</html>', 400),
      );
      await expectLater(
        client.complete(request()),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.message, 'message', contains('bad gateway')),
        ),
      );
    });

    test('404 → badRequest，提示地址写法', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => http.Response('{}', 404),
      );
      await expectLater(
        client.complete(request()),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.kind, 'kind', AiFailureKind.badRequest)
              .having((f) => f.hint, 'hint', contains('/v1')),
        ),
      );
    });

    test('429 → rateLimited，可以重试', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => http.Response('{}', 429),
      );
      await expectLater(
        client.complete(request()),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.kind, 'kind', AiFailureKind.rateLimited)
              .having((f) => f.isRetryable, 'retryable', isTrue),
        ),
      );
    });

    test('503 → serverError', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => http.Response('{}', 503),
      );
      await expectLater(
        client.complete(request()),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.kind, 'kind', AiFailureKind.serverError),
        ),
      );
    });

    test('200 但不是 JSON → badResponse', () async {
      final HttpAiApiClient client =
          clientReturning((_) => http.Response('hello', 200));
      await expectLater(
        client.complete(request()),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.kind, 'kind', AiFailureKind.badResponse),
        ),
      );
    });

    test('200 但没有 choices → badResponse，带上服务端说的话', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => jsonResponse(<String, Object?>{
          'error': <String, Object?>{'message': 'quota exceeded'},
        }),
      );
      await expectLater(
        client.complete(request()),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.kind, 'kind', AiFailureKind.badResponse)
              .having((f) => f.message, 'message', contains('quota exceeded')),
        ),
      );
    });

    test('内容为空 → emptyContent；被截断时提示少给几个词', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => jsonResponse(okPayload(content: '   ', finishReason: 'length')),
      );
      await expectLater(
        client.complete(request()),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.kind, 'kind', AiFailureKind.emptyContent)
              .having((f) => f.hint, 'hint', contains('截断')),
        ),
      );
    });

    test('超时 → timeout', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => TimeoutException('too slow'),
      );
      await expectLater(
        client.complete(request()),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.kind, 'kind', AiFailureKind.timeout)
              .having((f) => f.isRetryable, 'retryable', isTrue),
        ),
      );
    });

    test('连不上 → network，并提示代理/本地服务', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => http.ClientException('connection refused'),
      );
      await expectLater(
        client.complete(request(baseUrl: 'http://127.0.0.1:11434/v1')),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.kind, 'kind', AiFailureKind.network)
              .having((f) => f.hint, 'hint', contains('本地模型')),
        ),
      );
    });

    test('地址为空 / 模型为空 → notConfigured（还没发请求就拦下）', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => jsonResponse(okPayload()),
      );
      await expectLater(
        client.complete(request(baseUrl: '')),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.kind, 'kind', AiFailureKind.notConfigured),
        ),
      );
      await expectLater(
        client.complete(request(model: '  ')),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.kind, 'kind', AiFailureKind.notConfigured),
        ),
      );
    });

    test('地址不是合法链接 → badRequest', () async {
      final HttpAiApiClient client = clientReturning(
        (_) => jsonResponse(okPayload()),
      );
      await expectLater(
        client.complete(request(baseUrl: 'not a url')),
        throwsA(
          isA<AiApiFailure>()
              .having((f) => f.kind, 'kind', AiFailureKind.badRequest),
        ),
      );
    });
  });
}
