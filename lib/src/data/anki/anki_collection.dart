import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../core/ids.dart';
import '../../domain/models/deck.dart';
import 'anki_schema.dart';

/// 一个 Anki 集合文件（collection.anki2）。
///
/// 除了读写 Anki 自己的表，这里还负责三件杂事：
/// 1. 把应用内的字符串 id 映射到 Anki 的整数 id（Anki 的主键必须是整数）；
/// 2. 维护 col 表里的 conf / models / decks / dconf（Anki 把配置存在 JSON 里）；
/// 3. 广播“数据变了”，让 Riverpod 的 StreamProvider 能刷新。
///
/// sqlite3 的 API 是同步的，所以仓库层用 Future 包一层只是为了接口统一。
class AnkiCollection {
  AnkiCollection._(this.db, this.path);

  final Database db;

  /// 文件路径；内存库为 null。
  final String? path;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _lastId = 0;

  /// 任何写入之后都会推一个事件。
  Stream<void> get changes => _changes.stream;

  void notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  static AnkiCollection openAt(String filePath) {
    final collection = AnkiCollection._(sqlite3.open(filePath), filePath);
    collection._init();
    return collection;
  }

  static AnkiCollection openInMemory() {
    final collection = AnkiCollection._(sqlite3.openInMemory(), null);
    collection._init();
    return collection;
  }

  void _init() {
    if (path != null) {
      db.execute('pragma journal_mode = wal');
    }
    for (final String sql in kAnkiSchema) {
      db.execute(sql);
    }
    for (final String sql in kAppSchema) {
      db.execute(sql);
    }

    _lastId = <int>[
      _maxId('notes'),
      _maxId('cards'),
      _maxId('revlog'),
    ].reduce((int a, int b) => a > b ? a : b);

    _ensureColRow();
    _ensureDefaultDeck();
    _ensureNotetype();
  }

  void dispose() {
    unawaited(_changes.close());
    db.close();
  }

  /// 为了在测试里方便地检查 SQL 结果。
  int maxIdOf(String table) => _maxId(table);

  int _maxId(String table) {
    final ResultSet rows =
        db.select('select coalesce(max(id), 0) as m from $table');
    return (rows.first['m'] as int?) ?? 0;
  }

  /// Anki 的时间戳一律是“秒”。这里把“一天从凌晨 4 点开始”算出来，
  /// 和 Anki 的 rollover 规则保持一致。
  static int collectionCreationDay(DateTime now) {
    final DateTime local = now.toLocal();
    DateTime start = DateTime(local.year, local.month, local.day, 4);
    if (start.isAfter(local)) {
      start = start.subtract(const Duration(days: 1));
    }
    return start.millisecondsSinceEpoch ~/ 1000;
  }

  // ------------------------------------------------------------ col 表

  Row get _colRow => db.select('select * from col where id = 1').first;

  /// Anki 的集合创建日（秒），算 due 的时候要用。
  int get collectionCreatedAtSeconds => (_colRow['crt'] as int?) ?? 0;

  void _ensureColRow() {
    final int count = (_colRowOrNull()?['id'] == null) ? 0 : 1;
    if (count > 0) return;

    final DateTime now = DateTime.now();
    final int nowSec = now.millisecondsSinceEpoch ~/ 1000;
    db.execute(
      'insert into col (id, crt, mod, scm, ver, dty, usn, ls, conf, models, '
      'decks, dconf, tags) values (?,?,?,?,?,?,?,?,?,?,?,?,?)',
      <Object?>[
        1,
        collectionCreationDay(now),
        nowSec,
        now.millisecondsSinceEpoch,
        kAnkiSchemaVersion,
        0,
        0,
        0,
        jsonEncode(ankiDefaultConf(kAnkiNotetypeId)),
        jsonEncode(<String, Object?>{
          kAnkiNotetypeId.toString(): ankiNotetype(nowSec),
        }),
        jsonEncode(<String, Object?>{
          kDefaultAnkiDeckId.toString(): ankiDeck(
            kDefaultAnkiDeckId,
            Deck.defaultDeckName,
            nowSec,
          ),
        }),
        jsonEncode(<String, Object?>{'1': ankiDefaultDeckConfig()}),
        '{}',
      ],
    );
    db.execute(
      'insert or ignore into wc_deck_ids (uid, deck_id) values (?, ?)',
      <Object?>[Deck.defaultDeckId, kDefaultAnkiDeckId],
    );
  }

  Row? _colRowOrNull() {
    final ResultSet rows = db.select('select * from col where id = 1');
    return rows.isEmpty ? null : rows.first;
  }

  Map<String, Object?> _decodeColumn(String column) {
    final Object? raw = _colRow[column];
    if (raw is! String || raw.trim().isEmpty) return <String, Object?>{};
    final Object? decoded = jsonDecode(raw);
    if (decoded is Map) return decoded.cast<String, Object?>();
    return <String, Object?>{};
  }

  void _writeColumn(String column, Map<String, Object?> value) {
    db.execute(
      'update col set mod = ?, $column = ? where id = 1',
      <Object?>[DateTime.now().millisecondsSinceEpoch ~/ 1000, jsonEncode(value)],
    );
  }

  Map<String, Object?> readConf() => _decodeColumn('conf');

  Map<String, Object?> readModels() => _decodeColumn('models');

  Map<String, Object?> readDecks() => _decodeColumn('decks');

  Map<String, Object?> readDconf() => _decodeColumn('dconf');

  /// 保证笔记类型存在（万一 col.models 被 Anki 改过）。
  void _ensureNotetype() {
    final Map<String, Object?> models = readModels();
    if (models.containsKey(kAnkiNotetypeId.toString())) return;
    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    models[kAnkiNotetypeId.toString()] = ankiNotetype(nowSec);
    _writeColumn('models', models);
  }

