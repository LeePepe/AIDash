# 数据仓库分层蓝图：aidata（AI 用量遥测）

> 模式：**audit / 体检**（已有完整 L1–L5 分层）· 生成：2026-08-02 · 数据源：`schema/warehouse.sql` + 活库 introspect（`L3_merge/warehouse.db`、`L2_normalize/clean/*.db`，20 个源实测）
> 建模流派：**沿用项目既有体系**（Kimball 星型，已存在）· 命名：**沿用 L1–L5，不改名**
> 说明：本文是**设计蓝图**，非实现代码。实现见文末"分阶段 refine 计划"。
> 方法：由 `layered-data-warehouse` skill 对 **main 分支 live 代码 + 活库**实地发现产出，非套模板。所有数字均为实测。

> ## ⚠️ 实施后修订（2026-08-02，PR #140/#141/#142 落地后回填）
>
> 蓝图是设计时的判断；实施时的实测**推翻了其中三条**。原文保留不改（便于对照
> 判断错在哪），修订集中记在这里：
>
> | # | 蓝图原本说 | 实测结果 | 处置 |
> |---|---|---|---|
> | 1 | 建 `dim_date` 日历维表收敛 CST | **消不掉重复**——join 日历表仍需在 fact 侧写 `+8h` 才能对上。且底层时间戳有 3 种物理格式，无法统一 join | 改用 **STORED 生成列 `cst_day`**（写死 schema 一处 + 可索引）。已落地 #140 |
> | 2 | G1（日聚合该物化）**高优**，理由是"每天重扫 70 万行" | #140 加索引后收益塌了：`daily-cost` 0.66s、其余 ≤0.18s、**digest 全链 1.34s**。物化 4 张表最多省约 1 秒/天 | **G1 降级**，见下方"暂缓"说明 |
> | 3 | Phase 3 把 15 支孤儿**移到 `explore/` 目录** | 这些路径 publish 在 README 用法示例和 `cli.py --help` 里，移动会把每一处都弄断 | 改用 **`-- aidata-tier: explore` marker**（沿用既有 `aidata-attach:` 风格），文件不动。已落地 #142 |
>
> **进度**：Phase 1 ✅ #140 · Phase 4 ✅ #141 · Phase 3 ✅ #142 · **Phase 2 暂缓**（见下）
>
> ### Phase 2（物化 `dws_daily_*`）为何暂缓
>
> 两条独立的理由，任一条都足以暂停：
>
> 1. **性能前提已不成立**（上表第 2 条）。省 1 秒/天，不足以支撑 4 张新表的复杂度。
> 2. **`dws_daily_automation` 存在分层矛盾**：它的源 `state_db` 是 **L2-only**，
>    不在 `MERGE_SOURCES` 里。而 `merge.py` 是 L3、按设计只读那 9 个合并源。
>    要在 L3 物化一张来自"刻意不进 L3 的源"的表，就得破坏「memory/state_db 停
>    L2」这条边界——**蓝图当时没考虑到这层冲突**。
>
> **仍然成立的部分**：G2（`_sum_series` 聚合漏在 L5）与性能**无关**，它是纯粹的
> 分层越界——ADO∪GitHub 并集是复合指标口径，该在 SQL 里。若将来做 Phase 2，
> 应只做 G2 这一张 PR 表（两表合计 662 行，物化是为口径归位不是为快），
> 并跳过 `dws_daily_automation` 直到 state_db 的分层归属另行决定。
>
> **重启 Phase 2 的信号**：digest 全链超过约 10 秒，或 `fact_request` 再涨一个
> 量级（当前 708k）。

---

## 📋 执行摘要

1. **现状**：aidata 已经是一条**完整且纪律良好**的五层管线（`L1_collect → L2_normalize → L3_merge → L4_serve → L5_apps`）。体检的六项核心纪律里 **五项全绿**：脱敏红线（`rawio.write_raw` 单一 chokepoint，20/20 adapter 无绕过）、单向流（L1 无 import L5，L5 无绕 L4 直连 warehouse）、幂等（drop+rebuild / watermark / PK dedup，实测零重复行）、memory 停 L2 边界（未进 L3）、诚实 grain（多 fact 星型，未拍平成 OBT）。**这不是一个需要重建的仓库。**

