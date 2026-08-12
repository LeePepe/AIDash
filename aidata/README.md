# aidata — layered AI-usage telemetry

A single-machine, zero-service data platform that collects, normalizes, merges,
and serves telemetry about **how you use AI tooling** — across Claude Code CLI,
Multica runtime, AI-agent PRs (GitHub + Azure DevOps), background jobs, memory
stores, and a widening ring of activity signals: per-tool usage, attention /
screen-time (via gecko), local browsing, local git commit stream, a key-free
news radar, and 已采集反馈事件 (user star/todo reactions pulled back from the
AIDash app via `aidash_events`).

The data already exists on this machine but is scattered; aidata unifies it.
**20 sources** feed L1 (`config.SOURCES`); **9** of them merge into the L3
warehouse (`config.MERGE_SOURCES`), the other 11 stay L2-only and are queried
directly.

## Layers (strict, one-way flow)

```
L1 collect   →  L1_collect/raw/<source>/<date>.jsonl   append-only, redacted, source-of-truth
L2 normalize →  L2_normalize/clean/<source>.db         each source cleaned independently
L3 merge     →  L3_merge/warehouse.db                  fact_*/dim_* — only mergeable sources
L4 serve     →  L4_serve/queries/*.sql                 named queries
L5 apps      →  L5_apps/digest/                        daily digest (md archive + AIDash push)
```

Each layer only reads the one above and writes its own. **Memory sources stop at
L2** and are queried directly — they are not merged (no cross-source join need).

## Usage

```bash
python3 cli.py collect              # L1: fetch new data from all sources (read-only)
python3 cli.py normalize            # L2: clean each source
python3 cli.py merge                # L3: build warehouse.db
python3 cli.py query --list         # list queries
python3 cli.py query issues/trend               # token/failure trend by issue number
python3 cli.py query issues/drill --param id=MY-1213
python3 cli.py query roi/by-client              # cost/latency per tool
```

### First-run setup — `config_local.py`

This repo is public, so it carries **no** account, employer, or workspace
identifiers. `config.py` defaults them to empty, and every source that needs
one degrades to a no-op (ADR-23) — the digest still builds on a fresh checkout.

To collect from your own Multica workspaces / Azure DevOps repo:

```bash
cp config_local.example.py config_local.py   # then fill in real values
```

`config.py` runs `from config_local import *` as its **last** statement, so any
name you define there rebinds the default above it — only state what you
override. `config_local.py` is git-ignored; never commit it.

### Query catalog

The full set of named queries (across `behavior/ cost/ health/ inbox/ issues/
memory/ news/ radar/ roi/ time/ tools/ trend/ work/`) is **self-describing —
don't hand-maintain a list here** (it drifts). Discover them at runtime:

```bash
python3 cli.py query --list          # authoritative, always current
```

Highlights: `cost/pareto` (spend concentration), `cost/model-downgrade`
(opus-for-tiny-output waste), `health/agent-scorecard` (per-agent reliability),
`health/rework-loops`, `behavior/runaway-sessions`, `roi/daily-cost` (per-CST-day
spend). Run `collect → normalize → merge` in order; all three are **idempotent**
(watermarks + PK dedup + snapshot hashing), so re-running never duplicates.

#### Two tiers: production contract vs exploratory

Queries split into two populations with very different lifetimes, declared by a
header marker (same style as `-- aidata-attach:`):

```sql
-- aidata-tier: explore
```

- **production** (no marker) — consumed by the L5 digest. Their columns are a
  **contract**: changing the shape breaks a briefing card. 32 of them today.
- **explore** (marked) — no L5 consumer; they exist for ad-hoc investigation via
  `cli.py query <name>`. Nothing downstream depends on their columns, so they can
  be freely reshaped or deleted. 15 of them today.

Both tiers are listed by `query --list` and run identically — the marker is
documentation for humans and agents, not a runtime switch. `tests/test_query_tiers.py`
keeps the two sets honest in both directions: a production query with no consumer
fails (mark it explore), and an explore query that L5 imports fails (it is a
contract in disguise).

**Adding a query?** If the digest will read it, add no marker. If it is for your
own investigation, mark it `explore` — otherwise the test fails, by design.

## AI-usage daily digest (M1)

