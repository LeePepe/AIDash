# Tasks — Feature 003 今日规划任务完成态勾选（TODO done toggle）

按 **layer 收窄**（AGENTS.md 硬规则）拆分。每个 task = 一层 = 一个独立可 build/test
的 commit。依赖用 `--stage` 表达（Multica staged barrier）。

参照：`spec.md`（本目录，尤其 §8 latest-wins 决策修订）、
`specs/001-core-briefing-cli/data-model.md`（UserEvent 定义源）、
`.specify/memory/constitution.md`。

> **状态说明（2026-08-01）**：原 Stage 1 / Stage 2 已按 **toggle-from-parity** 实现并
> 合并进 main（MY-1308 #129 / MY-1309 #130）。spec.md §8 将完成态推断改为
> **latest-wins**（跨设备可靠）。因此本 tasks.md 重排为：**M1 迁移**已合并的 Core/App
> 从 parity → latest-wins，**M2 UI** 按 latest-wins 契约实现勾选控件。

---

## Stage 1 — Core 迁移到 latest-wins（blocker）

### T101 · [Core] UserEventAction.undone + latest-wins factory

**layer**: AIDashCore
**depends_on**: []
**test**: `swift test --package-path Packages/AIDashCore`

已合并的 `UserEvent.done` factory（Models/UserEvent.swift）用 parity 模型、无 `.undone`。
迁移到 latest-wins：

- `UserEventAction` 加 `case undone`（Models/UserEventAction.swift，rawValue `"undone"`；
  CaseIterable / Codable 自动带上）。旧记录不含 undone，向后兼容。
- `UserEvent` 加 `.undone(cardId:itemRef:device:)` factory，仿 `.done`（同结构，action=.undone）。
- 更新 `UserEvent.done` 的 doc-comment：不再说「无 .undone / 靠再点一次 done 翻转」，
  改述 latest-wins（取消完成 append 一条 `.undone`）。
- `stableItemRef` helper（MY-1308 已建）**保持不变**——ref 优先、否则 title 规范化摘要
  （确定性摘要，禁 `Hasher`/`hashValue`）。仅确认其确定性测试仍在。
- 在 `specs/001-core-briefing-cli/data-model.md` 的 UserEventAction 块补记 `undone` +
  一句 latest-wins 语义。

**Acceptance**
- [ ] `UserEventAction.undone` 存在；`UserEvent.undone(...)` factory 有单测（action==.undone、itemRef 透传、UUID 非空）。
- [ ] `UserEvent.done` doc-comment 反映 latest-wins。
- [ ] `stableItemRef` 确定性测试仍全绿（同文案同 ref、大小写/空白差异同 ref、异文案异 ref）。
- [ ] `swift test --package-path Packages/AIDashCore` 全绿。
- [ ] data-model.md 已记录 undone + latest-wins。

---

## Stage 2 — App 层迁移到 latest-wins

### T102 · [App] UserEventWriter.setDone + latest-wins doneRefs 推断

**layer**: AIDashApp（依赖 AIDashCore）
**depends_on**: [T101]
**test**: `xcodebuild test -scheme AIDashApp -destination 'platform=macOS'`（跑整个 AIDashAppTests，逐条核对 passed；swift-testing 勿用 -only-testing 过滤单 @Suite）

已合并的 `UserEventWriter.done`（Apps/AIDashApp/Sources/Sync/UserEventWriter.swift）与
parity 推断迁移到 latest-wins：

- `UserEventWriter` 加/改为 `setDone(cardId:itemRef:done:)`——按目标态 append 一条
  `.done` 或 `.undone` 事件（**不 dedup**，best-effort `try? save()`，同 star 的容错）。
  保留或废弃旧 `done(...)` 由实现决定，但对外契约是 setDone。App 是唯一事件写入者（§II）。
- 推断从「count 奇偶」改为 **latest-wins 纯函数**，便于测：
  `static func doneRefs(from events: [UserEventModel]) -> Set<String>`——按 itemRef 分组，
  取每组最新 timestamp 的事件，`.done` 则计入集合。
