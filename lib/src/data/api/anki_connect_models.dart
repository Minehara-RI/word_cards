import '../../core/ids.dart';
import '../../domain/models/card_language.dart';
import '../../domain/models/card_source.dart';
import '../../domain/models/word_card.dart';
import '../import/anki_import.dart' show AnkiCollectionReader;

/// AnkiConnect 说「这个动作不认识」时用的原文。
///
/// 必须一字不差：Yomitan 之类客户端靠这个字符串判断「功能不支持」还是
/// 「连接坏了」，换成「不认识的请求」它们会当成后者。
const String kUnsupportedAction = 'unsupported action';

/// AnkiConnect 的协议版本。6 是现在各客户端都在用的那一版。
const int kAnkiConnectVersion = 6;

/// 一次动作失败。要原样交给客户端看的错误串放在 [message] 里。
class AnkiConnectException implements Exception {
  const AnkiConnectException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 对外暴露的「笔记类型」。
///
/// 本应用物理上只有一张笔记类型（单词卡，7 个中文字段）。
/// 但外部工具（尤其是 Yomitan 的教程与预设）大多按 [Basic] 配置，
/// 所以这里在协议层做一次映射：模型名照客户端说的，字段换成本应用的那几个。
/// 物理表结构一行都不用改，用 Anki 打开还是干净的「单词卡」。
class VirtualNoteType {
  const VirtualNoteType(this.name, this.fields);

  final String name;
  final List<String> fields;

  static const VirtualNoteType wordCard = VirtualNoteType(
    '单词卡',
    <String>['单词', '释义', '音标', '例句', '词性', '备注', '干扰项'],
  );

  static const VirtualNoteType basic =
      VirtualNoteType('Basic', <String>['Front', 'Back']);

  static const List<VirtualNoteType> all = <VirtualNoteType>[wordCard, basic];

  static VirtualNoteType? find(String? name) {
    if (name == null) return null;
    for (final VirtualNoteType type in all) {
      if (type.name == name.trim()) return type;
    }
    return null;
  }
}

/// 外部请求里的一条笔记。
class InboundNote {
  const InboundNote({
    required this.modelName,
    required this.fields,
    this.deckName,
    this.tags = const <String>[],
    this.allowDuplicate = false,
    this.duplicateScope = 'collection',
  });

  final String modelName;
  final String? deckName;

  /// 字段名 → 原值。字段名按 Anki 的约定保留大小写，匹配时再归一化。
  final Map<String, String> fields;

  final List<String> tags;
  final bool allowDuplicate;

  /// collection（整个词库查重）或 deck（只在目标卡组里查重）。
  final String duplicateScope;

  static InboundNote fromJson(Map<String, Object?> json) {
    final Object? rawFields = json['fields'];
    final Map<String, String> fields = <String, String>{};
    if (rawFields is Map) {
      rawFields.forEach((Object? key, Object? value) {
        if (key == null) return;
        fields[key.toString()] = (value ?? '').toString();
      });
    }
    final Object? rawOptions = json['options'];
    Map<String, Object?> options = <String, Object?>{};
    if (rawOptions is Map) options = rawOptions.cast<String, Object?>();

    return InboundNote(
      modelName: (json['modelName'] as String?)?.trim() ?? '',
      deckName: (json['deckName'] as String?)?.trim(),
      fields: fields,
      tags: _tags(json['tags']),
      allowDuplicate: options['allowDuplicate'] == true,
      duplicateScope: (options['duplicateScope'] as String?)?.trim() ?? 'collection',
    );
  }

