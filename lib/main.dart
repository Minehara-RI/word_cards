import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'src/data/anki/anki_api_cache_repository.dart';
import 'src/data/anki/anki_card_repository.dart';
import 'src/data/anki/anki_collection.dart';
import 'src/data/anki/anki_deck_repository.dart';
import 'src/data/anki/anki_record_repository.dart';
import 'src/data/anki/anki_schema.dart';
import 'src/data/anki/anki_settings_repository.dart';
import 'src/data/anki/sembast_migrator.dart';
import 'src/state/providers.dart';
import 'src/ui/app.dart';
import 'src/ui/presentation/presentation_window.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端的演示窗口是同一个可执行文件的另一个 Flutter 引擎：
  // 先看当前引擎是不是那个窗口，是的话就只画演示画面，不去碰数据库。
  final PresentationWindow? presentation = await PresentationWindow.bootstrap();
  if (presentation != null) {
    await presentation.run();
    return;
  }

  // 本地库完全在设备上，不连任何服务器。
  // 存的就是 Anki 的 collection.anki2，可以直接拿 Anki 打开这个文件。
  final Directory directory = await getApplicationSupportDirectory();
  final String collectionPath = p.join(directory.path, kAnkiFileName);
  final String legacyPath = p.join(directory.path, 'word_cards.db');

  final AnkiCollection collection = AnkiCollection.openAt(collectionPath);
  await migrateSembastIntoAnki(
    collection: collection,
    legacyPath: legacyPath,
  );

  final AnkiDeckRepository decks = AnkiDeckRepository(collection);
  await decks.ensureDefault();

  runApp(
    ProviderScope(
      overrides: [
        ankiCollectionProvider.overrideWithValue(collection),
        cardRepositoryProvider
            .overrideWithValue(AnkiCardRepository(collection)),
        answerRecordRepositoryProvider
            .overrideWithValue(AnkiAnswerRecordRepository(collection)),
        deckRepositoryProvider.overrideWithValue(decks),
        settingsRepositoryProvider
            .overrideWithValue(AnkiSettingsRepository(collection)),
        apiCacheRepositoryProvider
            .overrideWithValue(AnkiApiCacheRepository(collection)),
      ],
      child: const WordCardsApp(),
    ),
  );
}
