# Daily Digest 与 AIDash 推送链架构

**生成日期**: 2026-06-30
**状态**: 架构现状记录 + 待简化点标记
**关联 cron**: `78d2b35a5693` / `e968439fa1f9` / `020f594ac460` / `487906888113`
**关联 skill**: `daily-digest` / `aidash`

---

## 1. 整体架构（数据流向）

```
            ┌──────────────────────────────────────────┐
            │  数据源（4 个并行采集）                   │
            │  - Multica 4 workspace × 全部 issue       │
            │  - Hermes cron 输出 + 状态                │
            │  - Sapphire ADO PR                        │
            │  - Hermes session_search                  │
            └─────────────────┬────────────────────────┘
                              │
                              ▼
            ┌──────────────────────────────────────────┐
            │  采集脚本（no_agent，输出 JSON to stdout）│
            │  ~/.hermes/scripts/                       │
            │    daily_digest_collector.py              │
            └─────────────────┬────────────────────────┘
                              │ JSON 注入 agent context
                              ▼
            ┌──────────────────────────────────────────┐
            │  Cron: unified-daily-digest (78d2b35a)    │
            │  schedule: 0 4 * * *  (每天 04:00)        │
            │  agent: 用 daily-digest skill 生成报告    │
            └─────────────────┬────────────────────────┘
                              │
              ┌───────────────┼───────────────┬──────────────────┐
              │               │               │                  │
              ▼               ▼               ▼                  ▼
        ┌──────────┐   ┌──────────┐   ┌──────────────┐   ┌─────────────────┐
        │ 微信精简 │   │ 本地文件 │   │ Multica issue │   │ AIDash menubar  │
        │ (必看层) │   │ (完整版) │   │ my workspace  │   │ (按需推，可选)  │
        │ 04:00 推 │   │ daily/   │   │ done 状态     │   │ 用户口令触发     │
        └──────────┘   │ YYYY-MM- │   └──────────────┘   └─────────────────┘
                       │ DD.md    │
                       └──────────┘

    周报路径（独立 cron，目前重复触发）：
    ┌─────────────────────────────────────┐
    │  Cron: daily-digest-周报 (e968439f)  │
    │  schedule: 0 4 * * 1  (周一 04:00)   │
    │  ⚠ 与 unified 同分钟，微信限流冲突   │
    │  → 待合并到 unified（plan A1）       │
    └─────────────────────────────────────┘
```

---

## 2. Daily Digest 现状

### 2.1 cron 配置

| job_id | name | schedule | 用途 | 现状 |
|---|---|---|---|---|
| `78d2b35a5693` | unified-daily-digest | `0 4 * * *` | 每日日报+任务看板 | ✅ 绿，但微信 rate limit |
| `e968439fa1f9` | daily-digest-周报 | `0 4 * * 1` | 周一周报 | ⚠ 与 unified 同分钟，重复触发 |

### 2.2 采集脚本

**路径**: `~/.hermes/scripts/daily_digest_collector.py`

**模式**: `no_agent=False`（脚本先跑，stdout 注入 agent context）

**4 个并行数据源**:
1. **Multica 云端**: 所有 4 workspace 的 issue list
   - 关键 pitfall: `multica issue list` 必须显式 `--limit 500`，默认 50 静默截断
2. **Hermes cron 输出**: 读 `~/.hermes/cron/output/{job_id}/*.md` 最新文件，截断 1000 chars
3. **Hermes cron 状态**: agent 侧 `cronjob(action='list')` 拿 enabled/paused/error/last_status
4. **Sapphire ADO PR**: `az repos pr list` 含 stuck 原因分析

**容错**: 采集脚本本身写一个 fallback 版日报（纯数据无 LLM 分析）到 `daily/YYYY-MM-DD.md`。即使后续 agent 失败，当天至少有可读文件。

**日期基准**: CST（Asia/Shanghai），不是 UTC（2026-06-10 修过 bug）

### 2.3 输出 sink（4 个）

| Sink | 内容 | 推送规则 |
|---|---|---|
| 微信 | 必看层（≤1500 字） | TODO 状态 + 深度分析 + 明日规划 |
| 本地文件 | 完整版 | `~/Development/personal/daily-digest/daily/YYYY-MM-DD.md` |
| Multica issue | 完整版 | my workspace, status=done, 标题"日报 YYYY-MM-DD" |
| AIDash menubar | 结构化 4 container × 8 card | **按需推**（用户口令触发，非自动） |

### 2.4 文件结构

