// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../logic/tone.dart';

/// 演示模式翻页时的声音提示。
///
/// 抽成接口是为了两件事：测试里能塞一个只记次数的假实现，
/// 以及用户把提示音关掉时可以换成静音实现。
abstract interface class PageTurnSound {
  Future<void> playPageTurn();

  Future<void> dispose();
}

/// 静音实现。
class SilentPageTurnSound implements PageTurnSound {
  const SilentPageTurnSound();

  @override
  Future<void> playPageTurn() async {}

  @override
  Future<void> dispose() async {}
}

/// 真正会出声的翻页提示音，支持两种来源：
///
/// - **内置**：按设定的频率与时长现算一段正弦波 WAV（默认 3000 Hz / 0.5 秒），
///   仓库里不带任何音频资源
/// - **自选**：用户自己挑一个音频文件，用哪个文件由上层配置决定
///
/// 自选文件不见了（被删/被清缓存）就自动退回内置提示音，
/// 保证讲课时不会突然没声音；彻底播不了时静默降级，绝不打断演示。
class AudioPageTurnSound implements PageTurnSound {
  AudioPageTurnSound({
    this.frequencyHz = 3000,
    this.durationMs = 500,
    this.sampleRate = 44100,
    this.customPath,
  });

  final int frequencyHz;
  final int durationMs;
  final int sampleRate;

  /// 自选音频的路径；为空表示用内置提示音。
  final String? customPath;

  AudioPlayer? _player;
  bool _unavailable = false;

  /// 自选文件是否真的存在。界面用它给出提示。
  bool get customFileAvailable {
    final String? path = customPath;
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  /// 最终会用到自选音频（而不是退回内置提示音）。
  bool get usesCustomFile => customFileAvailable;

  @override
  Future<void> playPageTurn() async {
    if (_unavailable) return;
    try {
      final AudioPlayer player = await _ensurePlayer();
      await player.stop();
      await player.resume();
    } catch (_) {
      // 没有音频设备、插件不可用等等，都不该打断演示。
      _unavailable = true;
      await _disposePlayer();
    }
  }

  Future<AudioPlayer> _ensurePlayer() async {
    final AudioPlayer? current = _player;
    if (current != null) return current;

    final AudioPlayer player = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(DeviceFileSource(await resolveSourcePath()));
    _player = player;
    return player;
  }

  /// 决定这次播放哪个文件。测试里可以直接验它。
  Future<String> resolveSourcePath() async {
    final String? path = customPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return path;
    }

    final Directory directory = await getTemporaryDirectory();
    final String name =
        'wc_beep_' + frequencyHz.toString() + '_' + durationMs.toString() + '.wav';
    final File file = File(p.join(directory.path, name));
    if (!file.existsSync() || file.lengthSync() == 0) {
      await file.writeAsBytes(
        buildToneWav(
          frequencyHz: frequencyHz,
          durationMs: durationMs,
          sampleRate: sampleRate,
        ),
        flush: true,
      );
    }
    return file.path;
  }

  @override
  Future<void> dispose() => _disposePlayer();

  Future<void> _disposePlayer() async {
    final AudioPlayer? player = _player;
    _player = null;
    try {
      await player?.dispose();
    } catch (_) {
      // 关不掉也无所谓。
    }
  }
}
