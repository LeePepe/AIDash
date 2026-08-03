# Finding: multica 服务中断（2026-08-03 起，预计 8 号恢复）

- **日期**: 2026-08-03
- **状态**: 进行中，**预计 2026-08-08 恢复**
- **严重度**: 低（数据完整性无损）— 但会让 briefing 上 4 个指标显示"停滞"，需知情不误判
- **来源**: 用户告知

---

## 一句话结论

multica 服务挂了，预计 8 号恢复。期间 multica 系源采不到新数据，**briefing 上相关指标会平/掉到 0，那是服务中断不是我的产出下降**。

## 影响面（4 个源，均 degrade-safe）

| 源 | 落到哪 | 中断期间表现 |
|---|---|---|
| `multica_issue` | `fact_issue` | 「完成 issue（近似）」趋势停在 08-02 |
| `multica_run` | `fact_task` | 「管道」完成/取消/失败趋势停滞 |
| `multica_comment` | L2-only | `planner-gap` / `rework-threads` 无新增 |
| `codex_prompts` 的 B 档 | — | `multica-agent-sdk` 会话不再新增（占 Codex 87%） |

最后采到的数据：`multica_run.ts_start` / `multica_issue.updated_at` 均为 **2026-08-02**。

## 为什么不用改代码

ADR-23 的降级契约已经覆盖：源不可达 → `collect()` 返回 0、不抛异常，digest 照常产出并在 source-health 里标注。04:00 cron 每源有 300s 预算，multica CLI 超时会被 `timeout` 截断并记一行警告，不影响其余 19 个源。

**已验证的先例**：M2 就明确写了「multica 失败降级为『数据缺失』而不崩 digest」。

## 恢复后要做什么

1. `python3 cli.py collect --source multica_issue`（其余 multica 源同理）——
   `multica_issue` 用 **per-workspace watermark + updated_since 14 天窗口**，
   所以中断期间被修改的老 issue 也能补回来，不会永久漏掉。
2. 对照 `fact_issue.updated_at` 是否重新出现 08-03..08-08 的数据。

## 判读提醒

8 月 3–8 日这段的 briefing 里，multica 相关指标的"下降箭头"**不代表产出下降**，
是数据源中断。看 8 号之后的第一份 briefing 时，「完成 issue」会出现一个补齐的
尖峰（14 天窗口回捞），同样不是当天真实完成量。
