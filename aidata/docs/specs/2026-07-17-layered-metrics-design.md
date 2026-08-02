# aidata 分层数据设计 — 从"干数字"到"多层语义指标"

**日期**: 2026-07-17（v2: 2026-07-18 加入目标驱动模型）
**状态**: 设计稿，待用户审阅后进入实现
**动机**: dashboard 上"只有 multica 相关内容看起来有意义"，其余全是不带业务语义的数字聚合。
**关联**: [aidata-digest 设计定稿](2026-07-10-aidata-digest-design.md)、[deep-analysis 计划](../plans/2026-07-10-deep-analysis.md)

---

## 0. 北极星：目标驱动，不是数据驱动（v2 核心）

**设计原则反转**：先定义 dashboard 要回答的问题（目标），数据为目标服务；
**回答不了任何目标的数字不上屏**。这直接治"只有 multica 看着有意义"的病——
因为屏上大部分数字确实不服务任何目标。

### 五大目标（2×3：视角 × 时间）

```
              过去(事实)        现在(判断/告警)       未来(行动)
   事实层    ① 做了什么         ② 需要处理什么①        （并入②）
   判断层    ⑤ 为什么(归因)     ③ 可以改进/值不值      （并入②）
   时间轴                      ④ 趋势(贯穿全部)
```

| # | 目标 | 一句话 | 数据支撑 | 今天状态 |
|---|---|---|---|---|
| ① | **做了什么** | 昨天在哪些项目/分支上花了精力 | `fact_turn.project/git_branch/attribution_skill` | ❌ 数据饱满，完全没用 |
| ② | **需要处理什么** | 等我处理/决策的统一队列（见下方分化） | multica issue + `fact_task` + 各 error log + agent 提议 | ⚠️ 只有 todo 占位 |
| ③ | **可以改进/值不值** | 哪里能更省更好 + 投入产出比 | `cost/model-downgrade`、`rework-loops`、cost÷outcome | ⚠️ 卡片硬编码，没接真实 query |
| ④ | **趋势是什么** | 各维度 ↑↓→ | `trend/*` | ✅ 唯一做扎实，但只有钱/token 无语义趋势 |
| ⑤ | **为什么** | 趋势/异常的归因 | project × model × cost 三维交叉 | ❌ 缺（趋势升到叙事的关键） |

### 目标②"需要处理什么"的分化（用户 2026-07-18 定义）

不是单纯 todo，而是一个**带优先级的"待我处理/决策"收件箱**，四类不同性质、共性都是"等我"：

| 子类型 | 本质 | 数据来源 | 例子 |
|---|---|---|---|
| **计划中的活** | 已知 todo | multica issue todo / `fact_task` pending | 常规待办 |
| **数据新发现** | 阈值触发、被动浮现 | 派生指标越界 | "opus 占 71% 成本可降级"、"某 workflow 失败率突增" |
| **卡顿/阻塞** | 坏掉了 | multica stall / `fact_ado_pr.age_hours` / `cron-errors.log` / `aidash-push-errors.log` | PR 卡 967h、workflow 反复 cancelled、push 静默失败 |
| **待决策** | 等 approve | **agent 提议**（未来 PM agent 等） | "PM agent 分析出新需求 X，是否立项" |

**关键**：最后一类"待决策"直接对应 AIDash 宪法核心模型（agent 提议 → 用户 react
approve/done/star）。用户规划的 **PM agent 就是这个队列的未来生产者**——dashboard
从"看板"升级为"人 ↔ agent 协作界面"。这个目标的数据结构必须预留 agent-提议的写入口。

### 目标 → 现有骨架的映射

- 目标是 L5（消费面）的组织原则；L4 query 是弹药，按目标挑选而非全堆。
- §3-§7 的维度/query/分期，全部服从于"点亮哪个目标"，而非"接哪个数据源"。

---

## 1. 问题陈述

用户反馈：AIDash dashboard「只有 multica 相关的内容看起来有意义」。

**根因（已用真实数据确诊）**：digest 目前只消费 **4 个** L4 trend query
（`daily-cost` / `daily-completed` / `daily-ado-pr` / `daily-automation`），
全部是**不带业务语义的数字聚合**（成本/token/请求数/自动化率）。唯一带
"具体在做什么"语义的是 issue 计数——它来自 multica，于是 dashboard 上只有
multica 像"真内容"。

