// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'presentation_frame.dart';
import 'presentation_view.dart';
import 'presentation_win32.dart';

/// 主窗口和演示窗口之间的控制通道名。
const String kPresentationChannelName = 'word_cards/presentation';

/// 演示窗口里的控制动作（演示窗口 -> 主窗口）。
const String kControlPrevious = 'previous';
const String kControlNext = 'next';
const String kControlPause = 'pause';
const String kControlExit = 'exit';

/// 演示窗口：单独一个 Flutter 引擎 + 单独一个系统窗口，强制最大化。
///
/// 主窗口仍然是唯一的「真相来源」：它算好每一帧推过来，这里只负责画；
/// 按键则原样回传给主窗口处理，所以暂停、翻页、答案 txt 都还是主窗口在管。
class PresentationWindow {
  PresentationWindow._(this.controller, this.payload);

  final WindowController controller;
  final PresentationWindowPayload payload;

  /// 当前引擎是演示窗口时返回实例；主窗口（或不是多窗口环境）返回 null。
  static Future<PresentationWindow?> bootstrap() async {
    try {
      final WindowController controller =
          await WindowController.fromCurrentEngine();
      final PresentationWindowPayload? payload =
          PresentationWindowPayload.tryDecode(controller.arguments);
      if (payload == null) return null;
      return PresentationWindow._(controller, payload);
    } catch (_) {
      // 手机、单元测试、插件不可用：都当普通主窗口
      return null;
    }
  }

  Future<void> run() async {
    // 演示窗口不给缩回去：开机就最大化（Win32 直接调，见 presentation_win32.dart）。
    PresentationWin32.maximize();
    runApp(PresentationWindowApp(controller: controller, payload: payload));
  }
}

class PresentationWindowApp extends StatefulWidget {
  const PresentationWindowApp({
    super.key,
    required this.controller,
    required this.payload,
  });

  final WindowController controller;
  final PresentationWindowPayload payload;

  @override
  State<PresentationWindowApp> createState() => _PresentationWindowAppState();
}

class _PresentationWindowAppState extends State<PresentationWindowApp> {
  late PresentationFrame _frame = widget.payload.frame;
  Timer? _maximizeEnforcer;

  @override
  void initState() {
    super.initState();
    unawaited(_bindMethodChannel());
    // 首帧画出来之后再最大化一次（那时窗口已经真的显示出来了）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PresentationWin32.maximize();
    });
    // 「强制最大化」：万一被还原了，两秒内再最大化回去。
    _maximizeEnforcer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => PresentationWin32.maximize(),
    );
  }

  @override
  void dispose() {
    _maximizeEnforcer?.cancel();
    super.dispose();
  }

  Future<void> _bindMethodChannel() async {
    try {
      await widget.controller.setWindowMethodHandler((MethodCall call) async {
        switch (call.method) {
          case 'frame':
            final Object? args = call.arguments;
            if (args is Map && mounted) {
              setState(() {
                _frame = PresentationFrame.fromMap(args.cast<String, Object?>());
              });
            }
            return true;
          case 'close':
            // 只关演示窗口这一个窗口，主窗口不受影响。
            PresentationWin32.close();
            return true;
          default:
            throw MissingPluginException(call.method);
        }
      });
    } catch (_) {
      // 绑定失败不影响首帧显示。
    }
  }

  /// 把控制动作回传给主窗口。
  Future<void> _send(String action) async {
    try {
      const WindowMethodChannel channel = WindowMethodChannel(
        kPresentationChannelName,
        mode: ChannelMode.unidirectional,
      );
      await channel.invokeMethod<Object?>('control', action);
    } catch (_) {
      // 主窗口没了就别管了。
    }
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      unawaited(_send(kControlPause));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyN) {
      unawaited(_send(kControlNext));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyP) {
      unawaited(_send(kControlPrevious));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      unawaited(_send(kControlExit));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = projectionBrightness(
      widget.payload.themeMode,
      MediaQuery.platformBrightnessOf(context),
    );

    return MaterialApp(
      title: '单词卡片 · 演示',
      debugShowCheckedModeBanner: false,
      home: Focus(
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) => _handleKey(event),
        child: PresentationView(frame: _frame, brightness: brightness),
      ),
    );
  }
}
