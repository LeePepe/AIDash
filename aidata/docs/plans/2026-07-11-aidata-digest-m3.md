# aidata-digest M3 Implementation Plan — ADO PR source + Hermes state.db source

> **For agentic workers:** TDD, task-by-task. Failing test → implement → pass → commit. Full suite green after each task. Mirror the M1 plan's style and the existing adapter pattern exactly.

**Goal:** Add two new aidata data sources and wire them into the digest:
- **A. ADO PR source** (EXT-4, ADR-6/13/22): `adapters/ado_pr.py` collects WorkspaceA PRs where creator = me, into a **separate** `fact_ado_pr` warehouse table.
- **B. Hermes state.db source** (EXT-5, ADR-7/13): `adapters/state_db.py` reads `~/.hermes/state.db` `sessions`, stops at **L2 clean** (not merged), exposing the `source` dimension → automation ratio.
- **C. Digest integration** (ADR-15/23): extend `L5_apps/digest/sources.py` + `render.py` to show ADO PR daily opened/merged and automation-ratio, template-only (no LLM), degrade-not-crash.

## Environment facts (VERIFIED live during planning)

- **az CLI is installed and authed** as `me@example.com` (this worktree). Both `az ad signed-in-user show` and `az repos pr list` work.
- **CRITICAL — identity id mismatch (deviates from ADR-22 literal text):** `az ad signed-in-user show` → AAD id `<AAD_OBJECT_ID>`. But ADO **Server** `createdBy.id` on my real PRs is a *different* descriptor `<ADO_CREATOR_ID>`. `az repos pr list --creator <AAD id>` returns `[]`; `--creator me@example.com` returns my PRs. **Resolution:** query with the email (`ADO_CREATOR_EMAIL`), then double-filter rows on the immutable ADO-native `createdBy.id` (`ADO_CREATOR_ID`). This honors ADR-22's *intent* (filter on an immutable id, not display name) while working against ADO Server. Both constants live in `config.py` with an explaining comment.
- **state.db `sessions.started_at` = epoch SECONDS (float)** → `date(started_at,'unixepoch','+8 hours')` (NOT `/1000`). Verified `1783774857.67556 → 2026-07-11`.
- **ADO `creationDate` / `closedDate` = ISO text with offset** (`2026-07-09T05:45:37.395565+00:00`) → sqlite parses directly: `date(created_date,'+8 hours')`. Verified boundary 15:30Z→07-09, 16:30Z→07-10.
- **state.db `source` values:** `cron, cli, acp, subagent, weixin, unknown`. **Automation definition (documented decision):** `AUTOMATED = {cron, subagent}` (scheduled / agent-spawned, no human in loop); everything else (`cli, acp, weixin, unknown`) = **manual** (human-initiated at a terminal/app/wechat; `unknown` treated as manual = conservative). Ratio = automated / total.
- state.db is 3.8 GB but the `sessions` scan is fast (~20 ms, 11.8k rows) via `query_ro` (system sqlite CLI).

## Global Constraints

- **CST `+8 hours` day bucketing** everywhere (ADR-2/22). Never `localtime`. Two source-specific expressions: epoch-seconds (state.db) vs ISO-text (ADO) — handled per-source, both `+8 hours`.
- **Secrets red line (ADR-23):** every raw write goes through `redaction.redact` (already enforced in `rawio.write_raw`). state.db: select ONLY the safe columns (never `system_prompt`, `model_config`, `origin_json`, `billing_*` auth). ADO: `remoteUrl` etc. pass through `redact_obj`.
- **Degrade-not-crash (ADR-23):** missing/unauthed az, missing state.db → adapter `collect()` returns 0 (matches memory/pr_cache pattern); digest fetchers return empty series + `SourceHealth(state="skipped:*"/"error")`, never raise. Solid + TESTED even though az/state.db happen to be live here.
- **Immutable original data (ADR-21):** additive only — new `fact_ado_pr` table, new clean DBs, new columns. Nothing existing is mutated. raw append-only.
- **ADR-13:** ADO PR → separate `fact_ado_pr` table (NOT merged into GitHub `fact_pr`). state.db → **L2 only**, queried directly (like memory sources), NOT in `MERGE_SOURCES`.
- **Stdlib only.** Read-only external. `subprocess` for `az`; `query_ro`/CLI sqlite for state.db reads.
- **Python style:** PEP 8, type annotations, functions < 50 lines, frozen dataclasses, files < 400 lines.
- **Tests:** pytest. Unit tests **HERMETIC** — monkeypatch `subprocess.run`/`az` and `query_ro` / `serve.run_query`; never depend on live az auth or a real state.db. Integration tests marked `@pytest.mark.integration`.

