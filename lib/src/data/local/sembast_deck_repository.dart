import 'package:sembast/sembast.dart';

import '../../domain/models/deck.dart';
import '../../domain/repositories.dart';
import 'app_database.dart';

class SembastDeckRepository implements DeckRepository {
  SembastDeckRepository(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  static Finder get _finder => Finder(
        sortOrders: <SortOrder>[SortOrder('created_at')],
      );

  @override
  Stream<List<Deck>> watch() => AppDatabase.decks
      .query(finder: _finder)
      .onSnapshots(_db)
      .map((snapshots) =>
          snapshots.map((snapshot) => Deck.fromMap(snapshot.value)).toList(growable: false));

  @override
  Future<List<Deck>> getAll() async {
    final snapshots = await AppDatabase.decks.query(finder: _finder).getSnapshots(_db);
    return snapshots
        .map((snapshot) => Deck.fromMap(snapshot.value))
        .toList(growable: false);
  }

  @override
  Future<void> upsert(Deck deck) =>
      AppDatabase.decks.record(deck.id).put(_db, deck.toMap());

  @override
  Future<void> delete(String id) async {
    if (id == Deck.defaultDeckId) return;
    await AppDatabase.decks.record(id).delete(_db);
  }

  @override
  Future<Deck> ensureDefault() async {
    final existing = await AppDatabase.decks.record(Deck.defaultDeckId).get(_db);
    if (existing != null) return Deck.fromMap(existing);
    final deck = Deck.fallback();
    await upsert(deck);
    return deck;
  }
}
