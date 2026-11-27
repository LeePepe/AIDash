# Goal-Aggregated & Session Work Summary Contracts (`aidash-work-status/v1`)

The `session_work` pipeline extends `aidata` across L1–L5 to model **Goal-Aggregated & Session-Level AI Work Status** (`aidash-work-status/v1`). It captures session duration, workflow role, invoked Skills (with reference/script usage vs. empty loads), a **4-Segment Action Split** (`search_read`, `code_edit`, `verify_script`, `spin_rework`), **Concrete Outputs** (`files_changed_count`, `commits_count`, `pr_number`), and **Plain-Language AI Optimization Signals**—stopping strictly at the Session Work Receipt grain without persisting raw prompts, transcripts, or local filesystem paths.

## Locked Contracts & Boundaries

- **Opt-In L1/L2 Projection (`adapters/session_work.py`)**:
  - Exposes `normalize_records(records, *, db_path=None)` and `collect(*, copilot_db=None, handoff_root=None, now=None)` to materialize `clean/session_work.db` (`session_work` table).
  - Excluded from `config.SOURCES`, `SCHEDULED_SOURCES`, and `MERGE_SOURCES`; invoked explicitly by Stage 3 of `scripts/aidata_digest_run.sh` before warehouse merge and snapshot emission.
  - Reads `~/.copilot/session-store.db` strictly read-only (`mode=ro&immutable=1`) across `sessions`, `turns`, `session_files`, `session_refs`, and `assistant_usage_events`, tolerating missing or legacy tables/columns without failing.
  - Links sessions to Goals via `cwd` matching `/worktrees/<goal>` or `/handoff/<goal>`, or `summary` matching `Goal <goal>`. Unlinked standalone sessions retain `goal_id = NULL` in L2/L3 and roll into the explicit `unassigned-daily` bucket in L4/L5 (`title = "日常独立会话（未绑定独立 Goal）"`, `is_unassigned_bucket = true`).
  - Optional clean/warehouse enrichment joins observed `script_call` (`verify_script_calls`, non-zero exit codes -> `spin_rework_calls` + `slow_or_failed_scripts_json`) and `reference_hits` (`search_read_calls` + `skills_json`). When `search_read_calls == 0` and `turn_count > code_edit_calls`, read/search turns are conservatively estimated as `max(0, turn_count - code_edit_calls - verify_script_calls - spin_rework_calls)` with explicit provenance so the 4-segment action bar reflects observed turn distribution.
- **Privacy & Grain Redline**:
  - Persists only metadata, 8-character short session IDs (`session_id_short`), sanitized repository/goal/branch slugs, sanitized 1-line summary labels (`<=80` chars with absolute home paths, credentials, tokens, and emails scrubbed), closed role/status enums, counts, and durations.
  - Raw prompt text, assistant transcripts, and local absolute paths never enter `raw/` or `clean/session_work.db`.
- **L3 Warehouse Fact (`schema/warehouse.sql` + `merge.py`)**:
  - `fact_session_work_summary`: `(session_uid PRIMARY KEY, source, session_id_short, goal_id, repo_name, branch_name, role_key, model_id, summary_label, started_at, ended_at, duration_sec, turn_count, total_tokens, skills_json, search_read_calls, code_edit_calls, verify_script_calls, spin_rework_calls, files_changed_count, commits_count, pr_number, slow_or_failed_scripts_json, cst_day)` where `cst_day` is a `STORED` generated column `date(COALESCE(ended_at, started_at), '+8 hours')` (never `localtime`).
  - `merge.py` commits open SQLite transactions before `DETACH DATABASE`.
- **L4 Exploratory Query (`L4_serve/queries/retro/goal_session_work_stream.sql`)**:
  - Marked `-- aidata-tier: explore` (and invoked directly by `work_status_snapshot.py` via split query constant so `test_query_tiers.py` digest production contracts stay intact).
  - Joins `fact_session_work_summary` with `dim_goal`, `fact_gtt_task_run`, `reference_hits`, and `script_call` over a rolling 14-day CST window to compute per-session and per-goal durations, 4-segment action counts, skills with script/reference touch counts vs. empty loads, review round badges (`R1` / `R2` / `R3+`), outputs (`files_changed_count`, `commits_count`, `pr_number`), and search-to-edit ratio.
- **L5 Plain-Language Snapshot (`L5_apps/digest/work_status_snapshot.py`)**:
  - Atomically writes `~/Library/Application Support/AIDash/jobs/aidata-digest/work-status.json` (`contract = "aidash-work-status/v1"`, `schema_version = 1`, `coverage_status`, `sample_size`, `window_cst = "14d"`, `source_as_of`, `pulse`, `goals`) and mirrors to iCloud (`sync_job_artifacts` includes `work-status.json`).
  - Missing warehouse or empty populations emit `coverage_status = "missing"` / `"unknown"` / `"partial"` rather than fabricated healthy zeros.
  - Plain-language optimization signals (`ai_signals`) never expose bare internal diagnostic codes (`S1..S12`, `M1..M5` metric codes, `L0..L3`, `R1_m3`, `H1..H5`, `HZN1..HZN5`, `python3`, `SKILL.md`, `session_id`).
