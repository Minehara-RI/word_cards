import 'dart:io';

import '../../domain/models/answer_record.dart';
import '../../domain/models/deck.dart';
import '../../domain/models/word_card.dart';
import '../local/app_database.dart';
import '../local/sembast_card_repository.dart';
import '../local/sembast_deck_repository.dart';
import '../local/sembast_record_repository.dart';
import '../local/sembast_settings_repository.dart';
import 'anki_card_repository.dart';
import 'anki_collection.dart';
import 'anki_deck_repository.dart';
import 'anki_record_repository.dart';
import 'anki_settings_repository.dart';

/// 迁移结果，用来在启动日志里说明搬了多少东西。
class MigrationReport {
  const MigrationReport({
    this.cards = 0,
    this.records = 0,
    this.decks = 0,
    this.migrated = false,
  });

  final int cards;
  final int records;
  final int decks;
  final bool migrated;

  static const MigrationReport none = MigrationReport();
}

/// 把旧版 sembast 库里的数据一次性搬进 Anki 库。
///
/// 只在「Anki 库里还没有卡片」且「旧的 word_cards.db 还在」的时候才动手；
/// 搬完把旧文件改名成 word_cards.db.migrated，避免重复导入。
Future<MigrationReport> migrateSembastIntoAnki({
  required AnkiCollection collection,
  required String legacyPath,
}) async {
  final File legacy = File(legacyPath);
  if (!legacy.existsSync()) return MigrationReport.none;

  final int existingNotes =
      (collection.db.select('select count(*) as c from notes').first['c']
              as int?) ??
          0;
  if (existingNotes > 0) return MigrationReport.none;

  int cardCount = 0;
  int recordCount = 0;
  int deckCount = 0;

  try {
    final AppDatabase database = await AppDatabase.openAt(legacyPath);
    try {
      final AnkiDeckRepository targetDecks = AnkiDeckRepository(collection);
      final List<Deck> decks = await SembastDeckRepository(database).getAll();
      for (final Deck deck in decks) {
        await targetDecks.upsert(deck);
        deckCount++;
      }
      await targetDecks.ensureDefault();

      final List<WordCard> cards = await SembastCardRepository(database).getAll();
      if (cards.isNotEmpty) {
        await AnkiCardRepository(collection).upsertAll(cards);
        cardCount = cards.length;
      }

      final List<AnswerRecord> records =
          await SembastAnswerRecordRepository(database).getAll();
      if (records.isNotEmpty) {
        await AnkiAnswerRecordRepository(collection).addAll(records);
        recordCount = records.length;
      }

      await AnkiSettingsRepository(collection)
          .save(await SembastSettingsRepository(database).load());
    } finally {
      await database.close();
    }
  } catch (_) {
    // 旧文件不是合法的 sembast 库，或者中途出错：不动它，下次启动再试。
    return MigrationReport.none;
  }

  try {
    final File backup = File('$legacyPath.migrated');
    if (backup.existsSync()) backup.deleteSync();
    legacy.renameSync(backup.path);
  } catch (_) {
    // 改名失败不影响已经迁完的数据。
  }

  return MigrationReport(
    cards: cardCount,
    records: recordCount,
    decks: deckCount,
    migrated: true,
  );
}
