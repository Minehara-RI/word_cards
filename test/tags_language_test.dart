// 标签与语言：内存模型、Anki 落库、批量导入三条路都要对得上。
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:word_flashcards/src/data/import/import_service.dart';
import 'package:word_flashcards/src/domain/models/card_language.dart';
import 'package:word_flashcards/src/domain/models/card_source.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';

import 'support/test_harness.dart';

const String kTwoWords = '''[
  {"word": "abandon", "definition": "v. 放弃；抛弃", "distractors": ["v. 遵守；坚持"]},
  {"单词": "meticulous", "释义": "adj. 一丝不苟的", "干扰项": ["adj. 漫不经心的"]}
]''';

void main() {
  group('标签解析', () {
    test('中英文逗号、分号、顿号都能分，重复的只留一个', () {
      expect(
        WordCard.parseTags('考研，第四单元, 考研; 高频、'),
        <String>['考研', '第四单元', '高频'],
      );
    });

    test('标签里的空格换成下划线（Anki 的标签不能带空格）', () {
      expect(WordCard.parseTags(' 四级 核心 '), <String>['四级_核心']);
      expect(WordCard.sanitizeTag('a b\tc'), 'a_b_c');
    });

    test('语言标签不会被当成用户标签', () {
      expect(WordCard.parseTags('lang::ja，N2'), <String>['N2']);
    });
  });

  group('语言', () {
    test('五种语言的 id / 标签 / 例句语言都在', () {
      expect(CardLanguage.values.length, 5);
      expect(CardLanguage.english.tag, 'lang::en');
      expect(CardLanguage.japanese.tag, 'lang::ja');
      expect(CardLanguage.fromId('ko'), CardLanguage.korean);
      expect(CardLanguage.fromId('unknown'), CardLanguage.english);
      expect(CardLanguage.korean.exampleLanguage, '韩文');
      expect(CardLanguage.japanese.phoneticHint, contains('平假名'));
      expect(CardLanguage.russian.phoneticHint, contains('国际音标'));
    });

    test('从标签串里读得出语言', () {
      expect(
        CardLanguage.fromTags(<String>['手动导入', 'lang::ru', '四级']),
        CardLanguage.russian,
      );
      expect(CardLanguage.fromTags(<String>['手动导入']), isNull);
      expect(CardLanguage.isLanguageTag('LANG::FR'), isTrue);
    });
  });

  group('落库', () {
    test('语言与标签写进 Anki 的 tags，读回来一模一样', () async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);
      await harness.cards.upsert(
        makeCard(id: 'c1', word: 'すいえい').copyWith(
          language: CardLanguage.japanese,
          tags: <String>['N2', '第1课'],
        ),
      );

      final WordCard back = (await harness.cards.getAll()).single;
      expect(back.language, CardLanguage.japanese);
      expect(back.tags, <String>['N2', '第1课']);
      expect(back.source, CardSource.manualImport);

      final ResultSet rows = harness.collection!.db.select(
        'select tags from notes',
      );
      final String raw = rows.first['tags'] as String;
      expect(raw, contains('lang::ja'));
      expect(raw, contains('N2'));
      expect(raw, contains('手动导入'));
      expect(raw.startsWith(' '), isTrue, reason: 'Anki 的标签串前后带空格');
    });

    test('只改内容不会把语言和标签弄丢', () async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);
      await harness.cards.upsert(
        makeCard(id: 'c1', word: 'abandon').copyWith(
          language: CardLanguage.french,
          tags: <String>['四级'],
        ),
      );
      final WordCard first = (await harness.cards.getAll()).single;
      await harness.cards.upsert(first.copyWith(definition: 'v. 放弃'));
      final WordCard second = (await harness.cards.getAll()).single;
      expect(second.language, CardLanguage.french);
      expect(second.tags, <String>['四级']);
      expect(second.definition, 'v. 放弃');
    });
  });

  group('批量导入', () {
    test('整批标签与语言会打到这一批词上', () async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);
      final ImportService service = ImportService(
        cards: harness.cards,
        decks: harness.decks,
      );

      final ImportReport report = await service.importJson(
        kTwoWords,
        deckId: 'default',
        tags: <String>['考研', '第四单元'],
        language: CardLanguage.russian,
      );
      expect(report.importedCount, 2);

      final List<WordCard> cards = await harness.cards.getAll();
      expect(cards, hasLength(2));
      for (final WordCard card in cards) {
        expect(card.language, CardLanguage.russian);
        expect(card.tags, <String>['考研', '第四单元']);
        expect(card.deckId, 'default');
      }
    });

    test('再次导入同一批词：旧标签保留，新标签并进去', () async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);
      final ImportService service = ImportService(
        cards: harness.cards,
        decks: harness.decks,
      );

      await service.importJson(kTwoWords,
          deckId: 'default', tags: <String>['第一遍']);
      await service.importJson(kTwoWords,
          deckId: 'default',
          overwriteExisting: true,
          tags: <String>['第二遍']);

      final List<WordCard> cards = await harness.cards.getAll();
      expect(cards, hasLength(2));
      expect(cards.first.tags, <String>['第一遍', '第二遍']);
    });

    test('导到别的卡组：老卡组一张不动，新卡组拿到这批词', () async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);
      final ImportService service = ImportService(
        cards: harness.cards,
        decks: harness.decks,
      );

      await service.importJson(kTwoWords, deckId: 'default');
      final ImportReport second = await service.importJson(
        kTwoWords,
        deckId: 'deck-new',
      );
      expect(second.deckId, 'deck-new');
      expect(await harness.cards.count(deckId: 'default'), 2);
      expect(await harness.cards.count(deckId: 'deck-new'), 2);
    });
  });
}