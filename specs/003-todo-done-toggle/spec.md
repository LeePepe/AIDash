# Spec 003 — 今日规划任务的完成态勾选（TODO done toggle）

## 1. 意图（Why）

「今日规划」container 用 `todoList` 卡渲染当天的行动项（TodoListCardView）。当前
是**纯只读**的——用户能看到任务，但没有任何"我做完了 / 取消完成"的交互通道。用户
希望把它当成真正的 TODO：**点一下勾选完成，再点取消**，并且完成的任务有明确视觉
标识（划线/勾/置灰）。

这条完成信号目前完全丢失。补上它，让今日规划从"只读清单"变成"可勾选清单"。

## 2. 复用既有架构（关键 — 不重造）

spec 002（star/收藏反馈闭环）已经建好一套**完全可复用**的用户事件机制，本 feature
沿用同一模式，只把 action 从 `.star` 换成 `.done`：

- **`UserEventAction.done` 已存在**（`Packages/AIDashCore/…/Models/UserEventAction.swift:2`）——
  枚举里 `case done` 已定义，尚未被 TodoList 使用。无需扩枚举。
- **`UserEvent` + `UserEventModel`（SwiftData）**：append-only 事件 + 本地持久化 +
  CloudKit 同步，已就绪。
- **toggle 从事件流推断**（spec 002 D2 的既定模式）：无独立 "un-done" action，当前
  完成态由该 itemRef 的事件历史推断（最新一条 done 事件的存在/计数奇偶，沿用 002
  对 star 的同一推断规则）。
- **`UserEventWriter`**（App 层，唯一事件写入者，constitution §II）：已有 `.star(...)`
  方法,照此加 `.done(cardId:itemRef:)`。
- **environment 注入模式**：TrendingCardView 用 `@Environment(\.starredItemRefs)` +
  `onStarItem` 闭包读当前态/发意图。TodoListCardView 照此加 `doneItemRefs` +
  `onToggleDone`。

## 3. 行为契约（What）

### 用户可见行为
- 今日规划卡的每个任务项前有一个可点击的勾选控件（圆圈/checkbox）。
- 点击未完成任务 → 标记完成：视觉上划线 + 勾选 + 置灰，并 append 一条
  `UserEvent(action:.done, itemRef:<任务标识>)`。
- 点击已完成任务 → 取消完成（沿用 002 的 toggle-from-events 推断，append 一条事件
  翻转推断态）。
- 完成态**跨 app 重启/跨天/跨设备保持**（本地 SwiftData + CloudKit，和 star 一致）。
- 点击目标 = 勾选控件；任务若同时有 ref（issue/PR 链接），标题仍可保留只读展示，
  **本 feature 不做 ref 跳转**（用户已明确：点击 = toggle done，不是跳转）。

### itemRef 的稳定性（关键约束）
任务项当前没有稳定 id（TodoListPayload.Item 有 title/priority/due/ref，无 id）。
完成态要靠 itemRef 跨天保持，需要一个**稳定标识**：
- 若 Item.ref 存在（issue/PR URL），用 ref 作 itemRef（天然稳定）。
- 若无 ref，用 title 的规范化 hash 作 itemRef（同一任务文案跨天稳定；文案变了视为
  新任务，可接受）。
- 这条决策与 002 对雷达 item 用 repoURL 作 itemRef 同源。

## 4. Acceptance criteria
- [ ] 今日规划每个任务项有可点击勾选控件；点击 toggle 完成态并 append 一条
      `UserEvent(action:.done, itemRef:…)`。
- [ ] 完成态视觉标识清晰（划线+勾+置灰）。
- [ ] 完成态跨 app 重启保持（SwiftData 持久化 + 从事件推断，沿用 002）。
- [ ] itemRef 稳定：有 ref 用 ref，无 ref 用 title 规范化 hash。
- [ ] 事件仅由 App 层 UserEventWriter 写入（constitution §II：CLI 不写事件）。
- [ ] 三正交卡片维度不混淆；渲染失败优雅回退；无 fatalError/try!/as!。
- [ ] `swift test --package-path Packages/AIDashUI` 与 `Packages/AIDashCore` 全绿。

