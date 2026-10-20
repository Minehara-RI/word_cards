// ignore_for_file: prefer_interpolation_to_compose_strings, prefer_initializing_formals

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../../core/ids.dart';
import '../../domain/models/card_language.dart';
import '../../domain/models/card_source.dart';
import '../../domain/models/deck.dart';
import '../../domain/models/word_card.dart';
import '../../domain/repositories.dart';

/// 导入 Anki 库时给用户的错误：消息本身就是能照着做的那句话。
class AnkiImportException implements Exception {
  const AnkiImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一条从 Anki 里读出来的笔记，字段已经按应用的模型拆好。
class AnkiNote {
  const AnkiNote({
    required this.word,
    required this.definition,
    required this.deckName,
    this.phonetic,
    this.example,
    this.partOfSpeech,
    this.note,
    this.tags = const <String>[],
    this.reviewCount = 0,
    this.lapses = 0,
    this.intervalDays = 0,
    this.easeFactor = 2.5,
    this.lastReviewedAt,
    this.nextReviewAt,
  });

  final String word;
  final String definition;
  final String deckName;

  final String? phonetic;
  final String? example;
  final String? partOfSpeech;
  final String? note;

  final List<String> tags;

  // ---- 从 Anki 的 cards 表搬过来的学习状态 ----
  final int reviewCount;
  final int lapses;
  final int intervalDays;
  final double easeFactor;
  final DateTime? lastReviewedAt;
  final DateTime? nextReviewAt;

  int get correctCount => reviewCount > lapses ? reviewCount - lapses : 0;

  double get accuracy =>
      reviewCount == 0 ? 0 : correctCount / reviewCount;
}

/// 一个笔记类型的字段映射：哪一列当单词、哪一列当释义。
class AnkiFieldMapping {
  const AnkiFieldMapping({
    required this.modelName,
    required this.fields,
    required this.wordIndex,
    required this.definitionIndex,
    this.phoneticIndex,
    this.exampleIndex,
    this.posIndex,
    this.noteIndex,
    this.recognized = true,
  });

  final String modelName;
  final List<String> fields;
  final int wordIndex;
  final int definitionIndex;
  final int? phoneticIndex;
  final int? exampleIndex;
  final int? posIndex;
  final int? noteIndex;

  /// 单词与释义两列都是按名字猜出来的（不是退回 0 / 1 的兜底）。
  final bool recognized;

  String get wordField => fields[wordIndex];

  String get definitionField => fields[definitionIndex];

  /// 预览里那一行「单词 ← 正面，释义 ← 背面」。
  String get summary => modelName +
      '：单词 ← ' +
      wordField +
      '，释义 ← ' +
      definitionField;
}

/// 解析结果：还没写进本地库，先给用户看一眼。
class AnkiCollectionPreview {
  const AnkiCollectionPreview({
    required this.fileName,
    required this.notes,
    required this.deckNames,
    required this.mappings,
    required this.totalNotes,
    required this.skipped,
    required this.warnings,
  });

  final String fileName;
  final List<AnkiNote> notes;

  /// 这批笔记落在哪些卡组里（已经做过「Default → 文件名」的替换）。
  final List<String> deckNames;

  final List<AnkiFieldMapping> mappings;

  /// 文件里一共有多少条笔记（含被跳过的）。
  final int totalNotes;

  /// 因为字段读不出来而跳过的条数。
  final int skipped;

  final List<String> warnings;

  int get importableCount => notes.length;

  bool get hasNotes => notes.isNotEmpty;
}

/// 读 .anki2：Anki 的 notes / cards 表 + col 里那段 models / decks JSON。
///
/// 全程只读，不会碰源文件。
class AnkiCollectionReader {
  const AnkiCollectionReader();

  /// 从内存里的字节读（手机上选中的文件不一定是真实路径）。
  AnkiCollectionPreview readBytes(Uint8List bytes, {String fileName = ''}) {
    final Directory dir = Directory.systemTemp.createTempSync('wf_anki_');
    try {
      final File temp = File(dir.path + Platform.pathSeparator + 'collection.anki2');
      temp.writeAsBytesSync(bytes, flush: true);
      return readFile(temp.path, fileName: fileName);
    } finally {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        // 临时文件删不掉不影响导入结果。
      }
    }
  }