Build a 4-section Markdown daily digest from raven trend data (template-only, no LLM):

```bash
python3 cli.py digest --date 2026-07-10   # reports on CST 2026-07-09
python3 cli.py digest                      # defaults to today CST
```

Output: `L5_apps/digest/archive/daily/<yesterday>.md`. Sections: ⚡ Trending
(cost/token/waste/pipeline/behavior arrows, CST day-over-day + 7-day avg),
📅 今日 TODO (rule-based), 🗂 昨日汇总, 🔍 可改良. Run `collect → normalize →
merge` first so the warehouse has the day being reported on. Optional LLM polish
(`--llm`, M4) and AIDash push (M5) build on top; the template is always the floor.

**M2 (multica, EXT-1/2/3):** the digest now also shows a "完成 issue（近似）"
trend and a per-workspace "昨日完成" line. The `multica_issue` adapter does an
`updated_since` window read (last 14 days) across EVERY configured workspace
with **per-workspace watermarks**, so old issues completed recently are
captured (the old `number > watermark` cursor missed them). `fact_issue` gains
`updated_at` + `project_id`. The count is **approximate** — `updated_at` moves on
any edit, not only completion (ADR-19). A multica failure degrades that section
to "数据缺失" without crashing the digest (ADR-23).

### M3 sources — ADO PR + Hermes state.db

- **ADO PR** (`fact_ado_pr`, separate from GitHub `fact_pr`): my Azure DevOps PRs
  via `az repos pr list`. The tracked repo is on ADO *Server*, whose
  `createdBy.id` differs from the AAD object id — we query by email then
  double-filter on the immutable ADO-native creator id (`config.ADO_CREATOR_ID`).
  Requires `az` login and the `ADO_*` constants set in `config_local.py`;
  degrades to empty + a health note if unauthed or unconfigured.
  Digest adds a Trending "开PR" arrow and a 昨日汇总 "开了 N 个 PR（合并 M 个）" line.
- **Hermes state.db** (L2-only, not merged — like the memory sources): per-session
  rows from `~/.hermes/state.db`. Exposes the `source` dimension → **automation
  ratio** = automated / total per CST day, where `AUTOMATED = {cron, subagent}`
  (scheduled / agent-spawned, no human in loop) and `{cli, acp, weixin, unknown}`
  = manual (`unknown` counts as manual — conservative). Only safe columns are read
  (never `system_prompt`/`model_config`/`billing_*`). Digest adds an automation
  arrow and a 昨日汇总 "自动化占比 X%" line. `started_at` is epoch **seconds**;
  ADO `created_date`/`closed_date` are ISO text — both bucketed to CST via `+8h`.

### M4 — optional LLM polish (`--llm`), number-guarded (ADR-18)

The deterministic template owns **every number**. `--llm` adds an OPTIONAL polish
pass that fills only bounded free-text slots — an overall 点评 (TL;DR) line and
refined TODO wording (the P0/P1 priority prefix and the underlying signal stay
template-owned). Slots are hard length-capped (150 / 120 chars, ADR-14).

```bash
python3 cli.py digest --date 2026-07-11          # template-only (default, no LLM)
python3 cli.py digest --date 2026-07-11 --llm    # opt into LLM polish
```

The LLM call is isolated in one module (`L5_apps/digest/llm.py`) — a stdlib
`urllib` client to the raven gateway (`ANTHROPIC_BASE_URL`, default
`http://localhost:7024`, pinned `claude-haiku-4.5`). The key is read from
`ANTHROPIC_API_KEY` / `RAVEN_API_KEY` and never logged. L1–L4 stay pure-data.

**Number-verification guard** (`L5_apps/digest/verify.py`): after polish, the
numeric tokens of the polished output are compared against the template. If the
LLM invented, altered, or dropped **any** number, the polish is rejected. Any of
— missing key, raven unreachable, timeout, malformed reply, or failed
verification — falls back to the **pure template** (ADR-16/18/23). The local
archive is a 必成 sink: it always produces, LLM or not. The template golden test
is unaffected; the LLM path is never golden-tested (non-deterministic by nature)
— instead the guard, the fallbacks, and `--llm`-off == template are unit-tested.

### M5 — 必看层 + AIDash push (`--aidash`) + cron wiring

