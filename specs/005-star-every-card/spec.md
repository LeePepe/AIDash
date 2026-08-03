# Feature 005 — Star 每一张卡片 + 修复 done 布线缺失

> **Status**: spec · 2026-08-03
> **Constitution basis**: 原则 I(Agent-Authored, User-Read)把 `star` / `done`
> 列为 app 唯一允许的 append-only 用户事件;原则 II 画好反馈闭环(App 写 events →
> CloudKit `events` → agent `aidash events pull` 异步拉回)。本 feature **不新增
> 架构**:把 spec 002 已规格化、已在雷达单项落地的 `star` 能力**扩到任意整张卡**,
> 并**补上 spec 003 done 能力在 UI 侧漏接的布线**——两者复用同一套 environment 注入
> + append-only writer 范式。

---

## 1. 意图(Why)

### 1a. star 每一张卡片

反馈闭环(spec 002)目前只有**一个入口**:GitHub 工具雷达卡里的**单个仓库条目**
可以 star(`itemRef == repo url`)。其它所有卡型——缓存命中率、返工率、失败根因、
新闻雷达、TODO——用户读到时即使"这张卡对我有用 / 我想多看这类",也**没有任何通道
把这个偏好发出去**。于是 aidata 只知道用户点了哪个 repo,不知道用户对**哪一类卡**
感兴趣。

本 feature 补上这条通道:**给每一张卡一个整卡级 star**。点一下 = append 一条
`UserEvent(action: .star, cardId: <卡 id>, itemRef: nil, cardType: <卡型>)`。
`itemRef == nil` 正是宪法/spec 002 D1 为"整卡事件"预留的语义(vs 单项 star 的
`itemRef == repo url`),两者**共存**,聚合时以 `itemRef IS NULL` 区分,不双计。

**这个信号在管道里的落点**:
```
用户点整卡星 ──► app 写一条 UserEvent(itemRef=nil, cardType=...) ──► CloudKit events
                                                        │  (L1 原始信号, append-only)
                                                        ▼
   aidata: aidash events pull --action star --since ...
                                                        ▼
   L2: 一行一事件, item_ref=NULL 保留, card_type 保留
                                                        ▼
   L4: 近 7 天各 card_type 的整卡 star 计数(第一个消费者)
                                                        ▼
   L5: 一张 insight 卡「你最常收藏的卡型」
```

### 1b. 修复 done 的 UI→writer 布线缺失(与 star 同一范式,故并入本 spec)

spec 003 / MY-1372 交付了 `UserEventWriter.setDone(cardId:itemRef:done:)` 方法**和它
的单元测试**(`UserEventWriterTests`),以及 `doneRefs(from:)` 的 latest-wins 推断。
**但没有任何 scene 或视图把 TodoList 卡的勾选接到这个 writer**:

- `TodoItemRow`(`TodoListCardView.swift:151`)的完成圈是
  `Image(systemName: "circle")` + `.accessibilityHidden(true)`——一个**静态装饰**,
  不是 `Button`,点不动。
- App 侧没有 `onToggleDone` 之类的 environment 注入(对比 star 有
  `StarFeedbackScope` 注入 `onStarItem`)。

结果:**方法在、测试绿、按钮却是死的,点 done 不产任何事件**。这正是"空心功能"
——method-in / button-static / no-wiring。因为它与 star 是**同一套** environment
注入 + append-only writer 范式,在本 spec 一起接线,避免各修一遍、避免再次漏接。

> **硬约束(本 spec 存在的直接原因)**:必须有一个**显式的「UI→writer 布线验证」
> task/acceptance**——不是"writer 方法有测试",而是"用户在真实卡上做出动作 →
> 一条事件落到 SwiftData"这条端到端链被显式验证。见 §3 US4、§6 硬约束。

---

## 2. 关键设计决策

### D1 — 整卡 star:`itemRef == nil`,与单项 star 共存

整卡 star 复用 spec 002 已有的 `UserEvent` / `UserEventModel`,**不加新字段承载"整卡"
语义**——"整卡"就是 `itemRef == nil`(spec 002 D1 已为此预留)。