  AnkiCollectionPreview readFile(String path, {String? fileName}) {
    final File file = File(path);
    if (!file.existsSync()) {
      throw AnkiImportException('找不到这个文件。');
    }
    if (_looksLikeZip(file)) {
      throw AnkiImportException(
        '这是一个 .apkg 压缩包，不是 .anki2 数据库。'
        '把它解压出来，取里面的 collection.anki2 再导入。',
      );
    }

    final Database db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
    } catch (error) {
      throw AnkiImportException('打不开这个文件：' + error.toString());
    }

    try {
      // schema 18 的 fields.name 声明了 COLLATE unicase，不注册这条 collation
      // 读 fields 表会直接报 "no such collation sequence"。
      try {
        db.createCollation(
          name: 'unicase',
          function: (String? a, String? b) =>
              (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase()),
        );
      } catch (_) {
        // 老 sqlite3 不支持也无所谓：schema 11 用不到它。
      }
      _checkTables(db);
      final Row? col = _colRow(db);
      final int createdAt = _collectionCreatedAt(col);
      final Map<String, Object?> models = _decodeJson(col?['models']);
      final Map<int, AnkiFieldMapping> mappings;
      final Map<int, String> deckNames;
      if (models.isEmpty) {
        // Anki 23.10 起是 schema 18：配置搬进 notetypes / fields / decks 三张表，
        // col.models 与 col.decks 是空字符串。
        final _Schema18? modern = _readSchema18(db);
        mappings = modern?.mappings ?? <int, AnkiFieldMapping>{};
        deckNames = modern?.deckNames ?? <int, String>{};
      } else {
        mappings = _readMappings(models);
        deckNames = _readDeckNames(_decodeJson(col?['decks']));
      }
      final Map<int, Row> cardsByNote = _readCards(db);
      final String fallbackName = _fileBaseName(fileName ?? path);

      final List<AnkiNote> notes = <AnkiNote>[];
      final List<String> warnings = <String>[];
      final Set<String> seen = <String>{};
      final Set<int> usedMids = <int>{};
      int total = 0;
      int emptySkipped = 0;
      int duplicateSkipped = 0;
      int exerciseSkipped = 0;
      final Set<String> exerciseTypes = <String>{};

      final ResultSet rows =
          db.select('select id, mid, flds, tags, mod from notes');
      for (final Row row in rows) {
        total++;
        final int noteId = (row['id'] as int?) ?? 0;
        final int mid = (row['mid'] as int?) ?? 0;
        final String raw = (row['flds'] as String?) ?? '';
        final List<String> fields = raw.split('\u001f');

        final AnkiFieldMapping? mapping =
            mappings[mid] ?? _fallbackMapping(fields.length);
        if (mapping == null) {
          emptySkipped++;
          continue;
        }
        // 选项 / 答案式的练习卡（不是单词卡）导进来只会变成一堆乱码词条：
        // 只有单词、释义两列都没认出来、结构又像练习时才跳过。
        if (!mapping.recognized && _looksLikeExercise(mapping.fields)) {
          exerciseSkipped++;
          exerciseTypes.add(mapping.modelName);
          continue;
        }

        final String word = _clean(fields[mapping.wordIndex]);
        final String definition = _clean(fields[mapping.definitionIndex]);
        if (word.isEmpty || definition.isEmpty) {
          emptySkipped++;
          continue;
        }

        final String deckName = _deckDisplayName(
          deckNames[_deckIdOf(cardsByNote[noteId])],
          fallbackName,
        );
        final String key = deckName.toLowerCase() + '|' + word.toLowerCase();
        if (!seen.add(key)) {
          duplicateSkipped++;
          continue;
        }

        usedMids.add(mid);
        final Row? card = cardsByNote[noteId];
        notes.add(
          AnkiNote(
            word: word,
            definition: definition,
            deckName: deckName,
            phonetic: _optional(fields, mapping.phoneticIndex),
            example: _optional(fields, mapping.exampleIndex),
            partOfSpeech: _optional(fields, mapping.posIndex),
            note: _optional(fields, mapping.noteIndex),
            tags: _splitTags(row['tags']),
            reviewCount: _intOf(card, 'reps'),
            lapses: _intOf(card, 'lapses'),
            intervalDays: _intOf(card, 'ivl'),
            easeFactor: (_intOf(card, 'factor') == 0
                    ? 2500
                    : _intOf(card, 'factor')) /
                1000,
            lastReviewedAt: _dateFromSeconds(_intOf(card, 'mod')),
            nextReviewAt: _dueDate(card, createdAt),
          ),
        );
      }

      if (emptySkipped > 0) {
        warnings.add('有 ' +
            emptySkipped.toString() +
            ' 条笔记的字段是空的（或只有一列），没法当成单词卡，已跳过。');
      }
      if (exerciseSkipped > 0) {
        warnings.add(
          '有 ' +
              exerciseSkipped.toString() +
              ' 条笔记属于练习型笔记类型（' +
              exerciseTypes.join('、') +
              '，字段是选项 / 答案那种），不是单词卡，已跳过。',
        );
      }
      if (duplicateSkipped > 0) {
        warnings.add('同一个卡组里重复出现的单词有 ' +
            duplicateSkipped.toString() +
            ' 条，只保留第一条。');
      }

      return AnkiCollectionPreview(
        fileName: fileName ?? _fileBaseName(path),
        notes: notes,
        deckNames: _uniqueNames(notes),
        // 只展示真的用到的那几种笔记类型；练习型的映射对用户没意义。
        mappings: <AnkiFieldMapping>[
          for (final MapEntry<int, AnkiFieldMapping> entry in mappings.entries)
            if (usedMids.contains(entry.key)) entry.value,
        ],
        totalNotes: total,
        skipped: emptySkipped,
        warnings: warnings,
      );
    } finally {
      db.close();
    }
  }

  // ---------------------------------------------------------------- 读取

  void _checkTables(Database db) {
    final Set<String> tables;
    try {
      tables = db
          .select("select name from sqlite_master where type = 'table'")
          .map((Row row) => row['name'] as String)
          .toSet();
    } on SqliteException {
      throw const AnkiImportException(
        '这个文件不是 SQLite 数据库，也不像 Anki 的 .anki2。',
      );
    }
    if (!tables.contains('notes')) {
      throw const AnkiImportException(
        '这个文件里没有 notes 表，不是 Anki 的集合文件。'
        '正常的 .anki2 一定有 notes / cards / col 三张表。',
      );
    }
  }

  Row? _colRow(Database db) {
    try {
      final ResultSet rows = db.select('select * from col limit 1');
      return rows.isEmpty ? null : rows.first;
    } on SqliteException {
      return null;
    }
  }

  int _collectionCreatedAt(Row? col) {
    final int raw = (col?['crt'] as num?)?.toInt() ?? 0;
    if (raw == 0) return 0;
    // 老版本存秒，新版本某些导出是毫秒。
    return raw > 100000000000 ? raw ~/ 1000 : raw;
  }

  Map<String, Object?> _decodeJson(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return <String, Object?>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, Object?>();
      return <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  Map<int, AnkiFieldMapping> _readMappings(Map<String, Object?> models) {
    final Map<int, AnkiFieldMapping> result = <int, AnkiFieldMapping>{};
    for (final MapEntry<String, Object?> entry in models.entries) {
      final int? mid = int.tryParse(entry.key);
      final Object? value = entry.value;
      if (mid == null || value is! Map) continue;
      final Map<String, Object?> model = value.cast<String, Object?>();
      final List<String> fields = <String>[];
      final Object? rawFields = model['flds'];
      if (rawFields is List) {
        for (final Object? field in rawFields) {
          if (field is Map) {
            fields.add((field['name'] as String?)?.trim() ?? '');
          } else {
            fields.add('');
          }
        }
      }
      if (fields.length < 2) continue;
      result[mid] = _mapFields(
        (model['name'] as String?) ?? '笔记类型 ' + entry.key,
        fields,
      );
    }
    return result;
  }

  Map<int, String> _readDeckNames(Map<String, Object?> decks) {
    final Map<int, String> result = <int, String>{};
    for (final MapEntry<String, Object?> entry in decks.entries) {
      final int? id = int.tryParse(entry.key);
      final Object? value = entry.value;
      if (id == null || value is! Map) continue;
      final String? name = (value['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      result[id] = name;
    }
    return result;
  }

  /// schema 18（Anki 23.10 起）：notetypes / fields / decks 三张表。
  ///
  /// 这几张表是 sqlite 之外的新结构，读不到就返回 null，让调用方退回 col 里的 JSON。
  _Schema18? _readSchema18(Database db) {
    final Set<String> tables;
    try {
      tables = db
          .select("select name from sqlite_master where type = 'table'")
          .map((Row row) => row['name'] as String)
          .toSet();
    } on SqliteException {
      return null;
    }
    if (!tables.contains('notetypes') || !tables.contains('fields')) {
      return null;
    }

    final Map<int, String> names = <int, String>{};
    try {
      for (final Row row in db.select('select id, name from notetypes')) {
        names[(row['id'] as int?) ?? 0] = (row['name'] as String?) ?? '';
      }
    } on SqliteException {
      return null;
    }

    final Map<int, List<String>> fieldsByType = <int, List<String>>{};
    try {
      for (final Row row
          in db.select('select ntid, ord, name from fields order by ntid, ord')) {
        final int ntid = (row['ntid'] as int?) ?? 0;
        final String name = (row['name'] as String?)?.trim() ?? '';
        (fieldsByType[ntid] ??= <String>[]).add(name);
      }
    } on SqliteException {
      return null;
    }

    final Map<int, AnkiFieldMapping> mappings = <int, AnkiFieldMapping>{};
    for (final MapEntry<int, List<String>> entry in fieldsByType.entries) {
      if (entry.value.length < 2) continue;
      mappings[entry.key] = _mapFields(
        names[entry.key] ?? ('笔记类型 ' + entry.key.toString()),
        entry.value,
      );
    }

    final Map<int, String> deckNames = <int, String>{};
    if (tables.contains('decks')) {
      try {
        for (final Row row in db.select('select id, name from decks')) {
          final String? name = (row['name'] as String?)?.trim();
          if (name == null || name.isEmpty) continue;
          deckNames[(row['id'] as int?) ?? 0] = name;
        }
      } on SqliteException {
        // 没有 decks 表就退回文件名当卡组名。
      }
    }

    return _Schema18(mappings: mappings, deckNames: deckNames);
  }

  /// 一条笔记可能有多张卡（正反两张），取复习次数最多的那张当代表。
  Map<int, Row> _readCards(Database db) {
    final Map<int, Row> result = <int, Row>{};
    ResultSet rows;
    try {
      rows = db.select(
        'select nid, did, odid, type, queue, due, ivl, factor, reps, lapses, '
        'mod from cards',
      );
    } on SqliteException {
      return result;
    }
    for (final Row row in rows) {
      final int nid = (row['nid'] as int?) ?? 0;
      final Row? previous = result[nid];
      if (previous == null ||
          _intOf(row, 'reps') > _intOf(previous, 'reps')) {
        result[nid] = row;
      }
    }
    return result;
  }

  // ---------------------------------------------------------------- 映射

  AnkiFieldMapping _mapFields(String modelName, List<String> fields) {
    final List<String> normalized =
        fields.map(_normalizeName).toList(growable: false);
    final int? wordFound = _findField(normalized, _wordKeys);
    final int? definitionFound = _findField(normalized, _definitionKeys);
    final int word = wordFound ?? 0;
    int definition = definitionFound ?? 1;
    if (definition == word) {
      definition = word == 0 ? 1 : 0;
    }
    return AnkiFieldMapping(
      modelName: modelName,
      fields: fields,
      wordIndex: word,
      definitionIndex: definition,
      recognized: wordFound != null && definitionFound != null,
      phoneticIndex: _findField(normalized, _phoneticKeys),
      exampleIndex: _findField(normalized, _exampleKeys),
      posIndex: _findField(normalized, _posKeys),
      noteIndex: _findField(normalized, _noteKeys),
    );
  }

  /// 连字段名的表都没有（很老的导出）时，按 Anki 的默认约定猜：正面、背面。
  AnkiFieldMapping? _fallbackMapping(int fieldCount) {
    if (fieldCount < 2) return null;
    final List<String> fields = <String>[
      for (int i = 0; i < fieldCount; i++) '字段 ' + (i + 1).toString(),
    ];
    return AnkiFieldMapping(
      modelName: '未知笔记类型',
      fields: fields,
      wordIndex: 0,
      definitionIndex: 1,
      recognized: false,
    );
  }

  /// 选项 / 答案式的练习题（不是单词卡）：有选项或判题字段，也有题干字段。
  static bool _looksLikeExercise(List<String> fields) {
    final List<String> names =
        fields.map(_normalizeName).toList(growable: false);
    bool hasAny(Set<String> keys) => names.any(keys.contains);
    return hasAny(_exerciseChoices) && hasAny(_exerciseStems);
  }

  static const Set<String> _exerciseChoices = <String>{
    'opta', 'optb', 'optc', 'optd', 'answer', 'verdict', 'wordbox', 'textblanks',
  };

  static const Set<String> _exerciseStems = <String>{
    'stem', 'prompt', 'lead', 'label', 'statement', 'title', 'textblanks',
  };

  static int? _findField(List<String> fields, List<String> keys) {
    for (final String key in keys) {
      for (int i = 0; i < fields.length; i++) {
        if (fields[i] == key) return i;
      }
    }
    for (final String key in keys) {
      for (int i = 0; i < fields.length; i++) {
        if (fields[i].contains(key)) return i;
      }
    }
    return null;
  }

  static String _normalizeName(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_\-*（）()【】\[\]]'), '');

  // ---------------------------------------------------------------- 文本

  /// Anki 的字段里是 HTML，可能还夹着音频、图片和填空标记。
  static String cleanText(String raw) {
    String text = raw;
    text = text.replaceAll(RegExp(r'\[sound:[^\]]*\]'), '');
    text = text.replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), '');
    text = text.replaceAll(
      RegExp(r'<br\s*/?>', caseSensitive: false),
      '\n',
    );
    text = text.replaceAll(
      RegExp(r'</(div|p|li|tr|h[1-6])>', caseSensitive: false),
      '\n',
    );
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = text.replaceAllMapped(
      RegExp(r'\{\{c\d+::(.*?)(?:::.*?)?\}\}'),
      (Match match) => match.group(1) ?? '',
    );
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
    text = text.replaceAllMapped(
      RegExp(r'&#(x?[0-9a-fA-F]+);'),
      (Match match) {
        final String value = match.group(1)!;
        final int? code = value.startsWith('x') || value.startsWith('X')
            ? int.tryParse(value.substring(1), radix: 16)
            : int.tryParse(value);
        return code == null ? match.group(0)! : String.fromCharCode(code);
      },
    );
    final List<String> lines = text
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
    return lines.join('\n').trim();
  }

  static String _clean(String raw) => cleanText(raw);

  static String? _optional(List<String> fields, int? index) {
    if (index == null || index >= fields.length) return null;
    final String value = cleanText(fields[index]);
    return value.isEmpty ? null : value;
  }

  static List<String> _splitTags(Object? raw) {
    if (raw is! String) return const <String>[];
    return raw
        .split(RegExp(r'\s+'))
        .map((String tag) => tag.trim())
        .where((String tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------- 杂项

  /// 筛选牌组（负 id）里的卡，真正属于 odid 那个牌组。
  static int _deckIdOf(Row? card) {
    if (card == null) return 1;
    final int did = (card['did'] as int?) ?? 1;
    if (did > 0) return did;
    final int odid = (card['odid'] as int?) ?? 0;
    return odid > 0 ? odid : 1;
  }

  static int _intOf(Row? row, String column) =>
      row == null ? 0 : ((row[column] as num?)?.toInt() ?? 0);

  static DateTime? _dateFromSeconds(int seconds) => seconds <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

  /// 复习卡的 due 是「距创建日第几天」；学习卡的 due 是秒级时间戳。
  static DateTime? _dueDate(Row? card, int collectionCreatedAt) {
    if (card == null) return null;
    final int type = _intOf(card, 'type');
    final int due = (card['due'] as num?)?.toInt() ?? 0;
    if (type == 2) {
      if (collectionCreatedAt == 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(
        (collectionCreatedAt + due * 86400) * 1000,
      );
    }
    if (type == 1 && due > 1000000000) return _dateFromSeconds(due);
    return null;
  }

  static String _deckDisplayName(String? raw, String fallback) {
    final String name = (raw ?? '').trim();
    if (name.isEmpty ||
        name == 'Default' ||
        name == '默认' ||
        name == '系统默认') {
      return fallback;
    }
    // schema 11 用 :: 分层，schema 18 用的是 \x1f。
    return name.replaceAll('::', ' / ').replaceAll('\u001f', ' / ');
  }

  static String _fileBaseName(String path) {
    final String name = path.split(RegExp(r'[\\/]')).last;
    final int dot = name.lastIndexOf('.');
    final String base = dot > 0 ? name.substring(0, dot) : name;
    return base.trim().isEmpty ? 'Anki 导入' : base;
  }

  static List<String> _uniqueNames(List<AnkiNote> notes) {
    final List<String> names = <String>[];
    for (final AnkiNote note in notes) {
      if (!names.contains(note.deckName)) names.add(note.deckName);
    }
    return names;
  }

  static bool _looksLikeZip(File file) {
    try {
      final RandomAccessFile handle = file.openSync();
      try {
        final Uint8List head = handle.readSync(4);
        return head.length >= 2 && head[0] == 0x50 && head[1] == 0x4B;
      } finally {
        handle.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- 字段名

  static const List<String> _wordKeys = <String>[
    '单词', '生词', '词汇', '词', 'word', 'front', '正面', 'expression',
    'term', 'question', '英文', '日文', '韩文', '法文', '俄文', '単語', '단어',
  ];

  static const List<String> _definitionKeys = <String>[
    '释义', '意思', '含义', '翻译', '解释', 'definition', 'meaning', 'back',
    '背面', '答案', '译文', '中文', '意味', '뜻', 'sens',
  ];

  static const List<String> _phoneticKeys = <String>[
    '音标', '发音', '读音', 'phonetic', 'ipa', 'pronunciation', 'reading',
    '假名', '読み',
  ];

  static const List<String> _exampleKeys = <String>[
    '例句', '例子', 'example', 'sentence', '用例', 'exemple',
  ];

  static const List<String> _posKeys = <String>[
    '词性', '词类', 'partofspeech', 'pos', '品词',
  ];

  static const List<String> _noteKeys = <String>[
    '备注', '注释', '笔记', 'note', 'notes', 'comment', 'memo', 'メモ',
  ];
}

/// schema 18 里读出来的笔记类型与卡组。
class _Schema18 {
  const _Schema18({required this.mappings, required this.deckNames});

  final Map<int, AnkiFieldMapping> mappings;
  final Map<int, String> deckNames;
}

/// 导入时把词放到哪儿。
enum AnkiDeckMode {
  perAnkiDeck('按 Anki 里的卡组分开'),
  singleDeck('全部放进当前卡组');

  const AnkiDeckMode(this.label);

  final String label;
}

class AnkiImportOptions {
  const AnkiImportOptions({
    this.deckMode = AnkiDeckMode.perAnkiDeck,
    this.targetDeckId,
    this.targetDeckName,
    this.importTags = true,
    this.overwriteExisting = false,
    this.language = CardLanguage.english,
  });

  final AnkiDeckMode deckMode;

  /// [AnkiDeckMode.singleDeck] 时用：落到哪个卡组。
  final String? targetDeckId;
  final String? targetDeckName;

  final bool importTags;
  final bool overwriteExisting;

  /// 卡片没有 lang::xx 标签时用哪种语言。
  final CardLanguage language;
}

class AnkiImportReport {
  const AnkiImportReport({
    required this.imported,
    required this.skippedDuplicates,
    required this.duplicateWords,
    required this.createdDecks,
    required this.warnings,
  });

  final int imported;
  final int skippedDuplicates;
  final List<String> duplicateWords;
  final List<String> createdDecks;
  final List<String> warnings;
}

/// 把解析好的笔记写进本地库：分卡组、去重、补够干扰项。
class AnkiImportService {
  AnkiImportService({
    required CardRepository cards,
    required DeckRepository decks,
    Clock clock = systemClock,
  })  : _cards = cards,
        _decks = decks,
        _clock = clock;

  final CardRepository _cards;
  final DeckRepository _decks;
  final Clock _clock;

  Future<AnkiImportReport> import(
    AnkiCollectionPreview preview,
    AnkiImportOptions options,
  ) async {
    final DateTime now = _clock();
    final Map<String, List<AnkiNote>> groups = <String, List<AnkiNote>>{};
    for (final AnkiNote note in preview.notes) {
      final String key = options.deckMode == AnkiDeckMode.perAnkiDeck
          ? note.deckName
          : (options.targetDeckName ?? note.deckName);
      groups.putIfAbsent(key, () => <AnkiNote>[]).add(note);
    }

    int imported = 0;
    final List<String> duplicateWords = <String>[];
    final List<String> createdDecks = <String>[];
    final List<String> warnings = <String>[...preview.warnings];

    for (final MapEntry<String, List<AnkiNote>> group in groups.entries) {
      final Deck deck = await _resolveDeck(
        group.key,
        options,
        createdDecks,
      );
      final List<AnkiNote> notes = group.value;
      final List<WordCard> existing = await _cards.findByWords(
        notes.map((AnkiNote note) => note.word).toList(growable: false),
        deckId: deck.id,
      );
      final Map<String, WordCard> existingByWord = <String, WordCard>{
        for (final WordCard card in existing) _key(card.word): card,
      };

      final List<String> pool =
          notes.map((AnkiNote note) => note.definition).toList(growable: false);
      final List<WordCard> toInsert = <WordCard>[];
      final List<WordCard> toUpdate = <WordCard>[];

      for (final AnkiNote note in notes) {
        final WordCard? previous = existingByWord[_key(note.word)];
        if (previous != null && !options.overwriteExisting) {
          duplicateWords.add(note.word);
          continue;
        }
        final List<String> tags = <String>[];
        final CardLanguage? fromTag = CardLanguage.fromTags(note.tags);
        if (options.importTags) {
          for (final String raw in note.tags) {
            if (CardLanguage.isLanguageTag(raw)) continue;
            final String tag = WordCard.sanitizeTag(raw);
            if (tag.isEmpty || tags.contains(tag)) continue;
            tags.add(tag);
          }
        }
        final CardLanguage language = fromTag ?? options.language;
        final List<String> distractors = _fillDistractors(note, pool);

        if (previous != null) {
          toUpdate.add(
            previous.copyWith(
              definition: note.definition,
              distractors: distractors,
              phonetic: note.phonetic,
              example: note.example,
              partOfSpeech: note.partOfSpeech,
              note: note.note,
              tags: <String>{...previous.displayTags, ...tags}.toList(growable: false),
              language: language,
              updatedAt: now,
              clearPhonetic: note.phonetic == null,
              clearExample: note.example == null,
              clearPartOfSpeech: note.partOfSpeech == null,
              clearNote: note.note == null,
            ),
          );
          continue;
        }

        toInsert.add(
          WordCard(
            id: newId(),
            word: note.word,
            definition: note.definition,
            distractors: distractors,
            phonetic: note.phonetic,
            example: note.example,
            partOfSpeech: note.partOfSpeech,
            note: note.note,
            deckId: deck.id,
            language: language,
            tags: tags,
            source: CardSource.anki,
            createdAt: now,
            updatedAt: now,
            reviewCount: note.reviewCount,
            correctCount: note.correctCount,
            wrongCount: note.lapses,
            mastery: note.accuracy.clamp(0.0, 1.0),
            lastReviewedAt: note.lastReviewedAt,
            nextReviewAt: note.nextReviewAt,
            intervalDays: note.intervalDays,
            easeFactor: note.easeFactor <= 0 ? 2.5 : note.easeFactor,
          ),
        );
      }

      if (toInsert.isNotEmpty) await _cards.upsertAll(toInsert);
      for (final WordCard card in toUpdate) {
        await _cards.upsert(card);
      }
      imported += toInsert.length + toUpdate.length;
    }

    return AnkiImportReport(
      imported: imported,
      skippedDuplicates: duplicateWords.length,
      duplicateWords: duplicateWords,
      createdDecks: createdDecks,
      warnings: warnings,
    );
  }

  Future<Deck> _resolveDeck(
    String name,
    AnkiImportOptions options,
    List<String> createdDecks,
  ) async {
    final List<Deck> all = await _decks.getAll();
    if (options.deckMode == AnkiDeckMode.singleDeck) {
      final String id = options.targetDeckId ??
          all.firstWhere(
            (Deck deck) => deck.id == Deck.defaultDeckId,
            orElse: () => Deck.fallback(),
          ).id;
      return Deck(
        id: id,
        name: options.targetDeckName ?? Deck.defaultDeckName,
        createdAt: _clock(),
      );
    }
    for (final Deck deck in all) {
      if (deck.name.trim().toLowerCase() == name.trim().toLowerCase()) {
        return deck;
      }
    }
    final Deck created =
        Deck(id: newId(), name: name, createdAt: _clock());
    await _decks.upsert(created);
    createdDecks.add(name);
    return created;
  }

  /// 干扰项不够 4 个时，从同一批单词的释义里借。
  List<String> _fillDistractors(AnkiNote note, List<String> pool) {
    final List<String> result = <String>[];
    final Set<String> seen = <String>{note.definition.trim().toLowerCase()};
    for (final String candidate in pool) {
      if (result.length >= WordCard.targetDistractorCount) break;
      final String value = candidate.trim();
      if (value.isEmpty) continue;
      if (!seen.add(value.toLowerCase())) continue;
      result.add(value);
    }
    return result;
  }

  static String _key(String word) => word.trim().toLowerCase();
}