2. **核心结论**：唯一的结构性缺失是 **DWS 汇总层不存在**。理论底座把 DWS 标为「复用主战场」——它缺席，本该下沉一次的东西就散落到上层：CST 日切散在 **18 个 SQL 文件共 39 处**、日粒度聚合每次查询现算（`trend/daily-cost` 实测 **SCAN fact_request 全表 708,375 行 + TEMP B-TREE**，0.21s CPU）、ADO∪GitHub 并集漏到 L5 的 Python（`_sum_series`）。这是**烟囱症状**，不是层数问题。

3. **头号 gap（G1）**：`trend/daily-*` 这 8 支查询是 Kimball 意义上的**周期快照事实表**（每天一行的度量快照），却每天从最细粒度明细现算。该物化为 `dws_daily_*`。

4. **SSOT 约束（体检确认无违规，但必须写死）**：成本派生的唯一实现是 `adapters/raven.py::_cost()`（`itok/1e6*p["in"] + otok/1e6*p["out"]`，在 **L2** 执行）。实测 L4/L5 **均无重抄**（`roi/daily-cost.sql` 用 `sum(COALESCE(cost_usd,0))`，L5 无任何 `per_mtok`/`1e6` 痕迹）。**任何 `dws_daily_cost` 必须 `SUM(cost_usd)`，绝不能重抄定价数学**——这是本蓝图最容易被违反的一条。

5. **体检的意外发现**：15/39 支 L4 查询无任何 L5 消费者；6 个源零消费者；4 条星型桥接键中 2 条实测近乎失效（`fact_task.pr_url→fact_pr` 命中率 **0.03%**）。这些是**治理债**，不是分层债——单独列 G5/G6/G7。

---

## 🗂️ 数据模型清单（Phase 0 发现，实测行数）

### 20 个源（`config.SOURCES`）

| 源 | L2 表 | grain（一行代表什么） | 实测行数 | raw 体积 | 幂等键 | 进 L3？ |
|---|---|---|---:|---:|---|---|
| raven | `req` | 一次 API 请求 | **708,375** | 475M | `request_id`(ULID) PK | ✓ `fact_request` |
| claude_jsonl | `turn` | 一个会话轮次 | **166,169** | 136M | `turn_uuid` PK + watermark | ✓ `fact_turn` |
| multica_comment | `comment` | 一条 issue 评论 | 15,282 | 44M | watermark + hash | ✗ L2-only |
| state_db | `session` | 一个 Hermes 会话 | 13,855 | 7.6M | watermark | ✗ L2-only |
| multica_run | `run` | 一次 agent run | 12,143 | 33M | `task_id` PK + watermark | ✓ `fact_task` |
| gecko | `focus_session` | 一段 app 聚焦 | 3,282 | 1.1M | watermark | ✗ L2-only |
| browser_history | `visit` | 一次域名访问 | 2,644 | 1.6M | watermark | ✗ L2-only |
| multica_issue | `issue` | 一个 issue | 1,895 | 6.1M | `issue_id` PK + **per-workspace** watermark | ✓ `fact_issue` |
| news | `news_item` | 一条头条 | 1,787 | 1.2M | snapshot hash | ✗ L2-only |
| hermes_tools | `tool_day` | 某工具某天调用数 | 983 | 3.9M | watermark | ✗ L2-only |
| ado_pr | `pr` | 我的一个 ADO PR | 525 | 63M | `pr_id` PK | ✓ `fact_ado_pr` |
| local_git | `commit_log` | 我的一次 commit | 468 | 168K | watermark + hash | ✗ L2-only |
| github_repo | `repo_snapshot` | 某 repo 某天快照 | 152 | 132K | `(repo,snapshot_date)` PK | ✓ `fact_repo_snapshot` |
| github_pr | `github_pr` | 我的一个 GitHub PR | 137 | 168K | `(repo,pr_number)` PK | ✓ `fact_github_pr` |
| memory_hermes_db | `fact` | 一条记忆 | 25 | 16K | snapshot hash | ✗ L2-only |
| memory_hermes_md | `entry` | 一条记忆条目 | 24 | 12K | snapshot hash | ✗ L2-only |
| claude_job | `job` | 一个后台 job | 21 | 52K | `task_id` PK + watermark | ✓ `fact_task` |
| memory_claude | `mem` | 一条记忆笔记 | 9 | 36K | snapshot hash | ✗ L2-only |
| pr_cache | `pr` | 一个 PR | **6** | 20K | `pr_url` PK | ✓ `fact_pr` |
| aidash_events | `user_event` | 一次 star/todo 反应 | **0** | — | timestamp watermark | ✗ L2-only |

