# Finding: `health/planner-gap` 是系统性误报

- **日期**: 2026-08-02
- **状态**: 已确诊，**修复推迟**（等 aidata → AIDash 仓库迁移之后再动手）
- **严重度**: 中 — 一个已知误报的指标正在 AIDash 新闻/AI 效能简报上屏，会误导判断
- **触发**: 2026-08-01 briefing 的「规划缺口」卡片报「50 个 issue 有 Engineer 干活但没走 Planner」，用户质疑「不是所有 issue 都需要 planner（修 bug、已规划完成的都不需要）」。

---

## 一句话结论

`health/planner-gap` 想问「有没有规划活动发生」，却拿「issue 评论里有没有人 `@Planner Lead` 派单」来代理这个问题。两者系统性不等价 —— planner 的真实产出结构上就不落在可被计数的评论里。**卡片显示 50 是 `LIMIT 50` 截断，真实命中 562，其中保守估计 ≥90%（~495+）是误报。** 用户的直觉是对的。

---

## 指标现状（事实）

- **定义**: `L4_serve/queries/health/planner-gap.sql`
  - 逻辑（`:19-28`）：按 issue 聚合 `multica_comment.comment.mention_role`，挑出
    `has_eng = 1 AND has_planner = 0` —— 即「有 Fullstack Engineer 提及、无 Planner Lead 提及」。
  - `LEFT JOIN fact_issue` 仅用于富化展示（identifier/status/priority），WHERE **不用**这些字段过滤。
  - 结尾 `LIMIT 50`。
- **上屏路径**: `L5_apps/digest/sources.py:715 fetch_planner_gap_count` → `L5_apps/digest/aidash.py:699-704`
  渲染成 insight 卡（仅当 count > 0）。
- **真实规模**: 去掉 LIMIT 后命中 **562**（卡片显示的 50 是截断值 → 告警本身严重低估体量）。

---

## 三方独立查证

### 角度 A — 设计意图：指标按设计就粗糙
- SQL 头注释（`:2-3`）、引入 commit `cc93043`、卡片文案（`aidash.py:702-703`）三处一字一致：
  「工程活 + 无 planner 提及 = 缺口 = 本该走 spec/规划却跳过」。**从设计起点就没打算区分 bug / 已规划 issue。**
- `fact_issue`（`schema/warehouse.sql:65-76`）**根本没有 issue 类型 / kind / is_bug 字段** —— 即使想按类型过滤，数据层也不支持。所以「漏实现过滤」不成立，是设计维度就缺。
- 设计文档把它定位为「弹药库 / L4 已建、未接 L5 的候选指标」（`docs/plans/2026-07-27-l1-l5-cleanup.md:151,154`；`docs/specs/2026-07-17-layered-metrics-design.md:264,285`）—— 一个文档里仍标注「未验证」的粗指标，被**悄悄提拔成用户可见卡片，中间没有语义验证 pass**。

### 角度 B — 真实工作流：跳过 planner 大多是设计允许的
- **Fast Path 是 dev-team 明写的跳过规则**（`multica-dev-team/live-20260728/team-lead.instructions.md:45-75`）：
  - Fast Path A（`:47`）：bug fix 带具体问题清单 → 跳过 plan / plan-review。
  - Fast Path B（`:54`）：已含具体改动点 / Figma 参数 / 验收标准的 issue → 跳过 Planner，直接给 FS。
  - `:64` TL 需注明跳过理由；`:75` 不确定才走完整 pipeline。
- **planner 的产出结构上不在 leaf issue 评论里**，三种机制都产生「真规划、零 Planner Lead 评论」：
  1. **规划在 parent、执行在 leaf**：MY-855 leaf 无 Planner，其 parent `611e5f4c` 有 3 条 Planner Lead 评论 + 4 次 Planner run；MY-630 parent `30e0da7d` 有 3 次 Planner run。
  2. **spec-kit / 人工规划替代 Planner agent**：MY-967（T050）整棵树 MY-928 零 Planner run，规划以 `specs/001-core-briefing-cli/plan.md` + research.md + tasks.md 形式存在。
  3. **planner 靠改 description 交接、不发评论**（`planner-lead.instructions.md:98-101,156-158`）：PRD 落 issue 描述而非评论，对评论计数器不可见。
- **抽查 5 个命中 issue 全部是合理跳过**：ABC-406（top-level bug，Fast Path A）、MY-967（spec-kit leaf，上游已规划）、MY-855 / MY-630（feature sub-issue，parent 已规划）、ABC-278（stall-report，根本不是工程任务）。

