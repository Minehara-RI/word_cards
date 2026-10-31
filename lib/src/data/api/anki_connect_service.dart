// 这里的字符串用 + 拼是刻意的（拼卡组名），关掉这条纯风格 lint。
// ignore_for_file: prefer_interpolation_to_compose_strings
// 私有字段用不了 this._x 形式的具名参数（Dart 不允许私有具名参数），
// 和 card_completion.dart 一样关掉这条。
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import '../../core/ids.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/deck.dart';
import '../../domain/models/word_card.dart';
import '../../domain/repositories.dart';
import '../anki/anki_collection.dart';
import 'anki_connect_models.dart';

/// 这个服务实现了哪些动作。
///
/// **apiReflect 只报这里列出来的东西**，客户端（Yomitan）据此决定显示哪些
/// 按钮、要不要发音频。所以没实现的动作千万不要往里加：报出去又做不到，
/// 客户端会在用户点下去的时候才炸。
///
/// 刻意不做的：guiBrowse / guiEditNote（本应用没有「卡片浏览器」这种窗口）、
/// storeMediaFile（卡片里不存音频图片）、suspend、sync、
/// findCards / cardsInfo（那套字段是 Anki 的调度语义，我们没有对等物）。
const List<String> kAnkiConnectActions = <String>[
  'version',
  'apiReflect',
  'multi',
  'requestPermission',
  'deckNames',
  'createDeck',
  'modelNames',
  'modelFieldNames',
  'canAddNotes',
  'canAddNotesWithErrorDetail',
  'addNote',
  'addNotes',
  'notesInfo',
  'findNotes',
  'updateNoteFields',
];

/// 处理 AnkiConnect 的那些动作。
///
/// 写进来的词走的是和界面同一个 CardRepository，所以加完立刻出现在列表里，
/// 也会被计入同步；没有第二条写入路径。
class AnkiConnectService {
  AnkiConnectService({
    required CardRepository cards,
    required DeckRepository decks,
    required SettingsRepository settings,
    required AnkiCollection collection,
    Future<void> Function(WordCard card)? onCardAdded,
    Clock clock = systemClock,
  })  : _cards = cards,
        _decks = decks,
        _settings = settings,
        _collection = collection,
        _onCardAdded = onCardAdded,
        _clock = clock;

  final CardRepository _cards;
  final DeckRepository _decks;
  final SettingsRepository _settings;
  final AnkiCollection _collection;
  final Future<void> Function(WordCard card)? _onCardAdded;
  final Clock _clock;

  /// 分发一个动作。失败一律抛 [AnkiConnectException]，消息原样给客户端看。
  Future<Object?> dispatch(String action, Map<String, Object?> params) async {
    switch (action) {
      case 'version':
        return kAnkiConnectVersion;
      case 'apiReflect':
        return _reflect(params);
      case 'multi':
        return _multi(params);
      case 'requestPermission':
        final AppSettings settings = await _settings.load();
        return <String, Object?>{
          'permission': 'granted',
          'requireApikey': (settings.apiServerKey ?? '').isNotEmpty,
        };
      case 'deckNames':
        return <String>[
          for (final Deck deck in await _decks.getAll()) deck.name,
        ];
      case 'createDeck':
        return _createDeck(params);
      case 'modelNames':
        return <String>[
          for (final VirtualNoteType type in VirtualNoteType.all) type.name,
        ];
      case 'modelFieldNames':
        final String name = (params['modelName'] as String?)?.trim() ?? '';
        final VirtualNoteType? model = VirtualNoteType.find(name);
        if (model == null) {
          throw AnkiConnectException('model was not found: ' + name);
        }
        return model.fields;
      case 'canAddNotes':
        return _canAddNotes(params, detailed: false);
      case 'canAddNotesWithErrorDetail':
        return _canAddNotes(params, detailed: true);
      case 'addNote':
        final Object? note = params['note'];
        if (note is! Map) {
          throw const AnkiConnectException('addNote 需要一个 note 参数');
        }
        return _addNote(note.cast<String, Object?>());
      case 'addNotes':
        return _addNotes(params);
      case 'notesInfo':
        return _notesInfo(params);
      case 'findNotes':
        return _findNotes(params);
      case 'updateNoteFields':
        return _updateNoteFields(params);
      default:
        throw const AnkiConnectException(kUnsupportedAction);
    }
  }

