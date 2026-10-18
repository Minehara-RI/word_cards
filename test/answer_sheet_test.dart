import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:word_flashcards/src/data/export/answer_sheet_service.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/quiz_direction.dart';
import 'package:word_flashcards/src/logic/quiz.dart';

import 'support/test_harness.dart';

/// 演示答案 txt：文件名带时间和卡组名，两种输出模式。
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wc_answers');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<QuizQuestion> twoQuestions() => <QuizQuestion>[
        QuizQuestion(
          card: makeCard(id: 'c1', word: 'abandon'),
          options: <String>[
            'v. 遵守；坚持',
            'v. 放弃；抛弃',
            'v. 增加；扩大',
            'v. 维持；供养',
            'v. 分配；指派',
          ],
          correctIndex: 1,
        ),
        QuizQuestion(
          card: makeCard(id: 'c2', word: 'meticulous', definition: 'adj. 一丝不苟的'),
          options: <String>['adj. 一丝不苟的', 'b', 'c', 'd', 'e'],
          correctIndex: 0,
        ),
      ];

  Future<AnswerSheet> write({
    required AnswerSheetMode mode,
    OptionLabelStyle labelStyle = OptionLabelStyle.letter,
    String deckName = '考研词汇',
  }) =>
      AnswerSheetService().write(
        questions: twoQuestions(),
        deckName: deckName,
        intervalSeconds: 5,
        labelStyle: labelStyle,
        mode: mode,
        customDirectory: dir.path,
        now: DateTime(2026, 10, 15, 22, 15, 30),
      );

  test('文件名 = 演示答案_时间_卡组名', () async {
    final AnswerSheet sheet = await write(mode: AnswerSheetMode.wordAndOption);
    expect(p.basename(sheet.path), '演示答案_20261015_221530_考研词汇.txt');
    expect(sheet.questions, 2);
    expect(File(sheet.path).existsSync(), isTrue);
  });

  test('单词 + 义项模式：写单词、音标和正确答案', () async {
    final AnswerSheet sheet = await write(mode: AnswerSheetMode.wordAndOption);
    final String text = await File(sheet.path).readAsString();
    expect(text, contains('卡组：考研词汇'));
    expect(text, contains('输出模式：单词 + 义项'));
    expect(text, contains('出题方向：词 → 义'));
    expect(text, contains('1. abandon'));
    expect(text, contains('音标：/əˈbændən/'));
    expect(text, contains('正确答案：B. v. 放弃；抛弃'));
    expect(text, contains('2. meticulous'));
    expect(text, contains('正确答案：A. adj. 一丝不苟的'));
  });

  test('只含选项模式：一行一题，不写单词', () async {
    final AnswerSheet sheet = await write(mode: AnswerSheetMode.optionOnly);
    final String text = await File(sheet.path).readAsString();
    expect(text, contains('输出模式：只含选项'));
    expect(text, contains('1. B. v. 放弃；抛弃'));
    expect(text, contains('2. A. adj. 一丝不苟的'));
    expect(text, isNot(contains('abandon')));
    expect(text, isNot(contains('音标')));
  });

  test('看中文选英文：题面写中文释义，答案写单词，不带音标', () async {
    final AnswerSheet sheet = await AnswerSheetService().write(
      questions: <QuizQuestion>[
        QuizQuestion(
          card: makeCard(id: 'c1', word: 'abandon'),
          options: <String>['abandon', 'meticulous', 'candid'],
          correctIndex: 0,
          direction: QuizDirection.meaningToWord,
        ),
      ],
      deckName: '考研词汇',
      intervalSeconds: 5,
      labelStyle: OptionLabelStyle.letter,
      mode: AnswerSheetMode.wordAndOption,
      customDirectory: dir.path,
      now: DateTime(2026, 10, 15, 22, 15, 30),
    );
    final String text = await File(sheet.path).readAsString();
    expect(text, contains('出题方向：义 → 词'));
    expect(text, contains('1. v. 放弃；抛弃'));
    expect(text, contains('正确答案：A. abandon'));
    // 音标是答案那个词的读音，反方向的答案文件里不该出现。
    expect(text, isNot(contains('音标')));
  });

  test('编号样式跟着走：12345 模式写数字', () async {
    final AnswerSheet sheet = await write(
      mode: AnswerSheetMode.optionOnly,
      labelStyle: OptionLabelStyle.number,
    );
    final String text = await File(sheet.path).readAsString();
    expect(text, contains('1. 2. v. 放弃；抛弃'));
  });

  test('卡组名里的非法字符会被换掉', () async {
    final AnswerSheet sheet =
        await write(mode: AnswerSheetMode.optionOnly, deckName: 'a/b:c*?');
    final String name = p.basename(sheet.path);
    expect(name, contains('a_b_c__'));
    expect(name.contains('/'), isFalse);
  });

  test('目录不存在会自己建出来', () async {
    final Directory nested = Directory(p.join(dir.path, 'sub', 'dir'));
    expect(nested.existsSync(), isFalse);
    final AnswerSheet sheet = await AnswerSheetService().write(
      questions: twoQuestions(),
      deckName: '默认词库',
      intervalSeconds: 8,
      labelStyle: OptionLabelStyle.number,
      mode: AnswerSheetMode.optionOnly,
      customDirectory: nested.path,
    );
    expect(File(sheet.path).existsSync(), isTrue);
  });
}
