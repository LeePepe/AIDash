# aidata-digest M5 Implementation Plan — AIDash push + 必看层 + cron wiring

> **For agentic workers:** TDD task-by-task. Each task = failing test → implement → pass → commit. Full unit suite green after each (`python3 -m pytest tests/ -q -m unit`). The template golden test (`test_digest_golden.py`) and all M1–M4 tests MUST stay green.

**Goal (ADR-12/14/16/17/23):** Add the final delivery layer on top of the deterministic digest — a compact ≤1500-char **必看层** (must-see) view, an **AIDash push** that transforms the digest into Briefing→Container→Card payloads and publishes them via the `aidash` CLI over XPC, and the **Hermes cron wiring** to run the whole chain at 04:00 CST. The AIDash push is **best-effort and non-fatal** (ADR-16/23): the local md archive is the 必成 sink and is written BEFORE any push; every push failure mode (no app, no CLI, launch fails, XPC error) degrades to a logged warning and the digest command still exits 0. Cron wiring is **prepared, not executed** — a ready-to-run installer with a dry-run that PRINTS what it would change; the human applies it manually.

**Architecture:** New pure module `L5_apps/digest/must_see.py` folds the full digest md into the compact must-see layer. New module `L5_apps/digest/aidash.py` has TWO halves: (1) a **pure** payload transform (`build_briefing`) that maps the 4 sections + source-health to typed cards, and (2) a **best-effort** push path (resolve CLI bin → ensure app running → run `briefing/container/card put` + `publish`), with all subprocess/`open`/`pgrep` interaction injected for hermetic testing. `app.write_digest` gains `push_aidash=False`; the push is wrapped so it can NEVER fail the digest. CLI gains `--aidash`. Cron: `scripts/aidata_digest_run.sh` (the collect→normalize→merge→digest chain) + `scripts/aidata_digest_cron.py` (dry-run installer/uninstaller). L1–L4 untouched; everything new is L5 or scripts/.

**Tech Stack:** Python 3.11 stdlib (`subprocess`, `json`, `re`, `tempfile`, `dataclasses`, `logging`), pytest. Tests are hermetic — subprocess/`open`/`pgrep`/bin-resolution are all injected or monkeypatched; the unit suite NEVER launches AIDash or shells out to a real `aidash`. Anything hitting the real app/CLI is `@pytest.mark.integration` and skippable.

## Global Constraints

- **Non-fatal AIDash (ADR-16/23).** Every push failure mode → logged warning; digest exits 0; archive already written. Tested for each mode.
- **Local archive first.** `write_digest` writes the md BEFORE attempting the push, so a push crash can't lose the digest.
- **Numbers stay template-owned (ADR-14/18).** The must-see layer is deterministic/template-based — it trims/folds existing template text; no LLM, no new numbers.
- **Layer purity (ADR-11).** AIDash push + cron live in L5 / scripts. L1–L4 untouched. The default (`--aidash` off) changes nothing.
- **Do NOT touch the live system.** No edits to `~/.hermes/cron/jobs.json`, no `open -a AIDash` in tests, no disabling the old cron. Installer is dry-run only.
- **Secrets.** No tokens logged or committed.
- **Style.** PEP 8, type annotations, functions < 50 lines, files < 400 lines, immutable frozen dataclasses, immutable/no-mutation patterns.

---

## File Structure

**New files:**
- `L5_apps/digest/must_see.py` — `must_see_layer(full_md, budget=1500) -> str`: parse sections, build TL;DR → trending(with arrows) → alerts(folded) → tomorrow's TODO → deep analysis, fold "连续 3+ 天不变" into "🔇 背景噪音: N 项无变化", enforce ≤1500 chars. Pure.
- `L5_apps/digest/aidash.py` — payload dataclasses (`Card`/`Container`/`Briefing`/`PushResult`), `parse_sections(md)`, `build_briefing(report_date, full_md, must_see)`, bin resolution, app-readiness, and `push_briefing(...)` with injected runner. The single AIDash boundary.
- `scripts/aidata_digest_run.sh` — the cron runner: `collect → normalize → merge → digest --date <today> --llm --aidash`. Committed to the repo (not the live system).
- `scripts/aidata_digest_cron.py` — dry-run installer: prints the NEW job JSON entry + the runner-script install + the disable of old `78d2b35a5693`. `--dry-run` default; `--apply` gated (not run here).
- `tests/test_must_see.py`, `tests/test_aidash_payload.py`, `tests/test_aidash_push.py`, `tests/test_digest_aidash.py`, `tests/test_cron_installer.py`.

**Modified files:**
- `L5_apps/digest/app.py` — `write_digest(report_date, use_llm=False, push_aidash=False) -> Path`; archive-first, then best-effort push (never raises).
- `cli.py` — `digest --aidash` flag.
- `README.md` — document the must-see layer, `--aidash`, the non-fatal contract, and the cron installer.

---

## Task 1: 必看层 must-see layer (`must_see.py`) — ADR-14

**Produces:** `must_see_layer(full_md: str, budget: int = 1500) -> str`. Deterministic fold of the full md:
1. TL;DR (1–3 lines): reuse the `> 💡 点评:` line if the LLM polish added one, else the 昨日汇总 headline fact.
2. Trending lines (arrows kept).
3. Trend alerts: lines with 🚩; fold any "连续 N 天(N≥3)持平/不变" items into one `🔇 背景噪音: N 项无变化`.
4. Tomorrow's TODO (the 今日 TODO section).
5. Deep analysis (可改良), trimmed last when over budget.
Enforce `len(result) <= budget` by trimming deep-analysis then trending extras, truncating with "…".