  // ------------------------------------------------------------ 元信息

  Map<String, Object?> _reflect(Map<String, Object?> params) {
    final List<String> scopes = (params['scopes'] as List?)
            ?.map((Object? scope) => scope.toString())
            .toList(growable: false) ??
        const <String>['actions'];
    final List<String>? requested = (params['actions'] as List?)
        ?.map((Object? action) => action.toString())
        .toList(growable: false);
    final List<String> actions = requested == null
        ? kAnkiConnectActions
        : <String>[
            for (final String action in requested)
              if (kAnkiConnectActions.contains(action)) action,
          ];
    return <String, Object?>{
      'scopes': <String>[
        for (final String scope in scopes)
          if (scope == 'actions') scope,
      ],
      'actions': actions,
    };
  }

  Future<Object?> _multi(Map<String, Object?> params) async {
    final List<Object?> actions =
        (params['actions'] as List?) ?? const <Object?>[];
    final List<Object?> results = <Object?>[];
    for (final Object? item in actions) {
      if (item is! Map) {
        results.add(<String, Object?>{
          'result': null,
          'error': 'multi 里的子请求格式不对',
        });
        continue;
      }
      final Map<String, Object?> sub = item.cast<String, Object?>();
      try {
        final Object? value = await dispatch(
          (sub['action'] as String?) ?? '',
          (sub['params'] as Map?)?.cast<String, Object?>() ?? <String, Object?>{},
        );
        results.add(value);
      } on AnkiConnectException catch (error) {
        results.add(<String, Object?>{'result': null, 'error': error.message});
      } catch (error) {
        results.add(<String, Object?>{'result': null, 'error': error.toString()});
      }
    }
    return results;
  }

  // ------------------------------------------------------------ 卡组

  Future<Object?> _createDeck(Map<String, Object?> params) async {
    final String name = normalizeDeckName((params['deck'] as String?) ?? '');
    if (name.isEmpty) {
      throw const AnkiConnectException('deck 名字不能是空的');
    }
    final Deck deck = await _resolveDeck(
      name,
      create: true,
      settings: await _settings.load(),
    );
    return _deckIntegerId(deck.id);
  }

  int _deckIntegerId(String uid) =>
      _collection.deckIdForUid(uid) ?? _collection.ensureDeckId(uid);

  // ------------------------------------------------------------ 写入

  Future<Object?> _canAddNotes(
    Map<String, Object?> params, {
    required bool detailed,
  }) async {
    final List<Object?> notes = (params['notes'] as List?) ?? const <Object?>[];
    final List<Object?> results = <Object?>[];
    for (final Object? item in notes) {
      String? error;
      if (item is! Map) {
        error = 'note 格式不对';
      } else {
        try {
          await _prepare(item.cast<String, Object?>(), createDeck: false);
        } on AnkiConnectException catch (failure) {
          error = failure.message;
        }
      }
      if (detailed) {
        results.add(<String, Object?>{
          'canAdd': error == null,
          'error': error,
        });
      } else {
        results.add(error == null);
      }
    }
    return results;
  }

