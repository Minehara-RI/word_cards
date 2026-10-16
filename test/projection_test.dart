import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/data/audio/beep_player.dart';
import 'package:word_cards/src/data/export/answer_sheet_service.dart';
import 'package:word_cards/src/domain/models/app_settings.dart';
import 'package:word_cards/src/domain/models/word_card.dart';
import 'package:word_cards/src/logic/quiz.dart';
import 'package:word_cards/src/state/projection_controller.dart';
import 'package:word_cards/src/state/providers.dart';

import 'support/test_harness.dart';

/// 只记次数，不真的发声。
class _CountingSound implements PageTurnSound {
  int count = 0;

  @override
  Future<void> playPageTurn() async => count++;

  @override
  Future<void> dispose() async {}
}

/// 只记下被要求写了哪些题，不真的落盘。
class _RecordingAnswerSheet extends AnswerSheetService {
  final List<List<QuizQuestion>> calls = <List<QuizQuestion>>[];

  @override
  Future<AnswerSheet> write({
    required List<QuizQuestion> questions,
    required String deckName,
    required int intervalSeconds,
    required OptionLabelStyle labelStyle,
    required AnswerSheetMode mode,
    String? customDirectory,
    DateTime? now,
  }) async {
    calls.add(questions);
    return AnswerSheet(path: '/fake/answer.txt', questions: questions.length);
  }
}

