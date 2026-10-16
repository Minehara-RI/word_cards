import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/logic/tone.dart';

/// 翻页提示音是现算的 wav，所以文件头和采样数必须自己保证对。
void main() {
  test('默认参数是 3000 Hz、0.5 秒、44.1 kHz 单声道 16 位', () {
    final Uint8List bytes = buildToneWav(frequencyHz: 3000, durationMs: 500);

    const int expectedSamples = 22050;
    expect(bytes.length, 44 + expectedSamples * 2);

    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');
    expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');

    final ByteData header = ByteData.sublistView(bytes, 0, 44);
    expect(header.getUint32(4, Endian.little), 36 + expectedSamples * 2);
    expect(header.getUint16(20, Endian.little), 1, reason: 'PCM');
    expect(header.getUint16(22, Endian.little), 1, reason: '单声道');
    expect(header.getUint32(24, Endian.little), 44100);
    expect(header.getUint32(28, Endian.little), 88200, reason: '每秒字节数');
    expect(header.getUint16(32, Endian.little), 2, reason: '块对齐');
    expect(header.getUint16(34, Endian.little), 16, reason: '位深');
    expect(header.getUint32(40, Endian.little), expectedSamples * 2);
  });

  test('波形真的是 3000 Hz：过零次数对得上', () {
    final Uint8List bytes = buildToneWav(
      frequencyHz: 3000,
      durationMs: 500,
      fadeMs: 1,
    );
    final ByteData data = ByteData.sublistView(bytes, 44);

    int crossings = 0;
    int? previous;
    for (int i = 0; i < 22050; i++) {
      final int value = data.getInt16(i * 2, Endian.little);
      if (previous != null &&
          ((previous < 0 && value >= 0) || (previous >= 0 && value < 0))) {
        crossings++;
      }
      previous = value;
    }
    // 3000 Hz 持续 0.5 秒 = 1500 个周期，每周期两次过零。
    expect(crossings, inInclusiveRange(2998, 3002));
  });

  test('时长可参数化', () {
    final Uint8List bytes = buildToneWav(frequencyHz: 1000, durationMs: 200);
    expect(bytes.length, 44 + (44100 * 200 / 1000).round() * 2);
  });

  test('首尾做了淡入淡出，不会爆音', () {
    final Uint8List bytes = buildToneWav(frequencyHz: 3000, durationMs: 500);
    final ByteData data = ByteData.sublistView(bytes, 44);
    expect(data.getInt16(0, Endian.little), 0);
    expect(data.getInt16(22050 * 2 - 2, Endian.little).abs() < 300, isTrue);

    int peak = 0;
    for (int i = 0; i < 22050; i++) {
      final int value = data.getInt16(i * 2, Endian.little).abs();
      if (value > peak) peak = value;
    }
    // 振幅取 0.35，满量程 32767 -> 大约 11468。
    expect(peak, inInclusiveRange(9000, 12000));
  });
}
