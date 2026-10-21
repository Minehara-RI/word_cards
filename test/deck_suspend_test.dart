// 卡组「挂起 / 恢复」：存得住、不弄丢 Anki 自己的字段、两个页面各按各的规则。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/data/audio/beep_player.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';
import 'package:word_flashcards/src/domain/models/deck.dart';
import 'package:word_flashcards/src/state/providers.dart';
import 'package:word_flashcards/src/ui/pages/projection_page.dart';
import 'package:word_flashcards/src/ui/pages/settings_page.dart';

import 'support/test_harness.dart';

/// 不在测试里真的发声。
class _SilentSound implements PageTurnSound {
  @override
  Future<void> playPageTurn() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  group('Anki 库', () {
    late TestHarness harness;

    setUp(() async {
      harness = await TestHarness.create();
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('挂起状态写进牌组 JSON，读回来还在', () async {
      await harness.decks.upsert(Deck(
        id: 'd1',
        name: '第一册',
        createdAt: DateTime(2026, 1, 1),
      ));
      await harness.decks.upsert(Deck(
        id: 'd1',
        name: '第一册',
        createdAt: DateTime(2026, 1, 1),
        suspended: true,
      ));

      final Deck deck = (await harness.decks.getAll())
          .firstWhere((Deck item) => item.id == 'd1');
      expect(deck.suspended, isTrue);

      final Map<String, Object?>? json = harness.collection
          ?.deckJsonList()
          .cast<Map<String, Object?>?>()
          .firstWhere(
            (Map<String, Object?>? item) =>
                item != null && (item['name'] as String?) == '第一册',
            orElse: () => null,
          );
      expect(json?['wcSuspended'], 1);

      // 恢复：标记去掉
      await harness.decks.upsert(deck.copyWith(suspended: false));
      final Deck restored = (await harness.decks.getAll())
          .firstWhere((Deck item) => item.id == 'd1');
      expect(restored.suspended, isFalse);
    });

    test('改名/挂起不清掉 Anki 的每日计数', () async {
      await harness.decks.upsert(Deck(
        id: 'd1',
        name: '第一册',
        createdAt: DateTime(2026, 1, 1),
      ));

      final AnkiCollectionLike collection = AnkiCollectionLike(harness);
      final Map<String, Object?> original = collection.jsonOf('第一册')!;
      collection.put(<String, Object?>{
        ...original,
        'revToday': <Object?>[5, 7],
      });

      await harness.decks.upsert(Deck(
        id: 'd1',
        name: '第一册（改）',
        createdAt: DateTime(2026, 1, 1),
        suspended: true,
      ));

      final Map<String, Object?> updated = collection.jsonOf('第一册（改）')!;
      expect(updated['revToday'], <Object?>[5, 7]);
      expect(updated['wcSuspended'], 1);
    });
  });

  group('界面', () {
    testWidgets('管理卡组里点「挂起」变「恢复」，再点回来', (tester) async {
      tester.view.physicalSize = const Size(1200, 3400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final TestHarness harness = TestHarness.fake();
      await harness.decks.upsert(Deck(
        id: 'd2',
        name: '新必修一',
        createdAt: DateTime(2026, 1, 1),
      ));
      await harness.cards.upsert(makeCard(id: 'c1', word: 'abandon', deckId: 'd2'));

      await tester.pumpWidget(harness.wrap(MaterialApp(
        home: const SettingsPage(),
      )));
      await tester.pumpAndSettle();

      final Finder suspendButton = find.byKey(const Key('deck-suspend-d2'));
      await tester.scrollUntilVisible(
        suspendButton,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(of: suspendButton, matching: find.text('挂起')),
        findsOneWidget,
      );

      await tester.tap(suspendButton);
      await tester.pumpAndSettle();

      Deck deck = (await harness.decks.getAll())
          .firstWhere((Deck item) => item.id == 'd2');
      expect(deck.suspended, isTrue);
      expect(
        find.descendant(of: suspendButton, matching: find.text('恢复')),
        findsOneWidget,
      );
      expect(find.textContaining('已挂起，不作答'), findsOneWidget);

      await tester.tap(find.byKey(const Key('deck-suspend-d2')));
      await tester.pumpAndSettle();
      deck = (await harness.decks.getAll())
          .firstWhere((Deck item) => item.id == 'd2');
      expect(deck.suspended, isFalse);
      expect(
        find.descendant(of: suspendButton, matching: find.text('挂起')),
        findsOneWidget,
      );
    });

    testWidgets('演示页照样列得出已挂起的卡组', (tester) async {
      tester.view.physicalSize = const Size(1400, 3400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final TestHarness harness = TestHarness.fake();
      await harness.decks.upsert(Deck(
        id: 'd2',
        name: '第二册',
        createdAt: DateTime(2026, 1, 1),
        suspended: true,
      ));
      await harness.cards.upsert(makeCard(
        id: 'c1',
        word: 'abandon',
        deckId: 'd2',
      ));
      await harness.settings.save(const AppSettings(
        projectionSource: ProjectionSource.deck,
        projectionDeckIds: <String>['d2'],
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardRepositoryProvider.overrideWithValue(harness.cards),
            answerRecordRepositoryProvider.overrideWithValue(harness.records),
            deckRepositoryProvider.overrideWithValue(harness.decks),
            settingsRepositoryProvider.overrideWithValue(harness.settings),
            apiCacheRepositoryProvider.overrideWithValue(harness.cache),
            pageTurnSoundProvider.overrideWithValue(_SilentSound()),
          ],
          child: const MaterialApp(home: ProjectionPage(onGoToAdd: _noop)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('projection-deck-d2')), findsOneWidget);
      expect(find.textContaining('可演示卡片'), findsOneWidget);
    });
  });
}

void _noop() {}

/// 只为了少写几行 collection 的包装。
class AnkiCollectionLike {
  AnkiCollectionLike(this.harness);

  final TestHarness harness;

  Map<String, Object?>? jsonOf(String name) {
    for (final Map<String, Object?> json in harness.collection!.deckJsonList()) {
      if (json['name'] == name) return json;
    }
    return null;
  }

  void put(Map<String, Object?> json) => harness.collection!.putDeckJson(json);
}
