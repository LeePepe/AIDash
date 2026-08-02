# aidata v2 —— 数据坑修复 + 首发深分析集

**日期**: 2026-07-10
**状态**: 已获用户设计批准，待写实现计划
**前置**: aidata v1（四层采集平台）已完成，见 `README.md`

## Context（为什么做这个）

aidata v1 把分散的 AI 使用数据收集、归一、合并、可查了，但目前只有 6-7 个基础汇总查询——用户评价「只是做了基础的内容收集和基本汇总」，最大不满足是**分析不够深**。

同时，对真实 warehouse（60 万请求 / 8.9 万轮次）做的三路数据探查暴露出一批**数据坑**，它们会让任何深分析得出误导性结论：模型名多写法导致成本少算、16,264 行「有 token 却无 cost」、multica tokens 字段被 schema 注释标错、部分字段已退化（cache、tool_call_count）。

本轮目标：**先在 L2 归一层根治所有数据坑（架构方案 A：坑在源头修，不在查询里绕），再基于干净地基交付一组「STRONG 数据支撑 + 独立可出结论」的深分析查询。** 覆盖用户的四个决策方向（优化个人用法 / 诊断 pipeline / 监控成本 / 沉淀知识）。

范围**不含**自动化采集、web 仪表盘、PR 采集补全——均为后续独立任务。

---

## 架构决策：坑在 L2 根治（方案 A）

数据坑一律在 **L2 归一层 + schema** 修复一次，warehouse 从此干净，L3/L4 及所有现有/未来查询自动受益。不在每个查询里就地绕（违背分层、重复处理、易漏），也不新增修正层（对当前规模是过度设计）。

核心原则：**原始字段不可变**——原始 `model` 列保留不动，归一结果作为新增派生列 `model_canon`，符合项目「不可变原始数据」规范。

---

## Part 1：数据坑修复清单（8 项）

### 组1 — 模型维度

| 坑 | 根因（已核实） | 修法 | 文件 |
|---|---|---|---|
| 模型名不统一 | `opus-4.7` vs `opus-4-7`、`opus-4.6-1m` vs `opus-4-6-1m` 等同模型多写法，聚合分裂、cost 部分命中 | 新增 `model_canon()` 归一函数（点分↔连字符统一、`-1m` 后缀统一），存为**派生列** `model_canon`；原始 `model` 不动 | `adapters/model_canon.py`(新)、`adapters/raven.py`、`schema/warehouse.sql` |
| 缺价目 | 16,264 行有 token 却无 cost，全因价目表漏了 `gpt-5-mini`(9104)、`claude-sonnet-4`(6625)、`claude-sonnet-4-5`、`claude-opus-4-6-1m`、`gpt-4.1` 等写法 | 补全 `dim_model.csv` 覆盖所有出现过的模型（以 `model_canon` 为键）；cost 计算改用 canon 查价，算出的值仍写回原 `cost_usd` 列（cost 不分叉，只是匹配用 canon） | `schema/dim_model.csv`、`adapters/raven.py` |

**注意**：另有 27,283 行 NULL cost 是因 token 本身 NULL（多为 error 请求）——这是**正确行为**，保持 NULL，不猜。

### 组2 — 字段正确性（schema 注释与标注）

| 坑 | 现状 | 修法 |
|---|---|---|
| multica tokens 标注错 | `schema/warehouse.sql` 注释写「tokens 仅 claude_job」，实际 499/508 multica_run 有值（2.54B，仓库最富成本信号） | 改正注释；确认 merge 正确带入（已带入，仅注释错） |
| tool_call_count 退化 | `fact_request.tool_call_count` 恒 0 | schema 标注 deprecated，分析层不用 |
| cache 字段坏 | `fact_request.cache_read/write` 100% NULL；`fact_turn.cache_creation` 恒 0 | schema 标注「不可用」；缓存分析只用 `fact_turn.cache_read` 做命中率，**不做省钱量化** |

### 组3 — 时区