> **集中度**：raven + claude_jsonl = 874,544 行，占全量 **87%**。

### L3 星型（`warehouse.db`，实测）

| 表 | 类型 | grain | 行数 | 来源 |
|---|---|---|---:|---|
| `fact_request` | 事务事实 | 一次 API 请求 | 708,375 | raven（1:1） |
| `fact_turn` | 事务事实 | 一个会话轮次 | 166,169 | claude_jsonl（1:1） |
| `fact_task` | 事务事实 | 一次 agent run / job | 12,164 | multica_run ∪ claude_job |
| `fact_issue` | 累积快照 | 一个 issue（`updated_at` 会变） | 1,895 | multica_issue（1:1） |
| `fact_ado_pr` | 累积快照 | 一个 ADO PR | 525 | ado_pr（1:1） |
| `fact_repo_snapshot` | **周期快照** | 某 repo 某天 | 152 | github_repo（1:1） |
| `fact_github_pr` | 累积快照 | 一个 GitHub PR | 137 | github_pr（1:1） |
| `fact_pr` | 累积快照 | 一个 PR | **6** | pr_cache + task 回填 |
| `dim_model` | 维度 | 一个模型的价格 | 31 | `schema/dim_model.csv` |
| `dim_session` | 维度（rollup） | 一个会话 | 12,278 | 从 `fact_request` GROUP BY |

### 已有派生/聚合服务（决定 SSOT）

| 位置 | 算什么 | 持久化？ | SSOT 地位 |
|---|---|---|---|
| **`adapters/raven.py::_cost()`** | `cost_usd = itok/1e6*in + otok/1e6*out`，按 `model_canon` 匹配价格 | **是**，落 L2 `req.cost_usd` | **权威且唯一**。L3 只 `SELECT cost_usd` 拷贝 |
| `adapters/model_canon.py::model_canon()` | 模型名归一 | 是，落 L2 | **权威**（`fact_request.model_canon`） |
| `merge.py` dim_session rollup | 会话级 request/token/cost 汇总 | 是，落 `dim_session` | 唯一 rollup |
| `L5_apps/digest/sources.py::_sum_series` | ADO+GitHub 每日序列相加 | **否，每次现算** | ⚠️ **聚合漏在 L5**（见 G2） |
| `L5_apps/digest/sources.py::_fold_top_n` | Top-N 折叠 + 其他归并 | 否，现算 | 展示逻辑，可留 L5 |
| `L5_apps/digest/cst.py::CST_DAY_EXPR` | CST 日切表达式常量 | — | ⚠️ **定义了但零复用**（见 G3） |

---

## 🏷️ 来源分类（Phase 1）

