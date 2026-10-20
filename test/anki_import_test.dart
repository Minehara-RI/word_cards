// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:word_flashcards/src/data/import/anki_import.dart';
import 'package:word_flashcards/src/domain/models/card_language.dart';
import 'package:word_flashcards/src/domain/models/card_source.dart';
import 'package:word_flashcards/src/domain/models/deck.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/ui/pages/anki_import_page.dart';

import 'support/test_harness.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('wf_anki_test_');
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {
      // 临时目录清不掉不影响断言。
    }
  });

  String writeAnki({
    required List<String> fields,
    required List<List<String>> notes,
    Map<String, String> decks = const <String, String>{'1': 'Default'},
    List<String> tags = const <String>[],
    int cardsDeck = 1,
    int reps = 0,
    int lapses = 0,
    int ivl = 0,
    int factor = 2500,
    int type = 0,
    int due = 0,
  }) {
    final String path = temp.path + Platform.pathSeparator + 'collection.anki2';
    final Database db = sqlite3.open(path);
    db.execute(
      'create table col (id integer primary key, crt integer, mod integer, '
      'scm integer, ver integer, dty integer, usn integer, ls integer, '
      'conf text, models text, decks text, dconf text, tags text)',
    );
    db.execute(
      'create table notes (id integer primary key, guid text, mid integer, '
      'mod integer, usn integer, tags text, flds text, sfld integer, '
      'csum integer, flags integer, data text)',
    );
    db.execute(
      'create table cards (id integer primary key, nid integer, did integer, '
      'ord integer, mod integer, usn integer, type integer, queue integer, '
      'due integer, ivl integer, factor integer, reps integer, lapses integer, '
      'left integer, odue integer, odid integer, flags integer, data text)',
    );

    db.execute('insert into col (id, crt, models, decks) values (1, ?, ?, ?)', <Object?>[
      1600000000,
      jsonEncode(<String, Object?>{
        '1': <String, Object?>{
          'id': 1,
          'name': '基础',
          'flds': <Object?>[
            for (int i = 0; i < fields.length; i++)
              <String, Object?>{'name': fields[i], 'ord': i},
          ],
        },
      }),
      jsonEncode(<String, Object?>{
        for (final MapEntry<String, String> entry in decks.entries)
          entry.key: <String, Object?>{
            'id': int.parse(entry.key),
            'name': entry.value,
          },
      }),
    ]);

    var noteId = 100;
    for (final List<String> row in notes) {
      db.execute(
        'insert into notes (id, mid, flds, tags, mod) values (?, 1, ?, ?, ?)',
        <Object?>[noteId, row.join('\u001f'), tags.join(' '), 1600000000],
      );
      db.execute(
        'insert into cards (id, nid, did, mod, type, queue, due, ivl, factor, '
        'reps, lapses) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          noteId,
          noteId,
          cardsDeck,
          1600000000,
          type,
          type,
          due,
          ivl,
          factor,
          reps,
          lapses,
        ],
      );
      noteId++;
    }
    db.close();
    return path;
  }


  /// schema 18（Anki 23.10 起）：字段在 notetypes / fields 表里，col 的 JSON 是空的。
  String writeAnki18() {
    final String path = temp.path + Platform.pathSeparator + 'modern.anki2';
    final Database db = sqlite3.open(path);
    db.createCollation(
      name: 'unicase',
      function: (String? a, String? b) =>
          (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase()),
    );
    db.execute(
      'create table col (id integer primary key, crt integer, models text, '
      'decks text)',
    );
    db.execute(
      'create table notes (id integer primary key, guid text, mid integer, '
      'mod integer, usn integer, tags text, flds text, sfld integer, '
      'csum integer, flags integer, data text)',
    );
    db.execute(
      'create table cards (id integer primary key, nid integer, did integer, '
      'ord integer, mod integer, usn integer, type integer, queue integer, '
      'due integer, ivl integer, factor integer, reps integer, lapses integer, '
      'left integer, odue integer, odid integer, flags integer, data text)',
    );
    db.execute(
      'create table notetypes (id integer primary key, name text not null, '
      'config blob not null)',
    );
    db.execute(
      'create table fields (ntid integer not null, ord integer not null, '
      'name text not null collate unicase, config blob not null, '
      'primary key (ntid, ord)) without rowid',
    );
    db.execute('create table decks (id integer primary key, name text not null)');

    db.execute("insert into col (id, crt, models, decks) values (1, 1600000000, '', '')");
    db.execute("insert into notetypes values (10, 'Kaishi', x'')");
    db.execute("insert into notetypes values (11, 'GW 选择题', x'')");
    const List<String> vocabFields = <String>[
      'Word', 'Word Reading', 'Word Meaning', 'Sentence', 'Notes',
    ];
    for (int i = 0; i < vocabFields.length; i++) {
      db.execute('insert into fields values (10, ?, ?, x\'\')', <Object?>[i, vocabFields[i]]);
    }
    const List<String> quizFields = <String>[
      'Label', 'Stem', 'OptA', 'OptB', 'OptC', 'OptD', 'Answer',
    ];
    for (int i = 0; i < quizFields.length; i++) {
      db.execute('insert into fields values (11, ?, ?, x\'\')', <Object?>[i, quizFields[i]]);
    }
    db.execute("insert into decks values (1, '系统默认')");
    db.execute("insert into decks values (2, 'Unit' || char(31) || 'Ch1')");
    db.execute("insert into decks values (3, 'Kaishi 1.5k')");

    db.execute(
      'insert into notes (id, mid, flds, tags, mod) values (100, 10, ?, ?, 1600000000)',
      <Object?>[
        <String>['私', 'わたし', '我（郑重）', '彼は学生です', '备注'].join('\u001f'),
        ' lang::ja ',
      ],
    );
    db.execute(
      'insert into notes (id, mid, flds, tags, mod) values (101, 11, ?, ?, 1600000000)',
      <Object?>[
        <String>['前缀', '题干', 'A', 'B', 'C', 'D', 'b'].join('\u001f'),
        '',
      ],
    );
    db.execute(
      'insert into cards (id, nid, did, mod, type, queue, due, ivl, factor, '
      'reps, lapses) values (100, 100, 2, 1600000000, 2, 2, 3, 10, 2500, 2, 0)',
    );
    db.execute(
      'insert into cards (id, nid, did, mod, type, queue, due, ivl, factor, '
      'reps, lapses) values (101, 101, 3, 1600000000, 0, 0, 0, 0, 2500, 0, 0)',
    );
    db.close();
    return path;
  }

  group('读取 .anki2', () {
    test('按字段名取单词与释义，HTML 和音频标记会被清掉', () {
      final String path = writeAnki(
        fields: <String>['单词', '释义', '音标', '例句'],
        notes: <List<String>>[
          <String>[
            '<div>abandon</div>',
            'v. 放弃<br>抛弃',
            '/əˈbændən/',
            'He <b>abandoned</b> it. [sound:abandon.mp3]',
          ],
        ],
        decks: <String, String>{'2': '考研::核心'},
        cardsDeck: 2,
        tags: <String>['lang::en', '考研'],
      );

      final AnkiCollectionPreview preview =
          const AnkiCollectionReader().readFile(path, fileName: '我的词库.anki2');

      expect(preview.totalNotes, 1);
      expect(preview.importableCount, 1);
      final AnkiNote note = preview.notes.single;
      expect(note.word, 'abandon');
      expect(note.definition, 'v. 放弃\n抛弃');
      expect(note.phonetic, '/əˈbændən/');
      expect(note.example, 'He abandoned it.');
      expect(note.deckName, '考研 / 核心');
      expect(note.tags, containsAll(<String>['lang::en', '考研']));
      expect(preview.deckNames, <String>['考研 / 核心']);
      expect(preview.mappings.single.wordField, '单词');
      expect(preview.mappings.single.definitionField, '释义');
    });

    test('Anki 的 Default 卡组换成文件名', () {
      final String path = writeAnki(
        fields: <String>['Front', 'Back'],
        notes: <List<String>>[
          <String>['meticulous', 'adj. 一丝不苟的'],
        ],
      );

      final AnkiCollectionPreview preview =
          const AnkiCollectionReader().readFile(path, fileName: '雅思核心.anki2');
      expect(preview.notes.single.deckName, '雅思核心');
    });

    test('字段名不认识时退回第 0 / 1 个字段', () {
      final String path = writeAnki(
        fields: <String>['甲', '乙', '丙'],
        notes: <List<String>>[
          <String>['resilient', 'adj. 有韧性的', '多余内容'],
        ],
      );

      final AnkiCollectionPreview preview =
          const AnkiCollectionReader().readFile(path);
      expect(preview.notes.single.word, 'resilient');
      expect(preview.notes.single.definition, 'adj. 有韧性的');
    });

    test('释义为空或只有一列的笔记会被跳过并给提醒', () {
      final String path = writeAnki(
        fields: <String>['单词', '释义'],
        notes: <List<String>>[
          <String>['abandon', ''],
          <String>['meticulous', 'adj. 一丝不苟的'],
        ],
      );

      final AnkiCollectionPreview preview =
          const AnkiCollectionReader().readFile(path);
      expect(preview.totalNotes, 2);
      expect(preview.importableCount, 1);
      expect(preview.skipped, 1);
      expect(preview.warnings, isNotEmpty);
    });

    test('复习状态会一起读出来', () {
      final String path = writeAnki(
        fields: <String>['单词', '释义'],
        notes: <List<String>>[
          <String>['abandon', 'v. 放弃'],
        ],
        reps: 5,
        lapses: 1,
        ivl: 30,
        type: 2,
        due: 10,
      );

      final AnkiNote note = const AnkiCollectionReader().readFile(path).notes.single;
      expect(note.reviewCount, 5);
      expect(note.lapses, 1);
      expect(note.correctCount, 4);
      expect(note.intervalDays, 30);
      expect(note.easeFactor, 2.5);
      expect(note.nextReviewAt, isNotNull);
    });

    test('schema 18：字段在 notetypes / fields 里，卡组用 \\x1f 分层', () {
      final String path = writeAnki18();
      final AnkiCollectionPreview preview =
          const AnkiCollectionReader().readFile(path, fileName: 'modern.anki2');

      expect(preview.totalNotes, 2);
      expect(preview.importableCount, 1);
      expect(preview.deckNames, <String>['Unit / Ch1']);

      final AnkiNote note = preview.notes.single;
      expect(note.word, '私');
      expect(note.definition, '我（郑重）');
      expect(note.phonetic, 'わたし');
      expect(note.example, '彼は学生です');
      expect(note.note, '备注');
      expect(note.deckName, 'Unit / Ch1');
      expect(note.reviewCount, 2);

      expect(preview.mappings.single.modelName, 'Kaishi');
      expect(preview.warnings.join(), contains('练习型'));
      expect(preview.warnings.join(), contains('GW 选择题'));
    });

    test('不是 SQLite 的文件给出明确错误', () {
      final String path = temp.path + Platform.pathSeparator + 'bad.anki2';
      File(path).writeAsStringSync('这不是数据库');
      expect(
        () => const AnkiCollectionReader().readFile(path),
        throwsA(isA<AnkiImportException>()),
      );
    });

    test('.apkg 压缩包会提示先解压', () {
      final String path = temp.path + Platform.pathSeparator + 'deck.apkg';
      File(path).writeAsBytesSync(<int>[0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]);
      expect(
        () => const AnkiCollectionReader().readFile(path),
        throwsA(
          isA<AnkiImportException>().having(
            (AnkiImportException error) => error.message,
            'message',
            contains('.apkg'),
          ),
        ),
      );
    });
  });

  group('写入本地库', () {
    AnkiCollectionPreview previewOf(List<AnkiNote> notes) => AnkiCollectionPreview(
          fileName: 'demo.anki2',
          notes: notes,
          deckNames: <String>[for (final AnkiNote note in notes) note.deckName],
          mappings: const <AnkiFieldMapping>[],
          totalNotes: notes.length,
          skipped: 0,
          warnings: const <String>[],
        );

    AnkiNote note(String word, String definition,
            {String deck = '考研', List<String> tags = const <String>[]}) =>
        AnkiNote(
          word: word,
          definition: definition,
          deckName: deck,
          tags: tags,
          reviewCount: 4,
          lapses: 1,
        );

    test('按 Anki 卡组建卡组，干扰项从同批释义里补，统计保留', () async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);
      final AnkiImportService service =
          AnkiImportService(cards: harness.cards, decks: harness.decks);

      final AnkiImportReport report = await service.import(
        previewOf(<AnkiNote>[
          note('abandon', 'v. 放弃'),
          note('meticulous', 'adj. 一丝不苟的'),
        ]),
        const AnkiImportOptions(),
      );

      expect(report.imported, 2);
      expect(report.createdDecks, <String>['考研']);

      final List<Deck> decks = await harness.decks.getAll();
      final Deck deck =
          decks.firstWhere((Deck item) => item.name == '考研');
      final List<WordCard> cards =
          await harness.cards.getAll(deckId: deck.id);
      expect(cards, hasLength(2));
      final WordCard abandon =
          cards.firstWhere((WordCard card) => card.word == 'abandon');
      expect(abandon.source, CardSource.anki);
      expect(abandon.reviewCount, 4);
      expect(abandon.wrongCount, 1);
      expect(abandon.mastery, closeTo(0.75, 1e-9));
      // 另一张卡的释义会补进来当干扰项。
      expect(abandon.distractors, contains('adj. 一丝不苟的'));
      expect(abandon.distractors.length, lessThanOrEqualTo(4));
    });

    test('再导一次会跳过同名单词，不会重复建卡组', () async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);
      final AnkiImportService service =
          AnkiImportService(cards: harness.cards, decks: harness.decks);
      final AnkiCollectionPreview preview = previewOf(<AnkiNote>[
        note('abandon', 'v. 放弃'),
      ]);

      await service.import(preview, const AnkiImportOptions());
      final AnkiImportReport second =
          await service.import(preview, const AnkiImportOptions());

      expect(second.imported, 0);
      expect(second.skippedDuplicates, 1);
      expect(second.duplicateWords, <String>['abandon']);
      final List<Deck> decks = await harness.decks.getAll();
      expect(
        decks.where((Deck deck) => deck.name == '考研').length,
        1,
      );
    });

    test('覆盖模式只换内容，不动本机学习进度', () async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);
      final AnkiImportService service =
          AnkiImportService(cards: harness.cards, decks: harness.decks);

      await service.import(
        previewOf(<AnkiNote>[note('abandon', 'v. 放弃')]),
        const AnkiImportOptions(),
      );
      final List<Deck> decks = await harness.decks.getAll();
      final Deck deck = decks.firstWhere((Deck item) => item.name == '考研');
      WordCard card =
          (await harness.cards.getAll(deckId: deck.id)).single;
      card = card.copyWith(reviewCount: 9, correctCount: 8, wrongCount: 1);
      await harness.cards.upsert(card);

      await service.import(
        previewOf(<AnkiNote>[note('abandon', 'v. 放弃；抛弃')]),
        const AnkiImportOptions(overwriteExisting: true),
      );

      final WordCard updated =
          (await harness.cards.getAll(deckId: deck.id)).single;
      expect(updated.definition, 'v. 放弃；抛弃');
      expect(updated.reviewCount, 9, reason: '覆盖不该把本机的复习次数冲掉');
    });

    test('全部放进当前卡组时不读 Anki 的卡组名', () async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);
      final AnkiImportService service =
          AnkiImportService(cards: harness.cards, decks: harness.decks);

      await service.import(
        previewOf(<AnkiNote>[
          note('abandon', 'v. 放弃', deck: '别的卡组'),
          note('meticulous', 'adj. 一丝不苟的', deck: '另一个'),
        ]),
        const AnkiImportOptions(
          deckMode: AnkiDeckMode.singleDeck,
          targetDeckId: Deck.defaultDeckId,
          targetDeckName: Deck.defaultDeckName,
        ),
      );

      final List<WordCard> cards = await harness.cards.getAll();
      expect(cards, hasLength(2));
      expect(cards.every((WordCard card) => card.deckId == Deck.defaultDeckId), isTrue);
      final List<Deck> decks = await harness.decks.getAll();
      expect(decks.any((Deck deck) => deck.name == '别的卡组'), isFalse);
    });

    test('lang::xx 标签会变成卡片语言，且不留在用户标签里', () async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);
      final AnkiImportService service =
          AnkiImportService(cards: harness.cards, decks: harness.decks);

      await service.import(
        previewOf(<AnkiNote>[
          note('水泳', '游泳', tags: <String>['lang::ja', 'N5']),
        ]),
        const AnkiImportOptions(),
      );

      final WordCard card = (await harness.cards.getAll()).single;
      expect(card.language, CardLanguage.japanese);
      expect(card.tags, <String>['N5']);
    });
  });

  testWidgets('导入页一开始只要求选文件', (tester) async {
    final TestHarness harness = TestHarness.fake();
    await tester.pumpWidget(
      harness.wrap(const MaterialApp(home: AnkiImportPage())),
    );
    await tester.pump();

    expect(find.text('选择 .anki2 文件'), findsOneWidget);
    expect(find.byKey(const Key('anki-import-button')), findsNothing);
  });
}
