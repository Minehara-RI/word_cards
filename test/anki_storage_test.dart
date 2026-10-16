import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:word_cards/src/data/anki/anki_schema.dart';
import 'package:word_cards/src/domain/models/answer_record.dart';
import 'package:word_cards/src/domain/models/app_settings.dart';
import 'package:word_cards/src/domain/models/deck.dart';
import 'package:word_cards/src/domain/models/word_card.dart';

import 'support/test_harness.dart';

void main() {
  late TestHarness harness;
  late Database db;

  setUp(() async {
    harness = await TestHarness.create();
    db = harness.collection!.db;
  });

  tearDown(() async {
    await harness.dispose();
  });

  group('Anki 库结构', () {
    test('建的是 Anki schema 11 的表', () {
      final Set<String> tables = db
          .select("select name from sqlite_master where type = 'table'")
          .map((Row row) => row['name'] as String)
          .toSet();
      expect(
        tables.containsAll(<String>['col', 'notes', 'cards', 'revlog', 'graves']),
        isTrue,
        reason: '缺 Anki 原生表：$tables',
      );

      final Set<String> indexes = db
          .select("select name from sqlite_master where type = 'index'")
          .map((Row row) => row['name'] as String)
          .toSet();
      expect(indexes.contains('ix_cards_sched'), isTrue);
      expect(indexes.contains('ix_revlog_cid'), isTrue);
    });

    test('col 行带完整的 conf / models / decks / dconf', () {
      final Row col = db.select('select * from col where id = 1').first;
      expect(col['ver'], kAnkiSchemaVersion);
      expect(col['crt'], isA<int>());

      final Map<String, Object?> models =
          (jsonDecode(col['models']! as String) as Map).cast<String, Object?>();
      final Map<String, Object?> notetype =
          (models[kAnkiNotetypeId.toString()]! as Map).cast<String, Object?>();
      expect((notetype['flds']! as List<Object?>).length, kNoteFields.length);
      expect((notetype['tmpls']! as List<Object?>).length, 1);
      expect(notetype['sortf'], kFieldWord);

      final Map<String, Object?> decks =
          (jsonDecode(col['decks']! as String) as Map).cast<String, Object?>();
      expect(decks.containsKey('1'), isTrue);

      final Map<String, Object?> dconf =
          (jsonDecode(col['dconf']! as String) as Map).cast<String, Object?>();
      expect(dconf.containsKey('1'), isTrue);

      expect(jsonDecode(col['tags']! as String), isEmpty);
    });

    test('应用自己的表用 wc_ 前缀，Anki 会忽略', () {
      final Set<String> tables = db
          .select("select name from sqlite_master where type = 'table'")
          .map((Row row) => row['name'] as String)
          .toSet();
      expect(
        tables.where((String name) => name.startsWith('wc_')).toSet(),
        <String>{
          'wc_card_ids',
          'wc_deck_ids',
          'wc_card_stats',
          'wc_card_fsrs',
          'wc_answer_log',
          'wc_settings',
          'wc_api_cache',
        },
      );
    });
  });

  group('卡片落库', () {
    test('写进去的是 Anki 的 notes + cards，不是私有格式', () async {
      await harness.cards.upsert(makeCard(id: 'c1', word: 'abandon'));

      final Row note = db.select('select * from notes').first;
      final Row card = db.select('select * from cards').first;

      expect(note['id'], isA<int>(), reason: 'Anki 的主键必须是整数');
      expect(note['mid'], kAnkiNotetypeId);
      expect(note['guid'], isA<String>());
      expect((note['guid']! as String).length, 10);
      expect((note['tags']! as String).contains('手动导入'), isTrue);
      expect(card['nid'], note['id']);
      expect(card['did'], 1);
      expect(card['ord'], 0);
      expect(card['type'], 0);
      expect(card['queue'], 0);

      final List<String> flds = (note['flds']! as String).split(kFieldSeparator);
      expect(flds.length, kNoteFields.length);
      expect(flds[kFieldWord], 'abandon');
      expect(flds[kFieldDefinition], 'v. 放弃；抛弃');
      expect(flds[kFieldPhonetic], '/əˈbændən/');

      // csum 必须是 sfld 的 sha1 前 8 位十六进制
      final int expected = int.parse(
        sha1.convert(utf8.encode('abandon')).toString().substring(0, 8),
        radix: 16,
      );
      expect(note['csum'], expected);
      expect(note['sfld'], 'abandon');
    });

    test('读回来字段一个不少', () async {
      final WordCard original = makeCard(
        id: 'c2',
        word: 'meticulous',
        definition: 'adj. 一丝不苟的',
        distractors: <String>['adj. 漫不经心的', 'adj. 慷慨的', 'adj. 沉默的', 'adj. 固执的'],
        phonetic: '/məˈtɪkjələs/',
        example: 'She is meticulous about details.',
        partOfSpeech: 'adj.',
        reviewCount: 12,
        correctCount: 9,
        mastery: 0.75,
      ).copyWith(note: '写作常用');

      await harness.cards.upsert(original);
      final WordCard loaded = (await harness.cards.getById('c2'))!;

      expect(loaded.word, original.word);
      expect(loaded.definition, original.definition);
      expect(loaded.distractors, original.distractors);
      expect(loaded.phonetic, original.phonetic);
      expect(loaded.example, original.example);
      expect(loaded.partOfSpeech, original.partOfSpeech);
      expect(loaded.note, original.note);
      expect(loaded.deckId, original.deckId);
      expect(loaded.reviewCount, 12);
      expect(loaded.correctCount, 9);
      expect(loaded.mastery, closeTo(0.75, 0.0001));
    });

    test('复习状态会同步到 Anki 的 cards 列', () async {
      await harness.cards.upsert(
        makeCard(id: 'c3', word: 'resilient').copyWith(
          reviewCount: 4,
          wrongCount: 2,
          intervalDays: 6,
          easeFactor: 2.3,
        ),
      );
      final Row card = db.select('select * from cards').first;
      expect(card['reps'], 4);
      expect(card['lapses'], 2);
      expect(card['ivl'], 6);
      expect(card['factor'], 2300);
      expect(card['type'], 2);
      expect(card['queue'], 2);
    });

    test('按单词查重与批量查重', () async {
      await harness.cards.upsert(makeCard(id: 'c1', word: 'Abandon '));
      await harness.cards.upsert(makeCard(id: 'c2', word: 'meticulous'));

      expect((await harness.cards.findByWord('abandon'))!.id, 'c1');
      expect((await harness.cards.findByWord('ABANDON'))!.id, 'c1');
      expect(await harness.cards.findByWord('nope'), isNull);

      final List<WordCard> hits =
          await harness.cards.findByWords(<String>['meticulous', 'abandon', 'x']);
      expect(hits.map((WordCard c) => c.id).toList()..sort(), <String>['c1', 'c2']);
    });

    test('删除会写 graves 并清掉关联行', () async {
      await harness.cards.upsert(makeCard(id: 'c1'));
      await harness.cards.deleteById('c1');

      expect(db.select('select * from notes'), isEmpty);
      expect(db.select('select * from cards'), isEmpty);
      expect(db.select('select * from wc_card_ids'), isEmpty);
      expect(db.select('select * from graves').length, 2);
    });

    test('排序按单词、忽略大小写', () async {
      await harness.cards.upsertAll(<WordCard>[
        makeCard(id: 'b', word: 'banana'),
        makeCard(id: 'a', word: 'Apple'),
        makeCard(id: 'c', word: 'cherry'),
      ]);
      final List<WordCard> cards = await harness.cards.getAll();
      expect(cards.map((WordCard c) => c.word).toList(),
          <String>['Apple', 'banana', 'cherry']);
    });
  });

  group('答题记录', () {
    test('同时写 wc_answer_log 和 Anki 的 revlog', () async {
      await harness.cards.upsert(makeCard(id: 'c1', word: 'abandon'));
      await harness.records.add(AnswerRecord(
        id: 'r1',
        cardId: 'c1',
        selected: 'v. 放弃；抛弃',
        expected: 'v. 放弃；抛弃',
        correct: true,
        reactionMs: 1234,
        answeredAt: DateTime(2026, 3, 1, 10),
        sessionId: 's1',
        deckId: Deck.defaultDeckId,
      ));

      final Row log = db.select('select * from wc_answer_log').first;
      expect(log['selected'], 'v. 放弃；抛弃');
      expect(log['correct'], 1);

      final Row rev = db.select('select * from revlog').first;
      expect(rev['ease'], 3);
      expect(rev['time'], 1234);
      expect(rev['cid'], db.select('select id from cards').first['id']);
      expect(log['revlog_id'], rev['id']);
    });

    test('答错记 ease = 1', () async {
      await harness.cards.upsert(makeCard(id: 'c1'));
      await harness.records.add(AnswerRecord(
        id: 'r2',
        cardId: 'c1',
        selected: 'v. 遵守；坚持',
        expected: 'v. 放弃；抛弃',
        correct: false,
        reactionMs: 800,
        answeredAt: DateTime(2026, 3, 1, 11),
        timedOut: true,
      ));
      expect(db.select('select ease from revlog').first['ease'], 1);
      expect(db.select('select timed_out from wc_answer_log').first['timed_out'], 1);
    });

    test('投影模式不写入 Anki 的复习历史', () async {
      await harness.cards.upsert(makeCard(id: 'c1'));
      await harness.records.add(AnswerRecord(
        id: 'r3',
        cardId: 'c1',
        selected: '',
        expected: 'v. 放弃；抛弃',
        correct: false,
        reactionMs: 5000,
        answeredAt: DateTime(2026, 3, 1, 12),
        mode: QuizMode.projection,
        timedOut: true,
      ));
      expect(db.select('select * from revlog'), isEmpty);
      expect(db.select('select mode from wc_answer_log').first['mode'], 'projection');
    });

    test('最近记录按时间倒序', () async {
      await harness.cards.upsert(makeCard(id: 'c1'));
      for (int i = 0; i < 3; i++) {
        await harness.records.add(AnswerRecord(
          id: 'r$i',
          cardId: 'c1',
          selected: 'x',
          expected: 'x',
          correct: true,
          reactionMs: 100,
          answeredAt: DateTime(2026, 3, 1 + i),
        ));
      }
      final List<AnswerRecord> recent = await harness.records.getRecent();
      expect(recent.first.answeredAt.day, 3);
      expect(recent.length, 3);
    });
  });

  group('牌组与配置', () {
    test('默认牌组就是 Anki 的 Deck 1', () async {
      final Deck deck = await harness.decks.ensureDefault();
      expect(deck.id, Deck.defaultDeckId);
      expect(deck.name, Deck.defaultDeckName);
      final Map<String, Object?> decks = (jsonDecode(
        db.select('select decks from col').first['decks']! as String,
      ) as Map)
          .cast<String, Object?>();
      final Map<String, Object?> one =
          (decks['1']! as Map).cast<String, Object?>();
      expect(one['name'], Deck.defaultDeckName);
      expect(one['conf'], 1);
    });

    test('新建牌组会写进 col.decks，删除时卡片回到默认牌组', () async {
      await harness.decks.upsert(
        Deck(id: 'deck-2', name: '考研词汇', createdAt: DateTime(2026, 2, 1)),
      );
      await harness.cards.upsert(makeCard(id: 'c1', deckId: 'deck-2'));

      final List<Deck> decks = await harness.decks.getAll();
      expect(decks.map((Deck d) => d.name).contains('考研词汇'), isTrue);
      expect((await harness.cards.getAll(deckId: 'deck-2')).length, 1);

      await harness.decks.delete('deck-2');
      expect((await harness.cards.getAll(deckId: 'deck-2')).length, 0);
      expect((await harness.cards.getAll(deckId: Deck.defaultDeckId)).length, 1);
      expect((await harness.decks.getAll()).length, 1);
    });

    test('配置存在 wc_settings，不污染 Anki 的 col.conf', () async {
      await harness.settings.save(const AppSettings(
        questionTimeLimitSeconds: 17,
        answerRevealMode: AnswerRevealMode.never,
        apiKey: 'sk-wc-secret',
      ));
      final AppSettings loaded = await harness.settings.load();
      expect(loaded.questionTimeLimitSeconds, 17);
      expect(loaded.answerRevealMode, AnswerRevealMode.never);
      expect(loaded.apiKey, 'sk-wc-secret');

      final String conf = db.select('select conf from col').first['conf']! as String;
      expect(conf.contains('sk-wc-secret'), isFalse);
    });
  });

  group('外部来的数据', () {
    test('Anki 侧新增的 note 会被自动认领并读出来', () async {
      final int id = DateTime.now().millisecondsSinceEpoch;
      db.execute(
        'insert into notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, '
        'flags, data) values (?,?,?,?,?,?,?,?,?,?,?)',
        <Object?>[
          id, 'abcdefghij', kAnkiNotetypeId, 0, -1, '',
          <String>['hello', 'int. 你好', '', '', '', '', ''].join(kFieldSeparator),
          'hello', 0, 0, '{}',
        ],
      );
      db.execute(
        'insert into cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, '
        'factor, reps, lapses, left, odue, odid, flags, data) '
        'values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        <Object?>[id, id, 1, 0, 0, -1, 0, 0, 0, 0, 2500, 0, 0, 0, 0, 0, 0, '{}'],
      );

      final List<WordCard> cards = await harness.cards.getAll();
      expect(cards.length, 1);
      expect(cards.first.word, 'hello');
      expect(cards.first.definition, 'int. 你好');
      expect(cards.first.id.isNotEmpty, isTrue);
      expect(db.select('select * from wc_card_ids').length, 1);
    });
  });
}
