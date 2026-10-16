import 'package:word_cards/src/domain/models/cached_generation.dart';
import 'package:word_cards/src/domain/repositories.dart';

/// 内存版生成缓存：widget / 单元测试用，不碰磁盘。
class FakeApiCacheRepository implements ApiCacheRepository {
  final Map<String, CachedGeneration> _entries = <String, CachedGeneration>{};

  /// 测试里想看「到底请求了几次」，就检查这个计数。
  int writeCount = 0;

  /// 预置一条缓存，省得测试自己算 key。
  void seed(CachedGeneration entry) => _entries[entry.key] = entry;

  @override
  Future<CachedGeneration?> read(
    String key, {
    required DateTime now,
    required Duration ttl,
  }) async {
    final CachedGeneration? entry = _entries[key];
    if (entry == null) return null;
    if (!entry.isFreshAt(now, ttl)) {
      _entries.remove(key);
      return null;
    }
    return entry;
  }

  @override
  Future<void> write(CachedGeneration entry) async {
    _entries[entry.key] = entry;
    writeCount++;
  }

  @override
  Future<void> clear() async => _entries.clear();

  @override
  Future<int> count() async => _entries.length;
}
