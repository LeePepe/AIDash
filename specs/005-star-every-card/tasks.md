# Tasks — Feature 005: Star 每一张卡片 + 修复 done 布线

> 一 task = 一 layer(Constitution §Development Workflow「按 layer 拆」)。每 task 各自
> 可独立 build/test,一层一 commit。标题用 spec-kit handoff 约定 `[T###] [Story]`。
> **不建任何手动 smoke-test task**(§User Feedback):布线验证走自动化端到端证据。

---

## [T001] [Story] Core:UserEvent 加可选 cardType + 整卡 star 工厂

**Layer**: AIDashCore · **Stage 1**(blocker)· **Blocked by**: None

**What**: 给 `UserEvent`(`Models/UserEvent.swift`)和其 SwiftData 镜像
`UserEventModel` 加**可选** `cardType: String?`,forward-compat 同 `itemRef`
(旧记录/旧 JSON 无键 → nil)。新增整卡 star 工厂
`UserEvent.starCard(cardId:cardType:device:)`(`action=.star, itemRef=nil,
cardType=<非空>`)。在 `specs/001-core-briefing-cli/data-model.md` 记录该字段。

**Acceptance**:
- [ ] `UserEvent` round-trip 编解码测试覆盖 `cardType` 存在 / 缺席(nil)两路。
- [ ] `starCard(...)` 产出 `action==.star && itemRef==nil && cardType==入参`。
- [ ] 旧 JSON(无 `cardType` 键)解码为 `cardType==nil`,不抛。
- [ ] `swift test --package-path Packages/AIDashCore` 全绿。

**Constitution refs**: §IV(schema 单源,字段只加在 Core)、§D(禁 fatalError/try!/as!)、
§G.1(新 public API 带 round-trip 测试)。

**Layer 约束**(Packages/AIDashCore CONTEXT.md):
- depends_on: [](仅 Apple 框架)
- red_lines: schema 唯一来源、CLI 永不直连 CloudKit、禁 fatalError/try!/as!、Swift 6 严格并发、新非 Apple 依赖需 ADR、三正交维度不混。
- test: `swift test --package-path Packages/AIDashCore`

---

## [T002] [Story] UI:整卡 star 按钮 + TODO 完成圈可点 + 4 个 environment 值

**Layer**: AIDashUI · **Stage 2** · **Blocked by**: MY-<T001>

**What**:
1. `StarActionEnvironment.swift` 新增 4 个 env 值(与现有对称):
   `onStarCard: (cardId,cardType)->Void`、`starredCardIds: Set<String>`、
   `onToggleDone: (cardId,itemRef,done)->Void`、`doneItemRefs: Set<String>`;默认
   nil / 空集 → no-op 降级。
2. 整卡 star 按钮:在 `CardRouter`(或其共享 chrome)层挂一个卡角 star 按钮,覆盖所有
   卡型(**sectionHeader 除外**——无 chrome),filled/outline 由 `starredCardIds` 驱动,
   tap 调 `onStarCard(currentCardId, <card.type.rawValue>)`。
3. `TodoItemRow`(`TodoListCardView.swift:151`)完成圈从静态 `.accessibilityHidden`
   `Image` 换成 `Button`:tap 调 `onToggleDone(currentCardId, stableItemRef(item),
   !isDone)`;圈/勾态由 `doneItemRefs` 驱动。

**Acceptance**:
- [ ] 4 个 env 值有默认 no-op;注入 spy 闭包的测试证明按钮 tap 会调对应闭包并传对参数。
- [ ] 整卡 star 按钮在每个卡型(除 sectionHeader)出现;≥2 个 `#Preview` 覆盖 filled/outline。
- [ ] TODO 圈是 `Button`(非静态 Image),44pt(iOS)/28pt(macOS)触达(§E.3)。
- [ ] star/done 按钮不改卡 size/style/chrome 结构(§I 维度不混);颜色走 token 不 inline。
- [ ] `swift test --package-path Packages/AIDashUI` 全绿。