```
~/Development/personal/daily-digest/
├── todos/YYYY-MM-DD.md           ← 白天随时追加（模式 A）
├── daily/YYYY-MM-DD.md           ← 04:00 cron 生成（模式 B+C）
├── weekly/YYYY-Www.md            ← 周一 04:00 cron 生成
└── retro/<topic>-<type>-<dates>.md  ← 手动 retro
```

---

## 3. AIDash 推送链现状

AIDash 是用户的 macOS menubar app（`/Applications/AIDash.app`），架构：

```
aidash CLI → XPC → AIDash app → SwiftData / CloudKit
```

CLI 只能 publish/读，从不直接写 CloudKit。

### 3.1 三个组件 + 一个手动入口

| 组件 | 类型 | 触发 | 用途 | 现状 |
|---|---|---|---|---|
| `aidash-snapshot.sh` | cron `020f594ac460`, every 30m, no_agent | 自动 | **数据采集**: 把 AIDash project 全部 issue 写 jsonl | ✅ 绿（近 3 天 3 次 multica down 警告） |
| `AIDash Spec Supervisor` | cron `487906888113`, every 30m, agent | 自动 | **spec 监督**: 让 AIDash project pipeline 按 constitution 推进 | ✅ 绿 |
| `aidash_digest_push.sh` | 脚本 in `~/.hermes/scripts/` | **未挂 cron** | **手动 oneshot**: cat 预生成的 `aidash_digest_payload.md` 出 stdout | ⚠ 仅模板，未自动化 |
| 用户口令触发 publish | agent 走 aidash skill | 用户说"推到 AIDash" | **正式 publish**: 4 container × 8 card 走 aidash CLI 6 步流程 | ✅ 实战可用 |

### 3.2 三者关系

**关键认知**: 三个组件**互不耦合**。

```
aidash-snapshot.sh:    采集 AIDash project 自己的 issue → jsonl
                       (供 Spec Supervisor 读 + 用户/agent 查 backlog)
                       ▲▲▲ 与 daily-digest 完全无关 ▲▲▲

AIDash Spec Supervisor: 读 AIDash project issue + repo 状态
                        → 推 pipeline 按 spec 走（提 issue / 评 PR）
                        ▲▲▲ 与 daily-digest 完全无关 ▲▲▲

aidash_digest_push.sh: 手动 oneshot 脚本，仅 cat 一份预写好的 payload
                       ▲▲▲ 实际不走 aidash CLI，是临时 stub ▲▲▲

用户口令触发 publish:    agent 走 aidash skill 把 daily digest 推 menubar
                        ▲▲▲ 这才是 daily-digest → AIDash 的真实路径 ▲▲▲
```

### 3.3 AIDash publish 标准流程（6 步）

每次推 briefing 走（详见 `~/.hermes/skills/productivity/aidash/templates/publish-today.sh`）：

1. `aidash briefing put --date today --generated-by <agent>`
2. 每 container: `container put --briefing-date today --id <stable-uuid> --title ... --order N --layout <auto|list|grid|hero> [--style ...]`
3. 每 card: `card put --container-id <c-uuid> --id <stable-uuid> --type <type> --size <size> --payload @file.json`
4. `briefing publish --date today` ← 原子生效

**UUID 必须 stable**: 同 UUID 重跑 = 覆盖，不重复。约定 `XXXXXXXX-MMDD-NNNN-0000-NNNNNNNNNNNN`。

### 3.4 4 container × N card 标准拆分

| order | container | layout | style | cards |
|---|---|---|---|---|
| 10 | 总览 | auto | accent | digest(hero) + metric(wide) + agentSummary(wide) |
| 20 | ADO PR Watch | list | warning | todoList(wide) |
| 30 | 今日规划 | list | accent | todoList(hero) P0/P1/P2 |
| 40 | 深度分析 | list | neutral | insight(wide) × 2-4 (可改进/不足/重复性/可探究) |

---

## 4. AIDash project Multica issue 现状

| 字段 | 值 |
|---|---|
| project_id | `396be26e-b5fa-44fa-8652-548e01e443f6` |
| workspace_id | `6a90176a-ca91-4760-8594-39e1cf97c2a4` (my) |
| issue 数 | 146 / 146 done (Phase 1 完成) |
| 最近 commit | 16h 前（活跃） |
| 状态分歧 | **Multica 146/146 done，但 repo 还在改** ← 待用户决策是否 reopen 进入下一阶段 |

snapshot 文件: `~/Development/AIDash/.aidash-state/aidash-snapshots.jsonl`（保留最近 250 条，~5 天）

---

## 5. VitalStride pipeline 对照

