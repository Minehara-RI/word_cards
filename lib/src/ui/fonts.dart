import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 全应用统一的无衬线字体。
///
/// 刻意不打包字体文件（一套 Noto CJK 就十几兆），改用各平台自带的
/// 无衬线字体：中文用系统的黑体系，拉丁字母、西里尔字母由主字体覆盖，
/// 日文假名与韩文谚文交给 [kAppFontFallback] 兜底，不会出现方框。
String? get kAppFontFamily {
  if (kIsWeb) return null;
  if (Platform.isWindows) return 'Microsoft YaHei UI';
  if (Platform.isAndroid || Platform.isLinux) return 'sans-serif';
  if (Platform.isMacOS || Platform.isIOS) return 'PingFang SC';
  return null;
}

/// 字体回退链：按「谁的字形覆盖面更合适」排。
///
/// 日文（假名）、韩文（谚文）、俄文（西里尔）各有专门字体，
/// 排在后面做兜底，这样同一个界面里混排五种语言也不会掉字形。
List<String> get kAppFontFallback {
  if (kIsWeb) return const <String>['sans-serif'];
  if (Platform.isWindows) {
    return const <String>[
      'Microsoft YaHei UI',
      'Microsoft YaHei',
      'Segoe UI',
      'Yu Gothic UI',
      'Meiryo UI',
      'Malgun Gothic',
      'Arial',
    ];
  }
  if (Platform.isAndroid) {
    return const <String>[
      'sans-serif',
      'Noto Sans CJK SC',
      'Noto Sans SC',
      'Noto Sans JP',
      'Noto Sans KR',
    ];
  }
  if (Platform.isMacOS || Platform.isIOS) {
    return const <String>[
      'PingFang SC',
      'Hiragino Sans',
      'Apple SD Gothic Neo',
      'Helvetica Neue',
    ];
  }
  if (Platform.isLinux) {
    return const <String>['Noto Sans CJK SC', 'DejaVu Sans', 'sans-serif'];
  }
  return const <String>['sans-serif'];
}

/// 演示模式（全屏投影）专用字号。
///
/// 教室最后一排也要看得清，所以只给三档：单词、选项、说明。
class ProjectionText {
  const ProjectionText._();

  /// 单词：屏幕上最大的一行。
  static const double word = 76;
  static const double wordSmall = 54;

  /// 选项：学生要能一眼分出编号和释义。
  static const double option = 34;
  static const double optionSmall = 26;

  /// 顶部信息（第 N/M 题、倒计时）。
  static const double meta = 26;
  static const double countdown = 40;

  /// 说明文字。
  static const double hint = 18;
}

/// 演示模式的大字样式：无衬线 + 加粗 + 略放宽字距，投影时更清楚。
TextStyle projectionStyle(
  BuildContext context, {
  required double size,
  FontWeight weight = FontWeight.w700,
  Color? color,
  double letterSpacing = 0,
  double height = 1.2,
}) {
  return TextStyle(
    fontFamily: kAppFontFamily,
    fontFamilyFallback: kAppFontFallback,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    height: height,
    color: color,
  );
}

/// 一段能覆盖五种语言的示例文本，用来验证字体链有没有掉字形。
const String kFontSampleText =
    '英语 abandon　法语 abandonner　日语 すいえい　韩语 사과　俄语 отказаться';