| 结构 | 标签 | honest keys / 备注 |
|---|---|---|
| raven `req`、claude_jsonl `turn`、multica_run `run`、claude_job `job` | **不可变事件源** | append-only，PK 幂等。**时间戳全 UTC**，日分桶必须显式 `+8h` |
| local_git `commit_log`、browser_history `visit`、gecko `focus_session`、multica_comment `comment` | **不可变事件源**（L2-only） | 同上，无跨源 join 需求故不合并 |
| multica_issue `issue`、ado_pr `pr`、github_pr `github_pr` | **累积快照**（里程碑会更新） | `updated_at`/`closed_date` 随流程推进被覆盖。**"完成数"是近似**——`updated_at` 任何编辑都会动（ADR-19） |
| **github_repo `repo_snapshot`** | **周期快照** ⭐ | 每 repo 每天一行 = 项目里**唯一已经物化的周期快照**。是 DWS 的现成先例 |
| memory_* ×3、news、hermes_tools、state_db | 事件/清单（L2-only） | 刻意停 L2 |
| `dim_model` | **维度**（主数据） | 自然键 `model`。**SCD Type 1**（覆盖）——改价不留史，见 G8 |
| `dim_session` | **已派生事实**（伪装成 dim） | 实测 12,278 行**全部 client=claude-cli**。命名叫 dim 但本质是会话级 rollup 事实 |
| `aidash_events` `user_event` | 反馈事件 | **0 行**，采集能力已建、无 L4/L5 消费者 |

### honest keys（不完美的键，如实标注）

实测四条星型桥接键的命中率：

| 桥 | 命中 / 总数 | 命中率 | 判定 |
|---|---|---:|---|
| `fact_turn.session_id → fact_request.session_uuid` | 166,164 / 166,169 | **99.99%** | ✅ 可靠 |
| `fact_task.issue_id → fact_issue.issue_id` | 12,143 / 12,164 | **99.8%** | ✅ 可靠（缺口=21 个 claude_job 本就无 issue） |
| `fact_task.session_id → fact_request.session_uuid` | 1,587 / 12,164 | **13%** | ⚠️ 弱。仅 codex/multica 路由为 claude-cli 时才有 |
| `fact_task.pr_url → fact_pr.pr_url` | **4** / 12,164 | **0.03%** | ❌ **近乎失效**（`fact_pr` 本身仅 6 行） |

> **grain 诚实性问题**：`fact_task` 混装两种 source，实测差异显著——`multica_run`(12,143) 100% 有 `issue_id`、786 条有 `error`；`claude_job`(21) **0% 有 issue_id**、0 条 error。合表可接受（都是"一次 agent 执行"），但**任何按 `issue_id`/`error` 的分析实际只覆盖 multica_run**，须在查询注释标注。

---

## 🧱 分层映射（沿用 L1–L5 命名 + 标准术语交叉映射）

> ⚠️ 映射是**跨体系类比，非官方对照**。Databricks/dbt 官方从不用 ODS/DWD/DWS 术语；且 Databricks 明说"若聚合表示驱动很多下游，**它们可以放在 Silver**"——"Silver 明细/Gold 聚合"是惯例非硬规定。命名亦无统一标准（DWM 是民间扩展）。**本项目已有 L1–L5 命名，沿用不改。**

| 本项目层 | 标准层 | 落到什么 | grain | Medallion | dbt |
|---|---|---|---|---|---|
| **L1_collect** | ODS | `raw/<source>/<date>.jsonl` | 源事件原样 | Bronze | (raw source) |
| **L2_normalize** | DWD 清洗 | `clean/<source>.db` ×20 | 最细明细（**成本在此派生**） | Silver | staging |
| **L3_merge** | DWD 汇聚 + DIM | `warehouse.db`：8 fact + 2 dim | 多 grain 星型 | Silver | intermediate |
| **（缺）** | **DWS** ❌ | **不存在** | — | Gold | marts |
| **L4_serve** | ADS | `queries/**.sql` ×39 | 报表口径 | Gold | marts |
| **L5_apps** | 消费应用 | `digest/*.py` ×17 → Markdown + Card payload | 卡片 | — | — |

**建议新增（补 DWS，物理上落在 `warehouse.db` 内，用 `dws_` 前缀，不新建目录/层号）**：