**两个已被浪费的资产**：
1. **L4 已有 21 个 query，digest 只用了 4 个** —— deep-analysis 那批
   （`health/*`、`cost/*`、`roi/*`、`behavior/*`）"造好了当弹药库"，从未接进 digest。
2. **warehouse 已有丰富维度未被 digest 触及** —— `fact_turn.project` /
   `git_branch` / `attribution_skill`（每条对话属于哪个项目/分支/用了哪个 skill），
   `fact_task` 的 workflow 成功率/失败率/重试，`fact_issue.project_id`。

结论：**这不是"缺数据"，是"缺把已有数据接到消费端"**。分层骨架（L1→L5）已存在且健康。

---

## 2. 分层现状盘点（L1→L5）

```
L1 collect   11 源，增量采集 → L1_collect/raw/<source>
L2 normalize 每源清洗 → L2_normalize/clean/<source>.db
L3 merge     warehouse.db：fact_request / fact_turn / fact_task /
             fact_issue / fact_pr / fact_ado_pr / dim_session / dim_model
L4 serve     queries/<domain>/<name>.sql，21 个（见 §4）
L5 apps      digest：只调 4 个 L4 query → 5 container × 6 card
```

**分层是健康的**，缺口在 **L4→L5 的消费面**：L4 弹药库只有 19% 被 L5 用上。

---

## 3. 可用维度全清单（均已用昨日真实数据验证）

| # | 维度 | warehouse 来源 | 昨日样本（07-14） | 回答的问题 | digest 用了 |
|---|---|---|---|---|---|
| A | **按项目工作量** | `fact_turn.project` | VitalStride 1042 / WorkspaceA 503 / AIDash 495 | 在做什么 | ❌ |
| B | 按分支 | `fact_turn.git_branch` | WorkspaceA@tabs/bugfix 503、AIDash@fix/metric-density 207 | 在哪条线干活 | ❌ |
| C | 按 skill/能力 | `fact_turn.attribution_skill` | multica-issue 68、auto-review-merge 44、impeccable 25 | 做了哪类事 | ❌ |
| D | 按模型成本 | `fact_request.model_canon` | opus-4.8 $922（71%）、gpt-5.6 $222、opus-4.7 $250 | 钱花在哪个模型 | ❌ |
| E | 按工具成本 | `fact_request.client` | claude-cli $1147、multica-sdk $222、codex $8 | 哪个工具烧钱 | ❌ |
| F | 成本/token/请求趋势 | `trend/*` | 成本 $1302、token 349M | 数字趋势 | ✅ |
| G | issue/PR 计数 | `fact_issue` / `fact_pr` | multica issue | 完成数 | ✅（仅计数） |
| H | 浪费额、自动化率 | `trend/*` | 浪费 $149、自动化 100% | 数字 | ✅ |
| I | **workflow 成功/失败/重试** | `fact_task` | completed 4826 / cancelled 6000 / failed 729；273 次二次重试 | pipeline 健康 | ❌ |
| J | **返工 issue** | `fact_task` group by issue | 失败最集中的 issue：27/25/15 次 | 哪些活反复失败 | ❌ |
| K | **活跃度（DAU 类比）** | `fact_turn` distinct session/day | 07-15：46 session / 15 项目 | 使用强度趋势 | ❌ |
| L | issue 按项目归属 | `fact_issue.project_id` | AIDash(<PROJECT_UUID>) 146/97 done | 各项目 issue 健康 | ❌（未拆项目） |

**核心洞察**：A–E、I–L 共 **9 个带业务语义的维度全部闲置**，digest 只用了 F/G/H 三个"干数字"维度。

---

## 4. L4 弹药库：已写好但没接进 digest 的 query

| query | 产出 | 对应维度 | 状态 |
|---|---|---|---|
| `health/task-failures` | 运行结果分布、重试压力、哪个 agent 失败最多 | I | ✅ 已写，**未用** |
| `health/agent-scorecard` | 每 agent 可靠性+速度+token | I | ✅ 未用 |
| `health/rework-loops` | 返工 issue（cancelled 后又 completed） | J | ✅ 未用 |
| `health/wasted-tokens` | token 浪费点 | — | ✅ 未用 |
| `cost/model-downgrade` | opus 用在小输出上的浪费($) | D | ✅ 未用 |
| `cost/pareto` | 成本集中度（top N 模型 = X% 花费） | D | ✅ 未用 |
| `cost/context-waste` | 大上下文小输出浪费 | — | ✅ 未用（"可改良"卡的数据源，但目前是硬编码文案） |
| `roi/by-client` | 工具对比（volume/token/cost/latency/error） | E | ✅ 未用 |
| `behavior/runaway-sessions` | 失控长 session | K | ✅ 未用 |
| `issues/drill`、`issues/trend` | issue 下钻/趋势 | L | ✅ 未用 |
| `trend/daily-behavior`、`trend/daily-pipeline` | 行为/pipeline 日线 | I/K | ✅ 未用 |

