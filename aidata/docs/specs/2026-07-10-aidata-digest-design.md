# AI 使用日报 (aidata-digest) — 设计文档 (定稿)

> 用 brainstorming 的一次一问 + grill-with-docs 的追问严格度产出。
> Glossary（术语表）+ ADR（决策记录 1~23）+ 架构总览 + 5 里程碑分期。
> **状态：定稿，可进入实现计划。**

## Context

用户已有一套 daily-digest（讲 multica 项目/任务/PR），现决定**抛弃旧的项目 digest**，
基于 aidata 的 AI 使用数据**新建一套独立的「AI 使用日报」**。digest 是 aidata 的消费者，
aidata 分层不变，但可按需增加数据源/内容。核心目标：**trending（趋势）**。

可复用的既有基础设施（来自现有 daily-digest 系统）：
- collector 脚本 → JSON 注入 agent → 分层生成 → 分层投递（微信必看层 + 本地/Multica 存档层）
- Hermes cron `0 4 * * *`（04:00 CST），skill 驱动
- 投递 sink：微信推送、本地 md 归档、Multica issue（my workspace <WS_MY_UUID>）

## Glossary（术语表）

- **AI 使用日报 / aidata-digest**：新建的 digest，数据源 = aidata warehouse，讲「昨天怎么用 AI / 花多少 / 哪里浪费 / pipeline 健康 / 趋势」。
- **四大板块**（用户明确的核心结构）：
  1. **Trending（重点）** — 今天 vs 昨天/近期，各维度方向 ↑↓→
  2. **今日 TODO** — 基于数据的可执行行动项
  3. **昨日汇总** — 昨天一整天 AI 使用全貌
  4. **可改良部分** — 深度分析，哪里能更好
- **必看层**：微信推送内容，精简分层（≤1500 字，沿用旧 digest 分层投递概念）。
- **存档层**：完整版，写本地文件 + Multica issue。
- **「昨天」**：digest 04:00 CST 跑时 = **CST 前一自然日 00:00–24:00**。

## ADR（架构决策记录）

### ADR-1：趋势基线直接从 warehouse 按天现算，不建独立快照层
aidata 事实表本就带时间戳（`fact_request.ts` epoch-ms、`fact_turn.ts`、`fact_issue.created_at`），
所以「今天 vs 昨天 vs 近 7 天」= warehouse 的一个按天 group by 查询。趋势是查询，不是新存储层。
digest 按需取某天/某时间段切片。**符合「aidata 分层不变、digest 按需消费」。**
- 代价/前提：见 ADR-2（时区）、未决 Q1（数据保留窗口）。

### ADR-2：日报按 CST（Asia/Shanghai）切天
digest 04:00 CST 跑，「昨天」= CST 前一自然日。aidata `ts` 存 UTC（v2 约定），
查询时 `date(ts/1000,'unixepoch','+8 hours')` 转 CST 再按天分组（显式 +8h，**不用** `localtime`——避免 host TZ 依赖，ADR-22）。
与旧 digest、用户作息一致。UTC 切天会错位 8 小时，弃用。

### ADR-3：趋势数据充足（raven 84 天连续日线）
raven 主源有 84 天连续日线（2026-04-16→今，CST 切天验证通过），日/周环比、滚动均值、
连续 N 天检测都可现算。**约束**：其他源回看窗口更短（claude jsonl 从 2026-06-09、memory 仅 53 行），
trending 里数据窗口不足的维度须标注「数据仅 N 天」，不硬画趋势。

### ADR-4：trending 必看层维度（用户圈定）
必看层画箭头：**pipeline 健康**、**效率/行为**、**multica issues 完成数（分 project）**，
「以及其他等等」（成本/token、浪费额降存档层或视字数纳入）。⚠️ 见「扩展需求」——
multica issues 分 project + 完成数依赖 aidata 尚缺的字段。

