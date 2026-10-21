import '../../domain/models/deck.dart';
import '../../domain/repositories.dart';
import 'anki_collection.dart';
import 'anki_schema.dart';

/// 词库仓库的 Anki 实现。
///
/// Anki 把牌组存在 col.decks 这个 JSON 里（schema 11 的约定），
/// 所以这里没有 decks 表，读写都走 col。
class AnkiDeckRepository implements DeckRepository {
  AnkiDeckRepository(this._collection);

  final AnkiCollection _collection;

  @override
  Stream<List<Deck>> watch() => _collection.watchValue(getAll);

  @override
  Future<List<Deck>> getAll() async {
    _collection.adoptOrphans();
    final List<Deck> result = <Deck>[];
    for (final Map<String, Object?> json in _collection.deckJsonList()) {
      final int ankiId = (json['id'] as num?)?.toInt() ?? kDefaultAnkiDeckId;
      String? uid = _collection.deckUidForId(ankiId);
      if (uid == null) {
        uid = ankiId == kDefaultAnkiDeckId
            ? Deck.defaultDeckId
            : ankiId.toString();
        _collection.db.execute(
          'insert or ignore into wc_deck_ids (uid, deck_id) values (?,?)',
          <Object?>[uid, ankiId],
        );
      }
      result.add(Deck(
        id: uid,
        name: (json['name'] as String?) ?? Deck.defaultDeckName,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          ((json['mod'] as num?)?.toInt() ?? 0) * 1000,
        ),
        suspended: (json[kAnkiSuspendedKey] as num?)?.toInt() == 1,
      ));
    }
    return result;
  }

  @override
  Future<void> upsert(Deck deck) async {
    final int ankiId = _collection.ensureDeckId(deck.id);
    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // 在原有 JSON 上改，而不是整条重写：牌组里的每日计数（revToday 之类）
    // 是 Anki 自己的状态，重写会把它们抹掉。挂起/恢复也不该顺手清一次。
    Map<String, Object?>? existing;
    for (final Map<String, Object?> json in _collection.deckJsonList()) {
      if ((json['id'] as num?)?.toInt() == ankiId) {
        existing = json;
        break;
      }
    }

    final Map<String, Object?> next = existing == null
        ? ankiDeck(ankiId, deck.name, nowSec, suspended: deck.suspended)
        : Map<String, Object?>.of(existing);
    next['id'] = ankiId;
    next['name'] = deck.name;
    next['mod'] = nowSec;
    if (deck.suspended) {
      next[kAnkiSuspendedKey] = 1;
    } else {
      next.remove(kAnkiSuspendedKey);
    }

    _collection.putDeckJson(next);
    _collection.notify();
  }

  @override
  Future<void> delete(String id) async {
    if (id == Deck.defaultDeckId) return;
    final int? ankiId = _collection.deckIdForUid(id);
    if (ankiId == null) return;
    _collection.removeDeckJson(ankiId);
    // 牌组没了，里面的卡片回到默认牌组，而不是被静默删掉。
    _collection.db.execute(
      'update cards set did = ? where did = ?',
      <Object?>[kDefaultAnkiDeckId, ankiId],
    );
    _collection.db.execute(
      'delete from wc_deck_ids where uid = ?',
      <Object?>[id],
    );
    _collection.notify();
  }

  @override
  Future<Deck> ensureDefault() async {
    _collection.db.execute(
      'insert or ignore into wc_deck_ids (uid, deck_id) values (?,?)',
      <Object?>[Deck.defaultDeckId, kDefaultAnkiDeckId],
    );
    _collection.ensureDeckId(Deck.defaultDeckId);
    for (final Deck deck in await getAll()) {
      if (deck.id == Deck.defaultDeckId) return deck;
    }
    final int nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _collection.putDeckJson(
      ankiDeck(kDefaultAnkiDeckId, Deck.defaultDeckName, nowSec),
    );
    return Deck(
      id: Deck.defaultDeckId,
      name: Deck.defaultDeckName,
      createdAt: DateTime.fromMillisecondsSinceEpoch(nowSec * 1000),
    );
  }
}
