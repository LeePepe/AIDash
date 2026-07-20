# Tasks — Feature 002 Star / 收藏 反馈闭环

按 **layer 收窄**（AGENTS.md 硬规则）拆分。每个 task = 一层 = 一个独立可 build/test
的 commit。依赖用 `--stage` 表达（Multica staged barrier）。

参照：`spec.md`（本目录）、`specs/001-core-briefing-cli/data-model.md`（UserEvent 定义源）、
`.specify/memory/constitution.md`。

---

## Stage 1 — 数据契约（blocker，其余全部依赖它）

### T001 · [Core] UserEvent 加可选 itemRef + 事件构造 helper

**layer**: AIDashCore
**depends_on**: []（零依赖）
**test**: `swift test --package-path Packages/AIDashCore`

给 `UserEvent`（Models/UserEvent.swift）与 `UserEventModel`（Storage/UserEventModel.swift）
增加**可选** `itemRef: String?`——被星标条目的稳定标识（雷达即 repo 的 GitHub URL）。

- additive、向后兼容：`UserEventModel` 新属性给默认值（CloudKit 兼容要求 scalar 可选/
  带默认，无 `@Attribute(.unique)`）；`UserEvent` 的 Codable 让旧记录解码为 nil（同
  TrendingPayload 里 delta/category/reason 的 forward-compat 手法）。
- `EventsPullParams` 增加可选 `itemRef` 过滤位（对齐现有 cardId/action 过滤），
  `EventsPullResult` 里的 `UserEvent` 自然带上 itemRef。
- 增一个 Core 层事件构造 helper（如 `UserEvent.star(cardId:itemRef:device:)` 或一个
  工厂），封装 UUID 生成 + timestamp，供 App 层调用（避免 App 层散落构造逻辑）。
- 在 `specs/001-core-briefing-cli/data-model.md` 的 UserEvent 块补记 `itemRef` 字段
  + 一句语义说明。
- **D2 取舍在此定**：toggle 是否需要显式 `unstar`？默认「只发 star、UI 态由已发事件
  推断」（不新增 enum case）。若评审认为富化侧必须显式撤销，再决定加 `UserEventAction.unstar`；
  spec 只约束 append-only、不删行。把最终决定写进 `specs/001-core-briefing-cli/data-model.md`。

**Acceptance**
- [ ] `UserEvent` 与 `UserEventModel` 均有可选 `itemRef`，旧记录/旧 JSON 解码为 nil 不报错（round-trip 测试）。
- [ ] `EventsPullParams` 支持按 `itemRef` 过滤（可选）。
- [ ] 提供 Core 层 star 事件构造 helper，有单测覆盖（id 非空 UUID、action==.star、itemRef 透传）。
- [ ] `swift test --package-path Packages/AIDashCore` 全绿。
- [ ] `specs/001-core-briefing-cli/data-model.md` 已记录 itemRef 及 D2 决定。

**Blocked by**: None — 可立即开始。

---

## Stage 2 — 读回入口 + UI 呈现（并行，均依赖 T001）

### T002 · [CLI] 实现 aidash events pull（T170 stub → 真实实现）

**layer**: aidash CLI（顶层 `CLI/**`，非 Packages 层；build/test 门在 pre-push/CI）
**test**: `xcodebuild -scheme aidash -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build`
（+ CLI 的 `*CommandTests` 单测，参照现有 BriefingGetCommand 的测试形态）

`AIDashCLI.swift` 的 `EventsPullCommand` 现在是 stub（返回 "not yet implemented (T170)"）。
实现它——这是 aidata 拉回星标信号的读回入口。

- 参数：`--since`（必填，date）`--until`（可选）`--card-id`（可选）`--action`（可选，done|star）
  `--item-ref`（可选，T001 新增的过滤位）；用现有 `DateResolver` 解析日期。
- 走现有 XPC 通道：`XPCClient` 发 `events.pull` 请求（App 侧 handler 已存在，见
  XPCHandlers.swift:426 `handleEventsPull`），拿 `EventsPullResult`。
- 输出：复用现有 `OutputFormatter`（human + `--json`），json 分支给 aidata 消费，每条含
  id/timestamp/device/cardId/itemRef/action。
- 退出码走现有 `ExitCode`/`ExitCodeMapper`。
- **注意**：CLI 只读 events，绝不写（宪法铁律）。

**Acceptance**
- [ ] `aidash events pull --since <date> --json` 返回真实事件数组（不再是 stub 报错）。
- [ ] 支持 `--action star` / `--item-ref <url>` / `--card-id` / `--until` 过滤，组合生效。
- [ ] `--json` 输出每条含 itemRef 字段；human 输出可读。
- [ ] 新增 `EventsPullCommandTests`（映射/参数解析/退出码），随 CLI 构建通过。

**Blocked by**: T001（需要 itemRef 已在 EventsPullParams/UserEvent 上）。

### T003 · [UI] 雷达条目星标按钮 + environment 动作注入

**layer**: AIDashUI
**depends_on**: [AIDashCore, DesignKit]
**test**: `swift test --package-path Packages/AIDashUI`

