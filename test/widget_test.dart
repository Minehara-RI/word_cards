// 占位：真正的测试见 test/ 下的各 *_test.dart。
// 这里放一条最基础的冒烟测试，保证 `flutter test` 始终有东西可跑。

import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/data/import/card_parser.dart';

void main() {
  test('解析器能处理最小卡片', () {
    final result = const CardParser().parse(
      '{"word":"abandon","definition":"v. 放弃","distractors":["v. 遵守"]}',
    );
    expect(result.cards, hasLength(1));
    expect(result.cards.first.word, 'abandon');
  });
}