### ADR-5：aidata 扩展 EXT-1/2/3 全做，workspace 限 workspace-a + my（不含 epichain）
- EXT-3：fact_issue 补 `updated_at` → 算「今日完成」（updated_at 落在 CST 昨天且 status=done）
- EXT-2：multica_issue adapter 循环采 workspace-a(<WS_A_UUID>) + my(<WS_MY_UUID>)（不含 epichain）
- EXT-1：采 `project_id`；project 为空时 trending 降级为分 workspace 展示
- 连带：multica_run/fact_task 采集也需覆盖 workspace-a（当前只 my）

### ADR-6：aidata 新增 ADO PR 源，采「我账户 creator 的 PR」
WorkspaceA repo，采 creator = 我（me）的 PR（含手动开 + AI agent 用我账户开的）。
Azure CLI（**me@example.com**）`az repos pr list --creator ...`。这是「我的 PR 活动」，非全项目进度。
落库形态见 Q9（独立表 vs 并入 fact_pr）。

### ADR-7：aidata 新增 Hermes state.db 源
per-session token + `source` 维度（cli/cron/acp/weixin/subagent），能算「自动化程度」。
raven 没有此行为维度。作为独立 L2 clean 源；是否进 L3 merge 见 Q10。
路径 `~/.hermes/state.db` 表 `sessions`（started_at, message_count, tool_call_count,
input_tokens, output_tokens, source, model）。

### ADR-8：今日 TODO = 规则出候选 + agent 精选
aidata 提供「信号查询」（硬阈值候选：opus 杀鸡>$X、agent 完成率<50%、浪费额环比涨…），
digest agent 从候选挑/排序/写成可执行句。硬数据打底防幻觉 + LLM 润色保灵活。

### ADR-9：aidata 是平台，digest 是其消费层之一
aidata 提供 L4 命名查询；digest 是建立在其上的一个应用。将来可有别的消费层（仪表盘/告警）。

### ADR-10：digest 逻辑长在 aidata 项目内
新增 `aidata digest --date YYYY-MM-DD` 子命令，自调 L4 查询组装四板块。
Hermes cron 退化为「定时调用 + 投递」通道。

