import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/data/api/anki_connect_models.dart';
import 'package:word_flashcards/src/data/api/anki_connect_service.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/card_language.dart';
import 'package:word_flashcards/src/domain/models/card_source.dart';
import 'package:word_flashcards/src/domain/models/deck.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';

import 'support/test_harness.dart';

/// 外部写入（AnkiConnect 兼容）的动作层。
///
/// 这里测的是「协议上的行为」，不是 HTTP：服务器那一层另有 wire 测试。
/// 用真的内存 Anki 库，因为写入路径本来就是真实的仓储。
void main() {
  late TestHarness harness;
  late AnkiConnectService service;

  setUp(() async {
    harness = await TestHarness.create();
    service = AnkiConnectService(
      cards: harness.cards,
      decks: harness.decks,
      settings: harness.settings,
      collection: harness.collection!,
    );
  });

  tearDown(() async {
    await harness.dispose();
  });

  Future<int> addBasic(
    String word,
    String definition, {
    String? deck,
    String model = 'Basic',
    List<String> tags = const <String>[],
    bool allowDuplicate = false,
  }) async {
    final Object? result = await service.dispatch('addNote', <String, Object?>{
      'note': <String, Object?>{
        'deckName': deck ?? Deck.defaultDeckName,
        'modelName': model,
        'fields': <String, Object?>{'Front': word, 'Back': definition},
        'tags': tags,
        'options': <String, Object?>{'allowDuplicate': allowDuplicate},
      },
    });
    return result! as int;
  }

  test('version 返回 6；客户端据此判断能不能用', () async {
    expect(await service.dispatch('version', <String, Object?>{}), 6);
  });

  test('apiReflect 只报实现过的动作', () async {
    final Map<String, Object?> result = (await service.dispatch(
      'apiReflect',
      <String, Object?>{
        'scopes': <String>['actions'],
        'actions': <String>['addNote', 'guiBrowse', 'sync'],
      },
    ))! as Map<String, Object?>;
    expect(result['actions'], <String>['addNote']);
    expect(result['scopes'], <String>['actions']);
  });

  test('不认识的动作用 unsupported action 这个原文', () async {
    expect(
      () => service.dispatch('guiBrowse', <String, Object?>{}),
      throwsA(isA<AnkiConnectException>().having(
        (AnkiConnectException e) => e.message,
        'message',
        kUnsupportedAction,
      )),
    );
  });

  test('模型名：两种都认，认不出来报 model was not found', () async {
    expect(
      await service.dispatch(
        'modelNames',
        <String, Object?>{},
      ),
      <String>['单词卡', 'Basic'],
    );
    expect(
      await service.dispatch(
        'modelFieldNames',
        <String, Object?>{'modelName': 'Basic'},
      ),
      <String>['Front', 'Back'],
    );
    expect(
      await service.dispatch(
        'modelFieldNames',
        <String, Object?>{'modelName': '单词卡'},
      ),
      kNoteFieldsForTest,
    );
    expect(
      () => service.dispatch(
        'modelFieldNames',
        <String, Object?>{'modelName': 'Cloze'},
      ),
      throwsA(isA<AnkiConnectException>()),
    );
  });

  test('addNote 落库成一张能考的卡，并按 um 记下来源', () async {
    final int id = await addBasic('serendipity', 'n. 意外发现珍宝的运气');
    expect(id, greaterThan(0));

    final List<WordCard> cards = await harness.cards.getAll();
    expect(cards, hasLength(1));
    final WordCard card = cards.single;
    expect(card.word, 'serendipity');
    expect(card.definition, 'n. 意外发现珍宝的运气');
    expect(card.source, CardSource.external);
    expect(card.language, CardLanguage.english);
    // 卡组里只有它自己，借不到干扰项 → 挂待补全。
    expect(card.distractors, isEmpty);
    expect(card.tags, contains(WordCard.incompleteTag));
  });

  test('干扰项从同卡组已有释义里借，借够就不挂待补全', () async {
    await harness.cards.upsertAll(<WordCard>[
      makeCard(id: 'a', word: 'alpha', definition: 'n. 甲'),
      makeCard(id: 'b', word: 'beta', definition: 'n. 乙'),
      makeCard(id: 'c', word: 'gamma', definition: 'n. 丙'),
      makeCard(id: 'd', word: 'delta', definition: 'n. 丁'),
    ]);
    await addBasic('epsilon', 'n. 戊');
    final WordCard card =
        (await harness.cards.getAll()).firstWhere((WordCard item) => item.word == 'epsilon');
    expect(card.distractors, hasLength(4));
    expect(card.tags, isNot(contains(WordCard.incompleteTag)));
  });

  test('重复的词按 Anki 的原话拒绝', () async {
    await addBasic('rain', 'n. 雨');
    expect(
      () => addBasic('Rain', 'n. 雨水'),
      throwsA(isA<AnkiConnectException>().having(
        (AnkiConnectException e) => e.message,
        'message',
        'cannot create note because it is a duplicate',
      )),
    );
  });

  test('allowDuplicate 为真时照样写进去', () async {
    await addBasic('rain', 'n. 雨');
    await addBasic('rain', 'n. 雨水', allowDuplicate: true);
    expect(await harness.cards.count(), 2);
  });

  test('canAddNotes 与带详情的版本形状对齐', () async {
    final Object? plain = await service.dispatch('canAddNotes', <String, Object?>{
      'notes': <Object?>[
        <String, Object?>{
          'modelName': 'Basic',
          'fields': <String, Object?>{'Front': 'one', 'Back': '一'},
        },
      ],
    });
    expect(plain, <Object?>[true]);

    final Object? detailed = await service.dispatch(
      'canAddNotesWithErrorDetail',
      <String, Object?>{
        'notes': <Object?>[
          <String, Object?>{
            'modelName': 'Nope',
            'fields': <String, Object?>{'Front': 'two', 'Back': '二'},
          },
        ],
      },
    );
    final List<Object?> list = detailed! as List<Object?>;
    final Map<String, Object?> item = list.single! as Map<String, Object?>;
    expect(item['canAdd'], isFalse);
    expect(item['error'], 'model was not found: Nope');
  });

  test('canAddNotes 不会顺手建出卡组', () async {
    await service.dispatch('canAddNotes', <String, Object?>{
      'notes': <Object?>[
        <String, Object?>{
          'deckName': '还没建过的卡组',
          'modelName': 'Basic',
          'fields': <String, Object?>{'Front': 'x', 'Back': 'y'},
        },
      ],
    });
    expect(await harness.decks.getAll(), hasLength(1));
  });

  test('addNote 没给卡组时进当前卡组；给了就建出来', () async {
    await harness.settings.save(
      const AppSettings(activeDeckId: 'deck-active'),
    );
    await harness.decks.upsert(Deck(
      id: 'deck-active',
      name: '当前在学的',
      createdAt: DateTime(2026, 1, 1),
    ));
    await service.dispatch('addNote', <String, Object?>{
      'note': <String, Object?>{
        'modelName': 'Basic',
        'fields': <String, Object?>{'Front': 'implicit', 'Back': 'a'},
      },
    });
    await addBasic('explicit', 'b', deck: '新卡组::子卡组');
    final List<Deck> decks = await harness.decks.getAll();
    expect(decks.map((Deck d) => d.name), contains('当前在学的'));
    // Anki 的层级分隔符换成界面上那套。
    expect(decks.map((Deck d) => d.name), contains('新卡组 / 子卡组'));
  });

  test('锁死卡组后忽略客户端给的 deckName', () async {
    await harness.decks.upsert(Deck(
      id: 'deck-locked',
      name: '只进这里',
      createdAt: DateTime(2026, 1, 1),
    ));
    await harness.settings.save(
      const AppSettings(apiServerDeckId: 'deck-locked'),
    );
    await addBasic('locked', 'a', deck: '客户端的卡组');
    final List<WordCard> cards = await harness.cards.getAll();
    expect(cards.single.deckId, 'deck-locked');
    expect(
      (await harness.decks.getAll()).any((Deck d) => d.name == '客户端的卡组'),
      isFalse,
    );
  });

  test('notesInfo 回读字段、模型名与 id', () async {
    final int id = await addBasic('serendipity', 'n. 意外发现珍宝的运气');
    final List<Object?> info =
        (await service.dispatch('notesInfo', <String, Object?>{
      'notes': <Object?>[id],
    }))! as List<Object?>;
    final Map<String, Object?> note = info.single! as Map<String, Object?>;
    expect(note['noteId'], id);
    expect(note['modelName'], 'Basic');
    expect(note['cards'], <int>[id]);
    final Map<String, Object?> fields =
        note['fields']! as Map<String, Object?>;
    expect((fields['Front']! as Map<String, Object?>)['value'], 'serendipity');
    expect((fields['Back']! as Map<String, Object?>)['value'], 'n. 意外发现珍宝的运气');
  });

  test('updateNoteFields 改内容并推进 updatedAt', () async {
    final int id = await addBasic('rain', 'n. 雨');
    final DateTime before =
        (await harness.cards.getAll()).single.updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await service.dispatch('updateNoteFields', <String, Object?>{
      'note': <String, Object?>{
        'id': id,
        'fields': <String, Object?>{'Front': 'rainbow', 'Back': 'n. 彩虹'},
      },
    });
    final WordCard card = (await harness.cards.getAll()).single;
    expect(card.word, 'rainbow');
    expect(card.definition, 'n. 彩虹');
    expect(card.updatedAt.isAfter(before), isTrue);
  });

  test('findNotes 认 deck: 查询', () async {
    final int id = await addBasic('rain', 'n. 雨');
    final List<Object?> ids = (await service.dispatch(
      'findNotes',
      <String, Object?>{'query': 'deck:"默认词库"'},
    ))! as List<Object?>;
    expect(ids, <int>[id]);
    expect(
      await service.dispatch(
        'findNotes',
        <String, Object?>{'query': 'deck:"不存在的卡组"'},
      ),
      isEmpty,
    );
  });

  test('multi 按顺序执行，失败的子请求给 error 信封', () async {
    final List<Object?> results = (await service.dispatch(
      'multi',
      <String, Object?>{
        'actions': <Object?>[
          <String, Object?>{'action': 'version', 'params': <String, Object?>{}},
          <String, Object?>{'action': 'guiBrowse', 'params': <String, Object?>{}},
        ],
      },
    ))! as List<Object?>;
    expect(results[0], 6);
    expect((results[1]! as Map<String, Object?>)['error'], kUnsupportedAction);
  });
}

/// 单词卡的字段顺序（和 kNoteFields 一致，这里抄一份免得测试直接依赖 schema）。
const List<String> kNoteFieldsForTest = <String>[
  '单词',
  '释义',
  '音标',
  '例句',
  '词性',
  '备注',
  '干扰项',
];