  Future<int> _addNote(Map<String, Object?> note) async {
    final _Prepared prepared = await _prepare(note, createDeck: true);
    final AppSettings settings = await _settings.load();
    final DateTime now = _clock();
    WordCard card = prepared.note.toCard(
      id: newId(),
      deckId: prepared.deck.id,
      language: settings.language,
      now: now,
    );
    card = await _fillDistractors(card);

    await _cards.upsert(card);
    // 记住「这张笔记当初是按哪个模型写的」：Basic 之类的模型名只存在于
    // 协议层，物理上还是同一张「单词卡」表。notes.data 是 Anki 的备注列，
    // 我们的卡片模板不读它，写在这里既不污染界面也不会被 Anki 冲掉。
    _rememberModel(card.id, prepared.model.name);

    final Future<void> Function(WordCard card)? after = _onCardAdded;
    if (after != null && settings.apiServerAutoComplete) {
      // 不 await：外部写入要快，补全失败也不该让客户端以为加卡失败。
      unawaited(after(card));
    }
    return _collection.noteIdForCard(card.id) ??
        _collection.ensureCardIds(card.id);
  }

  Future<Object?> _addNotes(Map<String, Object?> params) async {
    final List<Object?> notes = (params['notes'] as List?) ?? const <Object?>[];
    final List<Object?> results = <Object?>[];
    for (final Object? item in notes) {
      if (item is! Map) {
        results.add(null);
        continue;
      }
      try {
        results.add(await _addNote(item.cast<String, Object?>()));
      } on AnkiConnectException {
        // Anki 的 addNotes 就是「失败的给 null」，不中断整批。
        results.add(null);
      }
    }
    return results;
  }

  Future<Object?> _updateNoteFields(Map<String, Object?> params) async {
    final Object? raw = params['note'];
    if (raw is! Map) {
      throw const AnkiConnectException('updateNoteFields 需要一个 note 参数');
    }
    final Map<String, Object?> note = raw.cast<String, Object?>();
    final int noteId = (note['id'] as num?)?.toInt() ?? 0;
    final String? uid = _collection.cardUidForNote(noteId);
    final WordCard? existing = uid == null ? null : await _cards.getById(uid);
    if (existing == null) {
      throw AnkiConnectException('note was not found: ' + noteId.toString());
    }

    final InboundNote incoming = InboundNote.fromJson(note);
    WordCard next = existing;
    if (incoming.word.isNotEmpty && incoming.word != existing.word) {
      next = next.copyWith(word: incoming.word);
    }
    if (incoming.definition.isNotEmpty &&
        incoming.definition != existing.definition) {
      next = next.copyWith(definition: incoming.definition);
    }
    if (incoming.phonetic != null) {
      next = next.copyWith(phonetic: incoming.phonetic);
    }
    if (incoming.example != null) next = next.copyWith(example: incoming.example);
    if (incoming.partOfSpeech != null) {
      next = next.copyWith(partOfSpeech: incoming.partOfSpeech);
    }
    if (incoming.note != null) next = next.copyWith(note: incoming.note);
    if (incoming.distractors.isNotEmpty) {
      next = next.copyWith(
        distractors: incoming.distractors
            .where((String item) => item != next.definition)
            .toList(growable: false),
      );
    }
    if (incoming.userTags.isNotEmpty) {
      next = next.copyWith(tags: incoming.userTags);
    }

    // 改内容要推进 updatedAt，否则同步时会被对面「更早但更新」的版本盖掉。
    next = await _fillDistractors(next.copyWith(updatedAt: _clock()));
    await _cards.upsert(next);
    return null;
  }

  // ------------------------------------------------------------ 读回

  Future<Object?> _notesInfo(Map<String, Object?> params) async {
    final List<Object?> notes = (params['notes'] as List?) ?? const <Object?>[];
    final List<Object?> result = <Object?>[];
    for (final Object? item in notes) {
      final int noteId =
          item is num ? item.toInt() : int.tryParse(item.toString()) ?? 0;
      final String? uid = _collection.cardUidForNote(noteId);
      final WordCard? card = uid == null ? null : await _cards.getById(uid);
      if (card == null) {
        result.add(null);
        continue;
      }
      result.add(noteInfoJson(
        noteId: noteId,
        card: card,
        modelName: _storedModel(noteId) ?? VirtualNoteType.wordCard.name,
      ));
    }
    return result;
  }

