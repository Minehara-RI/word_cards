// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../domain/models/card_language.dart';
import '../../domain/models/card_source.dart';
import '../../domain/models/deck.dart';
import '../../domain/models/fsrs_memory.dart';
import '../../domain/models/word_card.dart';
import '../../domain/repositories.dart';
import 'anki_collection.dart';
import 'anki_schema.dart';

/// 写入时 usn 用 -1，意思是“这条还没同步过”，和 Anki 本地新建的数据一致。
const int _ankiUsn = -1;

/// 卡片仓库的 Anki 实现。
///
/// 一张卡片 = Anki 的 1 条 note + 1 条 card：
/// - notes.flds 里按固定字段顺序存单词/释义/音标/例句/词性/备注/干扰项
/// - cards 里存牌组与复习状态
/// - wc_card_stats 里存 Anki 表放不下的学习数据（答对次数、掌握度等）
class AnkiCardRepository implements CardRepository {
  AnkiCardRepository(this._collection);

  final AnkiCollection _collection;

  Database get _db => _collection.db;

  /// 单词的归一化形式，用于查重（忽略大小写、首尾与中间多余空白）。
  static String normalizeWord(String word) => word
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  static const String _selectColumns = '''
select n.id as note_id,
       n.flds as flds,
       n.tags as tags,
       n.mod as note_mod,
       c.did as did,
       c.mod as card_mod,
       c.ivl as ivl,
       c.factor as factor,
       c.reps as reps,
       c.lapses as lapses,
       i.uid as uid,
       s.review_count as review_count,
       s.correct_count as correct_count,
       s.wrong_count as wrong_count,
       s.total_reaction_ms as total_reaction_ms,
       s.mastery as mastery,
       s.last_reviewed_at as last_reviewed_at,
       s.next_review_at as next_review_at,
       s.interval_days as stat_interval_days,
       s.ease_factor as stat_ease_factor,
       s.created_at as created_at,
       s.updated_at as updated_at,
       f.stability as fsrs_stability,
       f.difficulty as fsrs_difficulty,
       f.reps as fsrs_reps,
       f.lapses as fsrs_lapses,
       f.state as fsrs_state,
       f.last_review_at as fsrs_last_review_at,
       f.due_at as fsrs_due_at
from notes n
join cards c on c.nid = n.id
join wc_card_ids i on i.note_id = n.id
left join wc_card_stats s on s.uid = i.uid
left join wc_card_fsrs f on f.uid = i.uid
''';

  static const String _order = 'order by lower(n.sfld) asc, n.id asc';

  String _deckFilter(String? deckId) {
    if (deckId == null) return '';
    final int? did = _collection.deckIdForUid(deckId);
    if (did == null) return 'where 1 = 0\n';
    return 'where c.did = $did\n';
  }

  @override
  Stream<List<WordCard>> watch({String? deckId}) =>
      _collection.watchValue(() => getAll(deckId: deckId));

  @override
  Future<List<WordCard>> getAll({String? deckId}) async {
    _collection.adoptOrphans();
    final ResultSet rows =
        _db.select('$_selectColumns ${_deckFilter(deckId)}$_order');
    return rows.map(_toCard).toList(growable: false);
  }

  @override
  Future<WordCard?> getById(String id) async {
    final int? noteId = _collection.noteIdForCard(id);
    if (noteId == null) return null;
    final ResultSet rows =
        _db.select('$_selectColumns where n.id = ?', <Object?>[noteId]);
    return rows.isEmpty ? null : _toCard(rows.first);
  }

  @override
  Future<WordCard?> findByWord(String word, {String? deckId}) async {
    final String key = normalizeWord(word);
    if (key.isEmpty) return null;
    for (final WordCard card in await getAll(deckId: deckId)) {
      if (normalizeWord(card.word) == key) return card;
    }
    return null;
  }

  @override
  Future<List<WordCard>> findByWords(List<String> words, {String? deckId}) async {
    final Set<String> keys = words
        .map(normalizeWord)
        .where((String key) => key.isNotEmpty)
        .toSet();
    if (keys.isEmpty) return const <WordCard>[];
    final List<WordCard> all = await getAll(deckId: deckId);
    return all
        .where((WordCard card) => keys.contains(normalizeWord(card.word)))
        .toList(growable: false);
  }

  @override
  Future<void> upsert(WordCard card) async {
    _collection.adoptOrphans();
    _db.execute('begin immediate');
    try {
      _writeCard(card);
      _db.execute('commit');
    } catch (_) {
      _db.execute('rollback');
      rethrow;
    }
    _collection.notify();
  }