**待新建**（数据在 warehouse，只差 query）：
- `work/by-project` — A：`fact_turn` 按 project 聚合昨日 turn/token（warehouse 层直接可查，无需动 L3）
- `work/by-branch` — B：+ git_branch
- `work/by-skill` — C：attribution_skill 聚合
- `trend/daily-active` — K：每天 distinct session/project 数

---

## 5. 分层语义设计：三阶指标

用户诉求"多层次数据结构：L1 基础 → L2 结合 → 更高阶"。映射到 aidata：

### 阶 0 — 原子事实（已有，L3 warehouse）
`fact_request`（62 万）、`fact_turn`（10 万，带 project/branch/skill）、
`fact_task`（1.1 万）、`fact_issue`、`fact_pr`。

### 阶 1 — 单维聚合（部分已有，L4 query）
按 project / model / client / agent / day 的 group-by。多数已写（§4），缺 A/B/C/K。

### 阶 2 — 派生指标（部分已有，需补）
- **workflow 成功率** = completed / (completed+cancelled+failed)（`health/task-failures` 已算）
- **重试率** = attempt>1 占比
- **模型成本集中度** = pareto top-N%（`cost/pareto` 已算）
- **降级机会额** = opus 小输出浪费 $（`cost/model-downgrade` 已算）
- **项目精力占比** = 各 project turn / 总 turn（待建 `work/by-project`）

### 阶 3 — 叙事/洞察（L5 digest 的 LLM polish 层）
把阶 2 指标组织成"昨天你在 VitalStride 冲刺（1042 turn），AIDash 做了两个分支
（metric-density + card-size），opus-4.8 占了 71% 成本，multica pipeline 成功率 42%
（cancelled 偏高，返工集中在 3 个 issue）"这种一句话读懂的叙事。

**关键**：阶 3 已有基础设施（digest 的 `--llm` polish），只是没喂阶 1/2 的高阶指标。

---

## 6. 卡片映射建议（L5 digest 新增/改造）

| 新容器/卡 | 数据源 | 内容 | 优先级 |
|---|---|---|---|
| **今日项目分布**（新卡，metric 或 digest section） | `work/by-project`（A） | VitalStride/WorkspaceA/AIDash 各 turn/token | P0（用户最想要） |
| **模型成本拆解**（新卡，metric） | `cost/pareto` + `model-downgrade`（D） | opus-4.8 71%、降级可省 $X | P0 |
| **Workflow 健康**（新容器，metric+insight） | `health/task-failures`（I）+ `rework-loops`（J） | 成功率 42%、返工 top-3 issue | P1（multica 深度） |
| **工具 ROI**（新卡，metric） | `roi/by-client`（E） | claude-cli vs codex vs multica | P2 |
| **活跃度趋势**（改造趋势指标） | `trend/daily-active`（K） | 每天 session/项目数 | P2 |
| 改造"可改良"卡 | `cost/context-waste`（现在硬编码） | 用真实 query 替换硬编码文案 | P1 |

---

## 7. 分期实现建议（按"点亮目标"组织，非按数据源）

每个 milestone 交付**一个可见的目标**，而不是"接一批 query"。

- **M1 — 点亮目标③「可以改进」+ 局部②「值不值」✅ 已完成（commit e28842a）**
  两张真实数据卡进"可改良"容器：`值不值·效率`（cost-per-completed-task 含失败
  + output-share，7 天滚动窗，research-backed 非 naive 比值）、`可改良·成本`
  （cost/pareto 集中度 + opus 小输出，口径按研究：不断言"降级省$X"）。
  新增 serve 参数 fallback、`roi/value-efficiency`、`cost/by-model-window`，
  修复 `_default_probe` 无超时会 hang 的真 bug。deep-research 报告见
  `2026-07-18-token-efficiency-research.md`。
  **数据缺口**：cache-read ratio 算不了（raven 未采 cache token）。

