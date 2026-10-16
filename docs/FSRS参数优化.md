# FSRS 参数优化（调研存档，未来开发用）

> 结论先行：**Anki 的 FSRS 参数优化是一次性的、由用户点按钮触发的机器学习训练**，
> 不是运行时自动发生的。本应用当前不使用它 —— 参数钉死成 Anki 25.09 内置的
> FSRS-6 参数集（`kFsrs6AnkiParameters`，见 `lib/src/logic/fsrs.dart`）。
> 这份文档把「将来要做的话该怎么做、必须复刻什么、会踩什么坑」记下来，免得重新摸底。

调研时间：2026-10；对照源码：`ankitects/anki` 主线 + `open-spaced-repetition/fsrs-rs v5.1.0`
（v5.1.0 正是 Anki 25.09 内置的版本，也就是我们那 21 个参数的来源）。

---

## 一、「自优化」到底是谁触发的

Anki 里没有任何后台任务替你拟合参数。完整流程是：

1. 用户在牌组预设（preset）里点 **Optimize**；
2. 后端拿这个预设下所有牌组的复习日志跑一遍训练；
3. 结果写回预设的 `fsrs_params_6`；
4. 界面显示「距上次优化 N 天」，超过 30 天提示一句
   （`daysSinceLastOptimization > 30 → deckConfigTimeToOptimize()`）。

另外只有两个批量/辅助入口：**Optimize All Presets**
（`UPDATE_DECK_CONFIGS_MODE_COMPUTE_ALL_PARAMS`）和 **Check health when optimizing**。

几个直接结论：

- **参数是按预设（不是按牌组、不是按账户）算的**：同一个预设下的所有牌组一起当训练集。
- 官方建议**一个月优化一次就够**，并且明确说**不要抄别人的参数**。
- 优化参数**不会立刻重排已排定的到期日**，除非开「Reschedule cards on change」。
- 所以「自优化」这个词只是相对于「手工填参数」而言，本质仍是**用户主动触发的一次训练**。

## 二、训练数据从哪来

后端 RPC 是 `compute_params`，入参：

```
search                        // 用哪些卡，默认 preset:"预设名" -is:suspended
ignore_revlogs_before_ms      // 「忽略某日期之前的复习」
current_params                // 当前参数，用于最后比好坏
num_of_relearning_steps       // 重学步数，影响冻结项
health_check                  // 要不要做体检
current_preset / total_presets // 批量优化时报进度
```

两步转换：

1. `revlog_for_srs(search)` 按搜索取出 revlog；
2. `fsrs_items_for_training(revlogs, next_day_at, ignore_revlogs_before)`
   把原始日志变成 `FSRSItem`：以「下一天的起点」切分复习，把同一天内的学习步骤
   折叠/打标（`enable_short_term: true` 时保留短期记忆信息），
   最终得到每张卡的 `(t_historys, r_historys, delta_ts, labels)` 序列。

阈值与守卫：

- **少于 400 条不报错**，由调用方看返回的 `fsrs_items` 数量决定怎么办
  （源码注释原话：does not return an error if there are less than 400 items）；
- 条数为 0 时**原样退回当前参数**；
- 官方手册把「复习量不足（a few hundred 以下）」列为效果不佳的第一大原因。

## 三、训练本身做了什么（fsrs-rs v5.1.0，21 个权重）

| 项目 | 取值 | 说明 |
|---|---|---|
| 目标函数 | 加权的二元交叉熵（BCE） | 预测「到点时还记得的概率」vs 实际过/不过 |
| 正则项 | L2 惩罚，按 `PARAMS_STDDEV` 归一化 | 缩放系数 `gamma * batch_size / total_size`、默认 `gamma = 1.0` |
| 优化器 | Adam（burn 后端），`eps = 1e-8` | 学习率 0.04 + 余弦退火 |
| 批大小 | 512 | 每轮打乱 |
| 每卡最长序列 | 64 条复习 | 超出的截掉 |
| 随机种子 | 2023（固定） | 结果可复现 |
| epoch 数 | 库默认 5，**Anki 显式改成 8** | `TrainingConfig { num_epochs: 8, ..Default::default() }` |
| 近期加权 | `recency_weighted_fsrs_items` | 越近的复习权重越大 |
| 初始化 | `initialize_stability_parameters` | **不是随机初始化**：先只用「只有一条长期复习」的样本单独拟合前 4 个初始稳定度参数，再 `smooth_and_fill` 平滑补全，其余从默认参数出发 |
| 冻结/裁剪 | `freeze_initial_stability`、`freeze_short_term_stability`、`parameter_clipper` | 把每个参数卡在合法区间 |

