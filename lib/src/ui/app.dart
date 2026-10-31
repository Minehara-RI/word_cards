import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/app_settings.dart';
import '../state/providers.dart';
import '../state/server_providers.dart';
import 'pages/home_shell.dart';
import 'theme.dart';

class WordCardsApp extends ConsumerWidget {
  const WordCardsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    // 两个监听端点由设置里的开关决定起停。挂在应用根上而不是某个页面上：
    // 用户在「作答」页背单词时，浏览器插件照样能把词写进来。
    ref.watch(ankiConnectServerProvider);
    ref.watch(syncServerProvider);
    return MaterialApp(
      title: 'word_flashcards',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: switch (settings.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      // 字号缩放只影响全局文字大小，演示模式自己另有一套大字号。
      builder: (context, child) {
        final double scale = settings.fontScale.clamp(0.8, 1.6);
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomeShell(),
    );
  }
}