**Tests:** produces ≤1500 chars on the golden md; keeps TL;DR + arrows; folds 3+ flat items into the background-noise line and drops the raw lines; over-budget input gets truncated to ≤budget; empty/degraded md doesn't crash. All `@pytest.mark.unit`.

**Commit:** `feat(digest): 必看层 compact must-see layer with folding (ADR-14)`

---

## Task 2: AIDash payload transform (`aidash.py`, pure half) — ADR-16/17/23

**Produces:** frozen dataclasses `Card(id,type,size,payload,style)`, `Container(id,title,order,cards,layout,style,subtitle)`, `Briefing(date,generated_by,containers)`, `PushResult(ok,reason,published)`. `parse_sections(md) -> dict[str,list[str]]`. `build_briefing(report_date, full_md, must_see) -> Briefing` mapping (stable MMDD UUIDs):
- 总览 (order 10, accent): `digest`(hero) body = must-see layer; `insight`(wide, warning) = source-health line (ADR-23) when present.
- Trending (order 20): `trending`(wide) — items from trending lines (title=line, url=`aidata://trending/i`).
- 昨日汇总 (order 30): `insight`(wide) — body = 昨日汇总 lines.
- 今日规划 (order 40, accent): `todoList`(hero) — items with priority from P0/P1/P2 → high/medium/low.
- 可改良 (order 50): `insight`(wide) — body = 可改良 lines.

**Tests:** 4 sections + health → the expected card types; todoList priorities map correctly; trending items non-empty with a url each; digest card body == must-see; stable UUIDs are deterministic; a degraded md (数据缺失) still yields a valid briefing. `@pytest.mark.unit`.

**Commit:** `feat(digest): AIDash Briefing→Container→Card payload transform (ADR-16)`

---

## Task 3: AIDash push path (`aidash.py`, effectful half) — ADR-17/23, non-fatal

**Produces:**
- `resolve_aidash_bin(globber=...) -> str | None` — stat the DerivedData glob, newest first; `None` if absent (recipe pattern, no `which`).
- `ensure_app_running(opener, pgrep, poll=..., attempts=...) -> bool` — `open -a AIDash`, bounded readiness poll on `pgrep -lf AIDash`.
- `push_briefing(briefing, *, bin_path, runner, opener, pgrep) -> PushResult` — resolve/ensure/`briefing put`/`container put`×/`card put`×(payload via temp file `@`)/`publish`. ANY failure (bin None, app not up, non-zero exit, raised exc) → `PushResult(ok=False, reason=...)`, never raises.

**Tests (hermetic — fake runner/opener/pgrep, never real app):** happy path issues put+publish in order and returns ok; bin missing → skipped, no runner calls; app never comes up → skipped; runner returns non-zero (XPC error) → ok=False; runner raises (`FileNotFoundError`/`OSError`) → ok=False; no test spawns a real process. A `@pytest.mark.integration` real-push test is provided and skippable.

**Commit:** `feat(digest): best-effort non-fatal AIDash push via aidash CLI (ADR-17/23)`

---

## Task 4: app + CLI wiring (`app.py`, `cli.py`) — archive-first, non-fatal

**Produces:** `write_digest(report_date, use_llm=False, push_aidash=False) -> Path` — build md, **write archive first**, then if `push_aidash` attempt the push inside a broad try/except that logs a warning and continues (returns the archive path regardless). CLI `digest --aidash` (default off) → `write_digest(..., push_aidash=args.aidash)`; prints a concise push-result note.

**Tests (`test_digest_aidash.py`, hermetic):** with push monkeypatched to FAIL every mode, `write_digest(..., push_aidash=True)` still returns the archive path AND the file exists on disk; with push raising, still exits cleanly; `push_aidash=False` never calls the push at all; archive is written before the push attempt (assert file exists even when push raises). `@pytest.mark.unit`.

**Commit:** `feat(digest): wire non-fatal --aidash into write_digest + CLI (ADR-16/23)`

---

## Task 5: cron installer (PREPARE ONLY) — ADR-12

**Produces:**
- `scripts/aidata_digest_run.sh` — `cd <aidata> && python3 cli.py collect && normalize && merge && digest --date $(today CST) --llm --aidash`. Committed.
- `scripts/aidata_digest_cron.py` — reads `~/.hermes/cron/jobs.json`, builds a NEW `aidata-digest` job entry (matching the old job's JSON shape: schedule `0 4 * * *`, `no_agent: true`, `script: aidata_digest_run.sh`), and computes the disable of old `78d2b35a5693` (`enabled: false`, `state: paused`). `--dry-run` (default) PRINTS the new entry JSON + the runner-install + the disable, changing nothing. `--apply` is implemented but MUST NOT be run here.

**Tests (`test_cron_installer.py`, hermetic — a temp jobs.json fixture, never the real one):** the built new-job entry has the required keys + `0 4 * * *` + `no_agent` + the runner script; dry-run does not write the file; the disable targets exactly `78d2b35a5693` and flips `enabled`→false without touching other jobs. `@pytest.mark.unit`.

**Commit:** `feat(cron): prepared (not executed) aidata-digest installer + runner (ADR-12)`

---

## Task 6: docs + full regression + verification

- README M5 section (must-see, `--aidash` non-fatal contract, cron installer + manual go-live steps).
- Full unit suite green; golden + all M1–M4 tests unchanged.
- Verify: `python3 cli.py digest --date 2026-07-11 --aidash` (real push if AIDash reachable, else non-fatal degrade — either is acceptable); run `scripts/aidata_digest_cron.py --dry-run` and show the output. Do NOT apply.
- Ledger `.superpowers/sdd/m5-ledger.md` (one line per task, commit SHAs).

**Commit:** `docs(digest): document M5 must-see + AIDash push + cron installer`
</content>