**Constitution refs**: §II D4(UI 纯净、经 env 发意图)、§VI(star/done 是内容信号非维度)、
§E.3(触达)、§F(新可见文案入 xcstrings)、§I(令牌纪律)、§G.2(新 CardView 2 个 Preview)。

**Layer 约束**(Packages/AIDashUI CONTEXT.md):
- depends_on: [AIDashCore, DesignKit]
- red_lines: 只依赖 Core+DesignKit、容器数据驱动不硬编码、颜色走 DesignKit/几何走 DesignTokens 禁魔法值、三正交维度不混、视图 @MainActor+Swift 6、无 App 侧 LLM、无 fatalError/try!/as! 优雅回退。
- test: `swift test --package-path Packages/AIDashUI`

---

## [T003] [Story] App:StarFeedbackScope 扩注入 + writer 整卡 star 支持

**Layer**: AIDashApp · **Stage 2** · **Blocked by**: MY-<T001>, MY-<T002>

**What**:
1. `UserEventWriter`(`Sync/UserEventWriter.swift`)加/扩整卡 star 写入:
   `star(cardId:itemRef:cardType:)` 支持 `itemRef==nil` 且带 `cardType`(复用
   `UserEvent.starCard`);现有单项 `star` / `setDone` 不动语义。
2. `StarFeedbackScope`(`Scenes/BriefingWindowScene.swift`)扩注入:
   - `.environment(\.onStarCard) { cardId, cardType in writer.star(cardId:itemRef:nil, cardType:) }`
   - `.environment(\.onToggleDone) { cardId, itemRef, done in writer.setDone(cardId:itemRef:done:) }`
   - `.environment(\.starredCardIds, <@Query action==star && itemRef==nil 的 cardId 集>)`
   - `.environment(\.doneItemRefs, UserEventWriter.doneRefs(from: <@Query done/undone 事件>))`

**Acceptance**:
- [ ] `writer.star(itemRef:nil, cardType:)` 在内存 ModelContainer 上产出一行
      `action==star && itemRef==nil && cardType==入参`。
- [ ] `StarFeedbackScope` 注入了 4 个新 env 值(编译期 + 一个装配测试断言闭包非 nil)。
- [ ] App test target 全绿(含既有 `UserEventWriterTests`)。

**Constitution refs**: §II(app 写 events 唯一写路径、不复用 CLI 写)、§D(优雅回退)、
§Persistence(events append-only SwiftData 镜像 + CloudKit)。

**Layer 约束**(App 无独立 CONTEXT.md → 用宪法):
- red_lines: app 独占 CloudKit 身份;events append-only、app 不修改/解释内容;禁 fatalError/try!/as!;Swift 6 严格并发,XPC delegate 保持 nonisolated(§Off-actor)。
- test: App scheme 的 test target(`swift test` 或 xcodebuild test,含 `UserEventWriterTests`)。

---

## [T004] [Story] UI→writer 布线端到端验证(硬约束,独立 task)

**Layer**: AIDashApp(装配层)· **Stage 3** · **Blocked by**: MY-<T002>, MY-<T003>

**What**: spec.md §6 的**显式布线验证**。**不是** writer 单测——要证明"UI 卡片动作真的
到达 writer / SwiftData"。在内存 ModelContainer + 注入真实 writer 的 environment 下:

**Acceptance**(三条,全部自动化):
- [ ] **star 整卡**:对一张卡触发整卡 star 意图 → store 多出一行
      `action==star && itemRef==nil && cardType==该卡型`。
- [ ] **done TODO**:对一个 todoList 项触发 toggle → 多出 `action==done`;再触发一次 →
      多出 `action==undone`(latest-wins,spec 003 §8)。
- [ ] **反向哨兵**:未注入 environment 时,star/done 按钮 tap 为 no-op(store 行数不变、不崩)。
- [ ] 上述断言在自动化测试中运行(注入 spy 闭包断言被调 + 内存 store 断言事件行数),
      不依赖真机 / iCloud(§User Feedback:不建手动 smoke-test)。