/// 演示模式是「拿来做题的」：一个单词五个选项，全屏展示、屏幕点不了，
/// 每道题有停留限时，到点自动换下一题；翻页时响一次提示音。
/// **全程不显示答案**，结束后把答案写进一份 txt。
void main() {
  late _CountingSound sound;
  late _RecordingAnswerSheet sheets;
  late int soundLookups;

  Future<void> withProjection(
    WidgetTester tester,
    Future<void> Function(ProviderContainer container) body,
  ) async {
    sound = _CountingSound();
    sheets = _RecordingAnswerSheet();
    soundLookups = 0;
    final ProviderContainer container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWithValue(const AppSettings()),
        pageTurnSoundProvider.overrideWith((ref) {
          soundLookups++;
          return sound;
        }),
        answerSheetServiceProvider.overrideWithValue(sheets),
      ],
    );
    await tester.pumpWidget(const SizedBox.shrink());
    try {
      await body(container);
    } finally {
      container.dispose();
    }
  }

  ProjectionController controllerOf(ProviderContainer container) =>
      container.read(projectionControllerProvider.notifier);

  ProjectionState stateOf(ProviderContainer container) =>
      container.read(projectionControllerProvider);

  String wordOf(ProviderContainer container) =>
      stateOf(container).current!.card.word;

  List<WordCard> threeCards() => <WordCard>[
        makeCard(id: 'c1', word: 'alpha', definition: 'n. 第一个'),
        makeCard(id: 'c2', word: 'beta', definition: 'n. 第二个'),
        makeCard(id: 'c3', word: 'gamma', definition: 'n. 第三个'),
      ];

  testWidgets('每道题都有硬性限时，到点自动翻页', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(threeCards(), intervalSeconds: 2, loop: false);

      ProjectionState state = stateOf(container);
      expect(state.status, ProjectionStatus.running);
      expect(wordOf(container), 'alpha');
      expect(state.intervalMs, 2000);
      expect(state.remainingMs, 2000);
      expect(state.total, 3);

      await tester.pump(const Duration(seconds: 1));
      state = stateOf(container);
      expect(wordOf(container), 'alpha');
      expect(state.remainingMs, 1000);
      expect(state.remainingSeconds, 1);

      await tester.pump(const Duration(seconds: 1));
      state = stateOf(container);
      expect(wordOf(container), 'beta');
      expect(state.remainingMs, 2000, reason: '新的题倒计时重新开始');

      await tester.pump(const Duration(seconds: 2));
      expect(wordOf(container), 'gamma');

      await tester.pump(const Duration(seconds: 2));
      state = stateOf(container);
      expect(state.status, ProjectionStatus.finished);
      expect(state.remainingMs, 0);
      expect(sound.count, 2, reason: '只在 alpha->beta、beta->gamma 两次翻页时响');
    });
  });

  testWidgets('和测验一样是五选一，正确项有明确下标', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(threeCards(), intervalSeconds: 30);

      final ProjectionState state = stateOf(container);
      expect(state.options, hasLength(5));
      expect(state.options.toSet(), hasLength(5), reason: '选项不能重复');
      expect(state.correctIndex, inInclusiveRange(0, 4));
      expect(
        state.options[state.correctIndex],
        state.current!.card.definition,
        reason: '正确项就是这张卡的释义',
      );
      expect(state.questions.every((QuizQuestion q) => q.options.length == 5), isTrue);
    });
  });

  testWidgets('翻页时播提示音，手动翻页也算', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(
        threeCards(),
        intervalSeconds: 1,
        loop: true,
        announcePageTurns: true,
      );

      expect(sound.count, 0, reason: '开始显示第一题不算翻页');
      expect(soundLookups, 1, reason: '开着提示音才去拿播放器');

      await tester.pump(const Duration(seconds: 1));
      expect(sound.count, 1);

      controllerOf(container).next();
      expect(sound.count, 2);
      controllerOf(container).previous();
      expect(sound.count, 3);
    });
  });

  testWidgets('关掉提示音就完全不去碰音频', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(
        threeCards(),
        intervalSeconds: 5,
        loop: true,
        announcePageTurns: false,
      );

      await tester.pump(const Duration(seconds: 3));
      expect(soundLookups, 0, reason: '关掉时不应该创建播放器');
      expect(sound.count, 0);
      expect(wordOf(container), 'alpha');
    });
  });

  testWidgets('循环播放会绕回第一题并记轮次', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(threeCards(), intervalSeconds: 1, loop: true);

      await tester.pump(const Duration(seconds: 3));
      final ProjectionState state = stateOf(container);
      expect(state.status, ProjectionStatus.running);
      expect(wordOf(container), 'alpha');
      expect(state.loops, 1);
      expect(sound.count, 3);
    });
  });

  testWidgets('每轮重新打乱选项：绕回时题目会重建，词一个不少', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(
        threeCards(),
        intervalSeconds: 1,
        loop: true,
        reshuffleEachRound: true,
      );

      final List<QuizQuestion> firstRound = stateOf(container).questions;
      await tester.pump(const Duration(seconds: 3));

      final List<QuizQuestion> secondRound = stateOf(container).questions;
      expect(identical(firstRound, secondRound), isFalse,
          reason: '第二轮应该重新出题（选项顺序重新排）');
      expect(
        secondRound.map((QuizQuestion q) => q.card.word).toSet(),
        firstRound.map((QuizQuestion q) => q.card.word).toSet(),
        reason: '重新打乱只是换顺序，题不能丢',
      );
      expect(stateOf(container).loops, 1);
    });
  });

  testWidgets('关掉每轮重排时，绕回后沿用同一份题', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(
        threeCards(),
        intervalSeconds: 1,
        loop: true,
        reshuffleEachRound: false,
      );

      final List<QuizQuestion> firstRound = stateOf(container).questions;
      await tester.pump(const Duration(seconds: 3));
      expect(identical(firstRound, stateOf(container).questions), isTrue);
    });
  });

  testWidgets('暂停后计时不再推进，继续后恢复', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(threeCards(), intervalSeconds: 2, loop: true);

      controllerOf(container).togglePause();
      expect(stateOf(container).paused, isTrue);

      await tester.pump(const Duration(seconds: 5));
      final ProjectionState paused = stateOf(container);
      expect(wordOf(container), 'alpha');
      expect(paused.remainingMs, 2000, reason: '暂停期间不该扣时间');
      expect(sound.count, 0);

      controllerOf(container).togglePause();
      await tester.pump(const Duration(seconds: 2));
      expect(wordOf(container), 'beta');
    });
  });

  testWidgets('不循环放完最后一题：结束并写一份答案文件', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(
        threeCards(),
        intervalSeconds: 1,
        loop: false,
        deckName: '考研词汇',
      );

      expect(sheets.calls, isEmpty);
      await tester.pump(const Duration(seconds: 3));
      expect(stateOf(container).status, ProjectionStatus.finished);

      // 写文件是异步的，让微任务跑完
      await tester.pump();
      expect(sheets.calls, hasLength(1));
      expect(sheets.calls.single, hasLength(3));
    });
  });

  testWidgets('中途退出也会写答案，而且同一轮只写一次', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(
        threeCards(),
        intervalSeconds: 5,
        loop: true,
        deckName: '考研词汇',
      );

      await tester.pump(const Duration(seconds: 1));
      controllerOf(container).stop();
      await tester.pump();
      expect(sheets.calls, hasLength(1));

      // 再停一次不该重复写
      controllerOf(container).stop();
      await tester.pump();
      expect(sheets.calls, hasLength(1));
    });
  });

  testWidgets('没卡片时不写任何文件', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(
        const <WordCard>[],
        intervalSeconds: 5,
        loop: true,
      );
      expect(stateOf(container).status, ProjectionStatus.empty);
      controllerOf(container).stop();
      await tester.pump();
      expect(sheets.calls, isEmpty);
    });
  });

  testWidgets('随机播放只是换了顺序，题一个不少', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(
        threeCards(),
        intervalSeconds: 30,
        shuffle: true,
      );
      final List<String> words = stateOf(container)
          .questions
          .map((QuizQuestion question) => question.card.word)
          .toList();
      expect(words.toSet(), <String>{'alpha', 'beta', 'gamma'});
    });
  });

  testWidgets('不循环时在第一题上往前翻没有反应', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(threeCards(), intervalSeconds: 5, loop: false);
      controllerOf(container).previous();
      expect(wordOf(container), 'alpha');
      expect(sound.count, 0);
    });
  });

  testWidgets('演示状态里没有任何「显示答案」的开关', (tester) async {
    await withProjection(tester, (ProviderContainer container) async {
      controllerOf(container).start(threeCards(), intervalSeconds: 5);
      // 编译期就没有 toggleAnswer / answerRevealed 了；
      // 这里再确认一遍选项内容不会自己变成「已揭晓」的样子。
      expect(stateOf(container).options, hasLength(5));
      expect(stateOf(container).correctIndex, inInclusiveRange(0, 4));
    });
  });
}
