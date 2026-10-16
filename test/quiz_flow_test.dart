import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/state/quiz_controller.dart';
import 'package:word_cards/src/ui/pages/quiz_page.dart';

import 'support/test_harness.dart';

/// 直接把测验页挂起来并自动开一轮。
class _QuizHost extends ConsumerStatefulWidget {
  const _QuizHost();

  @override
  ConsumerState<_QuizHost> createState() => _QuizHostState();
}

class _QuizHostState extends ConsumerState<_QuizHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(quizControllerProvider.notifier).start(questionCount: 1);
    });
  }

  @override
  Widget build(BuildContext context) => const QuizPage();
}

void useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('点对正确选项给出反馈，并自动进入成绩单', (tester) async {
    useLargeSurface(tester);
    final harness = TestHarness.fake();
    await harness.cards.upsert(makeCard(id: 'c1', word: 'abandon'));

    await tester.pumpWidget(
      harness.wrap(const MaterialApp(home: _QuizHost())),
    );
    await tester.pumpAndSettle();

    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('第 1 / 1 题'), findsOneWidget);

    await tester.tap(find.text('v. 放弃；抛弃'));
    await tester.pump();

    expect(find.text('答对了'), findsOneWidget);

    // 自动翻页（850ms）之后是成绩单
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(find.text('正确率'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    final records = await harness.records.getAll();
    expect(records, hasLength(1));
    expect(records.single.correct, isTrue);
    expect(records.single.cardId, 'c1');
  });

  testWidgets('点错时高亮正确释义并提示', (tester) async {
    useLargeSurface(tester);
    final harness = TestHarness.fake();
    await harness.cards.upsert(makeCard(id: 'c1', word: 'abandon'));

    await tester.pumpWidget(
      harness.wrap(const MaterialApp(home: _QuizHost())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('v. 遵守；坚持'));
    await tester.pump();

    expect(find.textContaining('答错了'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(find.text('0%'), findsOneWidget);
    final records = await harness.records.getAll();
    expect(records.single.correct, isFalse);
    expect(records.single.selected, 'v. 遵守；坚持');
    expect(records.single.expected, 'v. 放弃；抛弃');
  });
}
