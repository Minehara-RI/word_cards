// ignore_for_file: prefer_interpolation_to_compose_strings

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:word_cards/src/data/anki/anki_api_cache_repository.dart';
import 'package:word_cards/src/data/anki/anki_card_repository.dart';
import 'package:word_cards/src/data/anki/anki_collection.dart';
import 'package:word_cards/src/data/anki/anki_deck_repository.dart';
import 'package:word_cards/src/data/anki/anki_record_repository.dart';
import 'package:word_cards/src/data/anki/anki_settings_repository.dart';
import 'package:word_cards/src/domain/models/card_source.dart';
import 'package:word_cards/src/domain/models/word_card.dart';
import 'package:word_cards/src/domain/repositories.dart';
import 'package:word_cards/src/state/providers.dart';

import 'fake_api_cache.dart';
import 'fake_repositories.dart';

/// 测试用的整套装配。
///
/// - TestHarness.create：真实的 Anki 内存库 + Anki 仓库，
///   用于普通 test（仓储层、导入服务要测真实现）。
/// - TestHarness.fake：纯 Dart 假仓库，用于 testWidgets。
class TestHarness {
  TestHarness._(
    this.cards,
    this.records,
    this.decks,
    this.settings,
    this.cache, [
    this.collection,
  ]);

  final CardRepository cards;
  final AnswerRecordRepository records;
  final DeckRepository decks;
  final SettingsRepository settings;

  /// 模式 B 的生成缓存（真实现 / 内存实现）。
  final ApiCacheRepository cache;

  /// 内存里的 Anki 集合，测试结束后关掉。
  final AnkiCollection? collection;

  static Future<TestHarness> create() async {
    final AnkiCollection collection = AnkiCollection.openInMemory();
    final AnkiDeckRepository decks = AnkiDeckRepository(collection);
    await decks.ensureDefault();
    return TestHarness._(
      AnkiCardRepository(collection),
      AnkiAnswerRecordRepository(collection),
      decks,
      AnkiSettingsRepository(collection),
      AnkiApiCacheRepository(collection),
      collection,
    );
  }

  static TestHarness fake() {
    final decks = FakeDeckRepository()..seedDefault();
    return TestHarness._(
      FakeCardRepository(),
      FakeAnswerRecordRepository(),
      decks,
      FakeSettingsRepository(),
      FakeApiCacheRepository(),
    );
  }

  Widget wrap(Widget child) => ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWithValue(cards),
          answerRecordRepositoryProvider.overrideWithValue(records),
          deckRepositoryProvider.overrideWithValue(decks),
          settingsRepositoryProvider.overrideWithValue(settings),
          apiCacheRepositoryProvider.overrideWithValue(cache),
        ],
        child: child,
      );

  Future<void> dispose() async => collection?.dispose();
}

/// 造一张卡片，字段都有默认值，测试里只写关心的部分。
WordCard makeCard({
  String? id,
  String word = 'abandon',
  String definition = 'v. 放弃；抛弃',
  List<String> distractors = const <String>[
    'v. 遵守；坚持',
    'v. 维持；供养',
    'v. 增加；扩大',
    'v. 分配；指派',
  ],
  String? phonetic = '/əˈbændən/',
  String? example,
  String? partOfSpeech,
  List<String> tags = const <String>[],
  String deckId = 'default',
  CardSource source = CardSource.manualImport,
  DateTime? createdAt,
  int reviewCount = 0,
  int correctCount = 0,
  double mastery = 0,
}) {
  final now = createdAt ?? DateTime(2026, 1, 1);
  return WordCard(
    id: id ?? 'card-' + word,
    word: word,
    definition: definition,
    distractors: distractors,
    phonetic: phonetic,
    example: example,
    partOfSpeech: partOfSpeech,
    tags: tags,
    deckId: deckId,
    source: source,
    createdAt: now,
    updatedAt: now,
    reviewCount: reviewCount,
    correctCount: correctCount,
    mastery: mastery,
  );
}

/// 一组稳定的测试卡片。
List<WordCard> sampleCards() => <WordCard>[
      makeCard(
        id: 'c1',
        word: 'abandon',
        definition: 'v. 放弃；抛弃',
        phonetic: '/əˈbændən/',
      ),
      makeCard(
        id: 'c2',
        word: 'meticulous',
        definition: 'adj. 一丝不苟的',
        distractors: <String>['adj. 漫不经心的', 'adj. 慷慨的', 'adj. 沉默的', 'adj. 固执的'],
        phonetic: '/məˈtɪkjələs/',
      ),
      makeCard(
        id: 'c3',
        word: 'resilient',
        definition: 'adj. 有韧性的',
        distractors: <String>['adj. 易碎的', 'adj. 冷淡的', 'adj. 奢侈的', 'adj. 含糊的'],
      ),
    ];