**Constitution refs**: §II(反馈闭环写路径)、§Testing(自动化证据)、§User Feedback
(不建手动 smoke-test task)。

**Layer 约束**: 同 T003(App 装配层)。

---

## [T005] [Story] aidata L1/L2:aidash_events 采集/归一 card_type 列

**Layer**: aidata(L1 collect + L2 normalize)· **Stage 4** · **Blocked by**: MY-<T003>

**What**: `aidata/adapters/aidash_events.py` 的 L2 归一在保留 `item_ref` 基础上,新增
`card_type` 列(从 `aidash events pull` 的事件 JSON 取 `cardType`,缺省 NULL 兼容旧事件)。
redaction 红线不变;degrade-not-crash(ADR-23)不变。

**Acceptance**:
- [ ] clean db 的 user_event 表含 `card_type` 列;有 `cardType` 的事件写入其值,无则 NULL。
- [ ] 无 `config_local.py` / app 不在 → collect() == 0,不抛(降级探针)。
- [ ] `/usr/bin/python3 -m pytest aidata/tests/ -q` 全绿。

**Constitution refs**: §II(aidata 是 agent,经 CLI 读回,不直连 CloudKit)、§Quality Gates gate5(aidata pytest)。

**Layer 约束**(aidata tech-context.md frontmatter):
- red_lines: layer-through(改卡从数据产生层往下)、L1 只追加只读源、严禁提交数据层/身份标识、降级不崩(ADR-23)、L(n) 只读 L(n-1)。
- test: `/usr/bin/python3 -m pytest aidata/tests/ -q`

---

## [T006] [Story] aidata L4:近 7 天各 card_type 整卡 star 计数查询

**Layer**: aidata(L4 serve)· **Stage 4** · **Blocked by**: MY-<T005>

**What**: 新增一条具名 SQL 查询(如 `L4_serve/queries/behavior/card-interest.sql`):
按 `card_type` 聚合近 7 天 `action=='star' AND item_ref IS NULL` 的整卡 star 计数,
降序。**`item_ref IS NULL` 过滤是关键**——与单项 star 分开,不双计(spec.md D1)。

**Acceptance**:
- [ ] 查询只计整卡 star(`item_ref IS NULL`),排除单项 star,近 7 天窗口按 CST 日切(ADR-22)。
- [ ] 空数据 → 返回空结果集(不抛),下游 L5 可降级。
- [ ] `/usr/bin/python3 -m pytest aidata/tests/ -q` 全绿(含该查询的 integration 测试若有 warehouse)。

**Constitution refs**: §Quality Gates gate5。

**Layer 约束**: 同 T005(aidata,改查询 → `L4_serve/queries/**.sql`)。

---

## [T007] [Story] aidata L5:"卡型兴趣" insight 卡 + golden 冻结

**Layer**: aidata(L5 apps/digest)· **Stage 4** · **Blocked by**: MY-<T006>

**What**: `L5_apps/digest/sources.py` 加 fetch_* 读 T006 查询;`aidash.py` 的
`build_briefing` 加一张 `insight` 卡"你最常收藏的卡型 Top-N"(数据缺失 → 降级不渲染,
ADR-23)。**同步冻结** `tests/test_digest_golden.py` 的 `frozen_trends`(aidata
tech-context §坑①——漏冻结会让 golden 在有数据的机器上漂移)。

**Acceptance**:
- [ ] L5 fetch 新查询并映射成一张 `insight` 卡;无数据时该卡不出现,digest 照常产出。
- [ ] `test_digest_golden.py` 冻结了新 fetch(degraded 空 bundle 即可),golden 稳定。
- [ ] `/usr/bin/python3 -m pytest aidata/tests/ -q` 全绿。

**Constitution refs**: §I(insight 卡走既有 CardType,复用不新增类型)、§Quality Gates gate5。

**Layer 约束**: 同 T005(aidata,改卡片内容 → layer-through:值已在 L4,故从 L5 映射合法)。
