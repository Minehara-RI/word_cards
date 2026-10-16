// 作答页的键盘映射（只在桌面端启用）。
//
// 单独放一个文件是为了能直接测：这里只做「按键 → 意图」的翻译，
// 不碰 Riverpod、不碰任何状态，也不判断平台（平台判断在页面里）。
import 'package:flutter/services.dart';

/// 键盘最多能表态这么多个选项：数字键只有 1-5，字母键是 A-E。
const int kMaxQuizOptions = 5;

const List<LogicalKeyboardKey> _digitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
];

const List<LogicalKeyboardKey> _numpadKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
];

const List<LogicalKeyboardKey> _letterKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.keyA,
  LogicalKeyboardKey.keyB,
  LogicalKeyboardKey.keyC,
  LogicalKeyboardKey.keyD,
  LogicalKeyboardKey.keyE,
];

/// 数字键 1-5、小键盘 1-5、字母 A-E → 选项下标（0 起）。
///
/// 不是选项键就返回 null，交给页面忽略。
int? quizOptionIndexForKey(LogicalKeyboardKey key) {
  for (final List<LogicalKeyboardKey> group in <List<LogicalKeyboardKey>>[
    _digitKeys,
    _numpadKeys,
    _letterKeys,
  ]) {
    final int index = group.indexOf(key);
    if (index >= 0) return index;
  }
  return null;
}

/// Enter（含小键盘回车）→ 进入下一题。
bool isQuizNextKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;

/// Esc → 退出本轮。
bool isQuizExitKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.escape;
