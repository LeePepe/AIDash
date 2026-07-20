# Feature 002 — Star / 收藏 反馈闭环(GitHub 工具雷达）

> **Status**: spec · 2026-07-20
> **Constitution basis**: 原则 I（Agent-Authored, User-Read）明确把 `star` 列为
> app 唯一允许的三种 append-only 用户事件之一（done / star / hide）；原则 II
> 画好反馈闭环（App 写 events → CloudKit `events` 记录类型 → agent 用
> `aidash events pull` 异步拉回）。本 feature **不新增架构**，只是把宪法预留、
> spec 001 User Story 3 已规格化的 `star` 能力**接线到 GitHub 工具雷达条目上**。

---

## 1. 意图（Why）

GitHub 工具雷达（feature 见 spec 001 的 TrendingCard + aidata 第 12 源）每天把
`collected-tools/` 里的仓库渲染成一张雷达卡，带 star 数 / Δ / 分类 / 推荐理由。
用户读到时会想：**「这个我感兴趣，先收藏，之后深入了解」**。

当前 app 是纯只读的——没有任何把「我对这条感兴趣」这个信号发出去的通道。于是这个
偏好信号丢失了：aidata 无从知道用户真正在意哪些工具，雷达无法据此加权、去重或
「明日放大」。

本 feature 补上这条通道：**给雷达里每个仓库条目一个星标按钮**。点一下 = 发一条
append-only `UserEvent(action: .star, itemRef: <repoURL>)`。这条事件即成为 aidata
管道的一路新 **L1 原始信号**（用户显式偏好），与 `fact_repo_snapshot`（客观 star 数）
平级。aidata 之后用 `aidash events pull --action star` 把它拉回，富化进雷达的 L2
（如 provenance=`starred` / 权重加成），最终反映到 L3 分析与明日雷达排序。

**这个信号在管道里的落点（回答「收集放到哪」）**：
```
用户点星 ──► app 写一条 UserEvent 行 ──► CloudKit `events` 记录类型
                                              │   （L1 原始信号，append-only）
                                              ▼
   aidata: `aidash events pull --action star --since ...`
                                              │
                                              ▼
   L2 富化：把「被星标」并进 repo_radar（provenance / 权重）
                                              ▼
   L3 分析 + 明日雷达排序放大被星标的工具
```

> aidata 侧（L1 采集脚本 + L2 富化）是**另一个 repo**（`~/Development/Personal/aidata`）
> 的改动，**不在本 spec 的 AIDash 交付范围内**。本 spec 交付 aidata 消费它的两个前提：
> ①**写回能力**（app 目前从不写 events）②**读回能力**（`aidash events pull` 目前是
> T170 stub）。aidata 侧作为 follow-up 单列。

---

## 2. 关键设计决策

### D1 — 星标粒度：单个仓库条目，不是整张卡

雷达卡里有 N 个仓库；用户的意图是「收藏**这一个工具**」，不是「收藏整张雷达卡」。
所以事件必须能定位到具体条目。

**现状**：`UserEvent` 只带 `cardId`（整卡级）。**需要一个可选的条目标识**。

**决策**：给 `UserEvent` / `UserEventModel` 增加一个**可选** `itemRef: String?` 字段，
存被星标条目的稳定标识——对雷达即 **repo 的 GitHub URL**（雷达条目本就以 url 为主键、
且天然稳定/全局唯一）。

- **additive、向后兼容**：旧记录 `itemRef` 解码为 nil（与 delta/category/reason 同款
  forward-compat 手法）；整卡级 `done`/`star` 仍可 `itemRef == nil`。
- **不违宪、不需要 ADR**：不引入新依赖、不改依赖方向、不碰并发/隐私约束。属于纯 schema
  additive，落到 `data-model.md` 记录即可（frontmatter 防腐 hook 不涉及此字段）。
- **不复用 CLI 写**：宪法铁律「CLI 永不写 events，只有 app 写 events」。写回由 app 在
  点击时 `modelContext.insert(UserEventModel)` 完成。

### D2 — 星标是切换（toggle），且 append-only

用户可以「星标」也可以「取消星标」。为遵守宪法「事件 append-only、app 不修改/解释
内容」：

