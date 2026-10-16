import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:word_cards/src/data/audio/beep_player.dart';

/// 翻页提示音可以换成用户自选的音频；文件不在了要能自动退回内置提示音。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('自选音频存在时就用它', () async {
    final Directory dir = Directory.systemTemp.createTempSync('wc_sound');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File file = File(p.join(dir.path, 'my-turn.mp3'));
    await file.writeAsBytes(<int>[1, 2, 3]);

    final AudioPageTurnSound sound = AudioPageTurnSound(customPath: file.path);
    expect(sound.customFileAvailable, isTrue);
    expect(sound.usesCustomFile, isTrue);
    expect(await sound.resolveSourcePath(), file.path);
  });

  test('自选音频不见了就退回内置提示音', () async {
    final AudioPageTurnSound sound = AudioPageTurnSound(
      customPath: p.join(Directory.systemTemp.path, 'definitely-missing.mp3'),
      frequencyHz: 2000,
      durationMs: 250,
    );
    expect(sound.customFileAvailable, isFalse);
    expect(sound.usesCustomFile, isFalse);
  });

  test('退回内置提示音时，现算出的 wav 文件名带上频率与时长', () async {
    const MethodChannel channel =
        MethodChannel('plugins.flutter.io/path_provider');
    final Directory dir = Directory.systemTemp.createTempSync('wc_sound_out');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => dir.path);

    final AudioPageTurnSound sound = AudioPageTurnSound(
      frequencyHz: 2000,
      durationMs: 250,
    );
    final String path = await sound.resolveSourcePath();
    expect(p.basename(path), 'wc_beep_2000_250.wav');
    expect(File(path).lengthSync(), 44 + (44100 * 250 / 1000).round() * 2);
  });
}
