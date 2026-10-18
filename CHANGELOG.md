# 更新日志

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.2.0] - 2026-10-18

### 新增

- **卡组可以重置和删除**：设置页「卡组」里多了「管理卡组」，每个卡组一行，显示词数与两个按钮：
  - **重置**：只清学习进度（复习次数、掌握度、答题记录、FSRS），词一张不少；
  - **删除**：把卡组和里面的词一起删掉，二次确认，不能恢复。
  默认词库是兜底卡组，可以重置、不能删除；删掉当前选中的卡组会自动切回「全部词库」。

### 修复

- **设置页「关于」里的版本号不再写死**：以前是一行硬编码的 `1.0.0`，发了 1.1.x 也不变。
  现在由 `scripts\gen_version.ps1` 从 `pubspec.yaml` 生成 `lib\src\app_version.dart`，
  打包脚本先跑这一步；`test\app_version_test.dart` 负责揪出「改了版本号却忘了重新生成」。

- **集成测试不再清空真实词库**：它跑的是真应用，以前用的是 `%APPDATA%` 里那份
  `collection.anki2`，而测试第一步就是「清空全部卡片」——每跑一次 `scripts\verify.ps1`
  就会把词库清空、再填回 3 张测试卡。现在测试跑在临时目录里，跑完即删。

## [1.1.1] - 2026-10-18

### 变更

- **Windows 安装包改为装进 `D:\Program Files\word_cards`**：全机器安装，装的时候弹一次 UAC，
  点「是」即可；装完在开始菜单「单词卡片」里是启动与卸载两个快捷方式（卸载那条也是中文的）。
  之前是静默装进 `%LOCALAPPDATA%\Programs\word_cards`。
- **安装目录可以自定义**：向导里「选择目标位置」这一页会显示出来，想装哪儿直接改，
  升级时沿用上次选的目录；静默安装用 `/DIR="E:\Apps\word_cards"`。
  打包时改默认值用 `-AppDir`。机器上没有 D 盘会自动退回系统盘的 Program Files。
- `scripts\build_windows.ps1` 新增 `-DeployTo <目录>`（`build_release.ps1` 透传）：
  构建完把整套程序镜像到指定浅目录，`word_cards.exe` 就在那一层，双击即跑。

## [1.1.0] - 2026-10-16

### 新增

- **出题方向三选一**：作答页（和演示页，两页共用同一个设置）可以选
  **看英文选中文**（默认）、**看中文选英文**、**混合**。
  混合时每道题随机用其中一种，题面上会标出这一题考哪边；
  反方向的选项从同批其它卡片的单词里借，音标不显示（那是答案的读音），
  演示的答案 txt 里也会写明这一轮用的是什么方向。

## [1.0.0] - 2026-10-16

第一个完整版本：手机与电脑都能打包发布。

### 新增

- **加入**：两种方式把词放进词库。
  - 网页聊天导入：粘贴 AI 返回的 JSON，容错解析、去重、自动补干扰项；
  - API 直连：10 个 OpenAI 兼容服务商预设（DeepSeek / OpenAI / Kimi / 智谱 /
    通义千问 / 硅基流动 / OpenRouter / Ollama / LM Studio / 自定义），
    按「地址 + 模型 + Prompt」的 sha256 缓存去重，失败分 11 类给原因与下一步，
    可一键降级回网页聊天导入。
- **作答**：五选一限时测验。每题限时（1–600 秒，不可关闭），
  三种正误显示策略（立即 / 统一 / 不显示），支持卡组、标签、语言筛选。
- **桌面端键盘作答**：数字 1-5、字母 A-E、Enter、Esc，屏幕上给按键提示。
- **演示（课堂投影）**：另开一个强制最大化的独立窗口，每词限时自动翻页、
  循环播放、可换翻页提示音、可导出答案 txt。
- **统计**：总正确率、掌握度分布、最近七天、按标签与语言拆解。
- **导出**：卡片 JSON、答题记录 CSV，以及一份 Anki 能直接打开的
  `collection.anki2`。
- **词库管理**：多卡组（单一「当前卡组」）、卡片标签、五种语言（英法日韩俄）。
- **复习算法**：两套并存、互不干扰 —— 原有算法（正确率 / 掌握度）与
  FSRS-6（基于官方 `dart-fsrs` 包，可调目标保留率）。
- **本机优先**：所有数据只存本机，不需要账号、不上传；API Key 只写在本地库里。

### 打包

- `scripts/build_release.ps1` 一条命令出齐：Android APK（通用包，三个 ABI）、
  Windows 免安装包（目录 + zip）、Windows 安装包（Inno Setup，按用户安装）。

### 已知限制

- Android APK 目前使用 **debug 签名**，适合自己安装与分发，上架应用商店前
  需要换成自己的 keystore，步骤见 [docs/构建与发布.md](docs/构建与发布.md)。
- API 直连不支持流式输出，失败也不会自动重试（避免重复计费）。
- API Key 以明文存在本机 SQLite 里（本机单用户应用的取舍，界面上已注明不外传）。
- FSRS 参数不做自优化，直接用官方包自带的那套；见 [docs/复习算法.md](docs/复习算法.md)。

[1.2.0]: https://github.com/Minehara-RI/word_cards/releases/tag/v1.2.0
[1.1.1]: https://github.com/Minehara-RI/word_cards/releases/tag/v1.1.1
[1.1.0]: https://github.com/Minehara-RI/word_cards/releases/tag/v1.1.0
[1.0.0]: https://github.com/Minehara-RI/word_cards/releases/tag/v1.0.0