---

## File Structure

**New files:**
- `adapters/ado_pr.py` — ADO PR adapter (`collect()` + `normalize()`).
- `adapters/state_db.py` — Hermes state.db adapter (`collect()` + `normalize()`).
- `L4_serve/queries/trend/daily-ado-pr.sql` — per-CST-day PRs opened (by created_date) + merged (by closed_date, status=completed).
- `L4_serve/queries/trend/daily-automation.sql` — per-CST-day automated/manual/total/ratio from `state_db.session`.
- `tests/test_ado_pr_adapter.py`, `tests/test_state_db_adapter.py` — hermetic adapter unit tests.
- `tests/test_sources_m3.py` — hermetic fetcher tests (ADO + automation, incl. degrade).
- `tests/test_render_m3.py` — render integration tests for ADO + automation lines.

**Modified files:**
- `config.py` — ADO constants, `HERMES_STATE_DB`, register `ado_pr` (SOURCES + MERGE_SOURCES) and `state_db` (SOURCES only).
- `schema/warehouse.sql` — add `fact_ado_pr` table.
- `merge.py` — attach clean/ado_pr.db and populate `fact_ado_pr`.
- `L5_apps/digest/sources.py` — `AdoPrTrends`, `AutomationTrends`, `fetch_ado_pr_trends()`, `fetch_automation_trends()`.
- `L5_apps/digest/render.py` — Trending + 昨日汇总 additions, health line extension (backward-compatible defaults).
- `L5_apps/digest/app.py` — `build_digest` fetches all three, passes to render.
- `tests/test_digest_golden.py` + `tests/fixtures/digest-2026-07-09.golden.md` — extend frozen fixture with ADO+automation, regenerate golden (hermetic).
- `README.md` — document the two new sources.

---

## Task 1: config — constants + source registration

**Files:** Modify `config.py`.

Add after external-source block:
```python
# Hermes per-session store (EXT-5, ADR-7). L2-only source (not merged).
HERMES_STATE_DB = HOME / ".hermes" / "state.db"

# Azure DevOps (EXT-4, ADR-6/22). WorkspaceA lives on ADO *Server* (<ado-server>),
# whose createdBy.id is a DIFFERENT namespace from the AAD object id returned
# by `az ad signed-in-user show`. We therefore query by email and double-filter
# on the immutable ADO-native creator id below (verified 2026-07-11).
ADO_ORG = "https://<ado-server>/DefaultCollection"
ADO_PROJECT = "<ADO_PROJECT>"
ADO_REPO = "WorkspaceA"
ADO_CREATOR_EMAIL = "me@example.com"
ADO_CREATOR_ID = "<ADO_CREATOR_ID>"  # immutable ADO Server descriptor
```

> **后来的变化**：这些 `ADO_*` 常量已从 `config.py` 外置到 git-ignored 的
> `config_local.py`（`config.py` 里默认空字符串，未配置时 ado_pr 降级为
> no-op）。本节保留 M3 当时的形态作为历史记录，其中的标识符均已替换为占位符。
Add `"ado_pr"` and `"state_db"` to `SOURCES`; add `"ado_pr"` to `MERGE_SOURCES` (NOT `state_db` — ADR-13, stops at L2).

**Test:** extend nothing new required, but add a quick unit test `tests/test_config_m3.py` asserting `ado_pr` in SOURCES & MERGE_SOURCES, `state_db` in SOURCES but NOT MERGE_SOURCES.

**Commit:** `feat(config): register ado_pr + state_db sources, ADO/state.db constants`

---

## Task 2: schema + merge wiring for fact_ado_pr

**Files:** Modify `schema/warehouse.sql`, `merge.py`.

Add table (ADR-13 field list + `closed_date` for merged-per-day counting — additive):
```sql
CREATE TABLE IF NOT EXISTS fact_ado_pr (
    pr_id         INTEGER PRIMARY KEY,
    title         TEXT,
    status        TEXT,               -- active | completed | abandoned
    created_date  TEXT,               -- ISO text (bucket via +8h)
    closed_date   TEXT,               -- ISO text; set when completed/abandoned
    creator_id    TEXT,               -- immutable ADO Server descriptor
    source_branch TEXT,
    target_branch TEXT,
    is_draft      INTEGER,            -- 0/1
    reviewers     TEXT,               -- JSON array
    age_hours     REAL,               -- age at normalize time
    repo          TEXT
);
CREATE INDEX IF NOT EXISTS idx_ado_pr_created ON fact_ado_pr(created_date);
```
In `merge.py`, after `fact_pr` block, add an attach+insert for `ado_pr` (alias `ap`), pulling clean `ado_pr.pr` → `fact_ado_pr`. `counts["fact_ado_pr"]`.