### 角度 C — 采集口径：`mention_role` 测的是「@了谁」不是「谁写的」
- **致命根因**（`adapters/multica_comment.py:49,127-132`）：`mention_role` 不是评论作者角色，而是**正文里第一个 `@`-mention 的接收方**（正则 `@([A-Za-z ]+?)\]`）。它是「派单指向」，不是「谁参与」。作者身份另存 `author_type`，只有 agent/member/system 三值、无角色。
- 后果：
  - **planner 产出全部落进 `mention_role=None`**：Plan Review 表格 / Implementation Plan / Plan approved 等正文不以 `@` 开头 → 归 None。抽样：**111 个不同 issue 的 planner 产出被吞进 None**。
  - **planner 派单反被记成 Engineer**：「Plan approved … [@Fullstack Engineer] please implement」→ 首个 `@` 是 Engineer → 这条 planner 评论 `mention_role='Fullstack Engineer'`，**反而给对方 has_eng 计分**（`Plan approved%` 开头 6 条里 5 条如此）。
- **None 共 8996 条**（占比最大）是「正文不以 @role 开头」的一切评论：Code Review Summary 1032、Pushed/PR/commit 状态 252、API/model 报错 133 等机器噪声，**混装着真实 planner 活动**（Plan Review 103 + Implementation Plan 57 …）。
- **排除大小写误报**：`mention_role` 里含 "plan" 的只有 `Planner Lead`（253 条），无变体；不是拼写导致漏判，是**语义口径错误**。
- **可直接证伪**：562 个 gap 中 **242 个**有 Team Lead 介入协调、**16 个**正文明有 Plan Review / Implementation Plan 却仍判无 planner。618 个 has_eng issue 里只有 123 个曾 @过 Planner Lead —— 剩下 495 个「gap」本质是「这批评论里没人再显式 @planner 派单」，而非「没规划过」。

---

## 判定

**(A) 指标设计粗糙为主 + (C) 采集口径过窄，共同放大。不是实现 bug。**
`_mention_role` 正则本身工作正常，问题是 planner-gap **复用了一个语义不匹配的字段**：想问「有没有规划活动」，却用「有没有人 @Planner Lead」代理，而 planner 的实际产出恰恰落在采集不到的 None 里。

---

## 修复方向（推迟执行 — 等 aidata → AIDash 迁移后）

> **决定（2026-08-02）**：修复推迟到 aidata 迁进 AIDash 仓库之后再做。迁移后 aidata 获得 github remote + Multica dev-team 接入，此修复可正常走 issue 流水线，无需本地手改。

三档，按投入递增：

1. **最小 — 撤卡**：移除 `aidash.py:699-704` 的 insight 渲染，别再上屏一个已知误报的指标。（成本最低，止血）
2. **修口径 — 换判定信号**：`has_planner` 改用「正文含 Plan Review / Implementation Plan / Plan approved 签名」判定，而非 `@`-mention；并叠加 **parent-tree 归因**（任一祖先有 Planner run，或存在 `specs/*/plan.md` → 算已规划）。同时排除 bug-fix / 非工程 issue 类型。
3. **治本 — 补作者角色字段**：在 normalize 阶段（`multica_comment.py`）从 comment 作者 / agent id 反查真实**作者角色**并入库，让 has_planner 能基于「谁写的」判定，而非「@了谁」。

**注意**：任何修复都应先给这个指标补语义验证测试（现有 `tests/test_batch2_cards.py:95-145` 只断言了「count>0 → 卡出现」的渲染语义，没验证 count 本身的正确性）。

---

## 关键文件索引

- `L4_serve/queries/health/planner-gap.sql:2-3,19-28` — 指标定义 + 误用字段
- `adapters/multica_comment.py:49,127-132` — `mention_role` = 首个 @-target 的派生逻辑（根因）
- `schema/warehouse.sql:65-76` — fact_issue 无类型字段
- `L5_apps/digest/sources.py:715-725`、`L5_apps/digest/aidash.py:699-704` — 已上屏 L5
- `docs/plans/2026-07-27-l1-l5-cleanup.md:151,154` — 「弹药库 / 未验证」定位
- `tests/test_batch2_cards.py:95-145` — 仅渲染语义测试，无 count 正确性断言
- `multica-dev-team/live-20260728/team-lead.instructions.md:45-75` — Fast Path 跳过 planner 规则
- `multica-dev-team/live-20260728/planner-lead.instructions.md:98-101,156-158` — planner 靠改 description 交接
