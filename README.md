# word_flashcards

[![CI](https://github.com/Minehara-RI/word_cards/actions/workflows/ci.yml/badge.svg)](https://github.com/Minehara-RI/word_cards/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Minehara-RI/word_cards)](https://github.com/Minehara-RI/word_cards/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Windows-lightgrey)

输入单词，让 AI 生成「正确释义 + 4 个有混淆性的干扰项」，然后做五选一限时测验。
Android 与 Windows 都能用，**所有数据只存在本机**：不联网、不上传、不需要账号。

本地数据库用的是 **Anki 的原生格式**（SQLite / `collection.anki2` / schema 11）：
库文件可以直接用 Anki 打开，复习历史写在 Anki 的 revlog 里，
导出页还能生成一份 `.anki2` 交给 Anki —— 细节见 [存储格式](docs/存储格式.md)。

## 功能

| | |
|---|---|
| **加入** | 手填单张卡片；粘贴大模型返回的 JSON 批量导入（容错解析、去重、自动补干扰项）；API 直连自动生成 |
| **作答** | 五选一限时测验；出题方向三选一（看词选义 / 看义选词 / 混合）；三种正误显示策略；桌面端数字键作答；按卡组 / 标签 / 语言决定考哪些词 |
| **演示** | 课堂投影（仅桌面端）：另开一个强制最大化的独立窗口，每词限时自动翻页，结束后导出答案 txt；**词汇来源可选**（当前卡组 / 全部词库 / 指定卡组，再按标签缩小） |
| **统计** | 总正确率、掌握度分布、最近七天、按标签与语言拆解、最需要加强的词 |
| **导出** | 卡片 JSON、答题记录 CSV，以及一份 Anki 能直接打开的 `collection.anki2` |
| **词库** | 多卡组（始终有一个「当前卡组」，可在设置里重置进度或整个删除）、卡片标签、五种语言（英 / 法 / 日 / 韩 / 俄） |
| **复习算法** | 原有算法（正确率 / 掌握度）与 FSRS-6 并存、互不干扰，目标保留率可调 |
| **本机优先** | 数据只存本机；API Key 只写在本地库里，界面上注明不外传 |

## 界面

上方一排入口，**桌面端五个：加入 / 作答 / 演示 / 统计 / 导出**；
**手机端四个：加入 / 作答 / 统计 / 导出**。
课堂投影是「一台电脑接投影仪」的场景，手机不做投屏，所以「演示」整页不给 ——
入口、页面、以及设置页里那套演示深浅色一起不出现。

| 作答 | 加入 | 演示：词汇来源 |
|---|---|---|
| ![作答](docs/screenshots/13-首页-作答.png) | ![加入](docs/screenshots/14-加入页.png) | ![词汇来源](docs/screenshots/33-演示-词汇来源.png) |

| 演示进行时（12345） | 演示进行时（ABCDE） | 统计 | 导出 |
|---|---|---|---|
| ![演示](docs/screenshots/16-演示进行时.png) | ![ABCDE](docs/screenshots/20-演示-ABCDE编号.png) | ![统计](docs/screenshots/17-统计.png) | ![导出](docs/screenshots/18-导出.png) |

| 独立演示窗口 | 演示答案文件 | 作答页本轮设置与 FSRS |
|---|---|---|
| ![演示窗口](docs/screenshots/22-演示-独立窗口最大化.png) | ![答案文件](docs/screenshots/21-演示答案文件.png) | ![作答设置](docs/screenshots/24-作答-本轮设置与FSRS.png) |

| 加入：卡组 / 标签 / 语言 | 导入：整批标签与卡组 | 设置：外观与语言字体 | 卡片列表 |
|---|---|---|---|
| ![加入](docs/screenshots/25-加入-卡组标签与语言.png) | ![导入](docs/screenshots/26-导入-整批标签与卡组选择.png) | ![设置](docs/screenshots/27-设置-外观与语言字体.png) | ![卡片](docs/screenshots/28-卡片列表-语言与标签.png) |

| 作答范围与标签筛选 | 桌面端键盘作答 | 导入页：API 直连 | 设置：AI 生成 |
|---|---|---|---|
| ![标签筛选](docs/screenshots/29-作答-标签筛选与全部.png) | ![键盘作答](docs/screenshots/30-作答-桌面键盘作答.png) | ![API 直连](docs/screenshots/31-导入页-API直连.png) | ![AI 生成](docs/screenshots/32-设置-API生成.png) |

## 安装

到 [Releases](https://github.com/Minehara-RI/word_cards/releases/latest) 下载对应平台的包。

### Android

下载 `word_flashcards-<版本>.apk` 传到手机，点开安装（需要允许「安装未知来源应用」）。

> 目前的 APK 用的是 **debug 签名** —— 它是合法签名，自己装、发给朋友都够用，
> 但要上架应用商店得换成自己的 keystore，见 [构建与发布](docs/构建与发布.md)。

### Windows

- `word_flashcards-setup-<版本>.exe`：双击安装，**会弹一次 UAC**，
  装到 `D:\Program Files\word_flashcards`，装完从开始菜单「word_flashcards」启动；
- 或者解压 `word_flashcards-win-x64.zip`，直接跑里面的 `word_flashcards.exe`，免安装。

卸载不会动用户数据（`%APPDATA%\com.minehara\word_flashcards\collection.anki2`）。
从 1.2.x 升级时新版会自动接管旧的 `word_cards` 数据目录；想彻底干净就先卸载旧版再装。

## 上手三步

1. **加入** —— 把词放进词库：手填一张，或者把大模型返回的 JSON 粘进来批量导入，
   或者在设置里配好 API 后直接让应用自己生成；
2. **作答** —— 在本轮设置里定好题目数量、出题方向、每题限时与正误显示方式，点开始测验；
3. **看结果** —— 成绩单给出正确率与错题，统计页看趋势，导出页可以把词库和记录带走。

课堂投影（**演示**）只有桌面端有：先在「词汇来源」里选这一场放哪些词
（当前卡组 / 全部词库 / 指定卡组，还能再按标签缩小），点「开始演示」会另开一个
最大化的窗口。学生口头作答，屏幕上不显示任何答案，结束后自动写出答案 txt。

## 从源码构建

需要 Flutter 3.47+ 稳定版，以及对应平台的工具链：
Android 要 JDK 17+ / Android SDK / NDK，Windows 要 Visual Studio 2022 与「使用 C++ 的桌面开发」。

```powershell
git clone https://github.com/Minehara-RI/word_cards.git
cd word_cards
flutter pub get
pwsh -File scripts\verify.ps1            # analyze + 单元测试 + Windows 集成测试
pwsh -File scripts\build_release.ps1     # 出 APK + Windows 免安装包 + 安装包
```

工具链路径集中在 `scripts\env.ps1`：它先看环境变量，再退回文件里的默认路径，最后找 PATH。
换机器只改这一个文件（或者把 `JAVA_HOME` / `ANDROID_HOME` / `PUB_CACHE` / `GRADLE_USER_HOME` / `FLUTTER_ROOT` 设好）。
产物都落在 `dist\`，版本号由 `pubspec.yaml` 的 `version:` 决定。
想在浅目录留一份双击就能跑的程序，加 `-DeployTo D:\word_flashcards`（见[构建与发布](docs/构建与发布.md)）。

## 文档

| 文档 | 内容 |
|---|---|
| [使用指南](docs/使用指南.md) | 每个页面怎么用：导入格式、API 配置与错误处理、作答规则、演示、设置项一览 |
| [存储格式](docs/存储格式.md) | Anki schema 11 表结构、`wc_` 扩展表、字段映射、标签与语言怎么存、与 Anki 互通 |
| [复习算法](docs/复习算法.md) | 两套算法怎么并存、FSRS 评分映射、目标保留率、参数从哪来 |
| [构建与发布](docs/构建与发布.md) | 脚本用法、产物清单、Android 签名、Windows 安装包、踩过的坑 |
| [CHANGELOG](CHANGELOG.md) | 版本变更 |

## 参与 / 许可

- 想改代码：[CONTRIBUTING.md](CONTRIBUTING.md)（环境、提交前要过的门、分层约定）
- 发现安全问题：[SECURITY.md](SECURITY.md)（**不要开公开 Issue**，走私密漏洞报告）

以 [MIT 许可证](LICENSE) 发布，© 2026 Minehara-RI。

> 第三方依赖各自遵循自己的许可证，见 `flutter pub deps` 或各自的 pubspec。
> 界面文案与文档均为中文。