## 5. Out of scope
- 点击跳转到 ref（用户明确不做）。
- aidata 侧消费 done 事件（可后续像 star 一样 `aidash events pull --action done`
  拉回分析——独立增量，不在本 feature）。
- 任务的增删改（今日规划仍由 aidata 生成，App 只加完成态）。

## 6. 按 layer 的 task 拆分（speckit tasks）
- **Stage 1 (AIDashCore)**: `UserEvent.done(cardId:itemRef:device:)` factory（仿
  `.star`）+ itemRef 稳定化 helper（ref 优先、否则 title hash）+ 单测。
- **Stage 2 (App)**: `UserEventWriter.done(cardId:itemRef:)` + 从事件推断某 card 的
  doneItemRefs 集合（仿 star 的推断）+ 单测。
- **Stage 3 (AIDashUI)**: TodoListCardView 加勾选控件 + `@Environment(\.doneItemRefs)`
  + `onToggleDone` 闭包 + 完成态样式（划线/勾/置灰）；App 注入 environment。快照/行为测。

依赖顺序：Stage1 → Stage2 → Stage3（用 Multica --stage barrier）。

## 7. Constitution refs
- §II：App 层是唯一事件写入者，CLI 不写事件。
- AIDashUI red_lines：容器通用渲染槽、三正交维度不混淆、无 fatalError/try!/as!、
  颜色走 DesignKit seed。
- 沿用 spec 002 D2 的 append-only 决策。

## 8. 决策修订（D-003-1，2026-08-01）：toggle-from-parity → latest-wins（跨设备）

**背景**：Stage 1（MY-1308，#129）与 Stage 2（MY-1309，#130）已按原文的
**toggle-from-parity**（done 事件计数奇偶：奇=完成、偶=取消）实现并合并进 main。
随后确立的产品目标是 **Mac + iPhone 双设备经 iCloud 同步**（见 spec 004），parity
在此场景下有正确性缺陷：

> 两台设备离线各点一次「完成」→ 同步后该 itemRef 有 2 条 `.done` 事件 → 计数为偶
> → 推断成「未完成」→ **丢掉一次勾选**。

star 用「存在即已收藏」（presence、幂等）规避了此问题，但 done 是真正的双向 toggle，
presence 不适用。因此本 feature 的完成态推断**从 parity 改为 latest-wins**：

- **新增 `UserEventAction.undone`**（append-only 不变——取消完成 append 一条 `.undone`，
  不删任何行，仍满足 §I / §II）。
- **状态推断（latest-wins）**：某 itemRef 取其**最新 timestamp** 的一条事件——`.done`
  → 已完成，`.undone` → 未完成，无事件 → 未完成。跨设备两端各点一次时，取较晚的一次为准，
  不再互相抵消。
- **`UserEvent.done` / `UserEventWriter` 需相应调整**：新增 `.undone` factory；写入方
  按目标态 append `.done` 或 `.undone`（不再靠再点一次 `.done` 翻转）；推断函数从
  「count 奇偶」改为「按 itemRef 分组取最新事件」。
- **CloudKit 合并语义**：`UserEventModel` 仍 append-only，两设备各自的事件都保留并同步，
  latest-wins 在读取端按 timestamp 归并，无写冲突。设备时钟偏差极端下可能取错较晚者
  （可接受的 v1 限制，与「文案变=新任务」同级）。

**迁移**：已合并的 parity 版 Core/App 代码由 spec 004 的迁移 task 改为 latest-wins；
UI（MY-1310 / T003）直接按 latest-wins 的 `doneItemRefs` + `onToggleDone(done:)` 契约实现。