| 事实表 | 类型 | grain | 度量 | 关联维度 | 替代现有 |
|---|---|---|---|---|---|
| `dws_daily_cost` | 周期快照 | 每 CST 日 | `cost_usd`(SUM)、`total_tokens`、`requests`、`waste_usd` | `dim_date` | `trend/daily-cost`、`daily-waste`、`roi/daily-cost` |
| `dws_daily_pipeline` | 周期快照 | 每 CST 日 | `completed`、`cancelled`、`failed` | `dim_date` | `trend/daily-pipeline` |
| `dws_daily_pr` | 周期快照 | 每 CST 日 | `opened`、`merged`（**ADO∪GitHub 在此合**） | `dim_date` | `trend/daily-ado-pr` + `daily-github-pr` + L5 `_sum_series` |
| `dws_daily_automation` | 周期快照 | 每 CST 日 | `automated`、`total`、`ratio` | `dim_date` | `trend/daily-automation` |

**一致性维度**：

| 维度 | 自然键 | SCD | 来源 | 状态 |
|---|---|---|---|---|
| `dim_model` | `model` | **Type 1**（覆盖） | `dim_model.csv` | 已有。改价不留史（G8） |
| `dim_session` | `session_id` | Type 1 | `fact_request` rollup | 已有。**实为事实非维度** |
| **`dim_date`** | `day`(CST) | Type 0 | 生成 | ❌ **缺失（G3 核心）** |

> **保持星型，不做 OBT**：`dws_daily_*` 按主题分 4 张（成本/管道/PR/自动化），**不拍成一张万能日宽表**——理论底座的 red-line 2：中间层保持星型换灵活，OBT 只在消费侧有理由时用。

---

## 📊 指标口径登记

> "一个指标、一个口径、一次加工、多次使用"。

| 指标 | 类型 | 口径（公式 + 修饰词） | 粒度 | 应在层 | 现有实现（SSOT） |
|---|---|---|---|---|---|
| **单请求成本** | 原子 | `itok/1e6*in + otok/1e6*out`，按 `model_canon` 匹配 | 请求 | L2 | **`adapters/raven.py::_cost()`** ⚠️ 禁重抄 |
| 每日成本 | 派生 | `SUM(cost_usd)` + CST 日 | 日 | **DWS**（应） | `trend/daily-cost.sql` 现算 |
| 每日浪费 | 派生 | 大 input 小 output 的成本 + CST 日 | 日 | **DWS**（应） | `trend/daily-waste.sql` 现算 |
| 每日完成 issue | 派生 | `status=done AND updated_at` CST 日 | 日 | **DWS**（应） | `trend/daily-completed.sql`。**近似口径**（ADR-19） |
| 每日 PR 开/合 | 复合 | ADO ∪ GitHub 并集 | 日 | **DWS**（应） | ⚠️ **裂成两支 SQL + L5 `_sum_series`** |
| 自动化占比 | 复合 | `{cron,subagent} / 全部`，`unknown` 算人工 | 日 | **DWS**（应） | `trend/daily-automation.sql` 现算 |
| 缓存命中率 | 派生 | cache_read / 总 input | 日 | DWS | `cost/cache-hit-rate.sql` |
| 返工率 | 派生 | 同 issue 多次 run 占比 | issue | DWS | `health/rework-rate.sql` |
| **CST 日切** | 修饰词 | `date(ts/1000,'unixepoch','+8 hours')`，**禁 `localtime`**（ADR-22） | — | **DIM**（应） | ⚠️ **散在 18 文件 39 处**；`CST_DAY_EXPR` 常量零复用 |

---

## 🔁 SCD 与增量/幂等策略（体检结果）

- **SCD**：`dim_model` 是 Type 1（改价覆盖，不留史）。**影响**：历史成本按*当前*价重算会漂移——但因成本在 L2 落库为 `cost_usd`，历史值已冻结，实际不受影响。**除非重跑 `normalize --source raven`**（G8）。
- **增量**：L1 用 watermark（14/20 源）或 snapshot hash（6 源）。L2/L3 全量 drop+rebuild（派生物，安全）。
- **幂等**：✅ **实测通过**。`cleanio.write_clean` drop+recreate；`merge.py` unlink+重建 + `INSERT OR IGNORE`。实测 `fact_repo_snapshot`/`fact_github_pr` 重复行均为 **0**。

