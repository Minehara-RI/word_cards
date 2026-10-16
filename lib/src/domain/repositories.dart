import 'models/answer_record.dart';
import 'models/app_settings.dart';
import 'models/cached_generation.dart';
import 'models/deck.dart';
import 'models/word_card.dart';

/// 卡片仓库。逻辑层只依赖这个接口，不关心底层是 sembast 还是别的实现。
abstract interface class CardRepository {
  /// 监听卡片变化；[deckId] 为空表示全部词库。
  Stream<List<WordCard>> watch({String? deckId});

  Future<List<WordCard>> getAll({String? deckId});

  Future<WordCard?> getById(String id);

  /// 按单词查找（忽略大小写与首尾空白）。
  Future<WordCard?> findByWord(String word, {String? deckId});

  Future<List<WordCard>> findByWords(List<String> words, {String? deckId});

  Future<void> upsert(WordCard card);

  Future<void> upsertAll(List<WordCard> cards);

  Future<void> deleteById(String id);

  Future<void> deleteAll({String? deckId});

  Future<int> count({String? deckId});
}

/// 答题记录仓库。
abstract interface class AnswerRecordRepository {
  Future<void> add(AnswerRecord record);

  Future<void> addAll(List<AnswerRecord> records);

  /// 最近的记录，按时间倒序。
  Future<List<AnswerRecord>> getRecent({int limit = 200});

  Future<List<AnswerRecord>> getSince(DateTime since);

  Future<List<AnswerRecord>> getAll();

  Stream<List<AnswerRecord>> watchRecent({int limit = 200});

  Future<void> deleteAll();
}

/// 词库仓库。
abstract interface class DeckRepository {
  Stream<List<Deck>> watch();

  Future<List<Deck>> getAll();

  Future<void> upsert(Deck deck);

  Future<void> delete(String id);

  /// 保证默认词库存在。
  Future<Deck> ensureDefault();
}

/// 用户配置仓库（单例文档）。
abstract interface class SettingsRepository {
  Stream<AppSettings> watch();

  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

/// 生成结果缓存仓库（模式 B）。
///
/// 存的是模型原文；[read] 会顺手判断有没有过期，过期就当没有。
abstract interface class ApiCacheRepository {
  Future<CachedGeneration?> read(
    String key, {
    required DateTime now,
    required Duration ttl,
  });

  Future<void> write(CachedGeneration entry);

  Future<void> clear();

  Future<int> count();
}

