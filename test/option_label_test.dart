import 'package:flutter_test/flutter_test.dart';
import 'package:word_flashcards/src/domain/models/app_settings.dart';

/// 演示模式的选项编号可以选 12345 或 ABCDE。
void main() {
  test('12345 模式从 1 开始编号', () {
    expect(OptionLabelStyle.number.labelFor(0), '1');
    expect(OptionLabelStyle.number.labelFor(4), '5');
  });

  test('ABCDE 模式给字母', () {
    expect(OptionLabelStyle.letter.labelFor(0), 'A');
    expect(OptionLabelStyle.letter.labelFor(4), 'E');
  });

  test('超过 26 个选项会绕回字母表开头，不会崩', () {
    expect(OptionLabelStyle.letter.labelFor(26), 'A');
  });

  test('编号样式能存能读，坏值退回 12345', () {
    const AppSettings settings = AppSettings(
      projectionOptionLabelStyle: OptionLabelStyle.letter,
    );
    expect(
      AppSettings.fromMap(settings.toMap()).projectionOptionLabelStyle,
      OptionLabelStyle.letter,
    );
    expect(OptionLabelStyle.fromId('letter'), OptionLabelStyle.letter);
    expect(OptionLabelStyle.fromId('nonsense'), OptionLabelStyle.number);
  });

  test('默认是 12345', () {
    expect(
      const AppSettings().projectionOptionLabelStyle,
      OptionLabelStyle.number,
    );
  });
}
