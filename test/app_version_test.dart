import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:word_cards/src/app_version.dart';

/// 界面「关于」里显示的版本号来自 lib/src/app_version.dart，
/// 那个文件是 scripts/gen_version.ps1 从 pubspec.yaml 生成的。
/// 这条测试专门抓「改了 pubspec 却忘了重新生成」。
void main() {
  test('界面显示的版本号与 pubspec.yaml 一致', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    // Dart 的 RegExp 不支持 (?m) 这种内联标志，多行要传 multiLine。
    final RegExpMatch? match =
        RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9]+)?)', multiLine: true)
            .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml 里没有 version:');
    expect(
      kAppVersion,
      match!.group(1),
      reason: 'lib/src/app_version.dart 过期了，跑 pwsh -File scripts\\gen_version.ps1',
    );
  });
}
