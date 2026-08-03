# Plan — Feature 005: Star 每一张卡片 + 修复 done 布线

> 对应 `spec.md`。本 plan **不重述**宪法规则,只 reference 章节号(§Development
> Workflow 硬约束)。实现按 **layer 拆**,一层一 commit,各自可独立 build/test
> (Constitution §Development Workflow「按 layer 拆,不用 vertical slice」)。

## 1. 架构判断:无新架构,纯 additive + 补线

- 复用 spec 002 的 environment 注入 + append-only writer 范式(§II 反馈闭环)。
- 唯一 schema 变化:Core `UserEvent` 加**可选** `cardType`(与 `itemRef` 同款
  forward-compat,§IV schema 单源;additive,**不需 ADR**——不改依赖方向/并发/隐私)。
- done 侧**零语义变化**:`setDone`/`done`/`undone`/`doneRefs` 已在 spec 003 交付并有
  单测,本 plan 只补 UI→writer 布线(spec.md §1b/§6)。

## 2. 层次映射(依赖方向:UI→Core,App→UI+Core,aidata 单向数据流)

| Layer | 交付 | 依赖 | 验证命令 |
|---|---|---|---|
| Core | `cardType` 字段 + `starCard` 工厂 + round-trip 测试 | 无(仅 Apple) | `swift test --package-path Packages/AIDashCore` |
| UI | 4 个 env 值 + 整卡 star 按钮 + TODO 圈可点 | Core, DesignKit | `swift test --package-path Packages/AIDashUI` |
| App | `StarFeedbackScope` 扩注入 + writer 整卡支持 | UI, Core | App test target(`UserEventWriterTests` + 新布线测试) |
| aidata L1/L2 | `card_type` 采集/归一 | 无 Swift 依赖 | `/usr/bin/python3 -m pytest aidata/tests/ -q` |
| aidata L4 | 近 7 天各 card_type 整卡 star 计数查询 | L2 clean db | 同上 |
| aidata L5 | "卡型兴趣" insight 卡 + golden 冻结 | L4 | 同上 |

## 3. 关键决策依据(spec → 实现)

- **D2 `cardType` 必要性**:`_kuid(mmdd,n)` 不编码卡型(`aidash.py:164`),序号槽随
  ADR-23 条件卡漂移 → 卡型必须随事件走,不能事后 join / 序号耦合。
- **D3 done 布线点**:`TodoItemRow`(`TodoListCardView.swift:151`)完成圈现为
  `.accessibilityHidden` 静态 `Image` → 换 `Button` 接 `onToggleDone`。
- **D4 对称注入**:新 env 值与现有 `onStarItem`/`starredItemRefs`/`currentCardId`
  对称(`StarActionEnvironment.swift`);App 侧扩 `StarFeedbackScope`
  (`BriefingWindowScene.swift`)。

## 4. 风险与缓解

- **契约漂移**(Python/Swift 各写一遍 payload):跑 `aidash-content` 的
  `contract_check.sh`;`cardType` 是事件字段不是卡 payload 字段,不过 CardType lint,
  但 aidata 侧 `aidash events pull` 的 JSON envelope 要带 `card_type`,靠 §6 布线验证
  + golden 兜底。
- **golden 漂移**:新增 L5 卡必须同步冻结 `test_digest_golden.py` 的 `frozen_trends`
  (aidata tech-context §两个反复踩到的坑①)。
- **空心功能复发**:§6 独立布线验证 task,acceptance 是端到端事件行断言,非 writer 单测。

## 5. Stage 依赖(→ tasks.md `--stage`)
- Stage 1:Core(T001)——blocker,先建。
- Stage 2:UI(T002)、App(T003)——依赖 Core 字段/工厂;T003 依赖 T002 的 env key。
- Stage 3:布线验证(T004)——依赖 T002+T003 接线完成。
- Stage 4:aidata L1/L2(T005)→ L4(T006)→ L5(T007)——链式,`card_type` 先落库。
