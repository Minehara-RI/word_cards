import 'package:sembast/sembast.dart';

import '../../domain/models/answer_record.dart';
import '../../domain/repositories.dart';
import 'app_database.dart';

/// 基于 sembast 的答题记录仓库。
class SembastAnswerRecordRepository implements AnswerRecordRepository {
  SembastAnswerRecordRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  static Finder _recentFinder(int limit) => Finder(
        sortOrders: <SortOrder>[SortOrder('answered_at', false)],
        limit: limit,
      );

  @override
  Future<void> add(AnswerRecord record) =>
      AppDatabase.records.record(record.id).put(_db, record.toMap());

  @override
  Future<void> addAll(List<AnswerRecord> records) async {
    if (records.isEmpty) return;
    await _db.transaction((txn) async {
      for (final record in records) {
        await AppDatabase.records.record(record.id).put(txn, record.toMap());
      }
    });
  }

  @override
  Future<List<AnswerRecord>> getRecent({int limit = 200}) async {
    final snapshots = await AppDatabase.records
        .query(finder: _recentFinder(limit))
        .getSnapshots(_db);
    return snapshots
        .map((snapshot) => AnswerRecord.fromMap(snapshot.value))
        .toList(growable: false);
  }

  @override
  Future<List<AnswerRecord>> getSince(DateTime since) async {
    final snapshots = await AppDatabase.records
        .query(
          finder: Finder(
            filter: Filter.greaterThanOrEquals(
              'answered_at',
              since.millisecondsSinceEpoch,
            ),
            sortOrders: <SortOrder>[SortOrder('answered_at', false)],
          ),
        )
        .getSnapshots(_db);
    return snapshots
        .map((snapshot) => AnswerRecord.fromMap(snapshot.value))
        .toList(growable: false);
  }

  @override
  Future<List<AnswerRecord>> getAll() async {
    final snapshots = await AppDatabase.records
        .query(
          finder: Finder(
            sortOrders: <SortOrder>[SortOrder('answered_at', false)],
          ),
        )
        .getSnapshots(_db);
    return snapshots
        .map((snapshot) => AnswerRecord.fromMap(snapshot.value))
        .toList(growable: false);
  }

  @override
  Stream<List<AnswerRecord>> watchRecent({int limit = 200}) {
    return AppDatabase.records
        .query(finder: _recentFinder(limit))
        .onSnapshots(_db)
        .map((snapshots) => snapshots
            .map((snapshot) => AnswerRecord.fromMap(snapshot.value))
            .toList(growable: false));
  }

  @override
  Future<void> deleteAll() => AppDatabase.records.delete(_db);
}
