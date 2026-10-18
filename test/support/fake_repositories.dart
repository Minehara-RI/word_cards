import 'dart:async';

import 'package:word_flashcards/src/domain/models/answer_record.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/deck.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/domain/repositories.dart';

/// 纯 Dart 假仓库：只用微任务，不碰真实计时器与磁盘。
///
/// testWidgets 跑在 fake-async 环境里，真实的 sembast 依赖计时器与锁，
/// 在那个环境里会永远挂住，所以 widget 测试统一用这一套。
String _key(String word) => word.trim().toLowerCase();

class FakeCardRepository implements CardRepository {
  final Map<String, WordCard> _cards = <String, WordCard>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  List<WordCard> _snapshot(String? deckId) {
    final list = _cards.values
        .where((card) => deckId == null || card.deckId == deckId)
        .toList()
      ..sort((a, b) => a.word.compareTo(b.word));
    return List<WordCard>.unmodifiable(list);
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Stream<List<WordCard>> watch({String? deckId}) {
    return Stream<List<WordCard>>.multi((listener) {
      listener.add(_snapshot(deckId));
      final subscription =
          _changes.stream.listen((_) => listener.add(_snapshot(deckId)));
      listener.onCancel = subscription.cancel;
    });
  }

  @override
  Future<List<WordCard>> getAll({String? deckId}) async => _snapshot(deckId);

  @override
  Future<WordCard?> getById(String id) async => _cards[id];

  @override
  Future<WordCard?> findByWord(String word, {String? deckId}) async {
    for (final card in _cards.values) {
      if (_key(card.word) == _key(word) &&
          (deckId == null || card.deckId == deckId)) {
        return card;
      }
    }
    return null;
  }

  @override
  Future<List<WordCard>> findByWords(
    List<String> words, {
    String? deckId,
  }) async {
    final keys = words.map(_key).toSet();
    return _cards.values
        .where((card) =>
            keys.contains(_key(card.word)) &&
            (deckId == null || card.deckId == deckId))
        .toList(growable: false);
  }

  @override
  Future<void> upsert(WordCard card) async {
    _cards[card.id] = card;
    _notify();
  }

  @override
  Future<void> upsertAll(List<WordCard> cards) async {
    for (final card in cards) {
      _cards[card.id] = card;
    }
    _notify();
  }

  @override
  Future<void> deleteById(String id) async {
    _cards.remove(id);
    _notify();
  }

  @override
  Future<void> deleteAll({String? deckId}) async {
    if (deckId == null) {
      _cards.clear();
    } else {
      _cards.removeWhere((_, card) => card.deckId == deckId);
    }
    _notify();
  }

  @override
  Future<void> resetProgress({String? deckId}) async {
    for (final MapEntry<String, WordCard> entry in _cards.entries.toList()) {
      final WordCard card = entry.value;
      if (deckId != null && card.deckId != deckId) continue;
      // 重新造一张同内容的卡：学习相关的字段全部归零，fsrs 也不带。
      _cards[entry.key] = WordCard(
        id: card.id,
        word: card.word,
        definition: card.definition,
        distractors: card.distractors,
        phonetic: card.phonetic,
        example: card.example,
        partOfSpeech: card.partOfSpeech,
        note: card.note,
        deckId: card.deckId,
        language: card.language,
        tags: card.tags,
        source: card.source,
        createdAt: card.createdAt,
        updatedAt: card.updatedAt,
      );
    }
    _notify();
  }

  @override
  Future<int> count({String? deckId}) async => _snapshot(deckId).length;
}

class FakeAnswerRecordRepository implements AnswerRecordRepository {
  final List<AnswerRecord> _records = <AnswerRecord>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  List<AnswerRecord> _recent(int limit) {
    final sorted = List<AnswerRecord>.of(_records)
      ..sort((a, b) => b.answeredAt.compareTo(a.answeredAt));
    return sorted.take(limit).toList(growable: false);
  }

  @override
  Future<void> add(AnswerRecord record) async {
    _records.add(record);
    _notify();
  }

  @override
  Future<void> addAll(List<AnswerRecord> records) async {
    _records.addAll(records);
    _notify();
  }

  @override
  Future<List<AnswerRecord>> getRecent({int limit = 200}) async =>
      _recent(limit);

  @override
  Future<List<AnswerRecord>> getSince(DateTime since) async => _records
      .where((record) => !record.answeredAt.isBefore(since))
      .toList(growable: false);

  @override
  Future<List<AnswerRecord>> getAll() async => List<AnswerRecord>.of(_records);

  @override
  Stream<List<AnswerRecord>> watchRecent({int limit = 200}) {
    return Stream<List<AnswerRecord>>.multi((listener) {
      listener.add(_recent(limit));
      final subscription =
          _changes.stream.listen((_) => listener.add(_recent(limit)));
      listener.onCancel = subscription.cancel;
    });
  }

  @override
  Future<void> deleteAll() async {
    _records.clear();
    _notify();
  }
}

class FakeDeckRepository implements DeckRepository {
  final Map<String, Deck> _decks = <String, Deck>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void seedDefault() {
    _decks[Deck.defaultDeckId] = Deck.fallback();
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Stream<List<Deck>> watch() {
    return Stream<List<Deck>>.multi((listener) {
      listener.add(List<Deck>.unmodifiable(_decks.values));
      final subscription = _changes.stream
          .listen((_) => listener.add(List<Deck>.unmodifiable(_decks.values)));
      listener.onCancel = subscription.cancel;
    });
  }

  @override
  Future<List<Deck>> getAll() async => List<Deck>.of(_decks.values);

  @override
  Future<void> upsert(Deck deck) async {
    _decks[deck.id] = deck;
    _notify();
  }

  @override
  Future<void> delete(String id) async {
    if (id == Deck.defaultDeckId) return;
    _decks.remove(id);
    _notify();
  }

  @override
  Future<Deck> ensureDefault() async {
    final existing = _decks[Deck.defaultDeckId];
    if (existing != null) return existing;
    final deck = Deck.fallback();
    await upsert(deck);
    return deck;
  }
}

class FakeSettingsRepository implements SettingsRepository {
  AppSettings _settings = const AppSettings();
  final StreamController<AppSettings> _changes =
      StreamController<AppSettings>.broadcast();

  @override
  Stream<AppSettings> watch() {
    return Stream<AppSettings>.multi((listener) {
      listener.add(_settings);
      final subscription = _changes.stream.listen(listener.add);
      listener.onCancel = subscription.cancel;
    });
  }

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
    if (!_changes.isClosed) _changes.add(settings);
  }
}