  static List<String> _tags(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((Object? item) => (item ?? '').toString().trim())
        .where((String tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  /// 按别名字段表取值；没有就用空串。
  ///
  /// 别名同时收英文（Front/Back/Sentence…）与中文（单词/释义…），
  /// 这样不管客户端按哪套模型配的，内容都能落进正确的字段。
  String field(List<String> aliases) {
    for (final String alias in aliases) {
      final String key = _normalize(alias);
      for (final MapEntry<String, String> entry in fields.entries) {
        if (_normalize(entry.key) == key) return entry.value;
      }
    }
    return '';
  }

  String get word => AnkiCollectionReader.cleanText(
        field(<String>['单词', 'Front', 'Word', 'Expression', 'Term', 'Headword']),
      ).trim();

  String get definition => AnkiCollectionReader.cleanText(
        field(<String>['释义', 'Back', 'Definition', 'Meaning', 'Translation']),
      ).trim();

  String? get phonetic {
    final String text = AnkiCollectionReader.cleanText(
      field(<String>['音标', 'Phonetic', 'Pronunciation', 'IPA', 'Reading']),
    ).trim();
    return text.isEmpty ? null : text;
  }

  String? get example {
    final String text = AnkiCollectionReader.cleanText(
      field(<String>['例句', 'Sentence', 'Example', 'Context']),
    ).trim();
    return text.isEmpty ? null : text;
  }

  String? get partOfSpeech {
    final String text = AnkiCollectionReader.cleanText(
      field(<String>['词性', 'PartOfSpeech', 'POS']),
    ).trim();
    return text.isEmpty ? null : text;
  }

  String? get note {
    final String text = AnkiCollectionReader.cleanText(
      field(<String>['备注', 'Notes', 'Note', 'Comment']),
    ).trim();
    return text.isEmpty ? null : text;
  }

  List<String> get distractors {
    final String text = AnkiCollectionReader.cleanText(
      field(<String>['干扰项', 'Distractors', 'Options']),
    );
    return text
        .split(RegExp(r'[\n|;；]+'))
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  /// 语言：优先看客户端带来的 lang::xx 标签，没有就用应用当前的默认语言。
  CardLanguage languageOr(CardLanguage fallback) =>
      CardLanguage.fromTags(tags) ?? fallback;

  /// 用户标签（去掉语言标签、去掉空白、按 Anki 的规矩把空格换成下划线）。
  List<String> get userTags => <String>[
        for (final String tag in tags)
          if (!CardLanguage.isLanguageTag(tag))
            if (WordCard.sanitizeTag(tag).isNotEmpty)
              WordCard.sanitizeTag(tag),
      ];

  WordCard toCard({
    required String id,
    required String deckId,
    required CardLanguage language,
    required DateTime now,
  }) {
    final List<String> merged = <String>[];
    for (final String item in distractors) {
      if (item == definition) continue;
      if (merged.contains(item)) continue;
      merged.add(item);
    }
    return WordCard(
      id: id,
      word: word,
      definition: definition,
      distractors: merged,
      phonetic: phonetic,
      example: example,
      partOfSpeech: partOfSpeech,
      note: note,
      deckId: deckId,
      language: languageOr(language),
      tags: userTags,
      source: CardSource.external,
      createdAt: now,
      updatedAt: now,
    );
  }

  static String _normalize(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[\s_\-*]'), '');
}

/// AnkiConnect 的「卡片」响应体。只做能如实回答的部分。
Map<String, Object?> noteInfoJson({
  required int noteId,
  required WordCard card,
  required String modelName,
}) {
  final List<String> fields = <String>[
    card.word,
    card.definition,
    card.phonetic ?? '',
    card.example ?? '',
    card.partOfSpeech ?? '',
    card.note ?? '',
    card.distractors.join('\n'),
  ];
  final List<String> names =
      modelName == VirtualNoteType.basic.name
          ? <String>['Front', 'Back']
          : VirtualNoteType.wordCard.fields;
  return <String, Object?>{
    'noteId': noteId,
    'profile': 'word_flashcards',
    'tags': <String>[
      for (final String tag in card.tags) tag,
      card.language.tag,
    ],
    'fields': <String, Object?>{
      for (int i = 0; i < names.length; i++)
        names[i]: <String, Object?>{
          'value': i < fields.length ? fields[i] : '',
          'order': i,
        },
    },
    'modelName': modelName.isEmpty ? VirtualNoteType.wordCard.name : modelName,
    'mod': card.updatedAt.millisecondsSinceEpoch ~/ 1000,
    'cards': <int>[noteId],
  };
}

/// 卡组名的归一化：Anki 用 `父::子`，本应用显示成 `父 / 子`。
String normalizeDeckName(String raw) {
  String name = raw.trim();
  name = name.replaceAll('\u001f', ' / ');
  name = name.replaceAll('::', ' / ');
  return name.replaceAll(RegExp(r'\s*/\s*'), ' / ').trim();
}

/// 新的卡片 id：和仓库里别的地方一样用 uuid，跨设备不会撞。
String newCardId() => newId();
