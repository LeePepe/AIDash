# Finding: multica 采集中断（2026-08-03 ~ 2026-08-10）

- **日期**: 2026-08-03 首次记录，**2026-08-10 查明真因并修复**
- **状态**: **已解决**（配置已改，CLI 恢复）
- **严重度**: 低（数据完整性无损）— 但会让 briefing 上 4 个指标显示"停滞"，需知情不误判
- **来源**: 首次为用户告知（当时判断为"服务中断"）；2026-08-10 实测推翻

---

## 一句话结论（2026-08-10 修订）

**不是 multica 服务挂了，是 multica 从 Azure 迁到了本地 Docker，而 CLI 配置还指着已被销毁的云端地址。**

原记录写的"服务挂了、预计 8 号恢复"是基于当时信息的推断，**已被实测推翻**——保留在下方以存档，但不要据此判读。

## 真因（2026-08-10 实测）

`~/.multica/config.json` 的 `server_url` 仍是
`https://multica-backend.niceglacier-0ceb698a.eastasia.azurecontainerapps.io`，
该域名 **DNS 已 NXDOMAIN**（Azure 资源已销毁）。CLI 每次调用都解析失败，
`collect()` 按 ADR-23 降级为 0 行、不抛异常——所以**中断是静默的**。

与此同时本地 Docker 一直健康在跑（compose 来源 `~/Development/multica`）：

| 容器 | 端口 |
|---|---|
| `multica-backend-1` | `127.0.0.1:8080` |
| `multica-frontend-1` | `127.0.0.1:3000` |
| `multica-postgres-1` | 5432（容器内） |

**修复**：`server_url` 改为 `http://127.0.0.1:8080`（旧配置备份为
`config.json.bak-*`）。现有 token 本地后端直接认，CLI 立即恢复。
aidata 无需改代码——`config.py:40` 的 `MULTICA_CONFIG` 读的就是同一份文件，
没有第二处硬编码。

## 为什么"8 号数据恢复"是个假信号

08-08/08-09 `fact_issue` 确实重新出现数据，当时看像"服务如期恢复"。实际是
**另一个 workspace（`75d31069` Sapphire）有活动**——那条路径当时能通。
而 workspace `my`（`6a90176a`，AIDash 所在）水位一直停在 `2026-08-02T22:22:18Z`。

2026-08-10 修复后重跑 `collect --source multica_issue` 返回 **+0**，直接查后端确认
workspace `my` 最新 issue 更新时间**确实就是 08-02**——**那段是真没活动，不是漏采**。
两件事必须分开看，否则会把"没干活"误读成"采集坏了"。

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

## 恢复后要做什么（2026-08-10 已执行）

1. ✅ `python3 cli.py collect --source multica_issue` —— 返回 +0，见上：workspace `my`
   08-02 后确实无活动。`multica_issue` 用 **per-workspace watermark + updated_since
   14 天窗口**，中断期间被修改的老 issue 能补回来，不会永久漏掉。
2. ⏳ 其余 multica 源（`multica_run` / `multica_comment`）同理重跑一次。

## 判读提醒

8 月 3–10 日这段的 briefing 里，multica 相关指标的"下降箭头"**不代表产出下降**，
是采集中断。

**但注意**：这段时间 workspace `my` 本来也确实没有活动，所以**别把"补齐尖峰"
当成必然**——修复后重跑并没有捞回任何新行。中断与真实静默在这里叠在了一起，
两者要分开归因。

## 教训：静默降级需要可见性

ADR-23 的降级契约按设计工作了（不崩），但**代价是中断静默了 7 天**。
配置指向一个 NXDOMAIN 域名，和"今天真没数据"在 briefing 上长得一模一样。
值得考虑：source-health 里区分 **「0 行但连通」** 与 **「连不上」**，
后者应该显式报警而不是静静显示 0。
