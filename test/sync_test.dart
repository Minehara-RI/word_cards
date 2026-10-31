import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/core/server_ports.dart';
import 'package:word_flashcards/src/data/sync/sync_client.dart';
import 'package:word_flashcards/src/data/sync/sync_server.dart';
import 'package:word_flashcards/src/data/sync/sync_service.dart';
import 'package:word_flashcards/src/data/sync/sync_url.dart';
import 'package:word_flashcards/src/domain/models/answer_record.dart';
import 'package:word_flashcards/src/domain/models/deck.dart';
import 'package:word_flashcards/src/domain/models/sync_snapshot.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/logic/sync_merge.dart';

import 'support/fake_repositories.dart';
import 'support/test_harness.dart';

void main() {
  group('地址整理', () {
    test('只填 IP 就补默认端口', () {
      // 只填 IP 时补的是固定端口 5033。
      expect(normalizeSyncBaseUrl('192.168.1.5'), 'http://192.168.1.5:5033');
      expect(
        normalizeSyncBaseUrl('192.168.1.5:9000'),
        'http://192.168.1.5:9000',
      );
      expect(
        normalizeSyncBaseUrl(' http://192.168.1.5:9000/ '),
        'http://192.168.1.5:9000',
      );
      expect(
        normalizeSyncBaseUrl('[fe80::1]:5033'),
        'http://[fe80::1]:5033',
      );
      expect(kSyncPort, 5033);
      expect(kApiServerPort, 8766);
      expect(normalizeSyncBaseUrl(''), isNull);
      expect(normalizeSyncBaseUrl('http://'), isNull);
    });
  });

  group('合并（纯函数）', () {
    WordCard card({
      String id = 'c1',
      String word = 'alpha',
      String definition = 'n. 甲',
      DateTime? updatedAt,
      DateTime? lastReviewedAt,
      int reviewCount = 0,
      String deckId = Deck.defaultDeckId,
    }) =>
        WordCard(
          id: id,
          word: word,
          definition: definition,
          distractors: const <String>['x', 'y', 'z', 'w'],
          deckId: deckId,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: updatedAt ?? DateTime(2026, 1, 1),
          lastReviewedAt: lastReviewedAt,
          reviewCount: reviewCount,
        );

    SyncSnapshot snap({
      String device = 'A',
      List<WordCard> cards = const <WordCard>[],
      List<Deck> decks = const <Deck>[],
      List<AnswerRecord> answers = const <AnswerRecord>[],
      List<SyncTombstone> tombstones = const <SyncTombstone>[],
    }) =>
        SyncSnapshot(
          deviceId: device,
          deviceName: device,
          generatedAt: DateTime(2026, 1, 1),
          cards: cards,
          decks: decks,
          answers: answers,
          tombstones: tombstones,
        );

    WordCard? find(SyncSnapshot snapshot, String id) {
      for (final WordCard item in snapshot.cards) {
        if (item.id == id) return item;
      }
      return null;
    }

    test('内容取更晚的编辑', () {
      final SyncSnapshot merged = mergeSnapshots(
        snap(cards: <WordCard>[
          card(definition: '旧的', updatedAt: DateTime(2026, 1, 2)),
        ]),
        snap(device: 'B', cards: <WordCard>[
          card(definition: '新的', updatedAt: DateTime(2026, 1, 3)),
        ]),
      );
      expect(find(merged, 'c1')!.definition, '新的');
    });

    test('进度取最后复习的那一端，内容仍取更晚编辑', () {
      final SyncSnapshot a = snap(cards: <WordCard>[
        card(
          definition: 'A 的释义',
          updatedAt: DateTime(2026, 1, 2),
        ),
      ]);
      final SyncSnapshot b = snap(device: 'B', cards: <WordCard>[
        card(
          definition: 'B 的释义',
          updatedAt: DateTime(2026, 1, 1),
          lastReviewedAt: DateTime(2026, 3, 1),
          reviewCount: 5,
        ),
      ]);
      // A 后改了内容但没复习；B 没改内容但最近复习过。
      final WordCard merged = find(mergeSnapshots(a, b), 'c1')!;
      expect(merged.definition, 'A 的释义');
      expect(merged.reviewCount, 5);
    });

    test('交换顺序得到同一份数据（可交换）', () {
      final WordCard mine = card(definition: 'A', updatedAt: DateTime(2026, 1, 5));
      final WordCard theirs = card(
        definition: 'B',
        updatedAt: DateTime(2026, 1, 5),
        reviewCount: 2,
        lastReviewedAt: DateTime(2026, 2, 2),
      );
      final SyncSnapshot ab =
          mergeSnapshots(snap(cards: <WordCard>[mine]), snap(device: 'B', cards: <WordCard>[theirs]));
      final SyncSnapshot ba =
          mergeSnapshots(snap(device: 'B', cards: <WordCard>[theirs]), snap(cards: <WordCard>[mine]));
      expect(find(ab, 'c1')!.definition, find(ba, 'c1')!.definition);
      expect(find(ab, 'c1')!.reviewCount, find(ba, 'c1')!.reviewCount);
    });

    test('再合一次不变（幂等）', () {
      final SyncSnapshot a = snap(cards: <WordCard>[card()]);
      final SyncSnapshot once = mergeSnapshots(a, a);
      final SyncSnapshot twice = mergeSnapshots(once, a);
      expect(twice.cards.length, once.cards.length);
      expect(find(twice, 'c1')!.definition, find(once, 'c1')!.definition);
    });

    test('删除不会复活', () {
      final SyncSnapshot merged = mergeSnapshots(
        snap(cards: <WordCard>[card()]),
        snap(device: 'B', tombstones: <SyncTombstone>[
          SyncTombstone(
            uid: 'c1',
            deletedAt: DateTime(2026, 5, 1),
          ),
        ]),
      );
      expect(find(merged, 'c1'), isNull);
      expect(merged.tombstones, hasLength(1));
    });

    test('删掉之后又改过的卡会回来（修改时间晚于删除时间）', () {
      final SyncSnapshot merged = mergeSnapshots(
        snap(cards: <WordCard>[
          card(updatedAt: DateTime(2026, 5, 2)),
        ]),
        snap(device: 'B', tombstones: <SyncTombstone>[
          SyncTombstone(uid: 'c1', deletedAt: DateTime(2026, 5, 1)),
        ]),
      );
      expect(find(merged, 'c1'), isNotNull);
    });

    test('卡组被删：卡不跟着消失，退回默认卡组', () {
      final SyncSnapshot merged = mergeSnapshots(
        snap(
          decks: <Deck>[
            Deck(id: 'd1', name: '临时', createdAt: DateTime(2026, 1, 1)),
          ],
          cards: <WordCard>[card(deckId: 'd1')],
        ),
        snap(device: 'B', tombstones: <SyncTombstone>[
          SyncTombstone(
            uid: 'd1',
            kind: SyncTombstone.kindDeck,
            deletedAt: DateTime(2026, 6, 1),
          ),
        ]),
      );
      expect(merged.decks.map((Deck d) => d.id), isNot(contains('d1')));
      expect(find(merged, 'c1')!.deckId, Deck.defaultDeckId);
    });

    test('答题记录按 id 取并集', () {
      AnswerRecord record(String id) => AnswerRecord(
            id: id,
            cardId: 'c1',
            selected: 'a',
            expected: 'a',
            correct: true,
            reactionMs: 100,
            answeredAt: DateTime(2026, 1, 1),
          );
      final SyncSnapshot merged = mergeSnapshots(
        snap(answers: <AnswerRecord>[record('r1')]),
        snap(device: 'B', answers: <AnswerRecord>[record('r2'), record('r1')]),
      );
      expect(merged.answers.map((AnswerRecord r) => r.id).toSet(),
          <String>{'r1', 'r2'});
    });
  });

  group('两台设备真的同步一次（走 HTTP）', () {
    late TestHarness a;
    late TestHarness b;
    late SyncServerHandle server;
    late SyncClient client;

    setUp(() async {
      a = await TestHarness.create();
      b = await TestHarness.create();
      client = SyncClient();
    });

    tearDown(() async {
      await server.close();
      client.close();
      await a.dispose();
      await b.dispose();
    });

    SyncService serviceOf(TestHarness harness) => SyncService(
          cards: harness.cards,
          decks: harness.decks,
          records: harness.records,
          sync: harness.sync,
        );

    Future<String> startNodeA({String? pin}) async {
      server = await startSyncServer(
        service: serviceOf(a),
        port: 0,
        deviceName: () => '电脑',
        pin: () => pin,
      );
      return 'http://127.0.0.1:${server.port}';
    }

    test('B 推上去，两端都拿到对方的词', () async {
      await a.cards.upsert(makeCard(id: 'mine', word: 'alpha', definition: 'n. 甲'));
      await b.cards.upsert(makeCard(id: 'theirs', word: 'beta', definition: 'n. 乙'));
      final String url = await startNodeA();

      final SyncService serviceB = serviceOf(b);
      final SyncSnapshot mine = await serviceB.buildSnapshot(deviceName: '手机');
      final SyncSnapshot merged = await client.exchange(url, mine);
      await serviceB.applyMerged(merged);

      expect(await a.cards.count(), 2);
      expect(await b.cards.count(), 2);
      expect(
        (await b.cards.getAll()).map((WordCard c) => c.word).toSet(),
        <String>{'alpha', 'beta'},
      );
    });

    test('删除会传过去，不会同步完又回来', () async {
      await a.cards.upsert(makeCard(id: 'gone', word: 'alpha', definition: 'n. 甲'));
      await b.cards.upsert(makeCard(id: 'gone', word: 'alpha', definition: 'n. 甲'));
      await a.cards.deleteById('gone');
      final String url = await startNodeA();

      final SyncService serviceB = serviceOf(b);
      final SyncSnapshot merged =
          await client.exchange(url, await serviceB.buildSnapshot());
      await serviceB.applyMerged(merged);

      expect(await a.cards.count(), 0);
      expect(await b.cards.count(), 0);
    });

    test('口令不对直接拒绝', () async {
      final String url = await startNodeA(pin: '2468');
      final SyncService serviceB = serviceOf(b);
      final SyncSnapshot mine = await serviceB.buildSnapshot();
      await expectLater(
        client.exchange(url, mine, pin: '0000'),
        throwsA(isA<SyncFailure>()),
      );
      await expectLater(
        client.exchange(url, mine),
        throwsA(isA<SyncFailure>()),
      );
      // 口令对了就能过。
      final SyncSnapshot merged = await client.exchange(url, mine, pin: '2468');
      expect(merged.deviceName, '电脑');
    });

    test('ping 报出设备名与是否需要口令', () async {
      final String url = await startNodeA(pin: '2468');
      final SyncPeerInfo peer = await client.ping(url);
      expect(peer.deviceName, '电脑');
      expect(peer.requiresPin, isTrue);
      expect(peer.protocol, SyncSnapshot.protocol);
    });

    test('合并结果落库后进度与答题记录都在', () async {
      await a.cards.upsert(makeCard(id: 'shared', word: 'alpha', definition: 'n. 甲'));
      await b.cards.upsert(makeCard(id: 'shared', word: 'alpha', definition: 'n. 甲'));
      await b.records.add(AnswerRecord(
        id: 'r1',
        cardId: 'shared',
        selected: 'n. 甲',
        expected: 'n. 甲',
        correct: true,
        reactionMs: 900,
        answeredAt: DateTime(2026, 3, 3),
      ));
      final String url = await startNodeA();
      final SyncService serviceB = serviceOf(b);
      final SyncSnapshot merged =
          await client.exchange(url, await serviceB.buildSnapshot());
      await serviceB.applyMerged(merged);
      expect(await a.records.getAll(), hasLength(1));
      expect(await b.records.getAll(), hasLength(1));
    });
  });

  test('FakeSyncRepository 也认墓碑时间去重', () async {
    final FakeSyncRepository repo = FakeSyncRepository();
    await repo.addTombstone(SyncTombstone(
      uid: 'c1',
      deletedAt: DateTime(2026, 1, 5),
    ));
    await repo.addTombstone(SyncTombstone(
      uid: 'c1',
      deletedAt: DateTime(2026, 1, 1),
    ));
    final List<SyncTombstone> stones = await repo.tombstones();
    expect(stones, hasLength(1));
    expect(stones.single.deletedAt, DateTime(2026, 1, 5));
  });
}
