// 说明：本文件的字符串拼接刻意不使用插值语法，避免与转义/生成工具冲突。
// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';

/// 解析过程中的问题类型。
enum ParseIssueKind {
  emptyInput,
  syntaxError,
  notAnObject,
  missingField,
  invalidField,
  noCards,
}

/// 一条可以明确展示给用户的问题。
///
/// 设计约束：**不要笼统地说“格式错误”**，必须指出第几张卡片、缺哪个字段。
class ParseIssue {
  const ParseIssue(
    this.kind,
    this.message, {
    this.index,
    this.field,
    this.snippet,
  });

  final ParseIssueKind kind;

  /// 面向用户的中文描述。
  final String message;

  /// 第几张卡片（1-based）；整段格式错误时为 null。
  final int? index;

  /// 出问题的字段，结构化保留，便于测试与后续定位。
  final String? field;

  final String? snippet;

  /// 带位置前缀的完整文案，例如「第 2 张卡片：缺少 definition（正确释义）字段」。
  String get display => index == null ? message : '第 $index 张卡片：$message';

  @override
  String toString() => display;
}

/// 一张通过了校验、可以直接入库的卡片。
class ParsedCard {
  const ParsedCard({
    required this.word,
    required this.definition,
    required this.distractors,
    this.phonetic,
    this.example,
    this.partOfSpeech,
    this.position,
  });

  final String word;
  final String definition;
  final List<String> distractors;
  final String? phonetic;
  final String? example;
  final String? partOfSpeech;

  /// 用户粘贴内容里的序号（1-based），用于把警告对应回去。
  final int? position;

  ParsedCard copyWith({List<String>? distractors}) => ParsedCard(
        word: word,
        definition: definition,
        distractors: distractors ?? this.distractors,
        phonetic: phonetic,
        example: example,
        partOfSpeech: partOfSpeech,
        position: position,
      );

  @override
  String toString() =>
      'ParsedCard(' + word + ' -> ' + definition + ', ' + distractors.length.toString() + ' 个干扰项)';
}

/// 一次解析的完整结果：成功的卡片 + 具体问题 + 非致命警告。
class ParseResult {
  const ParseResult({
    this.cards = const <ParsedCard>[],
    this.issues = const <ParseIssue>[],
    this.warnings = const <String>[],
    this.repaired = false,
  });

  final List<ParsedCard> cards;
  final List<ParseIssue> issues;
  final List<String> warnings;

  /// LLM 输出不标准，解析器做过后处理（去代码块、补尾逗号等）。
  final bool repaired;

  bool get hasCards => cards.isNotEmpty;
  bool get hasIssues => issues.isNotEmpty;
}

/// 容错 JSON 解析器。
///
/// LLM 的输出经常不是干净的 JSON：外面套着闲聊、包在 Markdown 代码块里、
/// 字段名中英混杂、尾随逗号、全角标点。这个解析器的职责就是把它们
/// 尽量救回来，救不回来的部分给出**具体到第几张卡片、哪个字段**的提示。
class CardParser {
  const CardParser();

  static const CardParser instance = CardParser();

  static const String _tick = '\u0060';

  static ParseResult parseText(String raw) => instance.parse(raw);

  // ---------------------------------------------------------------- 字段别名

  static const List<String> _aliasWord = <String>[
    'word',
    'term',
    'text',
    'vocabulary',
    'headword',
    'english',
    '单词',
    '词',
    '英文',
    '单词原形',
  ];

  static const List<String> _aliasPhonetic = <String>[
    'phonetic',
    'phonetics',
    'ipa',
    'pronunciation',
    'pron',
    '音标',
    '读音',
    '发音',
  ];

  static const List<String> _aliasDefinition = <String>[
    'definition',
    'meaning',
    'correct',
    'correctdefinition',
    'correctanswer',
    'answer',
    '释义',
    '意思',
    '含义',
    '中文',
    '中文释义',
    '解释',
  ];

  static const List<String> _aliasDistractors = <String>[
    'distractors',
    'distractor',
    'wrong',
    'wrongs',
    'wronganswers',
    'incorrect',
    'incorrectanswers',
    'othermeanings',
    'decoys',
    '干扰项',
    '错误选项',
    '错误释义',
    '干扰释义',
  ];

