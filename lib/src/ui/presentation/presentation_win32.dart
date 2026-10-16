// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// 演示窗口的 Windows 原生操作：最大化、关闭。
///
/// 为什么不用 window_manager：演示窗口是 desktop_multi_window 起的**第二个引擎**，
/// 那个引擎里只注册了插件自己的通道，window_manager 的通道根本不存在
/// （实测报 MissingPluginException），所以在子窗口里调它没用。
///
/// 好在 desktop_multi_window 给子窗口用的窗口类和主窗口不一样
/// （FLUTTER_MULTI_WINDOW_WIN32_WINDOW vs 运行器自己的类），
/// 用 FindWindowW 按类名就能精确找到那个窗口，再调 ShowWindow / PostMessage。
class PresentationWin32 {
  PresentationWin32._();

  /// desktop_multi_window 在 Windows 上给子窗口用的窗口类名。
  static const String windowClassName = 'FLUTTER_MULTI_WINDOW_WIN32_WINDOW';

  static const int _swMaximize = 3;
  static const int _wmClose = 0x0010;

  static bool get supported => !kIsWeb && Platform.isWindows;

  static DynamicLibrary? _user32;
  static int Function(Pointer<Utf16>, Pointer<Utf16>)? _findWindow;
  static int Function(int, int)? _showWindow;
  static int Function(int)? _isZoomed;
  static int Function(int, int, int, int)? _postMessage;

  static bool _bind() {
    if (!supported) return false;
    if (_showWindow != null) return true;
    try {
      final DynamicLibrary library =
          _user32 ??= DynamicLibrary.open('user32.dll');
      _findWindow = library.lookupFunction<
          IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
      _showWindow = library.lookupFunction<Int32 Function(IntPtr, Int32),
          int Function(int, int)>('ShowWindow');
      _isZoomed =
          library.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
              'IsZoomed');
      _postMessage = library.lookupFunction<
          Int32 Function(IntPtr, Uint32, IntPtr, IntPtr),
          int Function(int, int, int, int)>('PostMessageW');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 多窗口插件创建的那个窗口的句柄；找不到返回 0。
  static int findPresentationWindow() {
    if (!_bind()) return 0;
    final Pointer<Utf16> className = windowClassName.toNativeUtf16();
    try {
      return _findWindow!(className, nullptr);
    } catch (_) {
      return 0;
    } finally {
      calloc.free(className);
    }
  }

  /// 现在是不是最大化的。
  static bool isMaximized() {
    if (!_bind()) return false;
    final int hwnd = findPresentationWindow();
    if (hwnd == 0) return false;
    try {
      return _isZoomed!(hwnd) != 0;
    } catch (_) {
      return false;
    }
  }

  /// 最大化；已经最大化就什么都不做。
  static bool maximize() {
    if (!_bind()) return false;
    final int hwnd = findPresentationWindow();
    if (hwnd == 0) return false;
    try {
      if (_isZoomed!(hwnd) != 0) return true;
      _showWindow!(hwnd, _swMaximize);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 关掉演示窗口（只关这一个窗口，不影响主窗口）。
  static bool close() {
    if (!_bind()) return false;
    final int hwnd = findPresentationWindow();
    if (hwnd == 0) return false;
    try {
      _postMessage!(hwnd, _wmClose, 0, 0);
      return true;
    } catch (_) {
      return false;
    }
  }
}
