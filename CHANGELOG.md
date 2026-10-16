# 更新日志

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.0.0] - 2026-10-16

第一个完整版本。五个阶段全部做完，手机与电脑都能打包发布。

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
  需要换成自己的 keystore，步骤见 [docs/打包与发布.md](docs/打包与发布.md)。
- API 直连不支持流式输出，失败也不会自动重试（避免重复计费）。
- API Key 以明文存在本机 SQLite 里（本机单用户应用的取舍，界面上已注明不外传）。
- FSRS 参数不做自优化；调研结论见 [docs/FSRS参数优化.md](docs/FSRS参数优化.md)。

[1.0.0]: https://github.com/Minehara-RI/word_cards/releases/tag/v1.0.0
