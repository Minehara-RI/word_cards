import 'package:sqlite3/sqlite3.dart';

import '../../domain/models/cached_generation.dart';
import '../../domain/repositories.dart';
import 'anki_collection.dart';

/// 生成缓存的 Anki 实现：单独一张 `wc_api_cache`，Anki 会忽略它。
///
/// 缓存的是**模型原文**，不是解析后的卡片 —— 解析器以后改进了，旧缓存也跟着受益。
class AnkiApiCacheRepository implements ApiCacheRepository {
  AnkiApiCacheRepository(this._collection);

  final AnkiCollection _collection;

  @override
  Future<CachedGeneration?> read(
    String key, {
    required DateTime now,
    required Duration ttl,
  }) async {
    if (ttl <= Duration.zero) return null;
    final ResultSet rows = _collection.db.select(
      'select response, model, prompt_tokens, completion_tokens, created_at '
      'from wc_api_cache where key = ?',
      <Object?>[key],
    );
    if (rows.isEmpty) return null;
    final Row row = rows.first;
    final CachedGeneration entry = CachedGeneration(
      key: key,
      response: row['response'] as String,
      model: (row['model'] as String?) ?? '',
      promptTokens: (row['prompt_tokens'] as int?) ?? 0,
      completionTokens: (row['completion_tokens'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as int?) ?? 0,
      ),
    );
    if (!entry.isFreshAt(now, ttl)) {
      _delete(key);
      return null;
    }
    return entry;
  }

  @override
  Future<void> write(CachedGeneration entry) async {
    _collection.db.execute(
      'insert or replace into wc_api_cache '
      '(key, response, model, prompt_tokens, completion_tokens, created_at) '
      'values (?,?,?,?,?,?)',
      <Object?>[
        entry.key,
        entry.response,
        entry.model,
        entry.promptTokens,
        entry.completionTokens,
        entry.createdAt.millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<void> clear() async {
    _collection.db.execute('delete from wc_api_cache');
  }

  @override
  Future<int> count() async {
    final ResultSet rows =
        _collection.db.select('select count(*) as c from wc_api_cache');
    return (rows.first['c'] as int?) ?? 0;
  }

  void _delete(String key) {
    _collection.db
        .execute('delete from wc_api_cache where key = ?', <Object?>[key]);
  }
}
