import 'package:sqlite3/sqlite3.dart';

import '../../core/ids.dart';
import '../../domain/models/sync_snapshot.dart';
import '../../domain/repositories.dart';
import 'anki_collection.dart';
import 'anki_schema.dart';

/// 同步状态的 Anki 实现：设备 id、删除记录，以及把对方的删除落到本地。
///
/// 为什么删除要单独记一张表：Anki 自己的 graves 存的是本地整数 note id，
/// 那个 id 是毫秒时间戳加递增，换一台设备就指向别的卡了，
/// 拿它同步等于随机删词。所以按卡片 uid 另记一份。
class AnkiSyncRepository implements SyncRepository {
  AnkiSyncRepository(this._collection);

  final AnkiCollection _collection;

  /// 设备 id 存在 wc_sync_meta 而不是 wc_settings：
  /// 它不是用户配置，清空设置也不该换一个身份（换了对方会以为是新设备）。
  static const String _deviceKey = 'device_id';

  @override
  Future<String> deviceId() async {
    final ResultSet rows = _collection.db.select(
      'select value from wc_sync_meta where key = ?',
      <Object?>[_deviceKey],
    );
    if (rows.isNotEmpty) {
      final String? value = rows.first['value'] as String?;
      if (value != null && value.trim().isNotEmpty) return value;
    }
    final String id = newId();
    _collection.db.execute(
      'insert or replace into wc_sync_meta (key, value) values (?,?)',
      <Object?>[_deviceKey, id],
    );
    return id;
  }

  @override
  Future<List<SyncTombstone>> tombstones() async {
    final ResultSet rows = _collection.db.select(
      'select uid, kind, deck_uid, deleted_at from wc_tombstones '
      'order by deleted_at asc',
    );
    return rows
        .map((Row row) => SyncTombstone.fromMap(<String, Object?>{
              'uid': row['uid'],
              'kind': row['kind'],
              'deck_uid': row['deck_uid'],
              'deleted_at': row['deleted_at'],
            }))
        .toList(growable: false);
  }

  @override
  Future<void> addTombstone(SyncTombstone tombstone) async {
    _write(tombstone);
  }

  void _write(SyncTombstone tombstone) {
    // 同一个对象被删两次时保留更晚的时间：更晚的那次才是「最后说的话」。
    _collection.db.execute(
      'insert into wc_tombstones (uid, kind, deck_uid, deleted_at, device_id) '
      'values (?,?,?,?,null) '
      'on conflict(uid, kind) do update set '
      'deleted_at = max(deleted_at, excluded.deleted_at), '
      'deck_uid = coalesce(excluded.deck_uid, deck_uid)',
      <Object?>[
        tombstone.uid,
        tombstone.kind,
        tombstone.deckUid,
        tombstone.deletedAt.millisecondsSinceEpoch,
      ],
    );
  }

  /// 把对方的删除记录落到本地。
  ///
  /// 刻意**不改写**删除时间：本地的 deleteById 会记一条「现在删的」，
  /// 如果拿它来应用对方的旧删除，删除时间就会被推到现在，
  /// 把对方随后修改过的卡又删掉一次。所以这里只动数据，墓碑沿用对方的。
  @override
  Future<void> applyTombstone(SyncTombstone tombstone) async {
    _write(tombstone);
    if (tombstone.isDeck) {
      _applyDeckDeletion(tombstone.uid);
    } else {
      _applyCardDeletion(tombstone.uid);
    }
    _collection.notify();
  }

  void _applyCardDeletion(String uid) {
    final int? noteId = _collection.noteIdForCard(uid);
    if (noteId == null) return;
    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _collection.db.execute('begin immediate');
    try {
      _collection.db.execute(
        'insert into graves (usn, oid, type) values (?,?,?)',
        <Object?>[-1, noteId, 0],
      );
      _collection.db.execute(
        'insert into graves (usn, oid, type) values (?,?,?)',
        <Object?>[-1, noteId, 1],
      );
      _collection.db.execute('delete from cards where nid = ?', <Object?>[noteId]);
      _collection.db.execute('delete from notes where id = ?', <Object?>[noteId]);
      _collection.db.execute('delete from wc_card_ids where note_id = ?', <Object?>[noteId]);
      _collection.db.execute('delete from wc_card_stats where uid = ?', <Object?>[uid]);
      _collection.db.execute('delete from wc_card_fsrs where uid = ?', <Object?>[uid]);
      _collection.db.execute(
        'delete from wc_answer_log where card_uid = ?',
        <Object?>[uid],
      );
      _collection.db.execute('commit');
    } catch (_) {
      _collection.db.execute('rollback');
      rethrow;
    }
    // 只为了让 col.mod 看起来有变化，Anki 打开时不会当成「没动过」。
    _collection.db.execute(
      'update col set mod = ? where id = 1',
      <Object?>[nowSec],
    );
  }

  void _applyDeckDeletion(String deckUid) {
    final int? deckId = _collection.deckIdForUid(deckUid);
    if (deckId == null) return;
    if (deckId == kDefaultAnkiDeckId) return;
    _collection.db.execute('begin immediate');
    try {
      // 卡不跟着消失：回到默认卡组，和界面上「删除卡组」的行为一致。
      _collection.db.execute(
        'update cards set did = ? where did = ?',
        <Object?>[kDefaultAnkiDeckId, deckId],
      );
      _collection.db.execute(
        'delete from wc_deck_ids where uid = ?',
        <Object?>[deckUid],
      );
      _collection.db.execute('commit');
    } catch (_) {
      _collection.db.execute('rollback');
      rethrow;
    }
    _collection.removeDeckJson(deckId);
  }
}