  @override
  Future<void> upsertAll(List<WordCard> cards) async {
    if (cards.isEmpty) return;
    _collection.adoptOrphans();
    _db.execute('begin immediate');
    try {
      for (final WordCard card in cards) {
        _writeCard(card);
      }
      _db.execute('commit');
    } catch (_) {
      _db.execute('rollback');
      rethrow;
    }
    _collection.notify();
  }

  @override
  Future<void> deleteById(String id) async {
    final int? noteId = _collection.noteIdForCard(id);
    if (noteId == null) return;
    _db.execute('begin immediate');
    try {
      _db.execute(
        'insert into graves (usn, oid, type) values (?,?,?)',
        <Object?>[_ankiUsn, noteId, 0],
      );
      _db.execute(
        'insert into graves (usn, oid, type) values (?,?,?)',
        <Object?>[_ankiUsn, noteId, 1],
      );
      _db.execute('delete from cards where nid = ?', <Object?>[noteId]);
      _db.execute('delete from notes where id = ?', <Object?>[noteId]);
      _db.execute('delete from wc_card_ids where note_id = ?', <Object?>[noteId]);
      _db.execute('delete from wc_card_stats where uid = ?', <Object?>[id]);
      _db.execute('delete from wc_card_fsrs where uid = ?', <Object?>[id]);
      _db.execute('commit');
    } catch (_) {
      _db.execute('rollback');
      rethrow;
    }
    _collection.notify();
  }

  @override
  Future<void> deleteAll({String? deckId}) async {
    if (deckId == null) {
      _db.execute('delete from cards');
      _db.execute('delete from notes');
      _db.execute('delete from wc_card_ids');
      _db.execute('delete from wc_card_stats');
      _db.execute('delete from wc_card_fsrs');
      _db.execute('delete from revlog');
      _collection.notify();
      return;
    }

    final int? did = _collection.deckIdForUid(deckId);
    if (did == null) return;
    final ResultSet rows =
        _db.select('select id, nid from cards where did = ?', <Object?>[did]);
    final List<List<int>> pairs = rows
        .map((Row row) => <int>[
              (row['id'] as int?) ?? 0,
              (row['nid'] as int?) ?? 0,
            ])
        .toList(growable: false);
    if (pairs.isEmpty) return;

    _db.execute('begin immediate');
    try {
      for (final List<int> pair in pairs) {
        _db.execute('delete from cards where id = ?', <Object?>[pair[0]]);
        _db.execute(
          'delete from notes where id = ? and not exists '
          '(select 1 from cards where nid = ?)',
          <Object?>[pair[1], pair[1]],
        );
        _db.execute(
          'delete from wc_card_stats where uid in '
          '(select uid from wc_card_ids where note_id = ? and not exists '
          '(select 1 from cards where nid = ?))',
          <Object?>[pair[1], pair[1]],
        );
        _db.execute(
          'delete from wc_card_fsrs where uid in '
          '(select uid from wc_card_ids where note_id = ? and not exists '
          '(select 1 from cards where nid = ?))',
          <Object?>[pair[1], pair[1]],
        );
        _db.execute('delete from wc_card_ids where note_id = ?', <Object?>[pair[1]]);
      }
      _db.execute('commit');
    } catch (_) {
      _db.execute('rollback');
      rethrow;
    }
    _collection.notify();
  }