  static const List<String> _aliasOptions = <String>[
    'options',
    'choices',
    '选项',
  ];

  static const List<String> _aliasExample = <String>[
    'example',
    'sentence',
    'examplesentence',
    '例句',
    '示例',
  ];

  static const List<String> _aliasPartOfSpeech = <String>[
    'partofspeech',
    'pos',
    'type',
    '词性',
  ];

  static const List<String> _aliasCards = <String>[
    'cards',
    'data',
    'items',
    'result',
    'results',
    'list',
    '卡片',
    '结果',
    '数据',
  ];

  static const List<String> _aliasAnswerIndex = <String>[
    'answerindex',
    'correctindex',
    'correctoptionindex',
    '正确选项',
  ];

  // ---------------------------------------------------------------- 入口

  /// 解析一段可能不干净的 JSON 文本。
  ParseResult parse(String raw) {
    final issues = <ParseIssue>[];
    final warnings = <String>[];
    final text = _sanitizeRaw(raw);

    if (text.isEmpty) {
      return const ParseResult(
        issues: <ParseIssue>[
          ParseIssue(ParseIssueKind.emptyInput, '还没有内容，请先把大模型返回的 JSON 粘贴到输入框。'),
        ],
      );
    }

    var repaired = false;
    Object? decoded;

    try {
      decoded = jsonDecode(text);
    } on FormatException {
      // 第二步：截取第一个括号完整的 JSON 片段（前后可能有闲聊）。
      final candidate = _extractBalanced(text) ?? text;
      try {
        decoded = jsonDecode(candidate);
      } on FormatException {
        // 第三步：结构化修复（注释、尾逗号、全角标点、未转义换行）。
        final fixed = _repair(candidate);
        repaired = fixed != candidate;
        try {
          decoded = jsonDecode(fixed);
        } on FormatException catch (error) {
          return ParseResult(
            issues: <ParseIssue>[
              ParseIssue(
                ParseIssueKind.syntaxError,
                _describeSyntaxError(error, candidate),
              ),
            ],
            warnings: warnings,
          );
        }
      }
    }

    final items = _itemsOf(decoded);
    if (items == null) {
      return ParseResult(
        issues: const <ParseIssue>[
          ParseIssue(
            ParseIssueKind.notAnObject,
            '顶层必须是对象 { ... } 或数组 [ ... ]，当前是别的东西。',
          ),
        ],
        warnings: warnings,
        repaired: repaired,
      );
    }

    final cards = <ParsedCard>[];
    for (var i = 0; i < items.length; i++) {
      final card = _mapItem(items[i], i + 1, issues, warnings);
      if (card != null) cards.add(card);
    }

    if (cards.isEmpty && issues.isEmpty) {
      issues.add(
        const ParseIssue(ParseIssueKind.noCards, '解析成功，但里面没有任何卡片。'),
      );
    }

    return ParseResult(
      cards: cards,
      issues: issues,
      warnings: warnings,
      repaired: repaired,
    );
  }

  // ---------------------------------------------------------------- 拆解步骤

  /// 去掉 BOM / 零宽字符，并在有 Markdown 代码块时取最长的那个块。
  static String _sanitizeRaw(String raw) {
    final text = raw
        .replaceAll('\uFEFF', '')
        .replaceAll('\u200B', '')
        .trim();
    final fenced = _longestFenceBody(text);
    return (fenced ?? text).trim();
  }

  /// 提取 Markdown 代码块里最长的正文；没有代码块时返回 null。
  static String? _longestFenceBody(String text) {
    final fence = _tick + _tick + _tick;
    if (!text.contains(fence)) return null;

    final bodies = <String>[];
    var cursor = 0;
    while (true) {
      final start = text.indexOf(fence, cursor);
      if (start < 0) break;
      final lineEnd = text.indexOf('\n', start);
      if (lineEnd < 0) break;
      final end = text.indexOf(fence, lineEnd);
      if (end < 0) break;
      bodies.add(text.substring(lineEnd + 1, end).trim());
      cursor = end + fence.length;
    }
    if (bodies.isEmpty) return null;

    bodies.sort((a, b) => b.length.compareTo(a.length));
    return bodies.first;
  }