- 更新调用点（若 BriefingWindowScene 已引用旧 done 推断）指向新纯函数。

**Acceptance**
- [ ] `setDone(...,done:true)` append 一条 `.done`；`done:false` append 一条 `.undone`。
- [ ] `doneRefs(from:)` latest-wins：done 后 undone → 不在集合；undone 后 done → 在集合；
      跨设备两条 done → 仍在集合（不再互相抵消）。
- [ ] 单测全绿；事件仅 App 层写入；无 fatalError/try!/as!。

---

## Stage 3 — UI 勾选控件（latest-wins 契约）

### T103 · [UI] TodoListCardView 勾选控件 + 完成态样式

**layer**: AIDashUI（依赖 AIDashCore + DesignKit）
**depends_on**: [T102]
**test**: `swift test --package-path Packages/AIDashUI`

沿用 spec 002 star 的 environment 注入模式（TrendingCardView 的 `StarItemButton`）：

- 加 done env 键（StarActionEnvironment.swift 或兄弟文件 DoneActionEnvironment.swift）：
  `ToggleDoneAction = @MainActor @Sendable (_ cardId:String,_ itemRef:String,_ done:Bool)->Void`；
  `EnvironmentValues.onToggleDone`（默认 nil）+ `doneItemRefs: Set<String>`（默认 []）。
- `TodoListCardView` 的 `TodoItemRow` 当前渲染静态 `Image(systemName:"circle")`——替换成
  `TodoCheckboxButton`，结构照抄 `TrendingCardView` 的 `StarItemButton`：
  - 读 `@Environment(\.onToggleDone/.doneItemRefs/.currentCardId/.theme)`
    （`currentCardId` 已由 CardRouter 注入，无需改 router）。
  - `itemRef = item.stableItemRef`；`isDone = doneItemRefs.contains(itemRef)`；乐观本地
    `@State` 翻转；tap → `onToggleDone(currentCardId, itemRef, !shown)`（latest-wins：
    显式传目标态，不靠再点翻转）。
  - 图标 `checkmark.circle.fill`（done）/`circle`（未），hit target 复用
    `AIDashSpacing.starButtonHitTarget`（mac 28 / touch 44，§E.3），`.buttonStyle(.plain)`，
    a11y label 本地化。
- 完成态样式（走 DesignKit token，禁硬编码色）：done 时 title `.strikethrough(true)` +
  `.foregroundStyle(theme.neutrals.text3)`（置灰）；勾选填充 `theme.primary.primary`。
- App 侧在 BriefingWindowScene 的 FeedbackScope（原 StarFeedbackScope）注入 `\.doneItemRefs`
  （用 T102 的 `doneRefs(from:)`）+ `\.onToggleDone`（调 `setDone`），与 star 两套 env 同注。
- 更新 previews 展示 done 行（注入 `\.doneItemRefs`）；本地化 xcstrings 加
  `todo.done_button.label` / `todo.done_button.label.done`（bundle:.module，仿 trending.star_button.label*）。

**Acceptance**
- [ ] 每个任务项有可点击勾选控件；点击 toggle 完成态并经 `onToggleDone` 发意图（带目标态）。
- [ ] 完成态视觉：划线 + 勾 + 置灰，走 DesignKit token（无 hex/系统色作信号）。
- [ ] 三正交维度不混淆；渲染失败优雅回退；无 fatalError/try!/as!。
- [ ] ≥2 个 #Preview 覆盖不同 CardSize（含一个 done 态）；`DoneActionEnvironmentTests` 覆盖
      默认 nil/空 + round-trip(cardId,itemRef,done)。
- [ ] `swift test --package-path Packages/AIDashUI` 全绿。

---

## 依赖顺序
Stage 1（T101）→ Stage 2（T102）→ Stage 3（T103），用 `--stage` barrier。
