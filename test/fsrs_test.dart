// FSRS 的公式由官方包（dart-fsrs）负责，这里测的是本应用的适配层：
// 状态映射、评分映射、队列排序，以及「打开 FSRS 不影响原有数据」。
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/fsrs_memory.dart';
import 'package:word_flashcards/src/domain/models/word_card.dart';
import 'package:word_flashcards/src/logic/fsrs.dart';

import 'support/test_harness.dart';

void main() {
  // 测试里关掉官方包的随机扰动，间隔才可预期。
  const FsrsConfig config = FsrsConfig(enableFuzzing: false);
  final FsrsScheduler scheduler = FsrsScheduler(config);
  final DateTime day1 = DateTime(2026, 3, 1, 9);

  group('配置', () {
    test('默认参数就是官方包的 FSRS-6 参数（21 个）', () {
      expect(FsrsConfig.defaults.parameters.length, 21);
      expect(FsrsConfig.defaults.parameters, kFsrs6DefaultParameters);
      expect(FsrsConfig.defaults.desiredRetention, 0.9);
      // 参数个数不对时退回官方默认值，避免把非法参数丢给官方包
      expect(
        FsrsConfig.normalizeParameters(const <double>[1, 2, 3]),
        kFsrs6DefaultParameters,
      );
      expect(() => config.build(), returnsNormally);
    });

    test('copyWith 只改指定字段', () {
      expect(
        FsrsConfig.defaults.copyWith(desiredRetention: 0.8).desiredRetention,
        0.8,
      );
    });
  });

  group('评分映射', () {
    test('超时和答错都是 Again', () {
      expect(
        fsrsRatingForAnswer(
            correct: false, timedOut: true, reactionMs: 5000, timeLimitMs: 5000),
        1,
      );
      expect(
        fsrsRatingForAnswer(
            correct: false, timedOut: false, reactionMs: 1200, timeLimitMs: 5000),
        1,
      );
    });

    test('答对按用时分成 Hard / Good / Easy', () {
      expect(
        fsrsRatingForAnswer(
            correct: true, timedOut: false, reactionMs: 1000, timeLimitMs: 5000),
        4,
      );
      expect(
        fsrsRatingForAnswer(
            correct: true, timedOut: false, reactionMs: 3000, timeLimitMs: 5000),
        3,
      );
      expect(
        fsrsRatingForAnswer(
            correct: true, timedOut: false, reactionMs: 4800, timeLimitMs: 5000),
        2,
      );
      expect(fsrsRatingLabel(1), contains('Again'));
      expect(fsrsRatingLabel(2), contains('Hard'));
      expect(fsrsRatingLabel(3), contains('Good'));
      expect(fsrsRatingLabel(4), contains('Easy'));
    });
  });

  group('复习', () {
    test('新卡第一次评分：用官方包的初始稳定性与难度', () {
      final FsrsReviewResult good =
          scheduler.review(previous: null, rating: 3, reviewedAt: day1);

      // w0..w3 就是四个评分的初始稳定性
      expect(good.memory.stability, closeTo(kFsrs6DefaultParameters[2], 1e-9));
      expect(good.memory.state, FsrsCardState.review);
      expect(good.memory.reps, 1);
      expect(good.memory.lapses, 0);
      expect(good.retrievability, 0, reason: '新卡还没学过，没有可提取度');
      expect(good.elapsedDays, 0);

      // 目标保留率 90% 时，间隔就是稳定性四舍五入后的天数
      expect(good.intervalDays, good.memory.stability.round());
      expect(
        good.memory.dueAt!.difference(day1).inDays,
        good.intervalDays,
      );

      final FsrsReviewResult again =
          scheduler.review(previous: null, rating: 1, reviewedAt: day1);
      expect(again.memory.stability,
          closeTo(kFsrs6DefaultParameters[0], 1e-9));
      expect(again.intervalDays, greaterThanOrEqualTo(1));
      expect(again.memory.lapses, 0, reason: '第一次就没答对不算遗忘');

      final FsrsReviewResult easy =
          scheduler.review(previous: null, rating: 4, reviewedAt: day1);
      expect(easy.intervalDays, greaterThan(good.intervalDays));
    });

    test('答对若干次：稳定性和间隔都在涨，难度在降', () {
      FsrsMemory memory = scheduler
          .review(previous: null, rating: 3, reviewedAt: day1)
          .memory;
      final double firstStability = memory.stability;
      final int firstInterval =
          scheduler.review(previous: null, rating: 3, reviewedAt: day1)
              .intervalDays;

      DateTime at = day1;
      for (int i = 0; i < 3; i++) {
        at = memory.dueAt!;
        final FsrsReviewResult result =
            scheduler.review(previous: memory, rating: 3, reviewedAt: at);
        expect(result.memory.stability, greaterThan(memory.stability));
        expect(result.memory.difficulty, lessThanOrEqualTo(memory.difficulty));
        expect(result.intervalDays, greaterThanOrEqualTo(firstInterval));
        memory = result.memory;
      }
      expect(memory.stability, greaterThan(firstStability));
      expect(memory.reps, 4);
    });

    test('Easy 给的间隔比 Good 长，Again 会把稳定性打下来', () {
      final FsrsMemory base = scheduler
          .review(previous: null, rating: 3, reviewedAt: day1)
          .memory;
      final DateTime at = base.dueAt!;

      final FsrsReviewResult hard = scheduler.review(
          previous: base, rating: 2, reviewedAt: at);
      final FsrsReviewResult good = scheduler.review(
          previous: base, rating: 3, reviewedAt: at);
      final FsrsReviewResult easy = scheduler.review(
          previous: base, rating: 4, reviewedAt: at);
      final FsrsReviewResult again = scheduler.review(
          previous: base, rating: 1, reviewedAt: at);

      expect(hard.intervalDays, lessThan(good.intervalDays));
      expect(good.intervalDays, lessThan(easy.intervalDays));
      expect(again.memory.stability, lessThan(base.stability));
      expect(again.memory.lapses, 1);
    });

    test('同一天再答一次不会把稳定性算飞', () {
      final FsrsMemory base = scheduler
          .review(previous: null, rating: 3, reviewedAt: day1)
          .memory;

      final FsrsReviewResult sameDay = scheduler.review(
        previous: base,
        rating: 3,
        reviewedAt: day1.add(const Duration(hours: 3)),
      );
      expect(sameDay.elapsedDays, 0);
      // 同一天内的复习走 short-term 分支：Good / Easy 至少不减稳定性
      expect(sameDay.memory.stability, greaterThanOrEqualTo(base.stability));
      expect(sameDay.memory.reps, 2);
    });

    test('未到期的卡不改记忆状态，只是被跳过', () {
      final FsrsMemory memory = scheduler
          .review(previous: null, rating: 3, reviewedAt: day1)
          .memory;
      expect(scheduler.isDue(null, day1), isTrue, reason: '新卡要学');
      expect(scheduler.isDue(memory, day1), isFalse);
      expect(scheduler.isDue(memory, memory.dueAt!), isTrue);
    });

    test('到期的可提取度接近目标保留率', () {
      const FsrsConfig retention = FsrsConfig(
        enableFuzzing: false,
        desiredRetention: 0.9,
      );
      final FsrsScheduler s = FsrsScheduler(retention);
      final FsrsMemory memory =
          s.review(previous: null, rating: 3, reviewedAt: day1).memory;
      expect(s.retrievabilityOf(memory, day1), closeTo(1.0, 1e-6));
      expect(
        s.retrievabilityOf(memory, memory.dueAt!),
        closeTo(0.9, 0.02),
      );
      expect(
        s.retrievabilityOf(memory, memory.dueAt!.add(const Duration(days: 30))),
        lessThan(0.7),
      );
    });

    test('目标保留率越高，间隔越短', () {
      final FsrsScheduler low = FsrsScheduler(
          const FsrsConfig(enableFuzzing: false, desiredRetention: 0.8));
      final FsrsScheduler high = FsrsScheduler(
          const FsrsConfig(enableFuzzing: false, desiredRetention: 0.95));
      expect(
        low.review(previous: null, rating: 3, reviewedAt: day1).intervalDays,
        greaterThan(
          high.review(previous: null, rating: 3, reviewedAt: day1).intervalDays,
        ),
      );
    });
  });

  group('复习队列', () {
    final DateTime now = DateTime(2026, 3, 20, 8);

    WordCard withMemory(String id, String word, FsrsMemory memory) =>
        makeCard(id: id, word: word).copyWith(fsrs: memory);

    test('到期的排前面，越可能忘的越靠前，新词最后', () {
      final List<WordCard> cards = <WordCard>[
        makeCard(id: 'new', word: 'zebra'),
        withMemory(
          'old',
          'alpha',
          FsrsMemory(
            stability: 10,
            difficulty: 5,
            reps: 2,
            state: FsrsCardState.review,
            lastReviewAt: DateTime(2026, 1, 1),
            dueAt: DateTime(2026, 1, 11),
          ),
        ),
        withMemory(
          'fresh',
          'beta',
          FsrsMemory(
            stability: 100,
            difficulty: 5,
            reps: 2,
            state: FsrsCardState.review,
            lastReviewAt: now,
            dueAt: now.add(const Duration(days: 100)),
          ),
        ),
      ];

      final List<FsrsQueueItem> queue = buildFsrsQueue(cards, now: now);
      expect(
        queue.map((FsrsQueueItem item) => item.card.word).toList(),
        <String>['alpha', 'zebra', 'beta'],
      );
      expect(queue.first.due, isTrue);
      expect(queue.last.due, isFalse);
      // 78 天没复习、稳定性 10 天，可提取度已经掉到 0.69 上下
      expect(queue.first.retrievability, lessThan(0.75));
      expect(countFsrsDue(cards, now: now), 2);
    });

    test('includeNew = false 时把没学过的词排除掉', () {
      expect(
        buildFsrsQueue(
          <WordCard>[
            makeCard(id: 'n1', word: 'alpha'),
            makeCard(id: 'n2', word: 'beta'),
          ],
          now: now,
          includeNew: false,
        ),
        isEmpty,
      );
    });
  });

  group('存取', () {
    test('记忆状态跟着卡片走一遍 Map 不丢东西', () {
      final WordCard card = makeCard(id: 'c1').copyWith(
        fsrs: FsrsMemory(
          stability: 12.5,
          difficulty: 4.25,
          reps: 3,
          lapses: 1,
          state: FsrsCardState.review,
          lastReviewAt: DateTime(2026, 3, 1, 9),
          dueAt: DateTime(2026, 3, 13, 9),
        ),
      );
      final WordCard back = WordCard.fromMap(card.toMap());
      expect(back.fsrs!.stability, 12.5);
      expect(back.fsrs!.difficulty, 4.25);
      expect(back.fsrs!.reps, 3);
      expect(back.fsrs!.lapses, 1);
      expect(back.fsrs!.state, FsrsCardState.review);
      expect(back.fsrs!.dueAt, DateTime(2026, 3, 13, 9));
    });

    test('FSRS 状态存在自己的表里，不碰原来的掌握度', () async {
      final TestHarness harness = await TestHarness.create();
      addTearDown(harness.dispose);

      await harness.cards.upsert(
        makeCard(id: 'c1', word: 'abandon', mastery: 0.42, reviewCount: 3),
      );
      final WordCard before = (await harness.cards.getAll()).single;

      final FsrsReviewResult result = scheduler.review(
        previous: null,
        rating: 3,
        reviewedAt: day1,
      );
      await harness.cards.upsert(before.copyWith(fsrs: result.memory));

      final WordCard after = (await harness.cards.getAll()).single;
      expect(after.fsrs, isNotNull);
      expect(after.fsrs!.stability, closeTo(result.memory.stability, 1e-9));
      // 老字段一个都没变
      expect(after.mastery, before.mastery);
      expect(after.reviewCount, before.reviewCount);
      expect(after.easeFactor, before.easeFactor);
      expect(after.intervalDays, before.intervalDays);

      // 再写一次（不带 FSRS 状态）：旧状态留在表里，不会被清掉
      await harness.cards.upsert(after.copyWith(word: 'abandon'));
      final WordCard again = (await harness.cards.getAll()).single;
      expect(again.fsrs!.stability, closeTo(result.memory.stability, 1e-9));
      expect(again.mastery, before.mastery);
    });
  });
}