- **与单项 star 共存**:雷达卡**同时**有单项 star(条目旁,`itemRef=url`)和整卡 star
  (卡角,`itemRef=nil`)。不废弃 `StarItemButton` / `onStarItem`。
- **聚合去重**:aidata 侧整卡兴趣聚合按 `item_ref IS NULL` 过滤,单项 star 的富化
  按 `item_ref IS NOT NULL` 过滤,两条消费路径天然不交叉、不双计。
- **additive、不违宪、不需 ADR**:不引入依赖、不改依赖方向、不碰并发/隐私约束。

### D2 — 新增 `cardType` 到 UserEvent(additive,forward-compat)

**问题**:第一个消费者要的是"近 7 天**各卡型** star 数"。但 L5 的 card id 是
`_kuid(mmdd, n)` = `22222222-{mmdd}-{n:04d}-...`(`aidata/L5_apps/digest/aidash.py:164`)
——**date-scoped、按序号编,不编码卡型**。所以从 `cardId` 恢复不出卡型,更不能靠
"第 5 张一定是 todoList"这种脆弱的序号槽耦合(卡的出现是 ADR-23 条件式的,序号会漂)。

**决策**:给 `UserEvent` / `UserEventModel` 增一个**可选** `cardType: String?`,由
App 在写整卡 star 时从当前 `CardModel.type.rawValue` 填。

- **与 `itemRef` 完全同款的 forward-compat 手法**:旧记录/旧 JSON 无此键 → 解码为 nil。
- **为什么放事件里而不是 aidata join**:卡型是**事件发生当时**的事实,和事件一起走
  最简单、最稳,不依赖 briefing 是否进仓、不依赖任何跨表 join。
- **单项 star / done 也顺带带上**(可选、无害):写事件时能拿到卡型就填,填了对未来
  的"按卡型看 done 完成率"等指标零成本铺路;拿不到就 nil,不强制。
- schema 单源:字段只加在 Core 的 `UserEvent`,App/CLI 不各自重定义。

### D3 — done toggle:接线,不改语义(沿用 spec 003 latest-wins)

done 的**语义层**(`setDone` / `done`/`undone` 工厂 / `doneRefs` latest-wins 推断)
spec 003 已做完且有测试,本 spec **不碰语义**,只补 UI→writer 布线:

- `TodoItemRow` 的完成圈从静态 `Image` 换成 `Button`,tap → 调 environment 注入的
  `onToggleDone(cardId, itemRef, done)` 闭包。填充态(圈 vs 勾)由注入的
  `doneItemRefs`(App 从 `doneRefs(from:)` 算)驱动,与 star 的 `starredItemRefs`
  完全对称。
- itemRef 用 `UserEvent.stableItemRef(for: item)`(spec 003 已实现的稳定派生:有
  `item.ref` 用之,否则 `title:` + SHA256(归一化 title))。
- **纯净性(原则 II + AIDashUI 红线)**:UI 层只发意图闭包,绝不碰 SwiftData/CloudKit;
  闭包未注入(预览/快照/测试)时降级为纯视觉 no-op,不崩。

### D4 — UI 层保持纯净:动作经 environment 注入(沿用 spec 002 D4)

整卡 star 与 done 都遵循 spec 002 D4 已确立的范式,**新增两组** environment 值,与
现有 `onStarItem` / `starredItemRefs` / `currentCardId` 对称:

| 用途 | 现有(单项 star) | 本 spec 新增 |
|---|---|---|
| 发意图 | `onStarItem: (cardId, itemRef)->Void` | `onStarCard: (cardId, cardType)->Void`;`onToggleDone: (cardId, itemRef, done)->Void` |
| 填充态 | `starredItemRefs: Set<String>` | `starredCardIds: Set<String>`;`doneItemRefs: Set<String>` |