给 `TrendingCardView` 的条目（`TrendingItemRow` 紧凑态 + `TrendingRepoCell` hero 态）
加星标按钮。UI 层保持纯净——不碰存储（红线：视图层无副作用、无 App 侧逻辑）。

- 新增一个 SwiftUI `Environment` key 注入动作闭包，语义如
  `onStarItem: (_ cardId: String, _ itemRef: String, _ desiredStarred: Bool) -> Void`，
  以及一个「当前是否已星标」查询闭包/集合（如注入一个 `starredItemRefs: Set<String>`
  让 UI 决定 filled/outline）。默认值为 no-op / 空集合 → 预览与快照不崩、纯视觉降级。
- 星形按钮：filled/outline 切换，tint `theme.primary`，点击轻动画；比未来的 done 更突出
  （spec 001 US3 + 本 spec D3）。触达区 ≥ 44pt。
- itemRef 用条目的 `item.url`（雷达条目稳定主键）。cardId 从渲染上下文取（`CardRouter`
  持有 `CardModel`，需把 card.id 透传进 TrendingCardView / 条目，或经 environment 提供
  当前 cardId）。评审时定「cardId 怎么到条目」的最干净路径（倾向 environment 提供
  currentCardId，避免给纯 payload 视图塞 model id）。
- 无障碍：星标按钮有独立 accessibilityLabel（如「星标 / 取消星标 <repo>」）并合入现有
  条目 accessibility。
- 快照回归：走既有 `AIDASH_SNAPSHOT`/`SnapshotRenderTests` harness，验证有/无星标态渲染。

**Acceptance**
- [ ] 雷达紧凑态与 hero 态每个条目都有星标按钮，filled/outline 由注入的已星标集合驱动。
- [ ] 点击调用注入的 `onStarItem` 闭包并传对 cardId + itemRef(url) + desired 态；未注入时 no-op 不崩。
- [ ] 星标视觉比普通 pill 更突出，触达区 ≥44pt，有 accessibilityLabel。
- [ ] `swift test --package-path Packages/AIDashUI` 全绿（含快照/token 合规测试）。

**Blocked by**: T001（需要事件语义确定；itemRef 概念对齐）。可与 T002 并行。

---

## Stage 3 — 接线写回（依赖 T001+T003）

### T004 · [App] 事件写入服务 + 把 star action 接到 BriefingView

**layer**: AIDashApp（顶层 `Apps/**`，build/test 门在 pre-push/CI）
**test**: `xcodegen generate` 后
`xcodebuild -scheme AIDashApp -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build`
（+ 若加了 App 层测试，走 AIDashAppTests；参照现有 XPCHandlers*Tests 形态）

补上 app 的 **events 写回能力**（app 目前从不写 events——这是本 feature 的核心新增）。

- 新增一个 App 层「UserEvent 写入服务」：接 cardId + itemRef + desired 态，用 T001 的
  Core helper 构造 `UserEvent`，`modelContext.insert(UserEventModel(...))` 写进 app 的
  SwiftData 容器（`CloudKitContainer`，其 `events` 由 NSPersistentCloudKitContainer 镜像
  到 CloudKit）。device 用现有 `DeviceIdentifier`。
- 把这个服务经 T003 定义的 `Environment` 注入 `BriefingView`（在 `BriefingWindowScene`
  的 `.ready(container)` 分支，紧邻 `.designTheme`/`.modelContainer` 处注入 onStarItem +
  starredItemRefs）。
- starredItemRefs：从本机已发、未撤销的 star 事件（按 cardId+itemRef）推断（@Query
  UserEventModel where action==star），喂回 UI 决定 filled 态（US2）。
- 遵守宪法：只 **insert**（append-only），绝不 update/delete 既有 event 行；只写 events，
  不碰 briefing 内容。
- headless/agent 模式（`AIDASH_XPC_AGENT=1`，见 [[aidash-data-pipeline-and-xpc]]）无 GUI、
  local-only，不渲染 BriefingView → 本 task 只影响 GUI 模式，注意别在 agent 模式引入
  CloudKit mirror（会 SIGTRAP）。

**Acceptance**
- [ ] GUI 模式下点雷达条目星标 → 一条 UserEventModel(action=star, itemRef=url) 落进 SwiftData（可在测试/调试菜单验证）。
- [ ] 重启 app / 跨设备同步后，已星标条目回显 filled（starredItemRefs 由已发事件推断）。
- [ ] 只 insert，不 update/delete 既有事件行（append-only）。
- [ ] `xcodebuild -scheme AIDashApp ... build` 通过；agent 模式不受影响、不引入 CloudKit mirror 崩溃。

**Blocked by**: T001 + T003。

---

## 依赖图

```
T001 (Core, Stage1) ──┬─► T002 (CLI,  Stage2)
                       ├─► T003 (UI,   Stage2)
                       │
        T003 ──────────┴─► T004 (App,  Stage3)
```

## 闭环验证（人工，跨 stage 完成后）

1. GUI 跑 app，渲染一张真实雷达卡，点两个仓库条目的星标。
2. Mac 上 `aidash events pull --since <today> --action star --json` → 应返回 2 条，
   itemRef == 两个 repo url。
3. （follow-up，aidata repo）aidata 用同命令拉回，富化雷达——不在本 feature。
