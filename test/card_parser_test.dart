// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/data/import/card_parser.dart';

/// 用 \u0060 拼出 Markdown 围栏，避免在源码里直接写反引号。
const String kFence = '\u0060\u0060\u0060';

void main() {
  const parser = CardParser();

  group('基本解析', () {
    test('单个对象', () {
      final result = parser.parse(
        '{"word":"abandon","definition":"v. 放弃","distractors":["v. 遵守","v. 维持"]}',
      );
      expect(result.issues, isEmpty);
      expect(result.cards, hasLength(1));
      expect(result.cards.first.word, 'abandon');
      expect(result.cards.first.definition, 'v. 放弃');
      expect(result.cards.first.distractors, <String>['v. 遵守', 'v. 维持']);
    });

    test('数组', () {
      final result = parser.parse(
        '[{"word":"a","definition":"甲","distractors":["乙"]},'
        '{"word":"b","definition":"丙","distractors":["丁"]}]',
      );
      expect(result.cards, hasLength(2));
      expect(result.cards[1].word, 'b');
    });

    test('顶层是 { cards: [...] } 也能认', () {
      final result = parser.parse(
        '{"cards":[{"word":"a","definition":"甲","distractors":["乙"]}]}',
      );
      expect(result.cards, hasLength(1));
    });

    test('可选字段被抓到', () {
      final result = parser.parse(
        '{"word":"a","definition":"甲","distractors":["乙"],'
        '"phonetic":"/ə/","example":"An example.","partOfSpeech":"noun"}',
      );
      final card = result.cards.single;
      expect(card.phonetic, '/ə/');
      expect(card.example, 'An example.');
      expect(card.partOfSpeech, 'noun');
    });
  });

  group('容错', () {
    test('Markdown 代码块 + 前后闲聊', () {
      final result = parser.parse(
        '好的，结果如下：\n' +
            kFence +
            'json\n' +
            '[{"word":"a","definition":"甲","distractors":["乙"]}]\n' +
            kFence +
            '\n还需要别的吗？',
      );
      expect(result.cards, hasLength(1));
      expect(result.issues, isEmpty);
    });

    test('中文字段名', () {
      final result = parser.parse(
        '{"单词":"abandon","释义":"v. 放弃","干扰项":["v. 遵守"],"音标":"/ə/"}',
      );
      expect(result.cards.single.word, 'abandon');
      expect(result.cards.single.definition, 'v. 放弃');
      expect(result.cards.single.distractors, <String>['v. 遵守']);
    });

    test('尾随逗号会被修掉', () {
      final result = parser.parse(
        '{"word":"a","definition":"甲","distractors":["乙","丙",],}',
      );
      expect(result.cards, hasLength(1));
      expect(result.repaired, isTrue);
    });

    test('全角引号当字符串定界符', () {
      final result = parser.parse(
        '{\u201Cword\u201D:\u201Ca\u201D,\u201Cdefinition\u201D:\u201C甲\u201D,\u201Cdistractors\u201D:[\u201C乙\u201D]}',
      );
      expect(result.cards, hasLength(1));
      expect(result.cards.single.word, 'a');
    });

    test('字段顺序不同不影响', () {
      final result = parser.parse(
        '{"distractors":["乙"],"definition":"甲","word":"a"}',
      );
      expect(result.cards.single.word, 'a');
    });

    test('多余未知字段被忽略', () {
      final result = parser.parse(
        '{"word":"a","definition":"甲","distractors":["乙"],"foo":[1,2,3]}',
      );
      expect(result.cards, hasLength(1));
      expect(result.issues, isEmpty);
    });

    test('options + answerIndex 变体', () {
      final result = parser.parse(
        '{"word":"a","options":["甲","乙","丙"],"answerIndex":0}',
      );
      expect(result.cards.single.definition, '甲');
      expect(result.cards.single.distractors, <String>['乙', '丙']);
    });

    test('只有 options + definition 时把正确项从选项里剔除', () {
      final result = parser.parse(
        '{"word":"a","definition":"甲","options":["甲","乙","丙"]}',
      );
      expect(result.cards.single.distractors, <String>['乙', '丙']);
    });
  });

  group('错误提示要具体', () {
    test('第 2 张缺 definition', () {
      final result = parser.parse(
        '[{"word":"a","definition":"甲","distractors":["乙"]},{"word":"b","distractors":["丁"]}]',
      );
      expect(result.cards, hasLength(1));
      expect(result.issues, hasLength(1));
      final issue = result.issues.single;
      expect(issue.kind, ParseIssueKind.missingField);
      expect(issue.index, 2);
      expect(issue.field, 'definition');
      expect(issue.display, contains('第 2 张卡片'));
      expect(issue.display, contains('definition'));
    });

    test('部分坏数据不影响其余卡片导入', () {
      final result = parser.parse(
        '[{"word":"a","definition":"甲","distractors":["乙"]},'
        '{"definition":"没有单词","distractors":["丁"]},'
        '{"word":"c","definition":"戊","distractors":["己"]}]',
      );
      expect(result.cards.map((card) => card.word), <String>['a', 'c']);
      expect(result.issues.single.index, 2);
    });

    test('干扰项与正确释义重复会被清掉，清空后报错', () {
      final result = parser.parse(
        '{"word":"a","definition":"甲","distractors":["甲","甲"]}',
      );
      expect(result.cards, isEmpty);
      expect(result.issues.single.field, 'distractors');
      expect(result.issues.single.message, contains('干扰项'));
    });

    test('语法错误给出行列位置', () {
      final result = parser.parse('{"word":"a", "definition": }');
      expect(result.cards, isEmpty);
      final issue = result.issues.single;
      expect(issue.kind, ParseIssueKind.syntaxError);
      expect(issue.display, contains('JSON 语法错误'));
      expect(issue.display, contains('行'));
    });

    test('空输入', () {
      final result = parser.parse('   ');
      expect(result.issues.single.kind, ParseIssueKind.emptyInput);
    });

    test('顶层是字符串', () {
      final result = parser.parse('"hello"');
      expect(result.issues.single.kind, ParseIssueKind.notAnObject);
    });
  });

  group('质量提醒', () {
    test('干扰项不足 4 个给 warning 但仍然可用', () {
      final result = parser.parse(
        '{"word":"a","definition":"甲","distractors":["乙","丙"]}',
      );
      expect(result.cards, hasLength(1));
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('干扰项'));
    });

    test('干扰项够 4 个不产生 warning', () {
      final result = parser.parse(
        '{"word":"a","definition":"甲","distractors":["乙","丙","丁","戊"]}',
      );
      expect(result.warnings, isEmpty);
    });
  });
}