- 「星标」→ append 一条 `action == .star` 的 UserEvent。
- 「取消星标」→ **不删除**任何行，而是 append **另一条** `action == .star`、带一个标记
  表示撤销的事件。**v1 从简**：取消星标 append 一条 `action == .done`（复用现有 enum，
  `done` 在雷达语境下即「已处理/撤销收藏」），或——若富化侧需要显式区分——在 T001
  评审时决定是否给 `UserEventAction` 增 `unstar`。**默认走「toggle 只发 star，UI 用
  本机已发 star 事件推断当前 filled 态」**，不发撤销事件（最简，且 append-only 天然满足；
  aidata 看到 star 事件流即可，重复 star 幂等按 itemRef+card 去重）。最终取舍在 T001 定，
  spec 只约束：**append-only、不删行、UI 态由已发事件推断**。

### D3 — 星标视觉比 done 更突出（承接 spec 001 US3）

spec 001 已定：`star` 必须比 `done` 更突出（更大触达区、更饱和色、专属动画）。雷达条目
的星标按钮遵循这条：filled/outline 星形图标、点击有轻动画、tint 用 `theme.primary`。

### D4 — UI 层保持纯净：动作经 environment 注入

`TrendingCardView` 在 AIDashUI 层，红线要求「无 App 侧副作用、视图层默认 @MainActor、
渲染失败优雅回退」。星标点击**不能**让 UI 层直接写 SwiftData/CloudKit（那是 App 层职责）。

**决策**：UI 层通过一个 SwiftUI `Environment` 注入的闭包（如
`onStarItem: (_ cardId: String, _ itemRef: String) -> Void`）发出意图；App 层在
`BriefingView` 外层注入真正写事件的实现。UI 层只负责「渲染星形态 + 调闭包」，不知道
CloudKit 存在。当闭包未注入（如预览/快照）时，星标按钮降级为纯视觉 no-op，不崩。

---

## 3. User Stories

### US1 — 用户星标一个雷达仓库条目（P1）

**Given** 雷达卡渲染了若干 GitHub 仓库条目，每个条目旁有一个星标按钮，
**When** 用户点击某条目的星标，
**Then** 100ms 内该星形图标切到 filled 态并播放轻动画，且一条
`UserEvent(action: .star, cardId: <雷达卡 id>, itemRef: <repo url>, device, timestamp)`
被写入本机 SwiftData 并排队镜像到 CloudKit `events` 记录类型。

### US2 — 星标态跨设备/重启保持（P2）

**Given** 用户在一台设备上星标了某条目，
**When** 事件经 CloudKit 同步到另一台设备、或 app 重启后重新渲染同一张雷达卡，
**Then** 该条目星形显示为 filled（态由「本账号已发、未撤销的 star 事件（按 cardId+itemRef）」
推断）。

### US3 — agent（aidata）拉回星标信号（P1，闭环的另一半）

**Given** 用户在过去几天星标了若干仓库，
**When** aidata 在 Mac 上运行 `aidash events pull --since <date> --action star`，
**Then** CLI 返回所有 star 事件，每条带正确的 `cardId` / `itemRef`（repo url）/ `device` /
`timestamp`，aidata 据此把这些仓库标记为「用户偏好」并入雷达富化。

**验收前提**：`aidash events pull` 当前是 T170 stub，本 feature 在 T002 实现它。

---

## 4. 范围边界

**In scope（本 spec 的 AIDash 交付）**：
- Core：`UserEvent`/`UserEventModel` 加可选 `itemRef`；事件构造 helper；`data-model.md` 记录。
- CLI：实现 `aidash events pull`（读回入口）。
- UI：雷达条目星标按钮 + 乐观填充 + environment 动作注入。
- App：事件写入服务 + 把 star action 接到 `BriefingView` environment（写回能力）。

**Out of scope（follow-up，不在本 spec）**：
- aidata 侧 L1 采集脚本 + L2 富化（另一个 repo `~/Development/Personal/aidata`）。
- app 内「收藏夹」浏览视图（宪法「glanceable 单一简报面」下不新增浏览面；v1 只发信号，
  由 agent 在明日雷达放大）。
- `done` 动作接线到其它卡型（本 feature 只碰雷达条目的 star）。
- `hide` 动作（spec 001 D17 已 defer 到 v2）。

---

## 5. 宪法对齐检查

- ✅ 原则 I：只发 append-only 事件（done/star/hide 集合内），app 不新增输入/编辑/浏览面。
- ✅ 原则 II：写路径唯一（app 写 events，CLI 读 events）；不复用 CLI 写。
- ✅ 原则 III（glanceable）：不新增页面，只在既有雷达条目上加一个小按钮。
- ✅ 无 App 侧 LLM；无新非 Apple 依赖；无 fatalError/try!/as!；Swift 6 严格并发。
- ✅ schema 单源：`itemRef` 只加在 Core 的 `UserEvent`，App/CLI 不各自重定义。