为了和 AIDash 链对比记录，VitalStride 走另一条路：

| job_id | name | schedule | 路径 |
|---|---|---|---|
| `44f135c30d42` | vitalstride-pm-daily | `0 8 * * *` | workdir=VitalStride, agent 走 `vitalstride-pm-scan` skill, 推微信 |

**与 AIDash 链的差异**:
- VitalStride 没有 snapshot cron（不需要，直接每天 PM scan 一次）
- VitalStride 没有 menubar app sink
- VitalStride 推送目标只有微信 + multica-quick-issue

---

## 6. 已知问题与待简化点

### 6.1 微信 rate limit 集中爆（4 个 job 都报）

| 时间 | job | last_delivery_error |
|---|---|---|
| 04:00 | unified-daily-digest | `iLink sendmessage rate limited; cooldown active for 30.0s` |
| 04:00 | daily-digest-周报 (周一) | 同上 |
| 08:00 | vitalstride-pm-daily | 同上 |
| 09:00 | sapphire-crash-pipeline | 同上 |

**根因**: 04:00 双触发 + 08:00/09:00 间隔虽够但似乎 iLink token bucket 累积未恢复

**简化方案**:
- A1 合并周报到 unified → 04:00 只剩 1 个 job
- C1 错峰到 04:00 / 08:15 / 09:15

### 6.2 aidash-snapshot 偶发「multica down」

近 3 天 3 次 `cron-errors.log`:
```
$(date) — empty issue list (multica down? token expired?)
```

**根因**: multica daemon 偶尔挂

**修法**: snapshot 脚本加二次重试（plan C3.1）
```bash
for i in 1 2 3; do
  ISSUES_JSON=$(multica issue list --project "$PROJECT_ID" --limit 500 --output json 2>/dev/null)
  [ -n "$ISSUES_JSON" ] && break
  sleep 5
done
```

### 6.3 `aidash_digest_push.sh` 是 stub

只 cat 预写的 `aidash_digest_payload.md`，**不实际调 aidash CLI**。

**两个方向（plan B3）**:
- **方向 A**: 删除此 stub，确认推送路径只走"用户口令触发"
- **方向 B**: 实现真正的自动 publish（cron 04:30 把当日 digest 推 menubar，免去用户手动）

### 6.4 daily-digest 周报与 unified 同分钟

| 周一 04:00 | unified 跑 daily digest |
| 周一 04:00 | 周报 cron 也跑 |
| 结果 | 微信 rate limit + 内容部分重叠 |

**修法（plan A1）**: 把周报逻辑并入 unified
```python
if weekday == 0:  # 周一
    append_weekly_section()
```

### 6.5 AIDash Multica project 状态分歧

- Multica issue: 146/146 done（Phase 1 收尾）
- Repo commit: 16h 前（还在加 token compliance matrix）
- Spec Supervisor cron 每 30m 在跑，但 project 已无 backlog

**待用户决策**:
- A) Multica reopen 一个 Phase 2 project 重新建 backlog
- B) AIDash 退出 multica 管理，纯走 repo + spec workflow
- C) 保持现状（Supervisor 当 watchdog，无 backlog 时空跑）

---

## 7. 相关文件速查

### 脚本
- `~/.hermes/scripts/daily_digest_collector.py` — 数据采集（unified cron 用）
- `~/.hermes/scripts/aidash-snapshot.sh` — AIDash 自己的 issue snapshot
- `~/.hermes/scripts/aidash_digest_push.sh` — oneshot stub（未挂 cron）
- `~/.hermes/scripts/aidash_digest_payload.md` — stub 的 payload 模板

### Skill
- `~/.hermes/skills/productivity/daily-digest/SKILL.md`
- `~/.hermes/skills/productivity/daily-digest/references/aidash-push-recipe.md`
- `~/.hermes/skills/productivity/aidash/SKILL.md`
- `~/.hermes/skills/productivity/aidash/templates/publish-today.sh`

### Spec
- `~/Development/AIDash/.specify/memory/constitution.md` — v1.4.0 权威 design tokens
- `~/Development/AIDash/specs/001-core-briefing-cli/contracts/cardtype-payloads.md`
- `~/Development/AIDash/specs/001-core-briefing-cli/contracts/cli-surface.md`

### 数据
- `~/Development/personal/daily-digest/daily/` — 每日日报存档
- `~/Development/AIDash/.aidash-state/aidash-snapshots.jsonl` — issue snapshot
- `~/Development/AIDash/.aidash-state/cron-errors.log` — snapshot 失败日志
