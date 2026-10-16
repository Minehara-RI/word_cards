// 这些文件里的字符串用 + 拼是刻意的（拼 SQL、拼路径），关掉这条纯风格 lint。
// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../anki/anki_collection.dart';
import '../../domain/models/answer_record.dart';
import '../../domain/models/word_card.dart';

/// 一次导出的结果。
class ExportResult {
  const ExportResult({
    required this.path,
    required this.bytes,
    required this.items,
    this.note,
  });

  final String path;
  final int bytes;
  final int items;
  final String? note;
}

/// 把数据导出成文件。
///
/// 导出的卡片 JSON 用的是导入器认得的那套字段，所以「导出 -> 再导入」是闭环的。
/// 另外还能直接导出一份 Anki 数据库文件，用 Anki 就能打开。
class ExportService {
  ExportService({this.collection});

  /// 当前打开的 Anki 集合，用来导出一份 Anki 能直接打开的库。
  final AnkiCollection? collection;

  /// 导出目录放在系统文档目录下，方便用户自己找到。
  Future<Directory> exportDirectory() async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(p.join(base.path, 'word_cards_exports'));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<ExportResult> exportCardsJson(List<WordCard> cards) async {
    final Directory directory = await exportDirectory();
    final Map<String, Object?> payload = <String, Object?>{
      'app': 'word_cards',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'count': cards.length,
      'cards': cards
          .map((WordCard card) => <String, Object?>{
                'word': card.word,
                'definition': card.definition,
                'phonetic': card.phonetic,
                'example': card.example,
                'part_of_speech': card.partOfSpeech,
                'note': card.note,
                'distractors': card.distractors,
                'deck': card.deckId,
                'source': card.source.id,
                'review_count': card.reviewCount,
                'correct_count': card.correctCount,
                'mastery': card.mastery,
              })
          .toList(growable: false),
    };
    final File file = File(
      p.join(directory.path, 'cards_' + _stamp(DateTime.now()) + '.json'),
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    return ExportResult(
      path: file.path,
      bytes: file.lengthSync(),
      items: cards.length,
    );
  }

  Future<ExportResult> exportRecordsCsv(
    List<AnswerRecord> records, {
    required List<WordCard> cards,
  }) async {
    final Directory directory = await exportDirectory();
    final Map<String, String> words = <String, String>{
      for (final WordCard card in cards) card.id: card.word,
    };

    final StringBuffer buffer = StringBuffer();
    buffer.writeln('时间,单词,选择,正确答案,是否正确,是否超时,反应毫秒,模式');
    for (final AnswerRecord record in records) {
      buffer.writeln(<String>[
        _csv(record.answeredAt.toIso8601String()),
        _csv(words[record.cardId] ?? record.cardId),
        _csv(record.selected.isEmpty ? '（未作答）' : record.selected),
        _csv(record.expected),
        record.correct ? '对' : '错',
        record.timedOut ? '是' : '否',
        record.reactionMs.toString(),
        _csv(record.mode.label),
      ].join(','));
    }

    final File file = File(
      p.join(directory.path, 'records_' + _stamp(DateTime.now()) + '.csv'),
    );
    // 带 BOM，Excel 打开中文才不会乱码。
    await file.writeAsString('\\uFEFF' + buffer.toString(), flush: true);
    return ExportResult(
      path: file.path,
      bytes: file.lengthSync(),
      items: records.length,
    );
  }

  /// 导出一份可以拿 Anki 直接打开的数据库文件。
  ///
  /// 用 VACUUM INTO 而不是复制文件：WAL 模式下最近的写入可能还在 -wal 里，
  /// 直接复制会丢数据，VACUUM 出来的是一份完整干净的库。
  Future<ExportResult> exportAnkiCollection() async {
    final AnkiCollection? collection = this.collection;
    if (collection == null) {
      throw StateError('当前没有可导出的数据库');
    }
    final Directory directory = await exportDirectory();
    final File file = File(
      p.join(directory.path, 'collection_' + _stamp(DateTime.now()) + '.anki2'),
    );
    if (file.existsSync()) file.deleteSync();
    final String escaped = file.path.replaceAll("'", "''");
    collection.db.execute("vacuum into '" + escaped + "'");
    return ExportResult(
      path: file.path,
      bytes: file.lengthSync(),
      items: (collection.db.select('select count(*) as c from notes').first['c']
                  as int?) ??
          0,
      note: '这个文件就是 Anki 的 collection.anki2，用 Anki 可以直接打开。',
    );
  }

  static String _stamp(DateTime now) {
    String two(int value) => value < 10 ? '0' + value.toString() : value.toString();
    return now.year.toString() +
        two(now.month) +
        two(now.day) +
        '_' +
        two(now.hour) +
        two(now.minute) +
        two(now.second);
  }

  static String _csv(String value) =>
      '"' + value.replaceAll('"', '""') + '"';
}
