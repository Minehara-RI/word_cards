// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';

import '../../domain/models/app_settings.dart';
import '../../domain/models/quiz_direction.dart';

/// 演示窗口参数里的类型标记：只有带这个标记的窗口才是演示窗口。
const String kPresentationWindowKind = 'word_flashcards.presentation';

/// 演示的一道题（窗口之间传的就是这个，不带任何学习状态）。
///
/// 窗口之间只传**题面**，不传单词本体：反方向（看中文选英文）的题面
/// 就是中文释义，传单词等于把答案发给演示窗口。音标同理，
/// 什么时候带、什么时候不带由主窗口决定（见 [phonetic]）。
class PresentationQuestion {
  const PresentationQuestion({
    required this.prompt,
    required this.options,
    this.phonetic,
    this.direction = QuizDirection.wordToMeaning,
  });

  /// 题面上显示的内容：正方向是单词，反方向是中文释义。
  final String prompt;

  /// 音标。反方向永远是 null —— 那是答案的读音。
  final String? phonetic;

  final List<String> options;

  /// 这一题考哪边。屏幕上要标出来（混合方向时全靠它提示学生选什么）。
  final QuizDirection direction;

  Map<String, Object?> toMap() => <String, Object?>{
        'prompt': prompt,
        'phonetic': phonetic,
        'options': options,
        'direction': direction.id,
      };

  factory PresentationQuestion.fromMap(Map<String, Object?> map) =>
      PresentationQuestion(
        prompt: (map['prompt'] as String?) ?? '',
        phonetic: map['phonetic'] as String?,
        options: <String>[
          for (final Object? option in (map['options'] as List<Object?>? ?? const <Object?>[]))
            option?.toString() ?? '',
        ],
        direction: QuizDirection.fromId(map['direction']),
      );
}

/// 演示画面的一帧：现在该显示哪道题、还剩多少秒。
///
/// 主窗口是唯一的“真相来源”，它把每一帧推给演示窗口；
/// 演示窗口只负责画，按键再回传给主窗口。
class PresentationFrame {
  const PresentationFrame({
    required this.status,
    required this.questions,
    required this.index,
    required this.remainingMs,
    required this.intervalMs,
    required this.paused,
    required this.loops,
    required this.labelStyle,
    this.message,
  });

  static const String statusRunning = 'running';
  static const String statusFinished = 'finished';
  static const String statusEmpty = 'empty';

  final String status;
  final List<PresentationQuestion> questions;
  final int index;

  /// 当前题还剩多少毫秒。
  final int remainingMs;

  /// 每题停留总时长（毫秒）。
  final int intervalMs;

  final bool paused;

  /// 已经循环了几轮。
  final int loops;

  /// 选项编号用 12345 还是 ABCDE。
  final OptionLabelStyle labelStyle;

  /// 结束 / 空状态的提示文字。
  final String? message;

  bool get isRunning => status == statusRunning;
  int get total => questions.length;
  int get position => total == 0 ? 0 : index + 1;
  PresentationQuestion? get current =>
      index >= 0 && index < total ? questions[index] : null;

  double get remainingRatio {
    if (intervalMs <= 0) return 0;
    return (remainingMs / intervalMs).clamp(0.0, 1.0);
  }

  int get remainingSeconds =>
      remainingMs <= 0 ? 0 : ((remainingMs + 999) ~/ 1000);

  Map<String, Object?> toMap() => <String, Object?>{
        'status': status,
        'questions': questions.map((PresentationQuestion q) => q.toMap()).toList(),
        'index': index,
        'remaining_ms': remainingMs,
        'interval_ms': intervalMs,
        'paused': paused,
        'loops': loops,
        'label_style': labelStyle.id,
        'message': message,
      };

  factory PresentationFrame.fromMap(Map<String, Object?> map) {
    final List<Object?> rawQuestions =
        map['questions'] as List<Object?>? ?? const <Object?>[];
    return PresentationFrame(
      status: (map['status'] as String?) ?? statusEmpty,
      questions: <PresentationQuestion>[
        for (final Object? item in rawQuestions)
          if (item is Map)
            PresentationQuestion.fromMap(item.cast<String, Object?>()),
      ],
      index: (map['index'] as num?)?.toInt() ?? 0,
      remainingMs: (map['remaining_ms'] as num?)?.toInt() ?? 0,
      intervalMs: (map['interval_ms'] as num?)?.toInt() ?? 0,
      paused: map['paused'] == true,
      loops: (map['loops'] as num?)?.toInt() ?? 0,
      labelStyle: OptionLabelStyle.fromId(map['label_style']),
      message: map['message'] as String?,
    );
  }

  String encode() => jsonEncode(toMap());

  static PresentationFrame? tryDecode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        final Map<String, Object?> map = decoded.cast<String, Object?>();
        if (map['kind'] != kPresentationWindowKind) return null;
        final Object? payload = map['frame'];
        if (payload is Map) {
          return PresentationFrame.fromMap(payload.cast<String, Object?>());
        }
      }
    } catch (_) {
      // 不是我们的窗口参数，当普通主窗口处理。
    }
    return null;
  }
}

/// 创建演示窗口时写进 arguments 的内容。
class PresentationWindowPayload {
  const PresentationWindowPayload({
    required this.frame,
    required this.themeMode,
  });

  final PresentationFrame frame;

  /// 演示模式自己的深浅色（主界面那套不影响这里）。
  final AppThemeMode themeMode;

  String encode() => jsonEncode(<String, Object?>{
        'kind': kPresentationWindowKind,
        'frame': frame.toMap(),
        'theme_mode': themeMode.id,
      });

  /// 解析窗口参数；返回 null 表示这不是演示窗口。
  static PresentationWindowPayload? tryDecode(String? raw) {
    final PresentationFrame? frame = PresentationFrame.tryDecode(raw);
    if (frame == null) return null;
    AppThemeMode mode = AppThemeMode.system;
    try {
      final Object? decoded = jsonDecode(raw!);
      if (decoded is Map) {
        mode = AppThemeMode.fromId(decoded['theme_mode']);
      }
    } catch (_) {
      // 忽略：退回跟随系统
    }
    return PresentationWindowPayload(frame: frame, themeMode: mode);
  }
}