> 版本提醒：更早的 fsrs-rs 完全依赖 `burn` 做自动微分；主线现在已换成
> **手写解析梯度 + 自带 Adam**（β₁=0.70、β₂=0.98、ε=1e-8，见
> `docs/BURN_REMOVAL.md`），FSRS-7 那条线是 lr=0.07 / 17 epochs。
> 如果将来要抄实现，**必须认准一个版本**，别把两代的超参混在一起。

## 四、训练完还有两道保护（这是最容易被忽略、也最该抄的部分）

1. **新参数不够好就不用**：把「当前参数」和「新参数」在**同一份数据**上各算一次 log loss，
   `if (current_log_loss <= optimized_log_loss)` 就保留旧参数。
   重学步数 > 1 时还有一段额外检查（模拟一次失败 + 若干重学步，短期稳定性反而更低则退回旧参数）。
   → 用户点了优化发现「没变化」不是 bug。
2. **体检（Check health）**：样本 > 300 条时才做，用时间序列切分做交叉评估，
   算**修正后的 log loss（阈值 1.11）和修正后的 RMSE（阈值 1.53）**，任一达标才算通过。
   修正是把「通过率 r」和「数据量 c」标准化，例如：

   `rmse_adjustment(r, c) = 0.0135 / (r^0.504 - 1.14) + 0.176 / ((c/1000)^0.825 + 2.22) + 0.101`

   （r = rating > 1 的比例，即通过率。）

## 五、工程实现细节

- 训练跑在后端 Rust（`rslib`）里，**另起一个线程每 100 ms 把进度推给界面**
  （`current/total iterations` 和 reviews），所以按钮会变成「取消」，
  中断靠进度回调里的 `want_abort`。
- 结果落在预设上：`fsrs_params_6`（proto 里同时保留 `fsrs_params_4/5`，
  切算法版本不会丢参数），另有 `fsrs_health_check`、`fsrs_legacy_evaluate`、
  `days_since_last_fsrs_optimize`、`ignore_revlogs_before_date`、
  `param_search`、`desired_retention`。
- 前端（`FsrsOptions.svelte`）负责：显示「距上次优化 N 天」、优化中显示进度、
  完成后把 `resp.params` 写进 `$config.fsrsParams6`。

## 六、别和「目标保留率」混为一谈

| | FSRS 参数 | 目标保留率 desired retention |
|---|---|---|
| 是什么 | 拟合「你的记忆长什么样」 | 你的**选择**：想花多少时间 |
| 怎么来 | 训练（优化按钮） | 手动选 0.70–0.97，或用模拟器/CMRR 估 |
| 影响 | 间隔曲线的形状 | 所有间隔整体长短 |

「Compute minimum recommended retention（CMRR）」在 **Anki 25.07 已移除**，并入模拟器；
它算的是「单位时间记住最多」的那个保留率，和参数优化是两回事。

## 七、我们真要做的话：三条路线

| 路线 | 与 Anki 的一致性 | 工作量 | 风险 |
|---|---|---|---|
| A. 把 fsrs-rs 的 `compute_parameters` 编成动态库（FFI，或 wasm） | 完全一致 | 大（Android + Windows 两套构建产物、交叉编译、体积） | 构建链复杂，但算法零风险 |
| B. 用 Dart 重写训练循环（加权 BCE + Adam + 裁剪 + 初始稳定性预拟合） | 需要逐项对齐，容易「像但不是」 | 中 | 实现细节多（正则、退火、冻结、裁剪），数值对不上就白做 |
| C. 用 JS 移植 `ts-fsrs-optimizer` | 移植版跟随上游，可能有滞后 | 中 | 要拖一个 JS 运行时（quickjs），最不划算 |

