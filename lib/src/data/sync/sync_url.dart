import 'dart:io';

/// 把用户手输的地址整理成可以请求的 base url。
///
/// 允许的写法（局域网里怎么顺手怎么输）：
/// - `192.168.1.5`                      → 补默认端口
/// - `192.168.1.5:8766`
/// - `http://192.168.1.5:8766/`
/// - `[fe80::1]:8766`（IPv6 要带方括号）
///
/// 认不出来就返回 null，界面提示「地址看起来不对」，不要拿一个
/// 拼错的地址去发请求，那样报出来的错会误导人（看起来像对方没开）。
String? normalizeSyncBaseUrl(String raw, {int defaultPort = 8766}) {
  String text = raw.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'http://$text';
  final Uri? uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;

  final int port = uri.hasPort ? uri.port : defaultPort;
  final String host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  String path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return '${uri.scheme}://$host:$port$path';
}

/// 这台机器在局域网里的 IPv4 地址（给「把地址念给对方」用）。
///
/// 刻意不引 network_info_plus：那个包在安卓上要定位权限，
/// 而这里只需要「本机有哪些网卡地址」，dart:io 自己就能问出来。
/// 会跳过回环与链路本地地址：那些地址对方永远连不上。
Future<List<String>> lanAddresses() async {
  final List<String> result = <String>[];
  try {
    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    for (final NetworkInterface interface in interfaces) {
      for (final InternetAddress address in interface.addresses) {
        final String ip = address.address;
        if (ip.startsWith('169.254.')) continue;
        if (!result.contains(ip)) result.add(ip);
      }
    }
  } on Object {
    // 有些平台（比如受限制的容器）枚举网卡会直接抛错，那就当没有。
    return result;
  }
  return result;
}
