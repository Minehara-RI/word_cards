import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/models/sync_snapshot.dart';
import 'sync_service.dart';

/// 同步服务的句柄。关掉它才算真的停止监听。
class SyncServerHandle {
  SyncServerHandle._(this._server);

  final HttpServer _server;

  int get port => _server.port;

  Future<void> close() => _server.close(force: true);
}

/// 收到一个请求时抛这个，界面直接把 message 显示出来。
class SyncFailure implements Exception {
  const SyncFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次同步最多收多大的包。整库现在只有几 MB，留到 128 MB 是给
/// 「几千张卡 + 几万条答题记录」的极端情况，不是给攻击者的。
const int _maxBodyBytes = 128 * 1024 * 1024;

/// 在局域网里开一个同步端点。
///
/// 只开两个路由：
/// - GET  /wc/ping      → 对方是谁、要不要口令、有多少张卡
/// - POST /wc/exchange  → 交换整份数据（对方发来的包 + 本端合并后的包）
///
/// 为什么要 HTTP 而不是 socket 自定义协议：手机上调试、用浏览器看、
/// 以后写脚本都方便，而且现有的 http 包就能测。
Future<SyncServerHandle> startSyncServer({
  required SyncService service,
  required int port,
  required String Function() deviceName,
  String? Function()? pin,
}) async {
  final HttpServer server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  server.listen((HttpRequest request) {
    unawaited(_handle(request, service: service, deviceName: deviceName, pin: pin));
  });
  return SyncServerHandle._(server);
}

Future<void> _handle(
  HttpRequest request, {
  required SyncService service,
  required String Function() deviceName,
  String? Function()? pin,
}) async {
  final HttpResponse response = request.response;
  // 浏览器里用脚本试接口时不会被 CORS 挡住；本机数据本来就要靠口令保护。
  response.headers.set('access-control-allow-origin', '*');
  response.headers.set('access-control-allow-headers', 'content-type, x-wc-pin');
  response.headers.set('access-control-allow-methods', 'GET, POST, OPTIONS');
  response.headers.set('cache-control', 'no-store');

  try {
    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return;
    }

    final String path = request.uri.path;

    if (request.method == 'GET' && path.endsWith('ping')) {
      await _json(response, HttpStatus.ok, <String, Object?>{
        'ok': true,
        'app': 'word_flashcards',
        'protocol': SyncSnapshot.protocol,
        'device_name': deviceName(),
        'requires_pin': (pin?.call() ?? '').isNotEmpty,
      });
      return;
    }

    if (request.method == 'POST' && path.endsWith('exchange')) {
      final String expected = pin?.call() ?? '';
      final String provided = request.headers.value('x-wc-pin') ?? '';
      if (expected.isNotEmpty && provided != expected) {
        await _json(response, HttpStatus.unauthorized, <String, Object?>{
          'ok': false,
          'error': '同步口令不对',
        });
        return;
      }

      final String body = await _readBody(request);
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const SyncFailure('同步包格式不对');
      }
      final SyncSnapshot remote =
          SyncSnapshot.fromJson(decoded.cast<String, Object?>());
      final SyncExchangeResult result =
          await service.acceptRemote(remote, deviceName: deviceName());
      await _json(response, HttpStatus.ok, <String, Object?>{
        'ok': true,
        'applied': result.applied.summary,
        'merged': result.merged.toJson(),
      });
      return;
    }

    if (request.method == 'GET' && (path == '/' || path.isEmpty)) {
      response.statusCode = HttpStatus.ok;
      response.headers.contentType =
          ContentType('text', 'html', charset: 'utf-8');
      response.write('<!doctype html><meta charset="utf-8">'
          '<title>word_flashcards</title>'
          '<body style="font-family:sans-serif;padding:24px">'
          '<h2>这是 word_flashcards 的设备同步端口</h2>'
          '<p>在这里看到这段字，说明同步服务正在运行。</p>'
          '<p>同步要在应用里点「设备同步」，把对方的地址和口令填进去；'
          '这个端口不提供网页界面，也没有可以随手点开的卡片列表。</p>');
      await response.close();
      return;
    }

    await _json(response, HttpStatus.notFound, <String, Object?>{
      'ok': false,
      'error': '没有这个接口',
    });
  } on SyncFailure catch (failure) {
    await _json(response, HttpStatus.badRequest, <String, Object?>{
      'ok': false,
      'error': failure.message,
    });
  } on FormatException catch (error) {
    await _json(response, HttpStatus.badRequest, <String, Object?>{
      'ok': false,
      'error': error.message,
    });
  } catch (error) {
    await _json(response, HttpStatus.internalServerError, <String, Object?>{
      'ok': false,
      'error': '同步失败：$error',
    });
  }
}

Future<String> _readBody(HttpRequest request) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in request) {
    builder.add(chunk);
    if (builder.length > _maxBodyBytes) {
      throw const SyncFailure('同步包太大了');
    }
  }
  return utf8.decode(builder.takeBytes());
}

Future<void> _json(
  HttpResponse response,
  int status,
  Map<String, Object?> payload,
) async {
  response.statusCode = status;
  response.headers.contentType =
      ContentType('application', 'json', charset: 'utf-8');
  response.write(jsonEncode(payload));
  await response.close();
}