---

## 🔗 血缘

```
20 源
 └─L1 adapters/<src>.collect() ──[rawio.write_raw → redact_obj 强制脱敏]──> raw/<src>/<date>.jsonl
     └─L2 adapters/<src>.normalize() ──[_cost() 派生成本 ★SSOT / model_canon()]──> clean/<src>.db
         ├─(11 源止步)──────────────────────────────┐
         └─L3 merge.py ──[1:1 拷贝 ×5 / fact_task 并集 / dim_session rollup]──> warehouse.db
             │                                      │
             │        ❌ DWS 缺失（该在此物化日聚合）  │
             ▼                                      ▼
             L4 serve.run_query() ──[warehouse + 按需 ATTACH L2-only]──> rows
                 └─L5 sources.fetch_* ──[⚠️_sum_series 聚合漏在此]──> dataclass
                     └─ render/must_see/llm+verify ──> archive/daily/<date>.md（必成 sink）
                         └─ aidash.build_briefing() ──> Card payload
                             └─ push_briefing() ──XPC──> AIDash（best-effort，失败不崩）
```

---

## 🚫 Red-lines（项目专属）

1. **成本 SSOT**：唯一实现是 **`adapters/raven.py::_cost()`**（L2）。任何 DWS/L4/L5 只能 `SUM(cost_usd)`，**绝不重抄 `tokens × dim_model` 定价数学**。体检确认目前无违规——`roi/daily-cost.sql` 用 `sum(COALESCE(cost_usd,0))`，L5 零 `per_mtok`/`1e6` 痕迹。**这条最容易在建 `dws_daily_cost` 时被违反。**
   > 配套已知坑：改 `dim_model.csv` 后**只跑 merge 无效**，必须 `normalize --source raven` 再 merge。哨兵是 `test_warehouse_integrity::test_no_tokens_without_cost`。

2. **脱敏不出 L1**：`rawio.write_raw` 是**唯一 chokepoint**（内部 `redact_obj`）。体检确认 **20/20 adapter 全部经由它**，零绕过。新增源必须走 `write_raw`，禁止直写 raw。

3. **诚实 grain**：`dws_daily_*` 按主题分 4 张，**禁止拍成一张万能日宽表**。`fact_task` 混装 multica_run/claude_job 的 grain 差异必须在查询注释标注。

4. **memory 停 L2**：memory_* ×3 不进 L3（体检确认未违反）。

5. **单向流**：L(n) 只读 L(n-1)。L1 禁 import L5（确认无违规）；L5 禁绕过 L4 直连 warehouse（确认无违规）。

6. **CST 显式 `+8h`**：禁 `localtime`（ADR-22，机器时区依赖破坏可复现性）。体检确认 39 处全部合规——问题是**重复**不是错误。

7. **降级不崩**：任一源失败返回 0，digest 照常产出并在 health 标注（ADR-23）。md 归档是必成 sink，写在 push 之前。

---

## 🔍 Gap 分析（现状 vs 分层理想）

