import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:word_flashcards/src/data/api/anki_connect_server.dart';
import 'package:word_flashcards/src/data/api/anki_connect_service.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';

import 'support/test_harness.dart';

/// 线格式：这一层决定 Yomitan 之类的客户端能不能连上。
///
/// 三条规矩都是 AnkiConnect 的既有行为，改了就会让客户端报
/// 「Anki connection failure」这种看不出原因的错误：
/// 1. version >= 5 回 {result, error}；< 5 回裸结果；
/// 2. 动作失败也是信封（HTTP 仍是 200）；
/// 3. 口令不对时回 HTTP 403。
void main() {
  late TestHarness harness;
  late AnkiConnectHandle handle;
  late Uri url;

  setUp(() async {
    harness = await TestHarness.create();
    handle = await startAnkiConnectServer(
      service: AnkiConnectService(
        cards: harness.cards,
        decks: harness.decks,
        settings: harness.settings,
        collection: harness.collection!,
      ),
      settings: harness.settings,
      port: 0,
      allowLan: false,
    );
    url = Uri.parse('http://127.0.0.1:${handle.port}/');
  });

  tearDown(() async {
    await handle.close();
    await harness.dispose();
  });

  Future<http.Response> post(
    Map<String, Object?> body, {
    Map<String, String>? headers,
  }) =>
      http.post(
        url,
        headers: <String, String>{
          'content-type': 'application/json',
          ...?headers,
        },
        body: jsonEncode(body),
      );

  test('version 6 回信封，version 2 回裸结果', () async {
    final http.Response six = await post(<String, Object?>{
      'action': 'version',
      'version': 6,
      'params': <String, Object?>{},
    });
    expect(six.statusCode, 200);
    expect(jsonDecode(six.body), <String, Object?>{'result': 6, 'error': null});

    final http.Response two = await post(<String, Object?>{
      'action': 'version',
      'version': 2,
      'params': <String, Object?>{},
    });
    expect(jsonDecode(two.body), 6);
  });

  test('动作失败也是信封，HTTP 200', () async {
    final http.Response response = await post(<String, Object?>{
      'action': 'guiBrowse',
      'version': 2,
      'params': <String, Object?>{},
    });
    expect(response.statusCode, 200);
    final Map<String, Object?> body =
        (jsonDecode(response.body) as Map).cast<String, Object?>();
    expect(body['error'], 'unsupported action');
    expect(body['result'], isNull);
  });

  test('设了口令：没带 key 403，带了就正常', () async {
    await harness.settings.save(
      const AppSettings(apiServerKey: 'secret'),
    );
    final http.Response denied = await post(<String, Object?>{
      'action': 'version',
      'version': 6,
      'params': <String, Object?>{},
    });
    expect(denied.statusCode, 403);

    final http.Response allowed = await post(<String, Object?>{
      'action': 'version',
      'version': 6,
      'key': 'secret',
      'params': <String, Object?>{},
    });
    expect(allowed.statusCode, 200);
    expect(
      (jsonDecode(allowed.body) as Map)['result'],
      6,
    );
  });

  test('requestPermission 不校验口令，否则客户端先问就被挡住', () async {
    await harness.settings.save(
      const AppSettings(apiServerKey: 'secret'),
    );
    final http.Response response = await post(<String, Object?>{
      'action': 'requestPermission',
      'version': 6,
      'params': <String, Object?>{},
    });
    expect(response.statusCode, 200);
    final Map<String, Object?> body =
        (jsonDecode(response.body) as Map).cast<String, Object?>();
    final Map<String, Object?> result =
        (body['result']! as Map).cast<String, Object?>();
    expect(result['permission'], 'granted');
    expect(result['requireApikey'], isTrue);
  });

  test('OPTIONS 预检能过（浏览器扩展要它）', () async {
    final http.Request request = http.Request('OPTIONS', url);
    request.headers['origin'] = 'moz-extension://abc';
    request.headers['access-control-request-method'] = 'POST';
    final http.StreamedResponse response =
        await http.Client().send(request);
    expect(response.statusCode, 204);
    expect(response.headers['access-control-allow-origin'], '*');
  });

  test('一个完整的加卡请求走后，卡片真的在库里', () async {
    final http.Response response = await post(<String, Object?>{
      'action': 'addNote',
      'version': 6,
      'params': <String, Object?>{
        'note': <String, Object?>{
          'deckName': '默认词库',
          'modelName': 'Basic',
          'fields': <String, Object?>{'Front': 'harbor', 'Back': 'n. 港口'},
          'tags': <String>['lang::en'],
        },
      },
    });
    final Map<String, Object?> body =
        (jsonDecode(response.body) as Map).cast<String, Object?>();
    expect(body['error'], isNull);
    expect(body['result'], isA<int>());
    expect(await harness.cards.count(), 1);
  });
}