App 侧在 `StarFeedbackScope`(现有,`BriefingWindowScene.swift`)里**扩注入**:
- `onStarCard` → `writer.star(cardId:itemRef:nil, cardType:)`(整卡)
- `onToggleDone` → `writer.setDone(cardId:itemRef:done:)`(接 spec 003 已有方法)
- `starredCardIds` ← `@Query` 过滤 `action==star && itemRef==nil` 的 cardId 集合
- `doneItemRefs` ← `UserEventWriter.doneRefs(from:)`(已有)

未注入时全部降级 no-op(预览/快照)。

### D5 — 整卡 star 的视觉与触达(承接 spec 001 US3 / 002 D3)

整卡 star 是卡角的一个小星形按钮(filled/outline 由 `starredCardIds` 驱动),tint
`theme.primary`,轻点动画,44pt(iOS)/28pt(macOS)最小触达(宪法 §E.3)。它必须
**不遮挡、不改**卡片既有 chrome/内容(原则 VI:star 是内容信号,不是 `style`/`size`
维度)。与雷达单项 star 视觉一致,读者一眼知道"这是收藏动作"。

### D6 — 消费者最小化:先只采集 + 一个聚合,不建浏览面

用户明确"先只采集不急定消费"。本 spec 的**唯一**消费者是一张聚合 insight 卡(§3 US5)。
**out of scope**:app 内"收藏夹/置顶"浏览视图(宪法原则 III glanceable 单一简报面,
不新增浏览面;列 v2)。

---

## 3. User Stories

### US1 — 用户 star 一张整卡(P1)
**Given** 简报里任意一张卡(非 sectionHeader)角上有一个整卡 star 按钮,
**When** 用户点它,
**Then** 100ms 内星形切 filled + 轻动画,且一条
`UserEvent(action:.star, cardId:<卡 id>, itemRef:nil, cardType:<卡型>, device, timestamp)`
写入本机 SwiftData 并排队镜像到 CloudKit `events`。

### US2 — 整卡 star 态跨重启/设备保持(P2)
**Given** 用户 star 过某张卡,
**When** 事件经 CloudKit 同步到另一设备、或 app 重启重渲染同一张卡,
**Then** 该卡 star 显示 filled(态由"本账号已发、`itemRef==nil` 的 star 事件按 cardId"
推断——与 spec 002 单项态推断同构)。

### US3 — 单项 star 与整卡 star 共存(P1)
**Given** 一张雷达卡同时有条目单项 star 和卡角整卡 star,
**When** 用户分别点它们,
**Then** 产生两条不同事件(单项 `itemRef=url`;整卡 `itemRef=nil`),互不影响填充态,
aidata 聚合按 `item_ref IS NULL` 区分不双计。

### US4 — 用户勾选一个 TODO 项产出 done 事件(P1,修复空心功能)
**Given** 一张 todoList 卡渲染了若干可勾选任务项,
**When** 用户点某项的完成圈,
**Then** 该项 100ms 内切到"已完成"视觉,且一条
`UserEvent(action:.done, cardId:<卡 id>, itemRef:<stableItemRef>, device, timestamp)`
写入本机 SwiftData;**再点一次** append 一条 `action:.undone`(latest-wins 清除完成态,
spec 003 §8 语义,本 spec 不改)。

### US5 — agent 拉回并聚合出"卡型兴趣"(P1,闭环另一半 + 第一个消费者)
**Given** 用户过去几天 star 过若干整卡、勾过若干 TODO,
**When** aidata 运行 `aidash events pull --action star`(spec 002 T002 已实现读回),
**Then** 得到所有 star 事件带 `cardId`/`itemRef`(整卡为 NULL)/`cardType`/`device`/
`timestamp`;aidata L2 落库后,**L4 一条查询**产出"近 7 天各 `card_type` 的整卡
(`item_ref IS NULL`)star 计数",**L5 一张 insight 卡**渲染"你最常收藏的卡型 Top-N"。

---

## 4. 范围边界

**In scope**(按 layer):
- **Core**(`AIDashCore`):`UserEvent`/`UserEventModel` 加可选 `cardType`;整卡 star
  工厂 `UserEvent.starCard(cardId:cardType:device:)`(itemRef=nil);
  `specs/001-core-briefing-cli/data-model.md` 记录。