- **M2 — 点亮目标①「做了什么」✅ 已完成**
  新建 `work/by-project` query + "今日工作"容器（order 15，总览后/趋势前）。
  metric 卡：每项目一 item（value=昨日 assistant turns，context=会话数+输出量）。
  真实数据示例（07-17）：WorkspaceA 422 / VitalStride 249 / VoxPocket 166 / AIDash 24。
  `by-branch`/`by-skill` 留待 M3 深化。

- **M3 — 点亮目标②「需要处理什么」统一收件箱 ✅ 已完成**
  "今日规划"容器改用真实 action inbox（替换"无阈值触发行动项"占位）。
  `L5_apps/digest/inbox.py` 聚合四类，**每桶配额**（卡顿 5 / 待决策 3 / 计划 3 /
  发现 2）防止卡顿墙淹没其他：
  - 计划中的活 ← `inbox/pending-issues`（todo/in_review）→ medium
  - 数据新发现 ← 降级机会 > $500 阈值 → medium
  - 卡顿/阻塞 ← `inbox/stalled-prs`（PR>168h）+ blocked issue + 读
    `aidash-push-errors.log`/`cron-errors.log` → high
  - 待决策 ← **agent 提议写入口已建**：`L5_apps/digest/proposals.py` 读
    append-only `state/proposals.jsonl`（schema 见 `proposals.example.jsonl`），
    PM agent 未来 append，digest 读 pending → high。react 回写走 AIDash done/star。
  真实数据（07-18）：AIDash 推送报错 + cron empty + PR 卡 46/31/9 天 + $3403 发现。
  每桶独立 guard，任一失败降级为空不崩。

- **M4 — 点亮目标⑤「为什么」+ 深化④「趋势」到叙事**
  `trend/daily-active`（活跃度）+ project×model×cost 归因；
  调整 LLM polish prompt 把阶 2 指标织成阶 3 叙事
  （"成本降 49% 是因为昨天主要在 VitalStride cheap 任务，非效率提升"）。

**目标覆盖检查**：
| 目标 | 由哪个 M 点亮 |
|---|---|
| ① 做了什么 | M2 |
| ② 需要处理什么 | M3（局部 M1 的改进项） |
| ③ 可以改进/值不值 | M1 |
| ④ 趋势 | 已有 + M4 深化 |
| ⑤ 为什么 | M4 |

---

## 8. 关键约束（沿用 aidata 既有 ADR）

- **不动 L1/L2/L3 原始数据**（immutable）；新指标尽量在 L4 query 层，warehouse 已够用（§4 待建项均可 warehouse 直查）。
- **CST 切天**：所有时间 query 用 `datetime(ts/1000,'unixepoch','+8 hours')`（epoch-ms）或
  ISO 直接 `substr`（fact_turn.ts 是 ISO）。（ADR-2）
- **数据窗口标注**：claude_jsonl 从 2026-06-09 起，project 维度回看有限，趋势须标"数据 N 天"。（ADR-3）
- **degraded 优雅降级**：某维度无数据时卡片不崩，回退占位。（沿用现有 digest 行为）
- **目标②待决策类需预留 agent 写入口**：schema 设计一个"agent 提议"表/文件，PM agent 未来写入，digest 读出成"待决策"卡，用户 react 走现有 AIDash done/star 回写。
- **stdlib only**，query 是纯 .sql 经 `aidata query <name>` 跑。

---

## 9. 待用户决策

1. ~~范围~~ → 已定：M1 先做（"值不值/可改进"），用户已批"做做看"。
2. **multica workflow 深度**：成功率/失败率够，还是要下钻到"失败原因分类"
   （需看 fact_task 有无 error 字段 / 或从 multica_run 原始数据挖失败日志）？
3. **卡片密度**：dashboard 已有 5 容器 —— 是加新容器，还是替换现有"干数字"卡？
4. **M3 agent 提议入口**：PM agent 是近期计划还是远期？决定 M3 的"待决策"是先占位还是完整实现。

---

## 附录 A：当前实现状态（2026-07-27 快照）

> 本 spec 正文写于 2026-07-17，其中「L1 11 源」「L4 21 query」「L5 只用 4 query」
> 等数字是**设计时快照**，不代表当前实现。此后快速迭代新增了 9 个源
> （`config.SOURCES` 现为 **20** 源）、L4 query 增至 **35** 个、L5 消费面扩大。
> 下表按 **L1→L5** 分层如实标注每个源"到达哪一层"，供对照。以 `config.SOURCES`
> / `config.MERGE_SOURCES` 为准。

**图例**：✅ 到达该层｜—未到达｜时间分桶一律显式 `+8h`（ADR-22），禁用
`localtime`（正文若有 `localtime` 措辞以此为准）。