**建议**：除非将来数据量大到必须个性化，否则一律走「预设几套参数 + 用户手选」，
而不是上优化器。真要上，选 A。

## 八、如果将来接入：设计草案

- **数据**：`wc_answer_log`（`card_uid / correct / selected / reaction_ms /
  answered_at / mode / revlog_id`，见 `anki_schema.dart`）加评分映射，
  已经够拼出训练集：按天切分、由 `correct` 与选项映射出 Again/Hard/Good/Easy、
  由相邻 `answered_at` 算出 elapsed days。
- **触发**：**只做手动**（设置页一个「优化参数」按钮 + 「距上次优化 N 天」提示），
  不要静默自优化 —— 数据少或习惯乱时，静默优化只会把参数带偏。
- **存储**：21 个参数 + `days_since_last_fsrs_optimize` + 上次优化的
  log loss / RMSE 一起存 `wc_settings`；
  开「优化前先备份」性质的开关，出问题能退回。
- **必须复刻的保护**：① 新参数 log loss 更差就回退；② 体检阈值；
  ③ 数据量门槛（Anki 用 400 条，我们用同一个数量级）。
- **必须提醒用户的事**：评分习惯（忘记时用 Again 而不是 Hard）会直接影响参数质量。

## 九、验收要点（将来做的时候照这个测）

1. 训练集构造：同一天多次复习、忽略日期边界、条数不足时的行为；
2. 缓存/幂等：同一天重复优化结果一致（固定种子）；
3. 回退保护：喂噪声数据时参数**不变**；
4. 中断：优化中途取消不写库；
5. 与 Anki 对照：同一份 revlog 导出，Anki 优化结果与本实现结果的 log loss 差异在可接受范围内。

## 十、参考来源

- Anki 手册 · Deck Options · FSRS Parameters：<https://docs.ankiweb.net/deck-options.html#fsrs-parameters>
- Anki 源码 `rslib/src/scheduler/fsrs/params.rs`（`compute_params` 全貌）：
  <https://github.com/ankitects/anki/blob/main/rslib/src/scheduler/fsrs/params.rs>
- 预设字段 `proto/anki/deck_config.proto`：
  <https://github.com/ankitects/anki/blob/main/proto/anki/deck_config.proto>
- 前端 `ts/routes/deck-options/FsrsOptions.svelte`：
  <https://github.com/ankitects/anki/blob/main/ts/routes/deck-options/FsrsOptions.svelte>
- fsrs-rs v5.1.0 训练循环 `src/training.rs` / 初始化 `src/parameter_initialization.rs`：
  <https://github.com/open-spaced-repetition/fsrs-rs/blob/v5.1.0/src/training.rs>
- fsrs-rs 主线 `docs/BURN_REMOVAL.md` / `docs/TRAINING_DATA_FLOW.MD`：
  <https://github.com/open-spaced-repetition/fsrs-rs/blob/main/docs/BURN_REMOVAL.md>
- `ts-fsrs-optimizer`（JS 移植）：<https://www.npmjs.com/package/ts-fsrs-optimizer>

---

## 附：本仓库里的锚点

| 位置 | 内容 |
|---|---|
| `lib/src/logic/fsrs.dart` | `kFsrs6DefaultParameters`（dart-fsrs 自带）、`kFsrs6AnkiParameters`（Anki 25.09 那套）、`FsrsConfig` |
| `lib/src/data/anki/anki_schema.dart` | `wc_answer_log` 等 `wc_` 扩展表（训练数据来源） |
| `lib/src/data/anki/anki_record_repository.dart` | 作答记录读写（将来训练集的取数入口） |
| `wc_settings` | `key/value` JSON；将来放优化结果与上次优化时间 |

**当前决定**：参数不优化，用 `kFsrs6AnkiParameters`；
本文件只在真要开工时读。
