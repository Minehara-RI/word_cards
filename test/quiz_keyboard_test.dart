// 阶段二：桌面端用键盘作答（数字键 1-5 / A-E 选答、Enter 下一题、Esc 退出本轮）。
//
// 键盘只挂在桌面端，而 flutter test 是跑在桌面宿主上的，
// 所以这里走的就是「键盘开着」那条路。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/domain/models/word_card.dart';
import 'package:word_cards/src/state/quiz_controller.dart';
import 'package:word_cards/src/ui/pages/quiz_page.dart';
import 'package:word_cards/src/ui/quiz_keys.dart';

import 'support/test_harness.dart';

/// 桌面上第 N 个选项对应的键：数字键和字母键各一套，用例里按下标取。
const List<LogicalKeyboardKey> kQuizDigits = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
];

const List<LogicalKeyboardKey> kQuizLetters = <LogicalKeyboardKey>[
  LogicalKeyboardKey.keyA,
  LogicalKeyboardKey.keyB,
  LogicalKeyboardKey.keyC,
  LogicalKeyboardKey.keyD,
  LogicalKeyboardKey.keyE,
];

/// 直接把测验页挂起来；哪一轮由每个用例自己开。
class _QuizHost extends ConsumerStatefulWidget {
  const _QuizHost();

  @override
  ConsumerState<_QuizHost> createState() => _QuizHostState();
}

class _QuizHostState extends ConsumerState<_QuizHost> {
  @override
  Widget build(BuildContext context) => const QuizPage();
}

/// 首页放一个按钮，测验页是 push 上去的：
/// 只有这样才能验出 Esc 是不是真的退出了这一轮。
class _Launcher extends StatelessWidget {
  const _Launcher();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const QuizPage()),
            ),
            child: const Text('开始'),
          ),
        ),
      );
}

void useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('按键映射', () {
    test('数字键 1-5 与小键盘 1-5 都映射到选项下标', () {
      expect(quizOptionIndexForKey(LogicalKeyboardKey.digit1), 0);
      expect(quizOptionIndexForKey(LogicalKeyboardKey.digit5), 4);
      expect(quizOptionIndexForKey(LogicalKeyboardKey.numpad3), 2);
    });

    test('字母键 A-E 映射到选项下标', () {
      expect(quizOptionIndexForKey(LogicalKeyboardKey.keyA), 0);
      expect(quizOptionIndexForKey(LogicalKeyboardKey.keyE), 4);
    });

    test('不认识的键一律不认', () {
      expect(quizOptionIndexForKey(LogicalKeyboardKey.digit6), isNull);
      expect(quizOptionIndexForKey(LogicalKeyboardKey.keyF), isNull);
      expect(quizOptionIndexForKey(LogicalKeyboardKey.space), isNull);
    });

    test('Enter 与 Esc 各自只认自家那几个键', () {
      expect(isQuizNextKey(LogicalKeyboardKey.enter), isTrue);
      expect(isQuizNextKey(LogicalKeyboardKey.numpadEnter), isTrue);
      expect(isQuizNextKey(LogicalKeyboardKey.tab), isFalse);
      expect(isQuizExitKey(LogicalKeyboardKey.escape), isTrue);
      expect(isQuizExitKey(LogicalKeyboardKey.enter), isFalse);
    });

    test('选项最多 5 个，正好用完数字键', () {
      expect(kMaxQuizOptions, 5);
    });
  });

  Future<ProviderContainer> bootQuiz(
    WidgetTester tester,
    TestHarness harness, {
    List<WordCard>? cards,
    int questionCount = 1,
  }) async {
    useLargeSurface(tester);
    await harness.cards.upsertAll(
      cards ?? <WordCard>[makeCard(id: 'c1', word: 'abandon')],
    );

    await tester.pumpWidget(harness.wrap(const MaterialApp(home: _QuizHost())));
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(QuizPage)),
    );
    await container
        .read(quizControllerProvider.notifier)
        .start(questionCount: questionCount, shuffle: false);
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('数字键选答：按对了就跟点它一样，并落库', (tester) async {
    final harness = TestHarness.fake();
    final container = await bootQuiz(tester, harness);

    // 桌面端会画一行键盘提示，且只报本题真实存在的键
    expect(find.textContaining('键盘：1-5 或 A-E 选答'), findsOneWidget);

    final int correctIndex =
        container.read(quizControllerProvider).current!.correctIndex;
    await tester.sendKeyEvent(kQuizDigits[correctIndex]);
    await tester.pump();

    expect(find.text('答对了'), findsOneWidget);
    final records = await harness.records.getAll();
    expect(records, hasLength(1));
    expect(records.single.selected, 'v. 放弃；抛弃');
    expect(records.single.correct, isTrue);

    // 自动翻页后是成绩单
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(find.text('正确率'), findsOneWidget);
  });

  testWidgets('字母键与数字键等价', (tester) async {
    final harness = TestHarness.fake();
    final container = await bootQuiz(tester, harness);

    final int correctIndex =
        container.read(quizControllerProvider).current!.correctIndex;
    await tester.sendKeyEvent(kQuizLetters[correctIndex]);
    await tester.pump();

    expect(find.text('答对了'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(await harness.records.getAll(), hasLength(1));
  });

  testWidgets('答错的键也认；没作答时 Enter 不会被当成跳过', (tester) async {
    final harness = TestHarness.fake();
    final container = await bootQuiz(
      tester,
      harness,
      cards: sampleCards(),
      questionCount: 2,
    );

    // 还没选就按 Enter：原地不动，也不该多出记录
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    var state = container.read(quizControllerProvider);
    expect(state.index, 0);
    expect(state.isAnswered, isFalse);
    expect(await harness.records.getAll(), isEmpty);

    // 按一个错的键：照样记一笔错题
    final int correctIndex = state.current!.correctIndex;
    final int wrongIndex = correctIndex == 0 ? 1 : 0;
    await tester.sendKeyEvent(kQuizDigits[wrongIndex]);
    await tester.pump();
    expect(find.textContaining('答错了'), findsOneWidget);
    expect((await harness.records.getAll()).single.correct, isFalse);

    // 答完按 Enter：不用等自动翻页，立刻到第 2 题
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    state = container.read(quizControllerProvider);
    expect(state.index, 1);
    expect(state.isAnswered, isFalse);
    expect(await harness.records.getAll(), hasLength(1));
    expect(find.text('第 2 / 2 题'), findsOneWidget);

    // 把第 2 题答掉，别留一个还在跑的倒计时
    final int secondCorrect =
        container.read(quizControllerProvider).current!.correctIndex;
    await tester.sendKeyEvent(kQuizDigits[secondCorrect]);
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(find.text('正确率'), findsOneWidget);
    expect(await harness.records.getAll(), hasLength(2));
  });

  testWidgets('越界的键被吃掉：本题 4 个选项时按 5 不生效', (tester) async {
    final harness = TestHarness.fake();
    final container = await bootQuiz(
      tester,
      harness,
      cards: <WordCard>[
        makeCard(
          id: 'c1',
          word: 'abandon',
          distractors: <String>['v. 遵守；坚持', 'v. 维持；供养', 'v. 分配；指派'],
        ),
      ],
    );

    expect(container.read(quizControllerProvider).current!.options, hasLength(4));
    expect(find.textContaining('键盘：1-4 或 A-D 选答'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pump();

    expect(container.read(quizControllerProvider).isAnswered, isFalse);
    expect(await harness.records.getAll(), isEmpty);
  });

  testWidgets('Esc 退出本轮，回到进来那一页', (tester) async {
    useLargeSurface(tester);
    final harness = TestHarness.fake();
    await harness.cards.upsertAll(sampleCards());

    await tester.pumpWidget(harness.wrap(const MaterialApp(home: _Launcher())));
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();
    expect(find.byType(QuizPage), findsOneWidget);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(QuizPage)),
    );
    await container
        .read(quizControllerProvider.notifier)
        .start(questionCount: 3, shuffle: false);
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 3 题'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(QuizPage), findsNothing);
    expect(find.text('开始'), findsOneWidget);
    // 退出只是不再往下答，已经答过的部分不算
    expect(await harness.records.getAll(), isEmpty);
  });
}