**必看层 (must-see layer)** (`L5_apps/digest/must_see.py`): a deterministic,
≤1500-char compact fold of the full digest (ADR-14) — TL;DR → trending (arrows
kept) → alerts (with "连续 3+ 天不变" items folded into one `🔇 背景噪音: N 项无变化`
line) → 今日 TODO → 可改良. Template-based, no LLM, no new numbers. The full digest
stays the archive; the compact layer feeds the AIDash cards (and any future push).

**AIDash push** (`L5_apps/digest/aidash.py`): `build_briefing` maps the four
sections + the source-health line into AIDash Briefing→Container→Card payloads
(总览 digest + health insight, Trending trending, 昨日汇总 insight, 今日规划
todoList, 可改良 insight). `push_briefing` resolves the `aidash` CLI from
DerivedData (recipe glob, never `which`), ensures the app is running with a
bounded readiness poll (`open -a AIDash` + `pgrep`), then issues the
`briefing/container/card put` + `publish` calls over XPC (ADR-17).

```bash
python3 cli.py digest --date 2026-07-11               # archive only (default)
python3 cli.py digest --date 2026-07-11 --aidash      # also push to AIDash
python3 cli.py digest --date 2026-07-11 --llm --aidash # polish + push
```

**Non-fatal by contract (ADR-16/23):** the local md archive is written BEFORE the
push, and every push failure mode — no CLI, app won't launch (asleep Mac), XPC
error, or any raised exception — degrades to a logged warning. `write_digest`
still exits 0 and returns the archive path. Every failure mode is unit-tested
against a fake runner/opener/pgrep; the real-app path is a single skippable
`@pytest.mark.integration` test. No unit test ever launches the app.

**Cron wiring (ADR-12) — LIVE since 2026-07-12.** The `aidata-digest` Hermes job
(id `f6c875d937df`, schedule `0 4 * * *`, `no_agent`) runs daily at 04:00 CST;
the old `unified-daily-digest` job (`78d2b35a5693`) is `enabled:false`, kept for
rollback. The job invokes `~/.hermes/scripts/aidata_digest_run.sh`, which is a
**copy** of `scripts/aidata_digest_run.sh` from this repo — after editing the
runner here, re-sync it (`cp scripts/aidata_digest_run.sh ~/.hermes/scripts/`),
otherwise the live job keeps running the stale copy (this actually happened:
the 2026-07-18 `github_repo` addition only took effect after a manual re-sync
on 2026-07-22). The runner chains collect → normalize → merge →
`digest --llm --aidash` for CST today.

`scripts/aidata_digest_cron.py` is the installer used for the initial
registration (kept for reference / re-install on a new machine):

```bash
python3 scripts/aidata_digest_cron.py --dry-run   # print plan, change nothing
python3 scripts/aidata_digest_cron.py --apply     # register job + disable old
```

Run status is observable in `~/.hermes/cron/jobs.json` (`last_run_at` /
`last_status`) and per-run output under
`~/.hermes/cron/output/f6c875d937df/`. The old cron and
`~/.hermes/cron/jobs.json` are never touched by this repo's code or tests.

## Sources

All 20 sources below match `config.SOURCES`. **Merged? ✓** = enters the L3
warehouse (`config.MERGE_SOURCES`, 9 of them); **✗ L2-only** = cleaned to
`L2_normalize/clean/<source>.db` and queried directly, never merged.

