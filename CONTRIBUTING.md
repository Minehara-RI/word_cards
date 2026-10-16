# 参与开发

这是一个个人项目，但欢迎提 Issue 与 PR。下面是把开发环境跑起来、以及提交前
需要过的几道门。

## 环境

需要 Flutter 3.47 或更新的稳定版，以及对应平台的工具链：

| 平台 | 还需要 |
|---|---|
| Android | JDK 17+、Android SDK、NDK（`sqlite3_flutter_libs` 要编译原生库） |
| Windows | Visual Studio 2022 + 「使用 C++ 的桌面开发」工作负载 |

工具链路径集中在 [scripts/env.ps1](scripts/env.ps1)：它先看环境变量，
再退回文件里的默认路径，最后找 PATH。换机器只改这一个文件。

```powershell
git clone https://github.com/Minehara-RI/word_cards.git
cd word_cards
flutter pub get
pwsh -File scripts\verify.ps1 -SkipIntegration   # analyze + 单元测试
```

## 提交前必须过的门

```powershell
pwsh -File scripts\verify.ps1
```

它会依次跑：

1. `flutter analyze` —— **必须是 `No issues found`**，连 `info` 级 lint 也不放过；
2. `flutter test` —— 全量单元 / widget 测试；
3. Windows 集成测试（真起窗口跑一遍完整流程），跑完自动重建 Debug exe。

> 注意：集成测试跑的是**真实数据库**，会改设置项。CI 上无所谓，
> 本机跑完如果发现设置被改了，改回来就行。

## 代码约定

- **分层**：`domain`（纯 Dart 模型与接口）→ `data`（实现）→ `logic`（纯函数）
  → `state`（Riverpod）→ `ui`。
- **平台判断只允许出现在 UI 层**。`logic` 与 `data` 里出现
  `Platform.isWindows` 这类判断就是设计错了 ——
  手机端少一个「演示」入口，靠的是 UI 层的 `visibleHomeTabs()` 一个判断，
  其余代码一行都不用知道自己在哪个平台。
- **注释写「为什么」，不写「做什么」**。代码本身说明做什么；
  注释用来解释为什么这么选、踩过什么坑。
- 中文文案直接写在代码里（本项目只有中文界面）。
- 新增平台相关行为时，**留一个可注测试的缝**（例如把 target 作为参数传进去），
  别让测试去猜当前平台。

## 测试

- 单元 / widget 测试放 `test/`，文件名与被测对象对应（`fsrs_test.dart` 等）。
- 测试用的假实现（内存仓库、假 HTTP 客户端）放 `test/support/`。
- 调用外部 API 的测试**不要发真实请求** —— 用 `package:http/testing.dart`
  的 `MockClient`（见 `test/ai_api_client_test.dart`）。
- 修 bug 时**先写一个能复现的失败测试**，再改代码。

## 提交信息

用中文写清楚「做了什么」，一句话讲得完就一句话。
大改动可以在正文里分段说明动机与取舍。

## PR

- 一个 PR 只做一件事；
- 说明**为什么**这么改，而不只是改了什么；
- 改了界面就附一张截图（`docs/screenshots/` 里已有 31 张可以对照编号）；
- 确定 `pwsh -File scripts\verify.ps1` 全绿。

## 发布

打包与发布流程（APK / Windows 安装包、版本号从哪来、签名怎么换）见
[docs/构建与发布.md](docs/构建与发布.md)。
