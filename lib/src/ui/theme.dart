import 'package:flutter/material.dart';

import 'fonts.dart';

/// 品牌主色：偏冷静的靛蓝，长时间看题不刺眼。
const Color kSeedColor = Color(0xFF4F46E5);

const double kCardRadius = 16;

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: kSeedColor,
    brightness: brightness,
  );
  final isDark = brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // 全应用统一到一套无衬线字体上（含日/韩/俄的字形兜底）。
    fontFamily: kAppFontFamily,
    fontFamilyFallback: kAppFontFallback,
    scaffoldBackgroundColor: isDark ? const Color(0xFF121218) : const Color(0xFFF7F7FB),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? const Color(0xFF1E1E26) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.6),
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF1E1E26) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.6),
      space: 1,
      thickness: 1,
    ),
  );
}

/// 演示模式（全屏投影）用的主题。
///
/// 和主界面分开：这里只有深浅两套底色、更硬的对比度、更大的字号。
/// 用户可以在演示页或设置页单独指定演示模式用深色还是浅色，
/// 主界面该是什么样还是什么样。
ThemeData buildProjectionTheme(Brightness brightness) {
  final ThemeData base = buildAppTheme(brightness);
  final bool isDark = brightness == Brightness.dark;
  final Color ink = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0B1020);
  final Color paper = isDark ? const Color(0xFF0B0B10) : const Color(0xFFFFFFFF);

  return base.copyWith(
    scaffoldBackgroundColor: paper,
    cardColor: isDark ? const Color(0xFF16161E) : const Color(0xFFF3F4F8),
    // 只统一颜色：字号由演示页里的 projectionStyle 明确给出，
    // 用 fontSizeFactor 会因为个别样式没有 fontSize 而触发断言。
    textTheme: base.textTheme.apply(
      bodyColor: ink,
      displayColor: ink,
    ),
    iconTheme: base.iconTheme.copyWith(color: ink),
  );
}

/// 掌握度对应的颜色，卡片列表和统计里共用。
Color masteryColor(ColorScheme scheme, double mastery, {int reviewCount = 0}) {
  if (reviewCount == 0) return scheme.outline;
  if (mastery >= 0.8) return const Color(0xFF16A34A);
  if (mastery >= 0.5) return const Color(0xFFF59E0B);
  return const Color(0xFFDC2626);
}