| # | Source (`config` key) | Access | Grain | Merged? |
|---|---|---|---|---|
| 1 | raven (`raven`) | sqlite (CLI helper, read-only) | API request | ✓ `fact_request` |
| 2 | claude jsonl (`claude_jsonl`) | scan `~/.claude/projects` | conversation turn | ✓ `fact_turn` |
| 3 | multica issue (`multica_issue`) | `multica issue list` | issue | ✓ `fact_issue` |
| 4 | multica run (`multica_run`) | `multica issue runs`/`usage` | agent run | ✓ `fact_task` |
| 5 | multica comment (`multica_comment`) | `multica issue comment list` | issue comment | ✗ L2-only (2 L4 queries) |
| 6 | claude jobs (`claude_job`) | `~/.claude/jobs` | background job | ✓ `fact_task` |
| 7 | PR cache (`pr_cache`) | `~/.claude/gh-pr-status-cache.json` | PR | ✓ `fact_pr` |
| 8 | ADO PR (`ado_pr`) | `az repos pr list` (configured repo) | my ADO PR | ✓ `fact_ado_pr` |
| 9 | Hermes state.db (`state_db`) | `~/.hermes/state.db` `sessions` | session | ✗ L2-only (automation ratio) |
| 10 | Hermes tools (`hermes_tools`) | `~/.hermes/state.db` `messages` (tool_name only) | tool call | ✗ L2-only |
| 11 | memory claude (`memory_claude`) | `~/.claude/.../memory/*.md` | note | ✗ L2-only |
| 12 | memory hermes db (`memory_hermes_db`) | `~/.hermes/memory_store.db` | fact | ✗ L2-only |
| 13 | memory hermes md (`memory_hermes_md`) | `~/.hermes/memories/*.md` | entry | ✗ L2-only |
| 14 | github repo (`github_repo`) | `gh api repos/<owner>/<name>` (tool radar) | repo snapshot | ✓ `fact_repo_snapshot` |
| 15 | github PR (`github_pr`) | `gh pr list --author @me` | my GitHub PR | ✓ `fact_github_pr` |
| 16 | news (`news`) | HTTP RSS/JSON (Google News / HN / arXiv), key-free | headline | ✗ L2-only |
| 17 | aidash events (`aidash_events`) | `aidash events pull --json` (XPC) | star/todo event | ✗ L2-only — 采集能力已建，尚无事件落地 |
| 18 | local git (`local_git`) | `git log --numstat` across local repos | my commit | ✗ L2-only |
| 19 | browser history (`browser_history`) | Chrome `History` sqlite `urls` (read-only) | visited domain | ✗ L2-only |
| 20 | gecko (`gecko`) | `ai.hexly.gecko` sqlite `focus_sessions` (read-only) | app-focus session | ✗ L2-only |

## Key design notes (verified against real data)

- **raven session_id is heterogeneous** — a JSON blob with a real UUID only for
  claude-cli; codex/multica carry no conversation id (`session_uuid` NULL).
- **claude joins on camelCase `sessionId`** (= filename), not snake_case
  `session_id` (the resume/fork parent pointer).
- **No cost field anywhere** — derived from tokens × `schema/dim_model.csv`.
- **Multica per-issue tokens** come from `multica issue usage`; request-level
  attribution bridges via `run.session_id → fact_request.session_uuid`
  (works only where the runtime routed as claude-cli).
- **PR joins are URL-string joins** — fragile (comment-runs have empty pr_url).
- **Hermes counters are dead** — retrieval_count/helpful_count are all-zero in
  this runtime; dead-asset detection falls back to created/updated age.
- **Secrets red line**: every record is redacted before hitting raw. Memory
  sources embed live tokens — `redaction.py` strips them; verified no plaintext
  secret lands in raw.
- **Timestamps are UTC**: `fact_request.ts` (epoch ms) and raw shards store UTC.
  Any time-of-day / day-of-week / day-bucket query MUST convert to CST with an
  **explicit `+8 hours`** (ADR-22), never `localtime` — `localtime` depends on
  the host timezone and breaks reproducibility / cron correctness:
  `date(ts/1000,'unixepoch','+8 hours')`. Do not draw "morning vs night"
  conclusions from raw UTC values.

## Requirements

Runs on **Python 3.13** (`python3.13`; the tests and cron runner pin it). The
system `sqlite3` CLI (**3.51+**) is preferred for reads via `sqlite_ro.py`, which
falls back to the stdlib driver — the CLI historically mattered because an older
default `python3` bundled sqlite 3.19 (2017) that couldn't parse raven's schema;
`sqlite_ro.py` keeps that fallback so the platform survives interpreter/sqlite
version skew regardless of the box.

## Not in v1 (YAGNI)

Real-time push hooks and a web dashboard are still not built — the live surface
is the native AIDash daily push, which is a scheduled 04:00 digest, not a
real-time hook or a browser dashboard. Embedding / semantic analysis is also out.

Note on `aidash_events`: the AIDash app can pull user star/todo reactions back
into aidata (**已采集反馈事件**), but this is only a *collected feedback signal*
— it has no L4/L5 consumer yet, so it is deliberately NOT described as a closed
"feedback loop".
