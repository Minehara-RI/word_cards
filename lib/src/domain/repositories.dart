import 'models/answer_record.dart';
import 'models/app_settings.dart';
import 'models/cached_generation.dart';
import 'models/deck.dart';
import 'models/sync_snapshot.dart';
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

  /// 清掉学习进度（复习次数、掌握度、FSRS、答题记录），卡片本身保留。
  ///
  /// [deckId] 为空表示整个词库。
  Future<void> resetProgress({String? deckId});

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

/// 设备同步用的本地状态：设备身份 + 删除记录。
///
/// 单独一个接口是因为它既不属于卡片也不属于卡组，而且只有同步链路会用到。
abstract interface class SyncRepository {
  /// 这台设备的稳定 id（第一次调用时生成并落库）。
  Future<String> deviceId();

  /// 所有删除记录（卡片与卡组）。
  Future<List<SyncTombstone>> tombstones();

  /// 记一条删除记录。同一个对象重复记时保留更晚的时间。
  Future<void> addTombstone(SyncTombstone tombstone);

  /// 应用对方同步过来的删除：记下墓碑，并把本地对应的数据删掉。
  ///
  /// 和本地的 deleteById 不是一回事：那个会把删除时间记成「现在」，
  /// 用它来应用一条旧删除，会把对方后来改过的卡片又删掉一次。
  Future<void> applyTombstone(SyncTombstone tombstone);
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