### ADR-11：digest 的 LLM 调用放在 aidata 最高层（新增 L5 应用层 apps/）
L1采集→L2整理→L3合并→L4取用 保持纯数据、无 LLM。新增 **L5 应用层 apps/** 承载 digest：
调 L4 拿结构化数据 → 调 LLM（走 raven localhost:7024 + 现有 key）润色/TODO 精选 → 出成品。
LLM 依赖隔离在最高层，L1-L4 不动。

### ADR-12：新建 aidata-digest cron，禁用旧 unified-daily-digest
新建独立 cron job 调 `aidata digest`。旧 `unified-daily-digest`（id 78d2b35a5693）设 enabled:false
保留配置防回滚。新的稳定后再删旧的。

### ADR-13：ADO PR 用独立 fact_ado_pr 表 + state.db 只到 L2
- ADO PR schema（stuck_reasons/reviewers/vote/age_hours）与 GitHub fact_pr 差异大 → 独立 `fact_ado_pr` 表，不硬并。
- state.db 按 session 粒度、与 raven 口径不同、无干净 join 键 → 只到 L2 clean，digest 直接查，不进 warehouse merge（同 memory 源）。

### ADR-14：必看层字数分配 + 折叠
Trending~600 / 今日 TODO~400 / 昨日汇总~300 / 可改良~200（≤1500 总）。
连续 3+ 天不变的项折叠为一行「🔇 背景噪音: N 项无变化」。沿用旧 digest 分层惯例。

### ADR-15：昨日汇总板块内容
昨天总花费/请求数、top 模型、干了哪些 multica issue（分 workspace）、开了哪些 ADO PR、
自动化占比（来自 state.db source 维度：cron/自动 vs 手动）。

### ADR-16：投递 sink = 本地存档 + AIDash（⚠️ 有矛盾待解，见 Q12）
用户改定：**不投微信、不存 Multica issue、接入 AIDash、本地 md 存档**。
- 本地：`~/Development/AIDash/aidata/L5_apps/digest/daily/YYYY-MM-DD.md`
- AIDash：通过 `aidash` CLI（DerivedData，XPC）推 Briefing→Container→Card；
  card type 有 `trending/todoList/metric/insight/digest/sectionHeader` 正好对应四板块。
- ⚠️ **矛盾**：AIDash recipe 明确警告「不要把 publish 挂 cron」——app 是 UI 渲染层、需 app 正在跑（XPC）、
  `aidash_digest_push.sh` 是空 stub。凌晨 04:00 app 未必开着 → 自动推可能失败。见 Q12。

### ADR-17：cron 拉起 AIDash app 直推（解 ADR-16 的矛盾）
凌晨 cron 推 AIDash 前先 `open -a AIDash && sleep 2 && pgrep -lf AIDash` 确保 app 在跑，
再走 `aidash` CLI（DerivedData 路径，XPC）推 Briefing。防御：**推失败不阻塞主流程**
（本地存档是必成 sink），失败记日志。接受违背 AIDash「不挂 cron」原约定的风险。

## 架构总览（grilling 定稿）

```
aidata 平台（分层不变，L1-L4 纯数据无 LLM）
 ├ L1 采集   raven(有) + multica_issue(扩 workspace-a+my, +project_id +updated_at)
 │           + ADO PR(新, creator=我) + hermes state.db(新)
 ├ L2 整理   各源清洗；state.db 停这层供 digest 直查
 ├ L3 合并   fact_request / fact_turn / fact_issue(+project_id,+updated_at)
 │           / fact_task / fact_pr(GitHub) / fact_ado_pr(新独立表) / dim_*
 └ L4 取用   命名查询（新增 digest 用的：trending 各维度 / 昨日汇总 / TODO 候选信号 / 改良点）
 └ L5 应用(apps/, 新增)  aidata digest --date：调 L4 → 调 LLM(raven) 组装四板块 → 出成品
                        ├ 四板块：⚡Trending / 📅今日TODO / 🗂昨日汇总 / 🔍可改良
                        ├ 必看层 ≤1500字(600/400/300/200 + 折叠背景噪音)
                        └ sink：本地 md 存档(必成) + AIDash(cron 拉起 app 直推, 失败不阻塞)

Hermes cron（新建 aidata-digest job, 禁用旧 unified-daily-digest）
 04:00 CST → 调 aidata digest → 拉起 AIDash 推
```

时区：aidata ts 存 UTC，digest 查询 `+8 hours` 转 CST 按天切。「昨天」= CST 前一自然日。

## grill 完整性审查发现 → 补充决策（ADR-18~22）

审查（对抗式 fresh-eyes）发现 3 Blocker + 若干 should-fix。补决策如下：

### ADR-18（解 B2 LLM）：模板打底 + LLM 填槽 + codex review 核对
- 数字/箭头/预算/AIDash card 结构由**确定性模板**生成，不依赖 LLM → 数字准、结构合规、字数可控。
- LLM（raven 7024，pin 的 `claude-haiku-4.5`）**只填有限长文本槽**（点评、TODO 措辞），填后字数截断校验。
- 生成后 **`codex:review` 核对**：校验日报数字与 L4 查询结果一致（catch 幻觉）+ 结构完整。
- **fallback**：LLM 不可用 → 退纯模板版（数字齐、无点评）。本地存档因此**永远必成**，解 ADR-16 矛盾。

### ADR-19（解 B1 今日完成）：multica adapter 改 updated_since 回读
现有 `number > watermark` 单调水位线会漏掉「老 issue 昨天收尾」。改为：每次按
`updated_since`（近 N 天）窗口回读最近变动的 issue（不只新建），normalize 仍 last-write-wins。
配合 EXT-3 的 `updated_at` 列，「今日完成」= updated_at 落 CST 昨天 & status=done。
⚠️ 仍是近似（updated_at 任何编辑都会变）——digest 标注「完成数为近似」。若 multica API 有
状态流转时间则优先用它（待核实 API）。**连带修 EXT-2 水位线**：多 workspace 各自独立水位线，
新增 workspace-a 时全量 backfill，不共享 my 的已推进水位线。

### ADR-20（解 B3 + 分期）：MVP 分 5 里程碑，按依赖排序
- **M1**：raven-only trending（成本/token/浪费/pipeline/行为，raven 已有 84 天）→ 本地 md，**纯模板无 LLM**。可独立 ship，先看到价值。
- **M2**：multica EXT-1/2/3（project_id + workspace-a+my + updated_since 回读）→「今日完成/活跃」+ 分 workspace。
- **M3**：ADO PR 源（fact_ado_pr）+ state.db 源（自动化占比）。
- **M4**：L5 LLM 填槽润色 + codex review 核对。
- **M5**：AIDash 推送（cron 拉起 app）。
每个里程碑独立可 ship；L4 查询随对应 M 增量加。

### ADR-21（解保留窗口矛盾）：warehouse 保证 append-only ≥ 最大趋势窗口
修 ADR-1 与「全部已解」的矛盾：warehouse 的 fact_request 等是 append-only（merge 只增不删），
raven raw shard 也 append-only 归档，故历史不随源 pruning 缩水。趋势窗口上限 = 已积累天数。
**若**将来 raven.db 自身 pruning 导致 collect 拿不到老数据，已落 warehouse 的历史仍在（raw + warehouse 是独立留存）。无需额外快照表。

### ADR-22（解 ADO 身份 + project 缩水 + 其它 should-fix）
- **ADO 身份**：Azure CLI 账户 = **me@example.com**（WorkspaceA 在 <ado-server>）。用 `az ad signed-in-user show` 解析出稳定 id，filter 用不可变 `createdBy.id`（非 email/显示名）。config 常量固化。
- **project 缩水**：ADR-4 的「分 project」实际降级为**分 workspace**（EXT-1 承认 project 常 null）。必看层明确标 workspace 粒度，不承诺 project。
- **时区确定性**：统一用 `'+8 hours'`（不用 localtime，避免 host TZ 依赖）。
- **测试策略**：CST 切天边界测试（23:00–01:00）、今日完成查询、字数截断、LLM-fail fallback 的 golden-file 测试（固定 --date）。
- **幂等**：`aidata digest --date` 重跑覆盖当日 md；依赖当日 collector 已跑完（cron 顺序：先 collect 再 digest）。
- **CLI 可用性**：az/multica/aidash 缺失或 auth 过期时该源降级跳过 + 记日志，不炸主流程。

### ADR-23：数据源健康在日报中显式呈现（不静默降级）
降级不该隐形——否则「WorkspaceA PR 那行空的」分不清是「今天没开 PR」还是「没采到」。
- digest 生成时记录每源采集状态：`ok` / `skipped:auth过期` / `skipped:CLI缺失` / `skipped:app未开` / `stale:数据仅到 N 天前`。
- **AIDash**：顶部状态条或一张 `warning` style 卡显示「⚠️ 数据源健康：ADO PR 未采(auth过期)｜其余 ok」。
- **本地存档**：昨日汇总板块附一行「数据源：raven✅ multica✅ ADO⚠️过期 state.db✅」。
- **区分真无数据 vs 没采到**：某源 skipped 时，涉及它的 trending 维度标「数据缺失」，**不画 →/0 进展**（避免误导）。
- 采集状态作为 digest 数据包的一个字段（`source_health`），模板层渲染，不依赖 LLM。

## 未决问题（全部已解）

grilling 完成，Q1-Q12 全部落为 ADR-1~17。无剩余未决点。

## aidata 扩展需求（本次新发现，实测确认）

digest 要的内容暴露出 aidata 现有 warehouse 的缺口：

- **EXT-1：fact_issue 缺 `project_id`** — 需 multica_issue adapter 采集入库。⚠️ 真实 issue 的 `project_id` 常为 null（workspace 级），project 为空时降级分 workspace。
- **EXT-2：fact_issue 仅覆盖 my workspace** — 扩展到 workspace-a + my（不含 epichain）。
- **EXT-3：fact_issue 缺完成时间** — 补 `updated_at` 才能算「今日完成」。
- **EXT-4：新增 ADO PR 源**（独立 fact_ado_pr 表，creator=我）。
- **EXT-5：新增 Hermes state.db 源**（L2 only，供 source/自动化维度）。
- **EXT-6：新增 L5 应用层 apps/** 承载 digest（唯一引入 LLM 的层）。
