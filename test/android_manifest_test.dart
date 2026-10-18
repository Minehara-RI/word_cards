// release 包里必须带联网权限。
//
// 这条测试是补一次真实事故：Flutter 模板只在 debug/profile 的 manifest 里声明
// INTERNET，release 包漏了它 —— 于是安卓正式版的所有 API 直连都报
// 「Failed host lookup」，而 debug 包一切正常，四个版本都没人发现。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release 用的 AndroidManifest 声明了 INTERNET 权限', () {
    final String manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      manifest.contains('android.permission.INTERNET'),
      isTrue,
      reason: 'main 的 manifest 少了 INTERNET：release APK 会连不上任何 API',
    );
  });

  test('允许本地大模型用的明文 HTTP', () {
    final String manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      manifest.contains('android:usesCleartextTraffic="true"'),
      isTrue,
      reason: 'Ollama / LM Studio 默认是 http://，去掉这条它们就连不上了',
    );
  });
}