  Future<Object?> _findNotes(Map<String, Object?> params) async {
    final String query = (params['query'] as String?)?.trim() ?? '';
    final _ParsedQuery parsed = _ParsedQuery.parse(query);
    final List<Deck> decks = await _decks.getAll();
    final Set<String>? deckIds = parsed.deck == null
        ? null
        : <String>{
            for (final Deck deck in decks)
              if (normalizeDeckName(deck.name) ==
                  normalizeDeckName(parsed.deck!))
                deck.id,
          };
    if (deckIds != null && deckIds.isEmpty) return const <int>[];

    final List<WordCard> cards = await _cards.getAll();
    final List<int> ids = <int>[];
    for (final WordCard card in cards) {
      if (deckIds != null && !deckIds.contains(card.deckId)) continue;
      if (parsed.tag != null && !card.tags.contains(parsed.tag)) continue;
      if (parsed.text != null && parsed.text!.isNotEmpty) {
        final String needle = parsed.text!.toLowerCase();
        final bool hit = card.word.toLowerCase() == needle ||
            card.definition.toLowerCase().contains(needle);
        if (!hit) continue;
      }
      ids.add(_collection.noteIdForCard(card.id) ??
          _collection.ensureCardIds(card.id));
    }
    return ids;
  }

  // ------------------------------------------------------------ 内部

  /// 校验一条笔记能不能写进来，把该解析的都解析好。
  ///
  /// [createDeck] 为 false 时不会顺手建卡组：canAddNotes 只是预检，
  /// 预检里建出一个卡组会让用户莫名其妙多出一个空卡组。
  Future<_Prepared> _prepare(
    Map<String, Object?> noteJson, {
    required bool createDeck,
  }) async {
    final InboundNote note = InboundNote.fromJson(noteJson);
    final VirtualNoteType? model = VirtualNoteType.find(note.modelName);
    if (model == null) {
      throw AnkiConnectException('model was not found: ' + note.modelName);
    }
    if (note.word.isEmpty) {
      throw const AnkiConnectException('note is missing the 单词 / Front field');
    }
    if (note.definition.isEmpty) {
      throw const AnkiConnectException('note is missing the 释义 / Back field');
    }
    final AppSettings settings = await _settings.load();
    final Deck deck = await _resolveDeck(
      note.deckName,
      create: createDeck,
      settings: settings,
    );

    if (!note.allowDuplicate) {
      final WordCard? existing = await _cards.findByWord(
        note.word,
        deckId: note.duplicateScope == 'deck' ? deck.id : null,
      );
      if (existing != null) {
        throw const AnkiConnectException(
          'cannot create note because it is a duplicate',
        );
      }
    }
    return _Prepared(note: note, model: model, deck: deck);
  }

  Future<Deck> _resolveDeck(
    String? requested, {
    required bool create,
    required AppSettings settings,
  }) async {
    final List<Deck> decks = await _decks.getAll();
    Deck? byId(String? id) {
      if (id == null || id.isEmpty) return null;
      for (final Deck deck in decks) {
        if (deck.id == id) return deck;
      }
      return null;
    }

    // 设置里锁定了卡组就一律进它（客户端说什么都不管）；
    // 锁定的卡组被删了才往下走，不让外部写入无家可归。
    final Deck? locked = byId(settings.apiServerDeckId);
    if (locked != null) return locked;

    if (requested != null && requested.trim().isNotEmpty) {
      final String wanted = normalizeDeckName(requested);
      for (final Deck deck in decks) {
        if (normalizeDeckName(deck.name) == wanted) return deck;
      }
      if (!create) {
        throw AnkiConnectException('deck was not found: ' + requested);
      }
      final Deck deck = Deck(id: newId(), name: wanted, createdAt: _clock());
      await _decks.upsert(deck);
      return deck;
    }

    return byId(settings.activeDeckId) ??
        byId(Deck.defaultDeckId) ??
        Deck.fallback();
  }