- **UI**(`AIDashUI`):(a)新增 4 个 environment 值(D4 表);(b)整卡 star 按钮
  (CardRouter 层,覆盖所有卡型,sectionHeader 除外);(c)`TodoItemRow` 完成圈换
  Button + 接 `onToggleDone` + `doneItemRefs` 驱动填充态。
- **App**(`AIDashApp`):`StarFeedbackScope` 扩注入 `onStarCard`/`onToggleDone` 及
  `starredCardIds`/`doneItemRefs`;`writer.star` 支持整卡(itemRef=nil, cardType)。
- **aidata L1/L2**(`aidata/adapters/aidash_events.py`):`item_ref` 已保留;新增
  `card_type` 列的采集/归一(NULL 兼容)。
- **aidata L4**(`aidata/L4_serve/queries/`):新增"近 7 天各 card_type 整卡 star 计数"查询。
- **aidata L5**(`aidata/L5_apps/digest/`):新增一张"卡型兴趣" insight 卡 + golden 冻结。

**Out of scope**(v2 / follow-up):
- app 内"收藏夹/置顶"浏览视图(D6;宪法原则 III)。
- 单项 star / done 的 aidata 富化与更多指标(本 spec 只做**整卡 star 一个**聚合)。
- `hide` 动作(spec 001 D17 已 defer v2)。
- 把 `cardType` 回填到历史事件(additive,旧事件 nil,不回填)。

---

## 5. 宪法对齐检查
- ✅ 原则 I:只发 append-only 事件(star/done/undone 集合内);app 不新增输入/编辑/浏览面。
- ✅ 原则 II:写路径唯一(app 写 events,CLI 读 events);done/star 均由 app writer 写,不复用 CLI 写。
- ✅ 原则 III(glanceable):不新增页面/浏览面,只在既有卡上加一个小按钮 + 让 TODO 圈可点。
- ✅ 原则 VI:star 按钮 / done 圈是**内容信号**,不碰 `size`/`style`/chrome 结构维度。
- ✅ schema 单源:`cardType` 只加在 Core 的 `UserEvent`;§E.3 触达、§F i18n 适用于新按钮。
- ✅ §User Feedback:不建任何手动 smoke-test issue;UI→writer 布线由**自动化端到端证据**验证(§6)。

---

## 6. 硬约束 — UI→writer 布线验证(不可省)

本 spec 因 done 的"方法在、按钮死、没接线"而生。为**不重蹈覆辙**,tasks.md 必须包含
一个**独立的、显式的**布线验证 task,其 acceptance **不是** "writer 有单测",而是:

- **star 整卡**:存在一个自动化测试/可执行证据,证明"在注入了真实 writer 的
  environment 下,对一张卡触发整卡 star 意图 → SwiftData 里多出一行
  `action==star && itemRef==nil && cardType==<该卡型>`"。
- **done TODO**:存在一个自动化测试/可执行证据,证明"对一个 todoList 项触发 toggle
  意图 → SwiftData 里多出一行 `action==done`,再触发一次 → 多出 `action==undone`"。
- **反向哨兵**:证明未注入 environment 时按钮为 no-op(不崩、不写)——即 UI 纯净性。

这三条对应 §7 的布线验证 task。**光有 writer 单测不满足本约束**——必须验证"UI 动作
真的到达了 writer",即 environment 闭包确实被卡视图调用(可用注入 spy 闭包断言其被调、
或在内存 ModelContainer 上断言事件行数)。

---

## 7. 落地顺序提示(详见 tasks.md,按 layer 拆)
1. Core:`cardType` 字段 + 整卡 star 工厂 + round-trip 测试(blocker,先建)。
2. UI:4 个 environment 值 + 整卡 star 按钮 + TODO 圈可点(依赖 Core 的字段/工厂)。
3. App:`StarFeedbackScope` 扩注入 + writer 整卡支持(依赖 Core + UI 的 env key)。
4. **布线验证**(§6,独立 task):端到端断言 UI 动作 → 事件行。
5. aidata L1/L2 `card_type` 采集归一 → L4 聚合查询 → L5 insight 卡 + golden。
