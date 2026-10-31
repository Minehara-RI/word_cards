import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/models/app_settings.dart';
import '../../domain/repositories.dart';
import 'anki_connect_models.dart';
import 'anki_connect_service.dart';

/// 监听中的 AnkiConnect 兼容服务。
class AnkiConnectHandle {
  AnkiConnectHandle._(this._server);

  final HttpServer _server;

  int get port => _server.port;

  Future<void> close() => _server.close(force: true);
}

/// 一个请求最多收多大。加笔记是几十 KB 的事，32 MB 已经很宽松了。
const int _maxBodyBytes = 32 * 1024 * 1024;

/// 开一个 AnkiConnect 兼容的 HTTP 端点。
///
/// 和真的 Anki 插件保持同一套线格式：POST 一个 JSON，回一个 JSON。
/// 三处必须对齐，否则客户端会在奇怪的地方出错：
/// 1. 版本信封 —— version >= 5 回 {result, error}，< 5 回裸结果（Yomitan 就是 2）；
/// 2. 错误也用信封回，HTTP 仍是 200（客户端只看 error 字段）；
/// 3. 不认识的动作用 unsupported action 这个原文（客户端靠它判断「没这个功能」）。
///
/// [allowLan] 为 false 时只监听 127.0.0.1：浏览器插件在本机，够了；
/// 手机上没有插件，想从别的机器写才需要开。
Future<AnkiConnectHandle> startAnkiConnectServer({
  required AnkiConnectService service,
  required SettingsRepository settings,
  required int port,
  required bool allowLan,
}) async {
  final HttpServer server = await HttpServer.bind(
    allowLan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4,
    port,
  );
  server.listen((HttpRequest request) {
    unawaited(_handle(request, service: service, settings: settings));
  });
  return AnkiConnectHandle._(server);
}

Future<void> _handle(
  HttpRequest request, {
  required AnkiConnectService service,
  required SettingsRepository settings,
}) async {
  final HttpResponse response = request.response;
  // Yomitan 的 fetch 带 mode:'cors'，没有这几个头连握手都过不去。
  response.headers.set('access-control-allow-origin', '*');
  response.headers.set('access-control-allow-headers', 'content-type, x-api-key, key');
  response.headers.set('access-control-allow-methods', 'POST, OPTIONS');
  response.headers.set('cache-control', 'no-store');

  if (request.method == 'OPTIONS') {
    response.statusCode = HttpStatus.noContent;
    await response.close();
    return;
  }

  if (request.method != 'POST') {
    response.statusCode = HttpStatus.methodNotAllowed;
    response.headers.contentType = ContentType.text;
    response.write('AnkiConnect 只接受 POST');
    await response.close();
    return;
  }

  Map<String, Object?> payload;
  try {
    payload = await _readJson(request);
  } on Object catch (error) {
    response.statusCode = HttpStatus.badRequest;
    await _json(response, <String, Object?>{
      'result': null,
      'error': '请求不是合法的 JSON：$error',
    });
    return;
  }

  final String action = (payload['action'] as String?) ?? '';
  final int version = (payload['version'] as num?)?.toInt() ?? 4;
  final Map<String, Object?> params =
      (payload['params'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};

  final AppSettings current = await settings.load();
  final String expectedKey = current.apiServerKey ?? '';
  // requestPermission 刻意不校验口令：客户端要先问「要不要口令」才能决定
  // 怎么发请求，这一问被挡住就成了死循环。
  if (expectedKey.isNotEmpty && action != 'requestPermission') {
    final String provided = (payload['key'] as String?) ??
        request.headers.value('x-api-key') ??
        '';
    if (provided != expectedKey) {
      response.statusCode = HttpStatus.forbidden;
      await _json(response, <String, Object?>{
        'result': null,
        'error': 'invalid api key',
      });
      return;
    }
  }

  try {
    final Object? result = await service.dispatch(action, params);
    if (version >= 5) {
      await _json(response, <String, Object?>{'result': result, 'error': null});
    } else {
      // v4 及更早：直接把结果当响应体。Yomitan 发的是 version 2，
      // 它拿到数字/数组就直接用，套一层信封反而会让它认为连错了。
      await _json(response, result);
    }
  } on AnkiConnectException catch (error) {
    await _json(response, <String, Object?>{
      'result': null,
      'error': error.message,
    });
  } catch (error) {
    await _json(response, <String, Object?>{
      'result': null,
      'error': 'internal error: $error',
    });
  }
}

Future<Map<String, Object?>> _readJson(HttpRequest request) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in request) {
    builder.add(chunk);
    if (builder.length > _maxBodyBytes) {
      throw const FormatException('请求太大了');
    }
  }
  final Object? decoded = jsonDecode(utf8.decode(builder.takeBytes()));
  if (decoded is! Map) throw const FormatException('请求必须是 JSON 对象');
  return decoded.cast<String, Object?>();
}

Future<void> _json(HttpResponse response, Object? payload) async {
  response.headers.contentType =
      ContentType('application', 'json', charset: 'utf-8');
  response.write(jsonEncode(payload));
  await response.close();
}
