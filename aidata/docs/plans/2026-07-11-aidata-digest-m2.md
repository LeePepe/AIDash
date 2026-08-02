# aidata-digest M2 Implementation Plan — multica EXT-1/2/3 + 今日完成 trend

> **For agentic workers:** TDD task-by-task. Failing test → implement → pass → commit. Run the full suite after each task.

**Goal:** Fix the "today's completed issues" gap (ADR-19 / EXT-3) and broaden multica coverage (EXT-1/2). Change the `multica_issue` adapter from a monotonic `number > watermark` read to an **`updated_since` window read** (per-workspace watermarks), collect BOTH workspace-a + my workspaces, and capture `project_id` + `updated_at`. Add a `trend/daily-completed` L4 query and wire "完成 issue" into the digest's Trending + 昨日汇总 sections — deterministic, template-only, degrade-not-crash.

**Architecture:** L1 adapters (`multica_issue`, `multica_run`) change collection strategy. Schema `fact_issue` gains two columns. `merge.py` carries them. A new L4 query buckets completed issues per CST day + workspace. L5 `sources.py` gains a multica fetcher (health-wrapped), `render.py` gains two lines. No LLM (that's M4).

## Global Constraints (inherited from M1 + spec Global Constraints)

- **Immutable original data (spec):** never overwrite existing columns; only ADD `updated_at`, `project_id`. Raw is append-only; normalize is last-write-wins.
- **CST +8h (ADR-2/22):** `fact_issue.updated_at` is ISO text → bucket with `date(updated_at,'+8 hours')` (NOT the epoch-ms `CST_DAY_EXPR`). Verified: updated_at is `2026-07-10T20:01:53Z` form.
- **完成数为近似 (ADR-19):** updated_at moves on any edit; the digest labels the completed count 近似.
- **Per-workspace watermarks (ADR-19/EXT-2):** state keys `multica_issue:<ws>` / `multica_run:<ws>`; NEVER a shared global watermark. Adding workspace-a full-backfills that workspace independently.
- **Workspaces (ADR-5):** workspace-a `<WS_A_UUID>` + my `<WS_MY_UUID>`. NOT epichain, NOT work.
- **Degrade-not-crash (ADR-23):** multica CLI failure (auth/missing) → that source's series empty + `SourceHealth`, never a crash. Recorded in `source_health`, rendered by template.
- **Read-only external, stdlib only.** PEP 8, type annotations, functions < 50 lines, immutable dataclasses.
- **TDD hermetic units:** unit tests pass without live warehouse/CLI (monkeypatch data access); warehouse-touching tests are `@pytest.mark.integration`.

## CLI reality (verified against multica 0.3.42)

- `multica issue list --workspace-id <uuid> --limit 100 --offset N --output json` → `{issues:[...], total, has_more}`. limit hard-capped at 100 → paginate.
- No `updated_since` param, no sort-by-updated_at → fetch pages, client-filter `updated_at >= cutoff`.
- `multica issue runs <ident> --workspace-id <uuid> --output json`, `multica issue usage <ident> --workspace-id <uuid> --output json`.
- Issue fields used: `id, number, identifier, title, status, priority, created_at, updated_at, project_id, workspace_id`.

---

## File Structure

**New files:**
- `L4_serve/queries/trend/daily-completed.sql` — per-CST-day completed-issue count, grouped by (day, workspace_id).
- `tests/test_multica_issue_collect.py` — window-read + per-workspace watermark unit tests (CLI monkeypatched).
- `tests/test_multica_completed.py` — multica fetcher + render integration/unit tests.

**Modified files:**
- `config.py` — add `MULTICA_WORKSPACES` (uuid→name) + `MULTICA_UPDATED_WINDOW_DAYS`.
- `adapters/multica_issue.py` — window read, multi-workspace, per-ws watermark, +project_id +updated_at.
- `adapters/multica_run.py` — multi-workspace (per-ws watermark, `--workspace-id`), covers workspace-a.
- `schema/warehouse.sql` — `fact_issue` + `updated_at`, `project_id`.
- `merge.py` — carry the two new columns.
- `L5_apps/digest/sources.py` — `MulticaTrends` + `fetch_multica_completed(report_date)`.
- `L5_apps/digest/render.py` — Trending "完成 issue (近似)" + 昨日汇总 "昨日完成: N (分 workspace)" + health line.
- `L5_apps/digest/app.py` — build_digest fetches multica, passes to render.
- `tests/fixtures/digest-2026-07-09.golden.md` — regenerate after render change.

---

## Task 1: Schema + config — new columns & workspace constants

- Add `updated_at TEXT`, `project_id TEXT` to `fact_issue` (after `workspace_id`), plus `idx_issue_updated`.
- config: `MULTICA_WORKSPACES = (("<WS_A_UUID>-...","WorkspaceA"),("<WS_MY_UUID>-...","my"))`, `MULTICA_UPDATED_WINDOW_DAYS = 14`.
- Test: `tests/test_config_multica.py` asserts the two workspaces + window constant.
- Commit: `feat(schema): fact_issue +updated_at +project_id; config multica workspaces`.

## Task 2: multica_issue window read + multi-workspace (EXT-1/2/3, ADR-19)

- `collect()`: for each `(ws_id, _)` in `MULTICA_WORKSPACES`:
  - per-ws watermark key `f"{SOURCE}:{ws_id}"` (ISO `updated_at`).
  - first run (wm None) → full backfill (all pages); else window read: cutoff = now − WINDOW_DAYS, keep `updated_at >= cutoff`.
  - append only issues with `updated_at > wm` (append-only raw, lean); advance wm = max(updated_at).
  - paginate `--limit 100 --offset` until `has_more` false.
- `normalize()`: last-write-wins by `id`; carry `updated_at`, `project_id`. Clean DDL/COLS gain the two columns.
- Unit tests (CLI monkeypatched): window filter drops old-untouched issues but keeps old-recently-completed; per-ws watermark isolation; normalize carries new cols.
- Commit: `feat(multica): updated_since window read, multi-workspace, +project_id +updated_at`.

## Task 3: multica_run multi-workspace (EXT-2)

- Build known issues as `(identifier, number, workspace_id)` from multica_issue raw.
- Per-ws watermark `f"{SOURCE}:{ws_id}"`; fetch runs/usage with `--workspace-id ws`.
- Unit test: workspace-a idents collected with correct workspace flag (monkeypatched runner records calls).
- Commit: `feat(multica): multica_run covers workspace-a via per-workspace watermark`.

## Task 4: merge carries new columns

- Extend fact_issue INSERT/SELECT with `updated_at, project_id`.
- Integration test (skip if no clean db): merged fact_issue has non-null updated_at for some rows.
- Commit: `feat(merge): carry fact_issue.updated_at + project_id`.

## Task 5: L4 trend/daily-completed query

- `SELECT date(updated_at,'+8 hours') AS day, workspace_id, count(*) AS completed FROM fact_issue WHERE status='done' AND updated_at IS NOT NULL GROUP BY day, workspace_id ORDER BY day DESC`.
- Integration test: runs, columns `day, workspace_id, completed`.
- Commit: `feat(digest): trend/daily-completed query (completed issues per CST day + workspace)`.

## Task 6: sources — MulticaTrends fetcher

- `MulticaTrends(completed: list[(day,float)], completed_by_ws: dict[ws_name, list[(day,float)]], health)`.
- `fetch_multica_completed()` runs the query, maps `workspace_id`→friendly name via `MULTICA_WORKSPACES`, builds a total-per-day series + per-ws series; health-wrapped (error → empty).
- Unit test: degrade path (monkeypatch run_query → boom) → empty + error health. Hermetic reshape test with a fake run_query.
- Commit: `feat(digest): multica completed-issue fetcher with health tracking`.

## Task 7: render — Trending 完成 issue + 昨日完成 + health line

- `render_digest(raven, report_date, multica=None)` — optional param keeps M1 unit tests green.
- Trending: `完成 issue(近似): N ↑ vs 昨 M · 7日均 K` via `compute_trend(multica.completed)`; degraded → `数据缺失`.
- 昨日汇总: `昨日完成: N 个 issue (WorkspaceA: a, my: b)`.
- Health line includes multica state.
- Unit tests (hermetic MulticaTrends): lines present; degraded shows 数据缺失; determinism.
- Commit: `feat(digest): render 完成 issue trend + 昨日完成 per-workspace + multica health`.

## Task 8: app wiring + golden regen + full regression + docs

- `build_digest` fetches multica, passes to `render_digest`.
- Regenerate `tests/fixtures/digest-2026-07-09.golden.md`; eyeball.
- README note for M2.
- Full suite green. Ledger updated.
- Commit: `feat(digest): wire multica into build_digest; regen golden; docs`.

---

## Self-Review / EXT coverage

- EXT-1 project_id → Tasks 1,2,4 ✓  EXT-2 workspace-a+my → Tasks 1,2,3 ✓  EXT-3 updated_at + 今日完成 → Tasks 1,2,4,5,6,7 ✓
- ADR-19 window read + per-ws watermark → Task 2 ✓  ADR-23 degrade → Tasks 6,7 ✓  ADR-3 近似 label → Task 7 ✓
- Deferred to M3+: ADO PR, state.db, LLM slot-fill, AIDash. Out of M2 scope.