| # | 源 | L1 采集 | L2 clean | L3 merge (warehouse) | L4 query | L5 digest | 备注 |
|---|---|---|---|---|---|---|---|
| 1 | raven | ✅ | ✅ | ✅ `fact_request` | ✅ 多个 | ✅ 趋势/成本 | 核心 |
| 2 | claude_jsonl | ✅ | ✅ | ✅ `fact_turn` | ✅ work/by-project | ✅ sessions/turns + 按项目 | |
| 3 | multica_issue | ✅ | ✅ | ✅ `fact_issue` | ✅ issues/*, daily-completed | ✅ 完成 issue 趋势 | |
| 4 | multica_run | ✅ | ✅ | ✅ `fact_task` | ✅ health/agent-*, failure-* | — | 已 merge，L5 未直呈 |
| 5 | multica_comment | ✅ | ✅ | — (L2-only) | ✅ planner-gap / rework-threads | — | 有 2 个 L4 消费，未接 L5 |
| 6 | claude_job | ✅ | ✅ | ✅ `fact_task` | ✅ (并入 task 系列) | — | |
| 7 | pr_cache | ✅ | ✅ | ✅ `fact_pr` | ✅ inbox/stalled-prs | — | |
| 8 | ado_pr | ✅ | ✅ | ✅ `fact_ado_pr` | ✅ trend/daily-ado-pr | ✅ 开PR 箭头 | |
| 9 | state_db | ✅ | ✅ | — (L2-only) | ✅ daily-automation, cache-hit-rate, model-tier-usage | ✅ 自动化占比 | L2-only 但经 L4 query 上屏 |
| 10 | hermes_tools | ✅ | ✅ | — (L2-only) | — | — | 仅到 L2 |
| 11 | memory_claude | ✅ | ✅ | — (L2-only) | ✅ memory/claude-inventory | — | |
| 12 | memory_hermes_db | ✅ | ✅ | — (L2-only) | ✅ memory/hermes-inventory | — | |
| 13 | memory_hermes_md | ✅ | ✅ | — (L2-only) | — | — | 仅到 L2 |
| 14 | github_repo | ✅ | ✅ | ✅ `fact_repo_snapshot` | ✅ radar/latest | ✅ 工具雷达 | 新源，已贯通 L5 |
| 15 | github_pr | ✅ | ✅ | ✅ `fact_github_pr` | ✅ trend/daily-github-pr | ✅ 开PR（合并 GitHub+ADO） | 新源，已贯通 L5 |
| 16 | news | ✅ | ✅ | — (L2-only) | — | — | 仅到 L2 |
| 17 | aidash_events | ⚠️ 采集路径存在，**当前无 raw/无 clean DB**（尚无事件落地） | — | — | — | — | 不能称"已采集"，只是"已具备采集能力" |
| 18 | local_git | ✅ | ✅ | — (L2-only) | — | — | 仅到 L2 |
| 19 | browser_history | ✅ | ✅ | — (L2-only) | — | — | 仅到 L2 |
| 20 | gecko | ✅ | ✅ | — (L2-only) | — | — | 仅到 L2 |

**要点校正**（相对正文 11 源基线，新增 9 源）：

- 新增 9 源 ≠ 一律"已采集、待 L5 呈现"。分三档：
  1. **已贯通到 L5**：`github_repo`、`github_pr`（进 L3/L4/L5）。
  2. **已进 L2、有 L4 query 未接 L5**：`multica_comment`（planner-gap / rework-threads）。
  3. **仅到 L2、无下游**：`hermes_tools`、`news`、`local_git`、`browser_history`、
     `gecko`、`memory_hermes_md`。
  4. **特例**：`aidash_events` 采集路径已建，但**当前无 raw 分片、无 clean DB**
     （尚无用户反馈事件落地），因此**不能标为"已采集"**，只能说"已具备采集能力"。
- **merged（进 warehouse）仅 9 个**：raven / claude_jsonl / multica_issue /
  multica_run / claude_job / pr_cache / ado_pr / github_repo / github_pr
  （= `config.MERGE_SOURCES`）。其余 11 个均为 **L2-only**，不进 warehouse。
- 正文 §2「L4 21 query / L5 只用 4」为设计时快照；当前 L4 为 **35** 个 query，
  L5 digest 消费面已扩大（raven 趋势组 + work/by-project + daily-automation +
  daily-ado-pr + daily-github-pr + radar/latest 等）。