**Test:** covered by integration (Task 8) + a small `@pytest.mark.integration` in test_warehouse or a merge smoke. Since merge needs clean DBs, keep this as an integration check run at the end. For unit safety, no hermetic test here (pure SQL).

**Commit:** `feat(schema): fact_ado_pr table + merge wiring (ADR-13)`

---

## Task 3: adapters/ado_pr.py (TDD, hermetic)

**Interfaces:** `SOURCE = "ado_pr"`, `collect() -> int`, `normalize() -> int`.

**collect():**
- If `az` not on PATH (`shutil.which("az")` is None) → return 0 (degrade).
- Run `az repos pr list --repository <ADO_REPO> --project <ADO_PROJECT> --org <ADO_ORG> --creator <ADO_CREATOR_EMAIL> --status all --top 500 --output json` via `subprocess.run` (timeout ~60). On non-zero rc or JSON error → return 0 (degrade, per ADR-23; per-source isolation in cli.py also guards).
- Filter list to `pr["createdBy"]["id"] == ADO_CREATOR_ID` (immutable double-gate, ADR-22).
- `write_raw_snapshot(SOURCE, prs)` (hash-based dedup like pr_cache; volatile `age_hours` is NOT stored in raw, so snapshots change only on real field changes). Return count.

**normalize():** read raw, last-write-wins by `pullRequestId`, build clean table `pr`:
- pr_id, title, status, created_date(=creationDate), closed_date(=closedDate), creator_id(=createdBy.id), source_branch(sourceRefName minus `refs/heads/`), target_branch, is_draft(0/1), reviewers(JSON of [{name,vote}]), age_hours (computed from created_date vs `datetime.now(timezone.utc)`), repo(=repository.name).

