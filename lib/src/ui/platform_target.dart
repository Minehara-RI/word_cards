import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// 运行平台的大类。
///
/// **只允许 UI 层使用**：逻辑层与数据层不得出现任何平台判断，
/// 否则将来加 iOS / 鸿蒙时会被迫改共享代码。
enum PlatformTarget {
  mobile('移动端'),
  desktop('桌面端');

  const PlatformTarget(this.label);

  final String label;

  bool get isDesktop => this == PlatformTarget.desktop;
  bool get isMobile => this == PlatformTarget.mobile;
}

PlatformTarget detectPlatformTarget() {
  if (kIsWeb) return PlatformTarget.desktop;
  if (Platform.isAndroid || Platform.isIOS) return PlatformTarget.mobile;
  return PlatformTarget.desktop;
}

/// 能不能开「独立的演示窗口」。
///
/// 三个条件都要满足：
/// - 桌面系统（Windows / macOS / Linux 才有 desktop_multi_window）；
/// - 不是在 flutter test / integration_test 里跑（测试环境没有多窗口插件，
///   硬试会卡在平台通道上），测试统一走应用内全屏演示页那条路；
/// - 不是 Web。
bool supportsPresentationWindow() {
  if (kIsWeb) return false;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
  if (Platform.environment.containsKey('FLUTTER_TEST_DEVICE')) return false;
  return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}