| # | Gap | 类型 | 现状（实测） | 目标 | 优先级 | 状态 |
|---|---|---|---|---|---|---|
| **G1** | **日聚合该物化未物化** | 性能/复用 | `trend/daily-*` ×8 每次现算。`daily-cost` 实测 `SCAN fact_request`(708,375 行) + `USE TEMP B-TREE FOR GROUP BY`，0.21s CPU。无索引可用（`idx_req_ts` 对 `date(ts/1000,...)` 表达式无效） | 物化 `dws_daily_*` ×4，merge 时算一次 | **高** | ⏸ 暂缓 — 见顶部修订②（Phase 1 后收益塌了） |
| **G2** | **聚合逻辑漏在 L5** | 分层越界 | `sources.py::_sum_series` 在 Python 做 ADO∪GitHub 并集；`fetch_combined_pr_trends` 是复合指标 | 下沉到 `dws_daily_pr`，L5 回归纯 rows→dataclass 映射 | **高** | ⏸ 暂缓 — 随 Phase 2；理由与 G1 不同，见顶部 |
| **G3** | **缺 `dim_date`，CST 口径散落** | 一致性维度缺失 | `+8 hours` 在 **18 文件 39 处**重复。`cst.py::CST_DAY_EXPR` 常量定义了但**零复用**（grep 仅 1 处=定义处） | 建 `dim_date`（CST 日历），查询 join 而非各自 `+8h` | **高** | ✅ #140 — 改用生成列，非 dim_date |
| **G4** | `dim_session` 名实不符 | 建模 | 命名为 dim，实为 `fact_request` 的会话级 rollup 事实。实测 12,278 行全 `client=claude-cli` | 要么更名 `dws_session`，要么在注释标注其事实性质 | 中 | ✅ #141 — schema 注释标注 |
| **G5** | **15/39 查询无消费者** | 治理 | `behavior/runaway-sessions`、`cost/context-waste`、`health/agent-scorecard`、`health/rework-loops`、`health/rework-threads`、`health/task-failures`、`health/wasted-tokens`、`issues/drill`、`issues/trend`、`memory/*`×2、`roi/by-client`、`roi/daily-cost`、`tools/usage-rank`、`cost/by-model-window` | 移到 `explore/`，明确不承诺契约；L4 只留 24 支生产口径 | 中 | ✅ #142 — 改用 tier marker，非移动目录 |
| **G6** | **桥接键近乎失效** | honest keys | `fact_task.pr_url→fact_pr` 命中 **4/12,164 (0.03%)**；`fact_task.session_id→fact_request` **13%**。`fact_pr` 仅 6 行 | 要么修（pr_cache 采集面太窄），要么在 schema 注释显式标注"此 join 不可依赖" | 中 | ✅ #141 — 注释 + 测试锁定为已知弱 |
| **G7** | **6 源零消费者** | 治理 | `browser_history`(2,644 行)、`hermes_tools`(983)、`memory_*`×3(58)、`aidash_events`(0) 无任何 L5 消费 | 决定：接入消费面 or 停采（`browser_history` 每天采 1.6M 却无人读） | 低 | ○ 未做 — 需产品决策 |
| **G8** | `dim_model` 无 SCD | 治理 | Type 1 覆盖。改价后重跑 normalize 会**静默重写历史成本** | 加 `effective_from`/`effective_to`（Type 2），或至少文档化"改价不得重跑历史 normalize" | 低 | ✅ #141 — schema 注释 |
| **G9** | 数据质量校验偏薄 | 质量 | `test_warehouse_integrity` 仅 3 个断言（model_canon 存在、canon 折叠、有 token 必有 cost） | 补六维校验（见下） | 中 | ✅ #141 — 21 条六维断言 |
### 数据质量六维（逐项实测）

| 维度 | 现状 | 判定 |
|---|---|---|
| **唯一性** | `fact_repo_snapshot`/`fact_github_pr` 均有复合 PK，实测重复行 **0** | ✅ |
| **完整性** | `fact_request.cost_usd` NULL 率 **4.2%**（未知模型/NULL token，设计如此）；`fact_task.tokens=0` **3.5%** | ✅ 可解释 |
| **及时性** | `fact_request`/`fact_turn`/`fact_repo_snapshot` 最新均 **2026-08-02**（当天） | ✅ |
| **一致性** | 桥接键 2 条弱/失效（G6） | ⚠️ |
| **有效性** | 无 `accepted_values` 类校验（如 `status` 取值域、`state` 枚举） | ❌ 缺（G9） |
| **准确性** | `test_no_tokens_without_cost` 是唯一哨兵（守"新模型出了价格表没跟上"） | ⚠️ 单点 |

---

## 🗺️ 分阶段 refine 计划

> 本 skill 止于此计划；实现是之后单独任务。每阶段独立可验证。

