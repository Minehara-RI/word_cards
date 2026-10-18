import 'package:sembast/sembast.dart';

import '../../domain/models/word_card.dart';
import '../../domain/repositories.dart';
import 'app_database.dart';

/// 基于 sembast 的卡片仓库。
class SembastCardRepository implements CardRepository {
  SembastCardRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  /// 单词的归一化形式，用于查重（忽略大小写、首尾与中间多余空白）。
  static String normalizeWord(String word) =>
      word.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// 落库前补一个归一化字段，避免每次查重都全表扫描后做字符串处理。
  static Map<String, Object?> toRow(WordCard card) => <String, Object?>{
        ...card.toMap(),
        'word_key': normalizeWord(card.word),
      };

  static Finder _finder(String? deckId) => Finder(
        filter: deckId == null ? null : Filter.equals('deck_id', deckId),
        sortOrders: <SortOrder>[SortOrder('word')],
      );

  @override
  Stream<List<WordCard>> watch({String? deckId}) {
    return AppDatabase.cards
        .query(finder: _finder(deckId))
        .onSnapshots(_db)
        .map((snapshots) => snapshots
            .map((snapshot) => WordCard.fromMap(snapshot.value))
            .toList(growable: false));
  }

  @override
  Future<List<WordCard>> getAll({String? deckId}) async {
    final snapshots =
        await AppDatabase.cards.query(finder: _finder(deckId)).getSnapshots(_db);
    return snapshots
        .map((snapshot) => WordCard.fromMap(snapshot.value))
        .toList(growable: false);
  }

  @override
  Future<WordCard?> getById(String id) async {
    final value = await AppDatabase.cards.record(id).get(_db);
    return value == null ? null : WordCard.fromMap(value);
  }

  @override
  Future<WordCard?> findByWord(String word, {String? deckId}) async {
    final key = normalizeWord(word);
    final filter = deckId == null
        ? Filter.equals('word_key', key)
        : Filter.and(<Filter>[
            Filter.equals('word_key', key),
            Filter.equals('deck_id', deckId),
          ]);
    final snapshots =
        await AppDatabase.cards.query(finder: Finder(filter: filter)).getSnapshots(_db);
    if (snapshots.isEmpty) return null;
    return WordCard.fromMap(snapshots.first.value);
  }

  @override
  Future<List<WordCard>> findByWords(List<String> words, {String? deckId}) async {
    final keys = words.map(normalizeWord).toSet().toList(growable: false);
    if (keys.isEmpty) return const <WordCard>[];
    final filter = deckId == null
        ? Filter.inList('word_key', keys)
        : Filter.and(<Filter>[
            Filter.inList('word_key', keys),
            Filter.equals('deck_id', deckId),
          ]);
    final snapshots =
        await AppDatabase.cards.query(finder: Finder(filter: filter)).getSnapshots(_db);
    return snapshots
        .map((snapshot) => WordCard.fromMap(snapshot.value))
        .toList(growable: false);
  }

  @override
  Future<void> upsert(WordCard card) async {
    await AppDatabase.cards.record(card.id).put(_db, toRow(card));
  }

  @override
  Future<void> upsertAll(List<WordCard> cards) async {
    if (cards.isEmpty) return;
    await _db.transaction((txn) async {
      for (final card in cards) {
        await AppDatabase.cards.record(card.id).put(txn, toRow(card));
      }
    });
  }

  @override
  Future<void> deleteById(String id) =>
      AppDatabase.cards.record(id).delete(_db);

  @override
  Future<void> deleteAll({String? deckId}) async {
    final filter = deckId == null ? null : Filter.equals('deck_id', deckId);
    await AppDatabase.cards.delete(_db, finder: Finder(filter: filter));
  }

  @override
  Future<void> resetProgress({String? deckId}) async {
    final snapshots =
        await AppDatabase.cards.query(finder: _finder(deckId)).getSnapshots(_db);
    await _db.transaction((txn) async {
      for (final snapshot in snapshots) {
        final Map<String, Object?> row =
            Map<String, Object?>.of(snapshot.value);
        row['review_count'] = 0;
        row['correct_count'] = 0;
        row['wrong_count'] = 0;
        row['total_reaction_ms'] = 0;
        row['mastery'] = 0.0;
        row['last_reviewed_at'] = null;
        row['next_review_at'] = null;
        row['interval_days'] = 0;
        row['ease_factor'] = 2.5;
        row['fsrs'] = null;
        await AppDatabase.cards.record(snapshot.key).put(txn, row);
      }
    });
  }

  @override
  Future<int> count({String? deckId}) => AppDatabase.cards.count(
        _db,
        filter: deckId == null ? null : Filter.equals('deck_id', deckId),
      );
}