  @override
  Future<int> count({String? deckId}) async {
    if (deckId == null) {
      return (_db.select('select count(*) as c from cards').first['c'] as int?) ?? 0;
    }
    final int? did = _collection.deckIdForUid(deckId);
    if (did == null) return 0;
    final ResultSet rows = _db.select(
      'select count(*) as c from cards where did = ?',
      <Object?>[did],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  // ------------------------------------------------------------ 写入细节

  void _writeCard(WordCard card) {
    final int id = _collection.ensureCardIds(card.id);
    final int deckId = _collection.ensureDeckId(card.deckId);
    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final String flds = <String>[
      card.word,
      card.definition,
      card.phonetic ?? '',
      card.example ?? '',
      card.partOfSpeech ?? '',
      card.note ?? '',
      card.distractors.join(kDistractorSeparator),
    ].join(kFieldSeparator);

    _db.execute(
      'insert into notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, '
      'flags, data) values (?,?,?,?,?,?,?,?,?,?,?) '
      'on conflict(id) do update set mod=excluded.mod, tags=excluded.tags, '
      'flds=excluded.flds, sfld=excluded.sfld, csum=excluded.csum',
      <Object?>[
        id,
        _newGuid(),
        kAnkiNotetypeId,
        nowSec,
        _ankiUsn,
        _ankiTags(card),
        flds,
        card.word,
        _checksum(card.word),
        0,
        '{}',
      ],
    );

    // 新卡片 type=0/queue=0，复习过的卡片按 Anki 的复习卡处理。
    final bool isNew = card.reviewCount == 0;
    final int due = isNew || card.nextReviewAt == null
        ? 0
        : _dueDaysFor(card.nextReviewAt!);

    _db.execute(
      'insert into cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, '
      'factor, reps, lapses, left, odue, odid, flags, data) '
      'values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) '
      'on conflict(id) do update set did=excluded.did, mod=excluded.mod, '
      'type=excluded.type, queue=excluded.queue, due=excluded.due, '
      'ivl=excluded.ivl, factor=excluded.factor, reps=excluded.reps, '
      'lapses=excluded.lapses',
      <Object?>[
        id,
        id,
        deckId,
        0,
        nowSec,
        _ankiUsn,
        isNew ? 0 : 2,
        isNew ? 0 : 2,
        due,
        card.intervalDays,
        (card.easeFactor * 1000).round(),
        card.reviewCount,
        card.wrongCount,
        0,
        0,
        0,
        0,
        '{}',
      ],
    );

    _db.execute(
      'insert into wc_card_stats (uid, review_count, correct_count, wrong_count, '
      'total_reaction_ms, mastery, last_reviewed_at, next_review_at, '
      'interval_days, ease_factor, created_at, updated_at) '
      'values (?,?,?,?,?,?,?,?,?,?,?,?) '
      'on conflict(uid) do update set review_count=excluded.review_count, '
      'correct_count=excluded.correct_count, wrong_count=excluded.wrong_count, '
      'total_reaction_ms=excluded.total_reaction_ms, mastery=excluded.mastery, '
      'last_reviewed_at=excluded.last_reviewed_at, '
      'next_review_at=excluded.next_review_at, '
      'interval_days=excluded.interval_days, '
      'ease_factor=excluded.ease_factor, updated_at=excluded.updated_at',
      <Object?>[
        card.id,
        card.reviewCount,
        card.correctCount,
        card.wrongCount,
        card.totalReactionMs,
        card.mastery,
        card.lastReviewedAt?.millisecondsSinceEpoch,
        card.nextReviewAt?.millisecondsSinceEpoch,
        card.intervalDays,
        card.easeFactor,
        card.createdAt.millisecondsSinceEpoch,
        card.updatedAt.millisecondsSinceEpoch,
      ],
    );

    _writeFsrs(card.id, card.fsrs);
  }

  /// Anki 的标签串：空格分隔，前后各补一个空格（Anki 自己就是这个格式）。
  ///
  /// 第一个是来源（手动导入 / API 生成），接着是语言（lang::ja），
  /// 剩下的是用户自己打的标签。
  static String _ankiTags(WordCard card) {
    final List<String> tags = <String>[
      card.source.label,
      card.language.tag,
      for (final String tag in card.tags)
        if (WordCard.sanitizeTag(tag).isNotEmpty)
          if (!CardLanguage.isLanguageTag(tag)) WordCard.sanitizeTag(tag),
    ];
    return ' ' + tags.join(' ') + ' ';
  }

  /// FSRS 状态写进自己的表；卡片还没有 FSRS 状态时什么都不做，
  /// 这样关掉 FSRS 再打开时旧状态还在。
  void _writeFsrs(String uid, FsrsMemory? memory) {
    if (memory == null) return;
    _db.execute(
      'insert into wc_card_fsrs (uid, stability, difficulty, reps, lapses, '
      'state, last_review_at, due_at) values (?,?,?,?,?,?,?,?) '
      'on conflict(uid) do update set stability=excluded.stability, '
      'difficulty=excluded.difficulty, reps=excluded.reps, '
      'lapses=excluded.lapses, state=excluded.state, '
      'last_review_at=excluded.last_review_at, due_at=excluded.due_at',
      <Object?>[
        uid,
        memory.stability,
        memory.difficulty,
        memory.reps,
        memory.lapses,
        memory.state.id,
        memory.lastReviewAt?.millisecondsSinceEpoch,
        memory.dueAt?.millisecondsSinceEpoch,
      ],
    );
  }

  /// Anki 的 due 对复习卡来说是“距集合创建日多少天”。
  int _dueDaysFor(DateTime next) {
    final int crt = _collection.collectionCreatedAtSeconds;
    final int seconds = next.millisecondsSinceEpoch ~/ 1000;
    final int days = (seconds - crt) ~/ 86400;
    return days < 0 ? 0 : days;
  }

  static int _checksum(String text) {
    final String digest = sha1.convert(utf8.encode(text)).toString();
    return int.parse(digest.substring(0, 8), radix: 16);
  }

  static String _newGuid() {
    const String alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final Random random = Random();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 10; i++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  // ------------------------------------------------------------ 读回内存模型

  WordCard _toCard(Row row) {
    final List<String> flds =
        ((row['flds'] as String?) ?? '').split(kFieldSeparator);
    String field(int index) => index < flds.length ? flds[index] : '';

    final int? deckId = row['did'] as int?;
    final String deckUid = deckId == null
        ? Deck.defaultDeckId
        : (_collection.deckUidForId(deckId) ?? Deck.defaultDeckId);

    final int reps = (row['reps'] as int?) ?? 0;
    final int lapses = (row['lapses'] as int?) ?? 0;
    final List<String> tags = _splitTags((row['tags'] as String?) ?? '');
    final int noteModMs = ((row['note_mod'] as int?) ?? 0) * 1000;
    final int cardModMs = ((row['card_mod'] as int?) ?? 0) * 1000;
    final double factor = ((row['factor'] as int?) ?? 2500) / 1000;

    return WordCard.fromMap(<String, Object?>{
      'id': row['uid'],
      'word': field(kFieldWord),
      'definition': field(kFieldDefinition),
      'phonetic': field(kFieldPhonetic),
      'example': field(kFieldExample),
      'part_of_speech': field(kFieldPartOfSpeech),
      'note': field(kFieldNote),
      'distractors':
          field(kFieldDistractors).split(kDistractorSeparator),
      'deck_id': deckUid,
      'language': (CardLanguage.fromTags(tags) ?? CardLanguage.english).id,
      'tags': tags
          .where((String tag) => !CardLanguage.isLanguageTag(tag))
          .where((String tag) => tag != sourceFromTag(tags).label)
          .where((String tag) => tag != sourceFromTag(tags).id)
          .toList(growable: false),
      'fsrs': _fsrsFromRow(row)?.toMap(),
      'source': sourceFromTag(tags).id,
      'created_at': (row['created_at'] as int?) ?? noteModMs,
      'updated_at': (row['updated_at'] as int?) ?? cardModMs,
      'review_count': (row['review_count'] as int?) ?? reps,
      'correct_count': (row['correct_count'] as int?) ?? 0,
      'wrong_count': (row['wrong_count'] as int?) ?? lapses,
      'total_reaction_ms': (row['total_reaction_ms'] as int?) ?? 0,
      'mastery': (row['mastery'] as num?)?.toDouble() ?? 0,
      'last_reviewed_at': row['last_reviewed_at'] as int?,
      'next_review_at': row['next_review_at'] as int?,
      'interval_days':
          (row['stat_interval_days'] as int?) ?? ((row['ivl'] as int?) ?? 0),
      'ease_factor':
          (row['stat_ease_factor'] as num?)?.toDouble() ?? factor,
    });
  }

  /// 卡片来源存在 Anki 的 tag 里，这样在 Anki 里也能一眼看出来。
  static CardSource sourceFromTag(Iterable<String> tags) {
    for (final String raw in tags) {
      final String tag = raw.trim();
      if (tag.isEmpty) continue;
      for (final CardSource source in CardSource.values) {
        if (tag == source.id || tag == source.label) return source;
      }
    }
    return CardSource.manualImport;
  }

  /// 把 Anki 的标签串拆成一个个标签。
  static List<String> _splitTags(String tags) => tags
      .split(' ')
      .map((String tag) => tag.trim())
      .where((String tag) => tag.isNotEmpty)
      .toList(growable: false);

  /// 从查询出来的列里还原 FSRS 状态；没写过 FSRS 的卡片返回 null。
  static FsrsMemory? _fsrsFromRow(Row row) {
    final num? stability = row['fsrs_stability'] as num?;
    final num? reps = row['fsrs_reps'] as num?;
    if (stability == null && reps == null) return null;
    final int reviewCount = reps?.toInt() ?? 0;
    if (reviewCount == 0 && (stability?.toDouble() ?? 0) <= 0) return null;
    return FsrsMemory(
      stability: stability?.toDouble() ?? 0,
      difficulty: (row['fsrs_difficulty'] as num?)?.toDouble() ?? 0,
      reps: reviewCount,
      lapses: (row['fsrs_lapses'] as num?)?.toInt() ?? 0,
      state: FsrsCardState.fromId(row['fsrs_state']),
      lastReviewAt: _millis(row['fsrs_last_review_at']),
      dueAt: _millis(row['fsrs_due_at']),
    );
  }

  static DateTime? _millis(Object? value) => value is num
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
      : null;
}
