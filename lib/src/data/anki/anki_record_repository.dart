import 'package:sqlite3/sqlite3.dart';

import '../../domain/models/answer_record.dart';
import '../../domain/repositories.dart';
import 'anki_collection.dart';

/// 答题记录的 Anki 实现。
///
/// 一条答题记录会写两个地方：
/// - Anki 的 revlog：ease / ivl / time 这些都是 Anki 统计要用的原生字段
/// - wc_answer_log：应用自己的完整记录（选了什么选项、是不是超时、哪一轮测验）
///
/// 投影模式是纯演示，不产生答题记录。
class AnkiAnswerRecordRepository implements AnswerRecordRepository {
  AnkiAnswerRecordRepository(this._collection);

  final AnkiCollection _collection;

  Database get _db => _collection.db;

  static const String _select = 'select id, card_uid as card_id, selected, '
      'expected, correct, reaction_ms, answered_at, session_id, '
      'deck_uid as deck_id, mode, timed_out from wc_answer_log';

  @override
  Future<void> add(AnswerRecord record) async {
    _db.execute('begin immediate');
    try {
      _write(record);
      _db.execute('commit');
    } catch (_) {
      _db.execute('rollback');
      rethrow;
    }
    _collection.notify();
  }

  @override
  Future<void> addAll(List<AnswerRecord> records) async {
    if (records.isEmpty) return;
    _db.execute('begin immediate');
    try {
      for (final AnswerRecord record in records) {
        _write(record);
      }
      _db.execute('commit');
    } catch (_) {
      _db.execute('rollback');
      rethrow;
    }
    _collection.notify();
  }

  void _write(AnswerRecord record) {
    int? revlogId;
    if (record.mode != QuizMode.projection) {
      revlogId = _writeRevlog(record);
    }
    _db.execute(
      'insert or replace into wc_answer_log (id, card_uid, selected, expected, '
      'correct, reaction_ms, answered_at, session_id, deck_uid, mode, '
      'timed_out, revlog_id) values (?,?,?,?,?,?,?,?,?,?,?,?)',
      <Object?>[
        record.id,
        record.cardId,
        record.selected,
        record.expected,
        record.correct ? 1 : 0,
        record.reactionMs,
        record.answeredAt.millisecondsSinceEpoch,
        record.sessionId,
        record.deckId,
        record.mode.id,
        record.timedOut ? 1 : 0,
        revlogId,
      ],
    );
  }

  int? _writeRevlog(AnswerRecord record) {
    final int? cardId = _collection.noteIdForCard(record.cardId);
    if (cardId == null) return null;

    final ResultSet cardRows = _db.select(
      'select ivl, factor, reps from cards where id = ?',
      <Object?>[cardId],
    );
    final int ivl =
        cardRows.isEmpty ? 0 : ((cardRows.first['ivl'] as int?) ?? 0);
    final int factor =
        cardRows.isEmpty ? 2500 : ((cardRows.first['factor'] as int?) ?? 2500);
    final int reps =
        cardRows.isEmpty ? 0 : ((cardRows.first['reps'] as int?) ?? 0);

    final ResultSet lastRows = _db.select(
      'select ivl from revlog where cid = ? order by id desc limit 1',
      <Object?>[cardId],
    );
    final int lastIvl =
        lastRows.isEmpty ? 0 : ((lastRows.first['ivl'] as int?) ?? 0);

    int id = record.answeredAt.millisecondsSinceEpoch;
    final int existingMax = _collection.maxIdOf('revlog');
    if (id <= existingMax) id = existingMax + 1;

    // ease：1 = Again（答错/超时），3 = Good（答对）。Anki 的 revlog.ease 就是这个含义。
    // type：0 = 学习中的卡，1 = 复习卡。
    _db.execute(
      'insert or replace into revlog (id, cid, usn, ease, ivl, lastIvl, '
      'factor, time, type) values (?,?,?,?,?,?,?,?,?)',
      <Object?>[
        id,
        cardId,
        -1,
        record.correct ? 3 : 1,
        ivl,
        lastIvl,
        factor,
        record.reactionMs.clamp(0, 60000),
        reps == 0 ? 0 : 1,
      ],
    );
    return id;
  }

  List<AnswerRecord> _query(String sql, [List<Object?> parameters = const <Object?>[]]) {
    final ResultSet rows = _db.select(sql, parameters);
    return rows
        .map((Row row) => AnswerRecord.fromMap(Map<String, Object?>.from(row)))
        .toList(growable: false);
  }

  @override
  Future<List<AnswerRecord>> getRecent({int limit = 200}) async =>
      _query('$_select order by answered_at desc limit $limit');

  @override
  Future<List<AnswerRecord>> getSince(DateTime since) async => _query(
        '$_select where answered_at >= ? order by answered_at desc',
        <Object?>[since.millisecondsSinceEpoch],
      );

  @override
  Future<List<AnswerRecord>> getAll() async =>
      _query('$_select order by answered_at desc');

  @override
  Stream<List<AnswerRecord>> watchRecent({int limit = 200}) =>
      _collection.watchValue(() => getRecent(limit: limit));

  @override
  Future<void> deleteAll() async {
    _db.execute('delete from wc_answer_log');
    _db.execute('delete from revlog');
    _collection.notify();
  }
}