  /// 保证默认牌组存在。已经存在就不动它，免得把 Anki 的每日计数覆盖掉。
  void _ensureDefaultDeck() {
    db.execute(
      'insert or ignore into wc_deck_ids (uid, deck_id) values (?, ?)',
      <Object?>[Deck.defaultDeckId, kDefaultAnkiDeckId],
    );
    final Map<String, Object?> decks = readDecks();
    final Object? existing = decks[kDefaultAnkiDeckId.toString()];
    if (existing is Map && (existing['name'] as String?) != null) return;
    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    decks[kDefaultAnkiDeckId.toString()] =
        ankiDeck(kDefaultAnkiDeckId, Deck.defaultDeckName, nowSec);
    _writeColumn('decks', decks);
  }

  // ------------------------------------------------------------ 牌组 JSON

  List<Map<String, Object?>> deckJsonList() {
    final Map<String, Object?> decks = readDecks();
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    for (final Object? value in decks.values) {
      if (value is Map) result.add(value.cast<String, Object?>());
    }
    result.sort((Map<String, Object?> a, Map<String, Object?> b) =>
        ((a['id'] as num?)?.toInt() ?? 0).compareTo((b['id'] as num?)?.toInt() ?? 0));
    return result;
  }

  void putDeckJson(Map<String, Object?> deck) {
    final Map<String, Object?> decks = readDecks();
    decks[(deck['id'] as num).toInt().toString()] = deck;
    _writeColumn('decks', decks);
  }

  void removeDeckJson(int deckId) {
    final Map<String, Object?> decks = readDecks();
    decks.remove(deckId.toString());
    _writeColumn('decks', decks);
  }

  // ------------------------------------------------------------ id 映射

  /// 分配一个全局唯一的整数 id（毫秒时间戳，同一毫秒内递增）。
  int allocateId() {
    int candidate = DateTime.now().millisecondsSinceEpoch;
    if (candidate <= _lastId) candidate = _lastId + 1;
    _lastId = candidate;
    return candidate;
  }

  int? noteIdForCard(String uid) {
    final ResultSet rows =
        db.select('select note_id from wc_card_ids where uid = ?', <Object?>[uid]);
    return rows.isEmpty ? null : (rows.first['note_id'] as int?);
  }

  /// 拿到（必要时分配）卡片对应的 Anki 整数 id。note 与 card 用同一个 id。
  int ensureCardIds(String uid) {
    final int? existing = noteIdForCard(uid);
    if (existing != null) return existing;
    final int id = allocateId();
    db.execute(
      'insert into wc_card_ids (uid, note_id, card_id) values (?,?,?)',
      <Object?>[uid, id, id],
    );
    return id;
  }

  String? cardUidForNote(int noteId) {
    final ResultSet rows =
        db.select('select uid from wc_card_ids where note_id = ?', <Object?>[noteId]);
    return rows.isEmpty ? null : (rows.first['uid'] as String?);
  }

  int? deckIdForUid(String uid) {
    final ResultSet rows =
        db.select('select deck_id from wc_deck_ids where uid = ?', <Object?>[uid]);
    return rows.isEmpty ? null : (rows.first['deck_id'] as int?);
  }

  int ensureDeckId(String uid) {
    final int? existing = deckIdForUid(uid);
    if (existing != null) return existing;
    final int id = uid == Deck.defaultDeckId ? kDefaultAnkiDeckId : allocateId();
    db.execute(
      'insert or ignore into wc_deck_ids (uid, deck_id) values (?, ?)',
      <Object?>[uid, id],
    );
    return id;
  }

  String? deckUidForId(int deckId) {
    final ResultSet rows =
        db.select('select uid from wc_deck_ids where deck_id = ?', <Object?>[deckId]);
    return rows.isEmpty ? null : (rows.first['uid'] as String?);
  }

  /// 把 Anki 侧新增（例如用 Anki 导入）的笔记/牌组认领进来，
  /// 给它们补上应用内的字符串 id。通常什么都不用做。
  void adoptOrphans() {
    final ResultSet orphanDecks = db.select(
      'select distinct did from cards where did not in '
      '(select deck_id from wc_deck_ids)',
    );
    for (final Row row in orphanDecks) {
      final int deckId = (row['did'] as int?) ?? kDefaultAnkiDeckId;
      db.execute(
        'insert or ignore into wc_deck_ids (uid, deck_id) values (?, ?)',
        <Object?>[deckId.toString(), deckId],
      );
    }

    final ResultSet orphanNotes = db.select(
      'select id from notes where id not in (select note_id from wc_card_ids)',
    );
    for (final Row row in orphanNotes) {
      final int noteId = (row['id'] as int?) ?? 0;
      db.execute(
        'insert or ignore into wc_card_ids (uid, note_id, card_id) values (?,?,?)',
        <Object?>[newId(), noteId, noteId],
      );
    }
  }

  // ------------------------------------------------------------ 监听辅助

  /// 把一个“读取当前值”的函数变成会随数据变化重新推送的流。
  Stream<T> watchValue<T>(FutureOr<T> Function() read) {
    late StreamController<T> controller;
    StreamSubscription<void>? subscription;
    bool cancelled = false;

    Future<void> emit() async {
      if (cancelled) return;
      try {
        final T value = await read();
        if (!cancelled) controller.add(value);
      } catch (error, stack) {
        if (!cancelled) controller.addError(error, stack);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = changes.listen((_) => unawaited(emit()));
        unawaited(emit());
      },
      onCancel: () async {
        cancelled = true;
        await subscription?.cancel();
        subscription = null;
      },
    );
    return controller.stream;
  }
}
