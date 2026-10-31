import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/sync_snapshot.dart';
import 'sync_server.dart' show SyncFailure;

/// 对方是谁。够界面决定「要不要问口令」和「显示的设备对不对」。
class SyncPeerInfo {
  const SyncPeerInfo({
    required this.deviceName,
    required this.protocol,
    required this.requiresPin,
  });

  final String deviceName;
  final int protocol;
  final bool requiresPin;
}

/// 同步的客户端：把本机数据推给对方，拿回合并后的整份数据。
class SyncClient {
  SyncClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 整库传输，超时给得比普通 API 宽：几百 MB 的卡在 2.4G Wi-Fi 上也能传完。
  static const Duration timeout = Duration(seconds: 90);

  /// 探一下对方在不在。失败抛 [SyncFailure]（带一句人话）。
  Future<SyncPeerInfo> ping(String baseUrl) async {
    final Uri uri = Uri.parse('$baseUrl/wc/ping');
    late final http.Response response;
    try {
      response = await _client.get(uri, headers: <String, String>{
        'accept': 'application/json',
      }).timeout(timeout);
    } on Object catch (error) {
      throw SyncFailure(_explain(error, baseUrl));
    }
    if (response.statusCode != 200) {
      throw SyncFailure('对方回了 HTTP ${response.statusCode}，不像是这个应用的同步端口');
    }
    final Object? decoded = _decode(response);
    if (decoded is! Map) {
      throw const SyncFailure('对方的回应不是同步服务，检查地址里的端口');
    }
    final Map<String, Object?> map = decoded.cast<String, Object?>();
    return SyncPeerInfo(
      deviceName: (map['device_name'] as String?) ?? '另一台设备',
      protocol: (map['protocol'] as num?)?.toInt() ?? 0,
      requiresPin: map['requires_pin'] == true,
    );
  }

  /// 推一份数据上去，拿回「两边合完之后」的整份数据。
  Future<SyncSnapshot> exchange(
    String baseUrl,
    SyncSnapshot mine, {
    String? pin,
  }) async {
    final Uri uri = Uri.parse('$baseUrl/wc/exchange');
    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
              if (pin != null && pin.isNotEmpty) 'x-wc-pin': pin,
            },
            body: jsonEncode(mine.toJson()),
          )
          .timeout(timeout);
    } on Object catch (error) {
      throw SyncFailure(_explain(error, baseUrl));
    }

    final Object? decoded = _decode(response);
    if (decoded is! Map) {
      throw const SyncFailure('对方的回应看不懂，可能不是同一个版本');
    }
    final Map<String, Object?> map = decoded.cast<String, Object?>();
    if (response.statusCode != 200 || map['ok'] != true) {
      final String message = (map['error'] as String?)?.trim() ?? '';
      if (response.statusCode == 401) {
        throw SyncFailure(message.isEmpty ? '同步口令不对' : message);
      }
      throw SyncFailure(message.isEmpty
          ? '同步失败（HTTP ${response.statusCode}）'
          : message);
    }
    final Object? merged = map['merged'];
    if (merged is! Map) {
      throw const SyncFailure('对方没有返回合并后的数据');
    }
    return SyncSnapshot.fromJson(merged.cast<String, Object?>());
  }

  void close() => _client.close();

  static Object? _decode(http.Response response) {
    // 用 bodyBytes 解：服务端不一定带 charset，http 包会按 latin1 解，
    // 中文词会变成乱码。
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on Object {
      return null;
    }
  }

  static String _explain(Object error, String baseUrl) {
    if (error is TimeoutException) {
      return '对方一直没回应。可能是同一时间只允许一个人同步，过一会儿再试。';
    }
    final String text = error.toString();
    if (text.contains('Connection refused') || text.contains('Failed host lookup')) {
      return '连不上 $baseUrl。检查：对方开了「设备同步」吗？两台设备在同一个 Wi-Fi 吗？'
          'Windows 上第一次监听会弹防火墙提示，要允许。';
    }
    if (text.contains('timed out')) {
      return '连 $baseUrl 超时了。多半是防火墙拦住了端口。';
    }
    return '同步请求失败：$text';
  }
}
