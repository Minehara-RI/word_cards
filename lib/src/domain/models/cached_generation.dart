/// 一次 API 生成的缓存条目。
///
/// 同一个「地址 + 模型 + 最终 Prompt」在缓存期内只请求一次：
/// 省钱，也避免同一批词被生成两遍。原文（而不是解析后的卡片）入库，
/// 这样解析器以后变聪明了，旧缓存也能跟着受益。
class CachedGeneration {
  const CachedGeneration({
    required this.key,
    required this.response,
    required this.createdAt,
    this.model = '',
    this.promptTokens = 0,
    this.completionTokens = 0,
  });

  /// 缓存键：地址 + 模型 + Prompt 的 sha256。
  final String key;

  /// 模型原样返回的正文（JSON 文本）。
  final String response;

  final String model;

  final int promptTokens;
  final int completionTokens;

  final DateTime createdAt;

  int get totalTokens => promptTokens + completionTokens;

  /// 在 [now] 这个时刻还算不算新鲜（[ttl] 为 0 表示不缓存）。
  bool isFreshAt(DateTime now, Duration ttl) {
    if (ttl <= Duration.zero) return false;
    return now.difference(createdAt) < ttl;
  }
}