**Hermetic tests (`tests/test_ado_pr_adapter.py`):**
- `test_collect_filters_to_my_creator_id`: monkeypatch `shutil.which`→"az" and `subprocess.run` to return a canned JSON with 2 PRs (mine + someone else's); monkeypatch `rawio.write_raw_snapshot` to capture; assert only my PR (matching ADO_CREATOR_ID) is written.
- `test_collect_degrades_when_az_missing`: monkeypatch `shutil.which`→None; assert `collect()==0`, no write.
- `test_collect_degrades_on_az_error`: subprocess returns rc=1; assert 0, no crash.
- `test_normalize_last_write_wins_and_fields`: monkeypatch `read_raw` to yield two snapshots of the same pr_id (status active→completed) + capture `write_clean`; assert final row status=completed, source_branch stripped of refs/heads/, is_draft int, reviewers is JSON string.
- `test_normalize_cst_created_date_preserved`: assert created_date passed through as ISO text (bucketing happens in SQL).

**Commit:** `feat(adapters): ado_pr — my WorkspaceA PRs into fact_ado_pr (ADR-6/22)`

---

## Task 4: adapters/state_db.py (TDD, hermetic)

**Interfaces:** `SOURCE = "state_db"`, `AUTOMATED_SOURCES = frozenset({"cron", "subagent"})`, `collect() -> int`, `normalize() -> int`.

**collect():**
- If `HERMES_STATE_DB` absent → return 0.
- `query_ro(HERMES_STATE_DB, "SELECT id, started_at, ended_at, message_count, tool_call_count, input_tokens, output_tokens, source, model FROM sessions WHERE started_at > ? ORDER BY started_at ASC", (watermark,))`. Watermark = float, default 0. (ONLY safe columns — never system_prompt/model_config/origin_json/billing_*.)
- If empty → 0. Else `write_raw(SOURCE, records)`; `set_watermark(SOURCE, max(started_at))`. Return count.

**normalize():** read raw, last-write-wins by `id`, clean table `session`:
- session_id(=id), started_at(REAL), ended_at, message_count, tool_call_count, input_tokens, output_tokens, source, model, is_automated (1 if source in AUTOMATED_SOURCES else 0).

**Hermetic tests (`tests/test_state_db_adapter.py`):**
- `test_collect_degrades_when_db_missing`: monkeypatch `config.HERMES_STATE_DB`/adapter's path to a nonexistent path; assert 0.
- `test_collect_reads_and_sets_watermark`: monkeypatch `query_ro`→canned rows, capture `write_raw` + `set_watermark`; assert count + watermark = max started_at.
- `test_normalize_is_automated_mapping`: canned raw with sources cron/cli/subagent/weixin/unknown; assert is_automated = 1 for cron+subagent, 0 for others.
- `test_normalize_started_at_is_epoch_seconds_float`: assert started_at stored unchanged (float), so SQL `unixepoch` bucketing is correct.

**Commit:** `feat(adapters): state_db — Hermes sessions at L2, automation dimension (ADR-7/13)`

---

## Task 5: L4 trend queries

**Files:** `L4_serve/queries/trend/daily-ado-pr.sql`, `L4_serve/queries/trend/daily-automation.sql`.

`daily-ado-pr.sql` (opened by created day + merged by closed day; single query, columns `day, opened, merged`):
```sql
-- trend/daily-ado-pr — per-CST-day PRs opened (created_date) + merged
-- (closed_date, status=completed). created_date/closed_date are ISO text →
-- date(col,'+8 hours') (ADR-2). Separate table from fact_pr (ADR-13).
WITH days(day) AS (
    SELECT DISTINCT date(created_date,'+8 hours') FROM fact_ado_pr WHERE created_date IS NOT NULL
    UNION
    SELECT DISTINCT date(closed_date,'+8 hours') FROM fact_ado_pr WHERE closed_date IS NOT NULL AND status='completed'
)
SELECT d.day AS day,
       (SELECT count(*) FROM fact_ado_pr WHERE date(created_date,'+8 hours')=d.day) AS opened,
       (SELECT count(*) FROM fact_ado_pr WHERE date(closed_date,'+8 hours')=d.day AND status='completed') AS merged
FROM days d
WHERE d.day IS NOT NULL
ORDER BY day DESC;
```

`daily-automation.sql` (reads the un-merged clean source directly, attached AS `state_db`):
```sql
-- trend/daily-automation — per-CST-day automation ratio from Hermes state.db
-- sessions (L2-only, ADR-13). started_at is epoch SECONDS → unixepoch +8h.
-- automated = cron/subagent (is_automated=1); manual = everything else.
SELECT date(started_at,'unixepoch','+8 hours')          AS day,
       sum(is_automated)                                AS automated,
       sum(CASE WHEN is_automated=0 THEN 1 ELSE 0 END)  AS manual,
       count(*)                                         AS total,
       round(sum(is_automated)*1.0/count(*), 3)         AS automation_ratio
FROM state_db.session
GROUP BY day
ORDER BY day DESC;
```

**Verify:** after collect→normalize→merge for these sources, `python3 cli.py query trend/daily-ado-pr` and `trend/daily-automation` return rows (integration; may be run at Task 8).

**Commit:** `feat(digest): L4 trend queries — daily-ado-pr + daily-automation`

---

## Task 6: sources.py fetchers (TDD, hermetic)

Add to `L5_apps/digest/sources.py`:
```python
@dataclass(frozen=True)
class AdoPrTrends:
    opened: list[tuple[str, float]]
    merged: list[tuple[str, float]]
    health: SourceHealth

@dataclass(frozen=True)
class AutomationTrends:
    ratio: list[tuple[str, float]]
    automated: list[tuple[str, float]]
    manual: list[tuple[str, float]]
    health: SourceHealth
```
- `fetch_ado_pr_trends()`: if `clean_path("ado_pr")` missing → `SourceHealth("ado_pr","skipped:未采集")` + empty. Else run `trend/daily-ado-pr`; on exception → `state="error"`. Reshape opened/merged series.
- `fetch_automation_trends()`: if `clean_path("state_db")` missing → skipped. Else run `trend/daily-automation`; reshape ratio/automated/manual; error→degrade.

**Hermetic tests (`tests/test_sources_m3.py`):**
- `test_fetch_ado_pr_degrades_when_clean_missing` (monkeypatch `config.clean_path` / `sources.clean_path`).
- `test_fetch_ado_pr_degrades_on_query_error` (monkeypatch clean_path→exists via a tmp, `serve.run_query`→boom; state error, empty).
- `test_fetch_ado_pr_reshapes_series` (monkeypatch run_query→canned rows; opened/merged tuples correct, health ok).
- Same three for automation (ratio series + degrade paths).

**Commit:** `feat(digest): ADO PR + automation trend fetchers with health (ADR-23)`

---

## Task 7: render.py integration (TDD)

Extend `render_digest` signature (backward-compatible so M1 `test_render.py` 2-arg calls still pass):
```python
def render_digest(t: RavenTrends, report_date: str,
                  ado: "AdoPrTrends | None" = None,
                  automation: "AutomationTrends | None" = None) -> str:
```
- **Health line:** append ` ado_pr<state>` / ` state.db<state>` markers when `ado`/`automation` provided (ADR-23 explicit health).
- **Trending:** when `ado` present & health ok → add `_fmt_trend("开PR", ado.opened, ...)` (and merged if useful). When `automation` present & ok → add automation-ratio arrow (format as percentage).
- **昨日汇总 (ADR-15):** add `- 开了 N 个 PR（合并 M 个）` from yesterday's opened/merged; add `- 自动化占比 X%（自动 A / 手动 B）` from yesterday's automation row.
- Degraded ADO/automation → print the health note, do NOT fabricate arrows (ADR-23: "数据缺失/未采集", never →/0).

**Tests (`tests/test_render_m3.py`, `@pytest.mark.unit`):**
- ADO opened line appears with arrow when 2+ days present.
- 昨日汇总 shows "开了 N 个 PR" for the yesterday value.
- automation-ratio percentage appears in 昨日汇总.
- degraded ADO → shows 未采集/skipped, no fake arrow.
- `render_digest(_rt(), date)` (no ado/automation) still returns the 4 M1 sections unchanged (regression guard).

**Commit:** `feat(digest): render ADO PR + automation in Trending/昨日汇总 (ADR-15/23)`

---

## Task 8: build_digest wiring + golden regen + integration verify + docs

- `app.py`: `build_digest` fetches raven + ADO + automation, passes all to `render_digest`.
- `tests/test_digest_golden.py`: add frozen `_FROZEN_ADO` (`AdoPrTrends`) and `_FROZEN_AUTOMATION` (`AutomationTrends`) with representative values; monkeypatch `app.fetch_ado_pr_trends` + `app.fetch_automation_trends` in the `frozen_trends` fixture. Regenerate `tests/fixtures/digest-2026-07-09.golden.md` from the frozen values; human-review (4 sections + new PR/automation lines, arrows correct).
- **Integration verify (live env):** run `python3 cli.py collect --source ado_pr` and `--source state_db`, then `normalize`, `merge`, and `query trend/daily-ado-pr` / `trend/daily-automation`. Confirm real rows OR (if a source degrades) confirm graceful 0 + health. Do NOT commit any raw/clean/warehouse artifacts (all gitignored).
- `README.md`: document `ado_pr` + `state_db` sources and the automation definition.
- Full suite: `python3 -m pytest -q` — all unit green; integration green when warehouse built.

**Commit:** `feat(digest): wire ADO+automation into build_digest; regen golden; docs`

---

## Self-Review — spec coverage

- EXT-4 / ADR-6 ADO PR, creator=me → Task 3 (email query + immutable-id double-filter, ADR-22 intent honored; AAD≠ADO-Server mismatch documented). ✓
- ADR-13 separate `fact_ado_pr` table → Task 2; state.db L2-only, not merged → Task 1/4. ✓
- EXT-5 / ADR-7 state.db `source` → automation ratio, defined & documented (cron+subagent vs rest) → Task 4/5. ✓
- CST `+8h`, epoch-seconds vs ISO-text divergence handled + boundary-verified → Tasks 4/5. ✓
- Secrets red line: state.db safe-columns-only + redact; ADO redact_obj → Tasks 3/4. ✓
- Degrade-not-crash: adapter returns 0 on missing az/db; fetchers empty+health; TESTED hermetically → Tasks 3/4/6. ✓
- ADR-15 昨日汇总 (开 N PR + automation ratio) + Trending arrows, template-only → Task 7. ✓
- ADR-23 explicit source_health in health line, no fake arrows when skipped → Tasks 6/7. ✓
- Immutable/additive, stdlib, read-only → throughout. ✓
- Golden hermetic + deterministic → Task 8. ✓

**Deferred to M4/M5:** LLM slot-filling + codex:review, must-see-layer char budget, AIDash push, cron rewire. Multica render integration (M2) is out of scope here.
