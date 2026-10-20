import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/ui/pages/import_page.dart';

import 'support/test_harness.dart';

const String kGoodJson = '''
[{"word":"abandon","definition":"v. 放弃；抛弃","distractors":["v. 遵守","v. 维持","v. 增加","v. 分配"]},
 {"word":"meticulous","definition":"adj. 一丝不苟的","distractors":["adj. 漫不经心的","adj. 慷慨的","adj. 沉默的","adj. 固执的"]}]
''';

/// 把测试画布调大，保证 ListView 里的控件都被真正构建出来。
void useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('粘贴合法 JSON 后实时预览可以导入', (tester) async {
    useLargeSurface(tester);
    final harness = TestHarness.fake();

    await tester.pumpWidget(
      harness.wrap(const MaterialApp(home: ImportPage())),
    );
    await tester.pumpAndSettle();

    // 一开始是空状态提示
    expect(find.textContaining('粘贴后会自动校验'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('import-json-field')),
      kGoodJson,
    );
    // 等防抖 + 重建
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('解析成功：2 张卡片'), findsOneWidget);
    // 注意：单词输入框的 hint 就是 "abandon"，所以这里用只可能出现在预览里的内容断言
    expect(find.text('meticulous'), findsOneWidget);
    expect(find.text('adj. 一丝不苟的'), findsOneWidget);
    expect(find.text('v. 放弃；抛弃'), findsOneWidget);

    // 「直接加入卡组」给了两个选择：合并到当前卡组 / 放入新卡组
    expect(find.text('放入新卡组…'), findsOneWidget);
    await tester.tap(find.text('合并到当前卡组（2 张）'));
    await tester.pumpAndSettle();

    expect(find.text('导入完成'), findsOneWidget);
    expect(find.text('成功导入 2 张'), findsOneWidget);

    await tester.tap(find.text('继续导入'));
    await tester.pumpAndSettle();

    final stored = await harness.cards.getAll();
    expect(stored, hasLength(2));
  });

  testWidgets('非法 JSON 给出具体位置提示', (tester) async {
    useLargeSurface(tester);
    final harness = TestHarness.fake();

    await tester.pumpWidget(
      harness.wrap(const MaterialApp(home: ImportPage())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('import-json-field')),
      '[{"word":"a","definition":"甲","distractors":["乙"]},{"word":"b","distractors":["丁"]}]',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // 好的那张仍然可导入，坏的那张明确告知是第 2 张缺 definition
    expect(find.textContaining('解析成功：1 张卡片'), findsOneWidget);
    expect(find.textContaining('第 2 张卡片'), findsOneWidget);
    expect(find.textContaining('definition'), findsWidgets);
  });
  testWidgets('粘贴超长 JSON：原文不进输入框，但照样能解析和导入', (tester) async {
    useLargeSurface(tester);
    final harness = TestHarness.fake();

    await tester.pumpWidget(
      harness.wrap(const MaterialApp(home: ImportPage())),
    );
    await tester.pumpAndSettle();

    // 900 张卡约 6 万字符：正经的批量导入量级，但远超输入框能渲染的上限。
    // 直接塞进 TextField 会让 Flutter 把整段文本排一次版（实测 37 万字符
    // 就要 250 MB 内存、卡两秒多），所以这里必须挡住。
    final buffer = StringBuffer('[');
    for (var i = 1; i <= 900; i++) {
      if (i > 1) buffer.write(',');
      buffer.write('{"word":"w$i","definition":"释义 $i","distractors":["甲$i","乙$i","丙$i"]}');
    }
    buffer.write(']');
    final String big = buffer.toString();
    expect(big.length, greaterThan(24000));

    await tester.enterText(find.byKey(const Key('import-json-field')), big);
    await tester.pump();
    await tester.pumpAndSettle();

    // 原文留在状态里，输入框保持空
    final TextField field =
        tester.widget<TextField>(find.byKey(const Key('import-json-field')));
    expect(field.controller!.text, isEmpty);
    expect(find.textContaining('没有放进输入框'), findsOneWidget);
    expect(find.textContaining('900 张卡片'), findsWidgets);

    // 解析结果照常可用，导入用的也是完整原文
    expect(find.textContaining('解析成功：900 张卡片'), findsOneWidget);
    await tester.tap(find.text('合并到当前卡组（900 张）'));
    await tester.pumpAndSettle();
    expect(find.text('导入完成'), findsOneWidget);

    await tester.tap(find.text('继续导入'));
    await tester.pumpAndSettle();
    expect(await harness.cards.getAll(), hasLength(900));
  });
}