  /// 从第一个 { 或 [ 开始，扫描到配对的收尾符号。
  static String? _extractBalanced(String text) {
    var start = -1;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '{' || ch == '[') {
        start = i;
        break;
      }
    }
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == '{' || ch == '[') {
        depth++;
      } else if (ch == '}' || ch == ']') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    return null;
  }

  /// 结构化修复：只在字符串外部动结构字符，字符串内容原样保留。
  static String _repair(String text) {
    final buffer = StringBuffer();
    var inString = false;
    var escaped = false;

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];

      if (inString) {
        if (escaped) {
          buffer.write(ch);
          escaped = false;
          continue;
        }
        if (ch == '\\') {
          buffer.write(ch);
          escaped = true;
          continue;
        }
        if (ch == '"') {
          inString = false;
          buffer.write(ch);
          continue;
        }
        if (ch == '\u201D' || ch == '\u201C') {
          inString = false;
          buffer.write('"');
          continue;
        }
        if (ch == '\n') {
          // 字符串里出现了没转义的换行
          buffer.write('\\n');
          continue;
        }
        if (ch == '\r') {
          continue;
        }
        buffer.write(ch);
        continue;
      }

      if (ch == '"') {
        inString = true;
        buffer.write(ch);
        continue;
      }
      if (ch == '\u201C' || ch == '\u201D') {
        inString = true;
        buffer.write('"');
        continue;
      }
      if (ch == '/' && i + 1 < text.length && text[i + 1] == '/') {
        while (i < text.length && text[i] != '\n') {
          i++;
        }
        continue;
      }
      if (ch == '/' && i + 1 < text.length && text[i + 1] == '*') {
        i += 2;
        while (i + 1 < text.length && !(text[i] == '*' && text[i + 1] == '/')) {
          i++;
        }
        i++;
        continue;
      }
      if (ch == '\uFF0C') {
        buffer.write(',');
        continue;
      }
      if (ch == '\uFF1A') {
        buffer.write(':');
        continue;
      }
      if (ch == '\uFF08' || ch == '\uFF09') {
        continue;
      }
      buffer.write(ch);
    }

    // 去掉对象/数组收尾前的多余逗号
    return buffer.toString().replaceAllMapped(
          RegExp(r',(\s*[}\]])'),
          (match) => match.group(1) ?? '',
        );
  }

  static String _describeSyntaxError(FormatException error, String source) {
    final offset = error.offset;
    if (offset == null || offset > source.length) {
      return 'JSON 语法错误：' + error.message;
    }
    var line = 1;
    var column = 1;
    for (var i = 0; i < offset; i++) {
      if (source[i] == '\n') {
        line++;
        column = 1;
      } else {
        column++;
      }
    }
    final preview = _snippetAt(source, offset);
    return 'JSON 语法错误：' +
        error.message +
        '（第 ' +
        line.toString() +
        ' 行第 ' +
        column.toString() +
        ' 列附近：' +
        preview +
        '）';
  }

  static String _snippetAt(String source, int offset) {
    final from = (offset - 12).clamp(0, source.length);
    final to = (offset + 12).clamp(0, source.length);
    final snippet = source.substring(from, to).replaceAll('\n', ' ');
    return '…' + snippet + '…';
  }

  // ---------------------------------------------------------------- 结构归一

  /// 把顶层结构收敛成「卡片对象的列表」。
  static List<Object?>? _itemsOf(Object? decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final map = _asStringMap(decoded);
      final nested = _pickRawList(map, _aliasCards);
      if (nested != null && nested.isNotEmpty) return nested;
      return <Object?>[decoded];
    }
    return null;
  }

  /// 取原始列表（不做字符串化），用于嵌套的卡片数组。
  static List<Object?>? _pickRawList(
    Map<String, Object?> map,
    List<String> aliases,
  ) {
    final value = _pick(map, aliases);
    if (value is List) return List<Object?>.from(value);
    return null;
  }

  static ParsedCard? _mapItem(
    Object? item,
    int position,
    List<ParseIssue> issues,
    List<String> warnings,
  ) {
    if (item is! Map) {
      issues.add(
        ParseIssue(
          ParseIssueKind.notAnObject,
          '这一项不是对象 { ... }，已跳过。',
          index: position,
          snippet: item?.toString(),
        ),
      );
      return null;
    }

    final map = _asStringMap(item);

    final word = _pickString(map, _aliasWord);
    var definition = _pickString(map, _aliasDefinition);
    var distractors = _pickList(map, _aliasDistractors);
    final options = _pickList(map, _aliasOptions);
    final answerIndex = _pickInt(map, _aliasAnswerIndex);

    if (options.isNotEmpty) {
      if (definition == null &&
          answerIndex != null &&
          answerIndex >= 0 &&
          answerIndex < options.length) {
        definition = options[answerIndex];
      }
      if (distractors.isEmpty && definition != null) {
        // 有些模型只给 options，把正确答案混在里面
        final correct = definition.trim();
        distractors = options
            .where((option) => option.trim() != correct)
            .toList(growable: false);
      }
    }

    if (word == null || word.isEmpty) {
      issues.add(
        ParseIssue(
          ParseIssueKind.missingField,
          '缺少 word（单词）字段。',
          index: position,
          field: 'word',
          snippet: _snippetOfMap(map),
        ),
      );
      return null;
    }

    if (definition == null || definition.isEmpty) {
      issues.add(
        ParseIssue(
          ParseIssueKind.missingField,
          '缺少 definition（正确释义）字段。',
          index: position,
          field: 'definition',
          snippet: _snippetOfMap(map),
        ),
      );
      return null;
    }

    final cleaned = _cleanDistractors(distractors, definition);
    if (cleaned.isEmpty) {
      issues.add(
        ParseIssue(
          ParseIssueKind.invalidField,
          '没有可用的干扰项：distractors 为空，或所有干扰项都与正确释义重复。',
          index: position,
          field: 'distractors',
          snippet: _snippetOfMap(map),
        ),
      );
      return null;
    }

    if (cleaned.length < 4) {
      warnings.add(
        '第 ' +
            position.toString() +
            ' 张卡片「' +
            word +
            '」只有 ' +
            cleaned.length.toString() +
            ' 个有效干扰项，测验时会自动从其他卡片借释义补齐 5 个选项。',
      );
    }

    return ParsedCard(
      word: word,
      definition: definition,
      distractors: cleaned,
      phonetic: _pickString(map, _aliasPhonetic),
      example: _pickString(map, _aliasExample),
      partOfSpeech: _pickString(map, _aliasPartOfSpeech),
      position: position,
    );
  }

  static List<String> _cleanDistractors(List<String> raw, String definition) {
    final seen = <String>{definition.trim().toLowerCase()};
    final result = <String>[];
    for (final item in raw) {
      final value = item.trim();
      if (value.isEmpty) continue;
      if (!seen.add(value.toLowerCase())) continue;
      result.add(value);
    }
    return result;
  }

  // ---------------------------------------------------------------- 取值工具

  static Map<String, Object?> _asStringMap(Map<Object?, Object?> map) {
    final result = <String, Object?>{};
    map.forEach((key, value) => result[key.toString()] = value);
    return result;
  }

  static String _normalizeKey(String key) {
    var value = key.toLowerCase();
    value = value.replaceAll(' ', '').replaceAll('\u3000', '');
    value = value.replaceAll('_', '').replaceAll('-', '');
    return value;
  }

  /// 按别名优先级取值。
  static Object? _pick(Map<String, Object?> map, List<String> aliases) {
    for (final alias in aliases) {
      final normalized = _normalizeKey(alias);
      for (final entry in map.entries) {
        if (_normalizeKey(entry.key) == normalized && entry.value != null) {
          return entry.value;
        }
      }
    }
    return null;
  }

  static String? _pickString(Map<String, Object?> map, List<String> aliases) {
    final value = _pick(map, aliases);
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is num || value is bool) return value.toString();
    return null;
  }

  static int? _pickInt(Map<String, Object?> map, List<String> aliases) {
    final value = _pick(map, aliases);
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static List<String> _pickList(Map<String, Object?> map, List<String> aliases) {
    final value = _pick(map, aliases);
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    if (value is String) {
      return value
          .split(RegExp(r'[\n;；]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static String _snippetOfMap(Map<String, Object?> map) {
    final text = jsonEncode(map);
    if (text.length <= 80) return text;
    return text.substring(0, 80) + '…';
  }
}
