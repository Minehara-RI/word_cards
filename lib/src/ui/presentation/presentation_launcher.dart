// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import '../../domain/models/app_settings.dart';
import 'presentation_frame.dart';
import 'presentation_window.dart';

/// 窗口列表变化（有窗口新建或关闭）时通知一次。
///
/// 用来发现「用户直接点了演示窗口的关闭按钮」这种情况。
Stream<void> presentationWindowChanges() => onWindowsChanged;

/// 主窗口这边的演示窗口管理器。
///
/// - [open] 开一个新窗口（隐藏启动 -> 把首帧塞进窗口参数 -> 显示）
/// - [push] 之后每一帧都推过去
/// - [close] 关掉窗口
/// - [isStillOpen] 用户直接关窗口时，主窗口靠它发现
///
/// 任何一步失败（手机、插件不可用、创建窗口被系统拒绝）都返回 false，
/// 调用方就退回「应用内全屏页」那条老路。
class PresentationWindowLauncher {
  WindowController? _window;
  bool _channelBound = false;
  String? lastError;

  String? get windowId => _window?.windowId;
  bool get isOpen => _window != null;

  Future<bool> open({
    required PresentationFrame frame,
    required AppThemeMode themeMode,
    required void Function(String action) onControl,
  }) async {
    await close();
    try {
      // 兜个底：万一平台通道卡住，宁可退回应用内全屏，也别把界面吊在这里。
      return await _open(frame, themeMode, onControl)
          .timeout(const Duration(seconds: 6));
    } catch (error) {
      lastError = error.toString();
      _window = null;
      return false;
    }
  }

  Future<bool> _open(
    PresentationFrame frame,
    AppThemeMode themeMode,
    void Function(String action) onControl,
  ) async {
    try {
      if (!_channelBound) {
        const WindowMethodChannel channel = WindowMethodChannel(
          kPresentationChannelName,
          mode: ChannelMode.unidirectional,
        );
        await channel.setMethodCallHandler((MethodCall call) async {
          if (call.method == 'control') {
            final Object? action = call.arguments;
            if (action is String) onControl(action);
            return true;
          }
          throw MissingPluginException(call.method);
        });
        _channelBound = true;
      }

      final WindowController controller = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: PresentationWindowPayload(
            frame: frame,
            themeMode: themeMode,
          ).encode(),
        ),
      );
      _window = controller;
      await controller.show();
      return true;
    } catch (error) {
      lastError = error.toString();
      _window = null;
      return false;
    }
  }


  /// 推一帧过去；窗口没开或推送失败都当无事发生（下一帧还会来）。
  Future<void> push(PresentationFrame frame) async {
    final WindowController? window = _window;
    if (window == null) return;
    try {
      await window.invokeMethod<Object?>('frame', frame.toMap());
    } catch (_) {
      // 忽略：窗口可能刚被关掉
    }
  }

  /// 关掉演示窗口。
  Future<void> close() async {
    final WindowController? window = _window;
    _window = null;
    if (window == null) return;
    try {
      await window.invokeMethod<Object?>('close');
    } catch (_) {
      // 窗口可能已经自己关了
    }
  }

  /// 演示窗口还在不在（用户可能直接点了窗口的关闭按钮）。
  Future<bool> isStillOpen() async {
    final String? id = windowId;
    if (id == null) return false;
    try {
      final List<WindowController> all = await WindowController.getAll();
      return all.any((WindowController controller) => controller.windowId == id);
    } catch (_) {
      return false;
    }
  }
}
