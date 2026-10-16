// ignore_for_file: prefer_interpolation_to_compose_strings, prefer_initializing_formals

import 'dart:math';

import '../../core/ids.dart';
import '../../domain/models/card_language.dart';
import '../../domain/models/card_source.dart';
import '../../domain/models/deck.dart';
import '../../domain/models/word_card.dart';
import '../../domain/repositories.dart';
import 'card_parser.dart';

/// 一次导入的完整报告：成功入库的卡片 + 跳过的重复 + 具体错误。
class ImportReport {
  const ImportReport({
    required this.parse,
    required this.imported,
    required this.duplicates,
    required this.warnings,
    required this.deckId,
  });

  final ParseResult parse;

  /// 真正写进本地库的卡片。
  final List<WordCard> imported;

  /// 因为本地已有同名单词而跳过的单词。
  final List<String> duplicates;

  /// 解析阶段的问题（可能只影响其中几张卡片）。
  List<ParseIssue> get errors => parse.issues;

  /// 解析与导入过程中所有需要告诉用户的提醒。
  final List<String> warnings;

  final String deckId;

  int get importedCount => imported.length;
  int get failedCount => parse.issues.length;
  int get duplicateCount => duplicates.length;

  bool get hasAnything =>
      imported.isNotEmpty || duplicates.isNotEmpty || parse.issues.isNotEmpty;
}

/// 手动导入服务：粘贴 JSON -> 容错解析 -> 去重 -> 补齐干扰项 -> 入库。
///
/// 这是“模式 A：网页聊天导入”的完整独立能力，不依赖任何网络。
class ImportService {
  ImportService({
    required CardRepository cards,
    required DeckRepository decks,
    Clock clock = systemClock,
    Random? random,
  })  : _cards = cards,
        _decks = decks,
        _clock = clock,
        _random = random ?? Random();

  final CardRepository _cards;
  final DeckRepository _decks;
  final Clock _clock;
  final Random _random;

  /// 只做解析，不改动任何数据。用于粘贴框的实时校验预览。
  ParseResult preview(String raw) => const CardParser().parse(raw);

  /// 解析并入库。
  ///
  /// [overwriteExisting] 为 true 时，本地已有同名单词会被新内容覆盖，
  /// 否则跳过并计入 [ImportReport.duplicates]。
  Future<ImportReport> importJson(
    String raw, {
    String? deckId,
    bool overwriteExisting = false,
    /// 给这一整批单词打上的标签（和卡片自己的标签合并，去重）。
    List<String> tags = const <String>[],
    /// 这批单词是哪国语言的词。
    CardLanguage language = CardLanguage.english,
    /// 这批卡是粘贴来的还是 API 生成的（只影响 source 字段与统计）。
    CardSource cardSource = CardSource.manualImport,
  }) async {
    final parsed = preview(raw);
    final targetDeckId = deckId ?? (await _decks.ensureDefault()).id;

    if (parsed.cards.isEmpty) {
      return ImportReport(
        parse: parsed,
        imported: const <WordCard>[],
        duplicates: const <String>[],
        warnings: parsed.warnings,
        deckId: targetDeckId,
      );
    }

    final warnings = <String>[...parsed.warnings];
    final duplicates = <String>[];

    // 1) 批内去重：同一批里重复出现的单词只保留第一张。
    final unique = <String, ParsedCard>{};
    for (final card in parsed.cards) {
      final key = _key(card.word);
      if (unique.containsKey(key)) {
        warnings.add('「' + card.word + '」在本批里出现了多次，只导入第一次出现的那张。');
        continue;
      }
      unique[key] = card;
    }

    // 2) 与本地已有卡片比对。
    final existing = await _cards.findByWords(
      unique.keys.map((key) => key).toList(growable: false),
      deckId: targetDeckId,
    );
    final existingByKey = <String, WordCard>{
      for (final card in existing) _key(card.word): card,
    };

    final toInsert = <WordCard>[];
    final toUpdate = <WordCard>[];
    final now = _clock();

    // 3) 干扰项池：不够 4 个干扰项时，从本批其他卡片的释义里借。
    final pool = _buildDistractorPool(unique.values);

    for (final entry in unique.entries) {
      final source = entry.value;
      final previous = existingByKey[entry.key];

      if (previous != null && !overwriteExisting) {
        duplicates.add(source.word);
        continue;
      }

      final distractors = _fillDistractors(source, pool);

      if (previous != null) {
        toUpdate.add(
          previous.copyWith(
            word: source.word,
            definition: source.definition,
            distractors: distractors,
            phonetic: source.phonetic,
            example: source.example,
            partOfSpeech: source.partOfSpeech,
            language: language,
            // 已有卡片：把新标签并进去，不打乱原来打的标签。
            tags: <String>{...previous.displayTags, ...tags}.toList(growable: false),
            source: cardSource,
            updatedAt: now,
            clearPhonetic: source.phonetic == null,
            clearExample: source.example == null,
            clearPartOfSpeech: source.partOfSpeech == null,
          ),
        );
      } else {
        toInsert.add(
          WordCard(
            id: newId(),
            word: source.word,
            definition: source.definition,
            distractors: distractors,
            phonetic: source.phonetic,
            example: source.example,
            partOfSpeech: source.partOfSpeech,
            deckId: targetDeckId,
            language: language,
            tags: <String>{...tags}.toList(growable: false),
            source: cardSource,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    }

    if (toInsert.isNotEmpty) await _cards.upsertAll(toInsert);
    for (final card in toUpdate) {
      await _cards.upsert(card);
    }

    return ImportReport(
      parse: parsed,
      imported: <WordCard>[...toInsert, ...toUpdate],
      duplicates: duplicates,
      warnings: warnings,
      deckId: targetDeckId,
    );
  }

  /// 把一张卡片的干扰项补到 4 个。
  List<String> _fillDistractors(ParsedCard card, List<String> pool) {
    final target = WordCard.targetDistractorCount;
    final result = <String>[...card.distractors];
    if (result.length >= target) return result.sublist(0, target);

    final seen = <String>{
      card.definition.trim().toLowerCase(),
      ...result.map((item) => item.trim().toLowerCase()),
    };
    final candidates = <String>[];
    for (final item in pool) {
      final value = item.trim();
      if (value.isEmpty) continue;
      if (seen.add(value.toLowerCase())) candidates.add(value);
    }
    candidates.shuffle(_random);

    for (final candidate in candidates) {
      if (result.length >= target) break;
      result.add(candidate);
    }
    return result;
  }

  List<String> _buildDistractorPool(Iterable<ParsedCard> cards) {
    final pool = <String>[];
    for (final card in cards) {
      pool.add(card.definition);
      pool.addAll(card.distractors);
    }
    return pool;
  }

  static String _key(String word) => word.trim().toLowerCase();

  /// 只解析不写库时用的便捷入口。
  static ParseResult parseOnly(String raw) => const CardParser().parse(raw);
}

/// 从词库导入/导出时都用得上的默认词库 id。
const String kDefaultDeckId = Deck.defaultDeckId;