  /// 从同卡组已有的释义里借几个干扰项。
  ///
  /// 外部写入多半只给「词 + 释义」，而五选一需要 4 个干扰项。
  /// 借不到就挂「待补全」标签，由界面提示用户补（或者开自动补全）。
  Future<WordCard> _fillDistractors(WordCard card) async {
    final int need = WordCard.targetDistractorCount;
    final List<String> distractors = <String>[...card.distractors];
    if (distractors.length < need) {
      final List<WordCard> siblings = await _cards.getAll(deckId: card.deckId);
      for (final WordCard other in siblings) {
        if (distractors.length >= need) break;
        final String candidate = other.definition.trim();
        if (candidate.isEmpty || candidate == card.definition) continue;
        if (distractors.contains(candidate)) continue;
        distractors.add(candidate);
      }
    }

    final List<String> tags = <String>[...card.tags];
    if (distractors.length < need) {
      if (!tags.contains(WordCard.incompleteTag)) {
        tags.add(WordCard.incompleteTag);
      }
    } else {
      tags.remove(WordCard.incompleteTag);
    }
    return card.copyWith(distractors: distractors, tags: tags);
  }

  void _rememberModel(String uid, String modelName) {
    final int? noteId = _collection.noteIdForCard(uid);
    if (noteId == null) return;
    if (modelName == VirtualNoteType.wordCard.name) return;
    _collection.db.execute(
      'update notes set data = ? where id = ?',
      <Object?>[jsonEncode(<String, Object?>{'wcModel': modelName}), noteId],
    );
  }

  String? _storedModel(int noteId) {
    final rows = _collection.db
        .select('select data from notes where id = ?', <Object?>[noteId]);
    if (rows.isEmpty) return null;
    final Object? raw = rows.first['data'];
    if (raw is! String || raw.trim().isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) return decoded['wcModel'] as String?;
    } on FormatException {
      return null;
    }
    return null;
  }
}

class _Prepared {
  const _Prepared({
    required this.note,
    required this.model,
    required this.deck,
  });

  final InboundNote note;
  final VirtualNoteType model;
  final Deck deck;
}

/// Anki 的搜索语法只认我们真能回答的那几种：卡组、标签、词面。
///
/// 不追求完整实现：findNotes 在客户端里主要用于「这条是不是已经有了」，
/// 认不出来的查询当成普通文本，比直接报错更不容易让人一头雾水。
class _ParsedQuery {
  const _ParsedQuery({this.deck, this.tag, this.text});

  final String? deck;
  final String? tag;
  final String? text;

  static _ParsedQuery parse(String raw) {
    String rest = raw;
    String? deck;
    String? tag;

    final RegExp deckPattern =
        RegExp(r'deck:"([^"]*)"|deck:([^s]+)', caseSensitive: false);
    final RegExpMatch? deckMatch = deckPattern.firstMatch(rest);
    if (deckMatch != null) {
      deck = deckMatch.group(1) ?? deckMatch.group(2);
      rest = rest.replaceRange(deckMatch.start, deckMatch.end, ' ');
    }

    final RegExp tagPattern =
        RegExp(r'tag:"([^"]*)"|tag:([^s]+)', caseSensitive: false);
    final RegExpMatch? tagMatch = tagPattern.firstMatch(rest);
    if (tagMatch != null) {
      tag = tagMatch.group(1) ?? tagMatch.group(2);
      rest = rest.replaceRange(tagMatch.start, tagMatch.end, ' ');
    }

    String text = rest.trim();
    // 字段前缀（"Front:word" / "word:word" / "sfld:word"）只保留值。
    final RegExpMatch? field =
        RegExp(r'^(?:[A-Za-z_]+|单词|释义):(.+)').firstMatch(text);
    if (field != null) text = field.group(1)!.trim();
    text = text.replaceAll('"', '').trim();
    return _ParsedQuery(
      deck: deck,
      tag: tag,
      text: text.isEmpty ? null : text,
    );
  }
}
