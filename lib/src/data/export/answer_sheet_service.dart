// 这里用 + 拼字符串是刻意的（拼答案文案），关掉这条纯风格 lint。
// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/app_settings.dart';
import '../../domain/models/quiz_direction.dart';
import '../../logic/quiz.dart';

/// 一次答案文件的写入结果。
class AnswerSheet {
  const AnswerSheet({required this.path, required this.questions});

  final String path;
  final int questions;
}

/// 演示结束之后，把这一轮出过的题和正确答案写成一个 txt。
///
/// 文件名带上时间与卡组名，方便一位老师连着上几个班之后区分：
/// 演示答案_20261015_221530_考研词汇.txt
class AnswerSheetService {
  /// 没有自定义目录时用的默认目录名（放在系统文档目录下）。
  static const String defaultFolderName = 'word_cards_answers';

  Future<Directory> resolveDirectory(String? customDirectory) async {
    final String? custom = customDirectory?.trim();
    if (custom != null && custom.isNotEmpty) {
      final Directory directory = Directory(custom);
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
      return directory;
    }
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory directory = Directory(p.join(base.path, defaultFolderName));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<AnswerSheet> write({
    required List<QuizQuestion> questions,
    required String deckName,
    required int intervalSeconds,
    required OptionLabelStyle labelStyle,
    required AnswerSheetMode mode,
    String? customDirectory,
    DateTime? now,
  }) async {
    final Directory directory = await resolveDirectory(customDirectory);
    final DateTime stamp = now ?? DateTime.now();
    final String name = '演示答案_' +
        _stamp(stamp) +
        '_' +
        _safeFileName(deckName) +
        '.txt';
    final File file = File(p.join(directory.path, name));
    await file.writeAsString(
      '\uFEFF' + _render(
        questions: questions,
        deckName: deckName,
        intervalSeconds: intervalSeconds,
        labelStyle: labelStyle,
        mode: mode,
        now: stamp,
      ),
      flush: true,
    );
    return AnswerSheet(path: file.path, questions: questions.length);
  }

  static String _render({
    required List<QuizQuestion> questions,
    required String deckName,
    required int intervalSeconds,
    required OptionLabelStyle labelStyle,
    required AnswerSheetMode mode,
    required DateTime now,
  }) {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('单词卡片 · 演示模式答案');
    buffer.writeln('时间：' + _readable(now));
    buffer.writeln('卡组：' + deckName);
    buffer.writeln('题数：' + questions.length.toString());
    buffer.writeln('每题停留：' + intervalSeconds.toString() + ' 秒');
    buffer.writeln('选项编号：' + labelStyle.label);
    buffer.writeln('输出模式：' + mode.label);
    buffer.writeln('出题方向：' + _directionLabel(questions));
    buffer.writeln();
    for (int i = 0; i < questions.length; i++) {
      final QuizQuestion question = questions[i];
      final String answer = labelStyle.labelFor(question.correctIndex) +
          '. ' +
          question.correctOption;
      final String number = (i + 1).toString() + '. ';
      if (mode == AnswerSheetMode.optionOnly) {
        // 只含选项：一行一题，不写题面
        buffer.writeln(number + answer);
        continue;
      }
      // 题面写的正是屏幕上显示的那一行：正方向是单词，反方向是中文释义。
      buffer.writeln(number + question.promptText);
      // 反方向不带音标：演示时它本来就不显示（那是答案的读音）。
      if (question.showsPhonetic) {
        final String? phonetic = question.card.phonetic;
        if (phonetic != null && phonetic.isNotEmpty) {
          buffer.writeln('   音标：' + phonetic);
        }
      }
      buffer.writeln('   正确答案：' + answer);
    }
    return buffer.toString();
  }

  /// 这份答案用的是什么出题方向：全正、全反，还是两种都有。
  static String _directionLabel(List<QuizQuestion> questions) {
    final bool anyReverse =
        questions.any((QuizQuestion question) => question.direction.isReverse);
    final bool anyForward =
        questions.any((QuizQuestion question) => !question.direction.isReverse);
    final QuizDirection round = anyReverse && anyForward
        ? QuizDirection.mixed
        : (anyReverse
            ? QuizDirection.meaningToWord
            : QuizDirection.wordToMeaning);
    return round.shortLabel + '（' + round.description + '）';
  }

  static String _stamp(DateTime time) {
    String two(int value) =>
        value < 10 ? '0' + value.toString() : value.toString();
    return time.year.toString() +
        two(time.month) +
        two(time.day) +
        '_' +
        two(time.hour) +
        two(time.minute) +
        two(time.second);
  }

  static String _readable(DateTime time) {
    String two(int value) =>
        value < 10 ? '0' + value.toString() : value.toString();
    return time.year.toString() +
        '-' +
        two(time.month) +
        '-' +
        two(time.day) +
        ' ' +
        two(time.hour) +
        ':' +
        two(time.minute) +
        ':' +
        two(time.second);
  }

  /// 文件名里不能出现的字符换成下划线。
  static String _safeFileName(String name) {
    final String cleaned =
        name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? '未命名卡组' : cleaned;
  }
}