| 坑 | 现状 | 修法 |
|---|---|---|
| ts 是 UTC | 时段分析会错位 | raw/warehouse 保持 UTC（正确存储惯例）；**L4 查询统一用显式** `date(ts/1000,'unixepoch','+8 hours')` 转 CST（ADR-22，禁用 `localtime`——依赖 host TZ）；写入 README 约定 |

---

## Part 2：首发深分析集（7 条 L4 查询）

每条 = 一个 SQL 文件 `L4_serve/queries/<簇>/<名>.sql`，`aidata query <名>` 直接出表，支持参数。所有数字来自对真实数据的验证查询。

### 成本决策
| 查询 | 作用 | 已验证锚点 |
|---|---|---|
| `cost/pareto` | 成本集中度：top N% 会话/天/模型占多少花费 | top 10% 会话 = 75.6% 花费 |
| `cost/model-downgrade` | 贵模型跑极小输出的请求 + 可省额 | opus-4-8: 5,279 次 <20 token, $1,534 |
| `cost/context-waste` | 大输入小输出（塞巨量上下文却几乎没输出） | 2,259 次, ~10万 avg input, $1,056 |

### Pipeline 决策
| 查询 | 作用 | 已验证锚点 |
|---|---|---|
| `health/agent-scorecard` | Agent 记分卡：完成率×平均耗时×平均 token | agent 105247d0 完成率 40.8%、996s/run、最烧 token（三信号交叉） |
| `health/wasted-tokens` | 花在 cancelled/failed run 上的 token 占比 | 452M = 17.8% multica token |
| `health/rework-loops` | 取消→重跑的 issue、run 次数长尾 | 80/106 issue 有返工环；单 issue 22 次 run |

### 行为决策
| 查询 | 作用 | 已验证锚点 |
|---|---|---|
| `behavior/runaway-sessions` | 失控会话：p90/p99/max 会话规模 + 超阈值清单 | 单会话最高 231M token / $1,160 / 60h |

### 明确不做（YAGNI + 数据不支撑）
- ❌ **PR 结局分析** — 仅 4 个 task 有 PR 链接，BLOCKED → 留给「补 PR 采集」独立任务
- ❌ **memory 深分析** — 全语料仅 53 行，现在做是人工清单非分析
- ❌ **skill ROI 全量** — 仅 5% 轮次有归因，只能做「token 大户 top N」不做全景
- ❌ **缓存省钱量化** — 字段坏（cache_creation 恒 0）
- ❌ **轮内工具序列** — tool_calls 每轮 ≤1 工具

---

## 执行顺序

1. 改 `schema/warehouse.sql`（加 model_canon 列、改注释、标注 deprecated/不可用）
2. 新增 `adapters/model_canon.py`；`adapters/raven.py` normalize 计算 canon + 用 canon 查价算 cost
3. 补全 `schema/dim_model.csv`
4. `merge.py` 带入 model_canon 列
5. 重跑 `aidata normalize`（raven 重算 cost）→ `aidata merge`
6. 写 7 条查询
7. 逐条验证

---

## 验证方式（端到端）

**修坑验证：**
- `SELECT sum(cost_usd IS NULL AND input_tokens IS NOT NULL AND output_tokens IS NOT NULL) FROM fact_request` → 应从 **16,264 降到 0**（有 token 必有 cost）
- `SELECT count(DISTINCT model_canon) < count(DISTINCT model) FROM fact_request` → 真（归一生效，如 opus-4.7/opus-4-7 合并）
- 总花费统计**上升**（补回 sonnet-4 / gpt-5-mini 的 cost）

**每条查询：**
- `aidata query <名>` 出表，关键数字与验证锚点吻合（agent-scorecard 里 105247d0≈40.8%；pareto top10%≈75.6%；wasted-tokens≈17.8%）

**幂等 & 不回归：**
- 重跑 normalize/merge：行数不变、model_canon 稳定
- 现有 7 条种子查询仍正常执行

---

## 范围边界

**做**：8 项数据坑修复（L2+schema）+ 7 条首发深分析查询。
**不做（后续独立任务）**：自动化采集（cron/hook）、web 仪表盘、PR 采集补全、memory 语料增长后的知识分析。