### Phase 1 — 建 `dim_date`，收敛 CST 口径（G3）
- **动**：`schema/warehouse.sql` 加 `dim_date`（CST 日历，覆盖数据实际跨度）；`merge.py` 生成；改造 39 处 `+8 hours` 为 join 或复用单一表达式常量。
- **验收**：`grep -c '+8 hours' L4_serve/queries/*/*.sql` 显著下降；所有 39 支查询结果**逐行不变**（回归快照对比）。
- **red-lines**：不触碰成本 SSOT；`localtime` 仍然禁用。
- **为何第一**：无行为变更、纯口径收敛，是后续 DWS 的地基（`dws_daily_*` 都要 join 它）。

### Phase 2 — 物化 `dws_daily_*` ×4（G1 + G2）
- **动**：`schema/warehouse.sql` 加 4 张 `dws_daily_*`；`merge.py` 在 fact 灌完后聚合一次；改造对应 L4 查询改读 DWS；L5 删 `_sum_series`/`fetch_combined_pr_trends` 的聚合职责。
- **验收**：① `trend/daily-*` 结果与改造前**逐行相同**；② `EXPLAIN QUERY PLAN` 不再 `SCAN fact_request`；③ `test_digest_golden` 仍绿。
- **red-lines**：⚠️ **`dws_daily_cost` 必须 `SUM(cost_usd)`，禁止重抄 `_cost()` 的定价数学**（红线 1）；4 张分表，禁 OBT（红线 3）。
- **注意**：`merge.py` 是 drop+rebuild，DWS 天然继承幂等，无需新增幂等机制。

### Phase 3 — L4 治理：生产口径 vs 探索查询分离（G5）
- **动**：15 支孤儿移到 `L4_serve/explore/`（或加 `-- aidata-status: explore` 标记）；README 说明 `explore/` 不承诺契约、不进 CI 回归。
- **验收**：`serve.list_queries()` 仍能列出全部；生产 24 支有测试覆盖，explore 无。

### Phase 4 — honest keys 与质量校验（G6 + G9 + G4 + G8）
- **动**：① `warehouse.sql` 给 `fact_task.pr_url`/`session_id` 加"此 join 命中率 0.03%/13%，不可依赖"注释；② 补六维校验（`status`/`state` 取值域、及时性断言）；③ `dim_session` 更名或标注；④ `dim_model` 加"改价不得重跑历史 normalize"文档化红线。
- **验收**：`pytest tests/test_warehouse_integrity.py` 断言数从 3 增至覆盖六维。

### Phase 5（可选，需用户决策）— 零消费源去留（G7）
- **动**：对 6 个零消费源逐个决定"接入消费面"或"停采"。`browser_history` 每天写 1.6M raw 却无人读，是最明显的候选。
- **注意**：这是**产品决策不是技术债**——`aidash_events` 的 0 行是"回流链路已建、等 L5 消费者"的有意状态，不应误判为死代码。

---

## ⚠️ 局限 & 待确认

- **本次未覆盖**：`L5_apps/digest/` 的 17 个模块只按"是否含聚合逻辑"扫过，未逐个审 render/todo_rules/inbox 的内部质量——那属于应用层设计，不在数仓分层范围。
- **`_fold_top_n` 归属存疑**：它做 Top-N + 其他归并，介于"聚合"与"展示"之间。本蓝图判为**展示逻辑，留 L5**（因 Top-N 的 N 是卡片决定的），但若将来多处复用同一 N，应下沉 DWS。
- **G6 的修法需用户拍板**：`fact_pr` 仅 6 行是因为 `pr_cache` 源本身采集面窄（`~/.claude/gh-pr-status-cache.json`）。是扩大采集、还是承认这条桥就是弱的并标注——是产品取舍。
- **映射是类比非官方对照**——已在「分层映射」节标注（Databricks/dbt 官方不用 ODS/DWD/DWS 术语；"Silver 明细/Gold 聚合"是惯例非硬规定）。
- **命名沿用 L1–L5**（用户指定）。DWS 建议以 `dws_` **表名前缀**落在既有 `warehouse.db` 内，**不新建层号/目录**——避免小数层号（如 L3.5）把编号变成承重结构。
