import 'dart:math';
import 'dart:typed_data';

/// 生成一个 16 位单声道 PCM 的 WAV 文件内容。
///
/// 演示模式翻页时的提示音就是用它现算出来的：3000 Hz、0.5 秒。
/// 做成纯函数是为了能在单元测试里直接检查采样数和文件头。
Uint8List buildToneWav({
  required int frequencyHz,
  required int durationMs,
  int sampleRate = 44100,
  double amplitude = 0.35,
  int fadeMs = 12,
}) {
  final int sampleCount = (sampleRate * durationMs / 1000).round();
  final int fadeSamples = max(1, (sampleRate * fadeMs / 1000).round());
  final ByteData samples = ByteData(sampleCount * 2);

  for (int i = 0; i < sampleCount; i++) {
    double envelope = 1;
    if (i < fadeSamples) {
      envelope = i / fadeSamples;
    }
    final int fromEnd = sampleCount - 1 - i;
    if (fromEnd < fadeSamples) {
      envelope = min(envelope, fromEnd / fadeSamples);
    }
    final double value =
        sin(2 * pi * frequencyHz * i / sampleRate) * amplitude * envelope;
    final int quantized = (value * 32767).round().clamp(-32768, 32767);
    samples.setInt16(i * 2, quantized, Endian.little);
  }

  const int headerBytes = 44;
  final int dataBytes = sampleCount * 2;
  final ByteData header = ByteData(headerBytes);

  void ascii(int offset, String text) {
    for (int i = 0; i < text.length; i++) {
      header.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, dataBytes, Endian.little);

  final Uint8List result = Uint8List(headerBytes + dataBytes);
  result.setRange(0, headerBytes, header.buffer.asUint8List());
  result.setRange(headerBytes, headerBytes + dataBytes, samples.buffer.asUint8List());
  return result;
}
