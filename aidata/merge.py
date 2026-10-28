"""L3 merge — build warehouse.db from mergeable clean sources.

Loads schema/warehouse.sql, the price map, then pulls each source's clean table
into the corresponding fact_* table. memory_* sources are NOT merged (they stop
at L2 and are queried directly).

Rebuild semantics: warehouse.db is a derived artifact — dropped and rebuilt from
clean/ each run, so merge is idempotent.
"""

from __future__ import annotations

import csv
import os
import sqlite3

from config import (
    SCHEMA_DIR,
    WAREHOUSE_DB,
    clean_path,
)


def _load_prices(conn: sqlite3.Connection) -> None:
    csv_path = SCHEMA_DIR / "dim_model.csv"
    if not csv_path.exists():
        return
    with csv_path.open(newline="", encoding="utf-8") as fh:
        rows = [
            (r["model"], float(r["input_per_mtok"]), float(r["output_per_mtok"]),
             float(r["cache_read_per_mtok"]), float(r["cache_write_per_mtok"]))
            for r in csv.DictReader(fh)
        ]
    conn.executemany(
        "INSERT OR REPLACE INTO dim_model VALUES (?, ?, ?, ?, ?)", rows
    )


def _load_automation_rules(conn: sqlite3.Connection) -> None:
    csv_path = SCHEMA_DIR / "automation_rules.csv"
    if not csv_path.exists():
        return
    rows = []
    with csv_path.open(newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            match = row["match"]
            if row["kind"] == "cwd_prefix":
                match = os.path.expanduser(match)
            rows.append((row["kind"], match, row["class"], row["note"]))
    conn.executemany(
        "INSERT OR REPLACE INTO dim_automation_rule VALUES (?, ?, ?, ?)", rows
    )


def _attach(conn: sqlite3.Connection, source: str, alias: str) -> bool:
    """ATTACH a clean source DB if it exists. Returns success."""
    db = clean_path(source)
    if not db.exists():
        return False
    conn.execute(f"ATTACH DATABASE ? AS {alias}", (str(db),))
    return True


def _detach(conn: sqlite3.Connection, alias: str) -> None:
    conn.execute(f"DETACH DATABASE {alias}")


def run_merge() -> dict[str, int]:
    WAREHOUSE_DB.parent.mkdir(parents=True, exist_ok=True)
    # Fresh rebuild — derived artifact.
    if WAREHOUSE_DB.exists():
        WAREHOUSE_DB.unlink()

    # autocommit (isolation_level=None): ATTACH cannot run inside a transaction,
    # and executescript would otherwise leave one open.
    conn = sqlite3.connect(WAREHOUSE_DB, isolation_level=None)
    counts: dict[str, int] = {}
    try:
        conn.executescript((SCHEMA_DIR / "warehouse.sql").read_text(encoding="utf-8"))
        _load_prices(conn)
        _load_automation_rules(conn)
        counts["dim_automation_rule"] = conn.execute(
            "SELECT count(*) FROM dim_automation_rule"
        ).fetchone()[0]

        # --- P0 GTT dimensions/facts ---
        if _attach(conn, "gtt_ledger", "gl"):
            conn.execute("""
                INSERT OR REPLACE INTO dim_goal
                SELECT goal_uid, machine_id, goal_id, title, owner, coordinator_bot,
                       tl_agent, tl_model, contract_sha, static_header_status,
                       derived_actual_status, is_status_drifted, task_total_count,
                       task_done_count, task_blocked_count, created_at, last_event_at,
                       ledger_sha256
                FROM gl.goal
            """)
            conn.execute("""
                INSERT OR REPLACE INTO fact_gtt_event
                SELECT event_uid, goal_uid, machine_id, goal_id, line_no, event_id, ts,
                       evt_type, task_id, actor_from, actor_to, ref_artifact, head_sha,
                       pr_number, model_id, contract_sha, is_bot_bypass, blocker_class,
                       note_preview
                FROM gl.gtt_event
            """)
            counts["dim_goal"] = conn.execute("SELECT count(*) FROM dim_goal").fetchone()[0]
            counts["fact_gtt_event"] = conn.execute(
                "SELECT count(*) FROM fact_gtt_event").fetchone()[0]
            _detach(conn, "gl")

        if _attach(conn, "gtt_receipt", "grt"):
            conn.execute("""
                INSERT OR REPLACE INTO dim_model_role
                SELECT role_model_key, role_name, tier, cli_tool, model_id, vendor,
                       is_escalated
                FROM grt.model_role
            """)
            conn.execute("""
                INSERT OR REPLACE INTO fact_gtt_task_run
                SELECT receipt_uid, goal_uid, machine_id, goal_id, task_id, role_name,
                       round_no, agent_name, cli_tool, model_id, vendor, status,
                       v5_verdict, head_sha, receipt_sha256, completed_at
                FROM grt.task_run
            """)
            counts["dim_model_role"] = conn.execute(
                "SELECT count(*) FROM dim_model_role").fetchone()[0]
            counts["fact_gtt_task_run"] = conn.execute(
                "SELECT count(*) FROM fact_gtt_task_run").fetchone()[0]
            _detach(conn, "grt")

        if _attach(conn, "workspace_hygiene", "wh"):
            conn.execute("""
                INSERT OR REPLACE INTO dim_repo
                SELECT repo_key, owner, repo_name, domain_group, local_main_path,
                       default_branch, head_sha, is_dirty, dirty_count, has_agents_md,
                       has_layer_map, has_verify_script, has_design_contract,
                       shared_ci_pinned_sha, ruleset_strict, updated_at
                FROM wh.repo
            """)
            conn.execute("""
                INSERT OR REPLACE INTO dim_repo
                SELECT repo_key, owner, repo_name, domain_group, local_main_path,
                       default_branch, head_sha, is_dirty, dirty_count, has_agents_md,
                       has_layer_map, has_verify_script, has_design_contract,
                       shared_ci_pinned_sha, ruleset_strict, updated_at
                FROM wh.repo
            """)
            conn.execute("""
                INSERT OR REPLACE INTO fact_workspace_hygiene_snapshot
                SELECT snapshot_date, machine_id, entity_type, canonical_path, repo_key,
                       goal_id, branch_name, head_sha, is_dirty, dirty_count,
                       is_merged_to_default, has_active_pane, has_implicit_dep,
                       safe_to_reclaim, reclaim_block_reason
                FROM wh.hygiene_snapshot
            """)
            counts["fact_workspace_hygiene_snapshot"] = conn.execute(
                "SELECT count(*) FROM fact_workspace_hygiene_snapshot").fetchone()[0]
            counts["dim_repo"] = conn.execute("SELECT count(*) FROM dim_repo").fetchone()[0]

            _detach(conn, "wh")

        # --- governance fingerprints (github_ruleset) ---
        if _attach(conn, "github_ruleset", "grs"):
            conn.execute("""
                INSERT INTO dim_repo
                  (repo_key, owner, repo_name, domain_group, local_main_path,
                   default_branch, head_sha, is_dirty, dirty_count,
                   has_agents_md, has_layer_map, has_verify_script,
                   has_design_contract, shared_ci_pinned_sha, ruleset_strict,
                   updated_at)
                SELECT repo_key, owner, repo_name, domain_group, local_main_path,
                       default_branch, head_sha, is_dirty, dirty_count,
                       has_agents_md, has_layer_map, has_verify_script,
                       has_design_contract, shared_ci_pinned_sha, ruleset_strict,
                       updated_at
                FROM grs.repo
                ON CONFLICT(repo_key) DO UPDATE SET
                    owner = COALESCE(excluded.owner, dim_repo.owner),
                    repo_name = COALESCE(excluded.repo_name, dim_repo.repo_name),
                    domain_group = COALESCE(excluded.domain_group, dim_repo.domain_group),
                    local_main_path = COALESCE(excluded.local_main_path, dim_repo.local_main_path),
                    default_branch = COALESCE(excluded.default_branch, dim_repo.default_branch),
                    head_sha = COALESCE(excluded.head_sha, dim_repo.head_sha),
                    is_dirty = COALESCE(excluded.is_dirty, dim_repo.is_dirty),
                    dirty_count = COALESCE(excluded.dirty_count, dim_repo.dirty_count),
                    has_agents_md = COALESCE(excluded.has_agents_md, dim_repo.has_agents_md),
                    has_layer_map = COALESCE(excluded.has_layer_map, dim_repo.has_layer_map),
                    has_verify_script = COALESCE(excluded.has_verify_script, dim_repo.has_verify_script),
                    has_design_contract = COALESCE(excluded.has_design_contract, dim_repo.has_design_contract),
                    shared_ci_pinned_sha = COALESCE(excluded.shared_ci_pinned_sha, dim_repo.shared_ci_pinned_sha),
                    ruleset_strict = COALESCE(excluded.ruleset_strict, dim_repo.ruleset_strict),
                    updated_at = COALESCE(excluded.updated_at, dim_repo.updated_at)
            """)
            conn.execute("""
                INSERT OR REPLACE INTO dim_workflow_gate
                  (workflow_gate_key, repo_key, workflow_file, workflow_name,
                   workflow_category, uses_shared_ci, pinned_shared_ci_ref,
                   is_required_check, timeout_minutes)
                SELECT workflow_gate_key, repo_key, workflow_file, workflow_name,
                       workflow_category, uses_shared_ci, pinned_shared_ci_ref,
                       is_required_check, timeout_minutes
                FROM grs.workflow_gate
            """)
            counts["dim_repo"] = conn.execute("SELECT count(*) FROM dim_repo").fetchone()[0]
            counts["dim_workflow_gate"] = conn.execute(
                "SELECT count(*) FROM dim_workflow_gate").fetchone()[0]
            _detach(conn, "grs")

        # --- GitHub Actions run/job facts ---
        if _attach(conn, "github_ci", "gci"):
            conn.execute("""
                INSERT OR REPLACE INTO fact_ci_workflow_run
                  (run_id, repo_key, workflow_name, workflow_category, event_trigger,
                   head_branch, head_sha, status, conclusion, run_attempt,
                   created_at, updated_at, duration_sec, html_url)
                SELECT run_id, repo_key, workflow_name, workflow_category, event_trigger,
                       head_branch, head_sha, status, conclusion, run_attempt,
                       created_at, updated_at, duration_sec, html_url
                FROM gci.workflow_run
            """)
            conn.execute("""
                INSERT OR REPLACE INTO fact_ci_job_run
                  (job_id, run_id, repo_key, job_name, status, conclusion,
                   runner_labels, is_self_hosted, created_at, started_at,
                   completed_at, queue_wait_sec, exec_sec, failed_step_name,
                   failure_category, error_excerpt)
                SELECT job_id, run_id, repo_key, job_name, status, conclusion,
                       runner_labels, is_self_hosted, created_at, started_at,
                       completed_at, queue_wait_sec, exec_sec, failed_step_name,
                       failure_category, error_excerpt
                FROM gci.job_run
            """)
            counts["fact_ci_workflow_run"] = conn.execute(
                "SELECT count(*) FROM fact_ci_workflow_run").fetchone()[0]
            counts["fact_ci_job_run"] = conn.execute(
                "SELECT count(*) FROM fact_ci_job_run").fetchone()[0]
            _detach(conn, "gci")

        # --- TestFlight / 04 delivery facts ---
        if _attach(conn, "release_tf", "rtf"):
            conn.execute("""
                INSERT OR REPLACE INTO fact_release_delivery
                  (delivery_uid, repo_key, run_id, workflow_name, trigger_event,
                   target_platform, head_sha, marketing_version, build_number,
                   gate_step_conclusion, archive_step_conclusion,
                   upload_step_conclusion, tag_step_conclusion, marker_tag_name,
                   marker_sha_before, marker_sha_after, is_marker_advanced,
                   asc_build_verified, delivery_outcome, total_duration_sec,
                   started_at, completed_at, failure_stage)
                SELECT delivery_uid, repo_key, run_id, workflow_name, trigger_event,
                       target_platform, head_sha, marketing_version, build_number,
                       gate_step_conclusion, archive_step_conclusion,
                       upload_step_conclusion, tag_step_conclusion, marker_tag_name,
                       marker_sha_before, marker_sha_after, is_marker_advanced,
                       asc_build_verified, delivery_outcome, total_duration_sec,
                       started_at, completed_at, failure_stage
                FROM rtf.delivery
            """)
            counts["fact_release_delivery"] = conn.execute(
                "SELECT count(*) FROM fact_release_delivery").fetchone()[0]
            _detach(conn, "rtf")

        # --- fact_request (raven) ---
        if _attach(conn, "raven", "rv"):
            # Clean databases are derived artifacts and may predate the cache
            # columns.  Keep those inputs compatible while making the absence
            # explicit as NULL rather than treating it as zero usage.
            rv_columns = {
                row[1] for row in conn.execute("PRAGMA rv.table_info(req)")
            }
            cache_read = "cache_read" if "cache_read" in rv_columns else "NULL"
            cache_write = "cache_write" if "cache_write" in rv_columns else "NULL"
            conn.execute(f"""
                INSERT INTO fact_request
                  (request_id, ts, client, version, model, model_canon,
                   resolved_model, input_tokens, output_tokens, cache_read,
                   cache_write, total_tokens, latency_ms, ttft_ms, status,
                   cost_usd, session_uuid, has_session, tool_call_count)
                SELECT request_id, ts, client, version, model, model_canon,
                       resolved_model, input_tokens, output_tokens,
                       {cache_read}, {cache_write},
                       total_tokens, latency_ms, ttft_ms, status, cost_usd,
                       session_uuid, has_session, tool_call_count
                FROM rv.req
            """)
            counts["fact_request"] = conn.execute(
                "SELECT count(*) FROM fact_request").fetchone()[0]
            _detach(conn, "rv")

        # --- fact_turn (claude_jsonl) ---
        if _attach(conn, "claude_jsonl", "cj"):
            cj_columns = {
                row[1] for row in conn.execute("PRAGMA cj.table_info(turn)")
            }
            skill_names = "skill_names" if "skill_names" in cj_columns else "NULL"
            conn.execute(f"""
                INSERT INTO fact_turn
                  (turn_uuid, session_id, parent_session_id, ts, project,
                   git_branch, role, model, attribution_skill, input_tokens,
                   output_tokens, cache_read, cache_creation, tool_calls,
                   finish_reason, skill_names)
                SELECT turn_uuid, session_id, parent_session_id, ts, project,
                       git_branch, role, model, attribution_skill, input_tokens,
                       output_tokens, cache_read, cache_creation, tool_calls,
                       finish_reason, {skill_names}
                FROM cj.turn
            """)
            counts["fact_turn"] = conn.execute(
                "SELECT count(*) FROM fact_turn").fetchone()[0]
            _detach(conn, "cj")

        # --- fact_issue (multica_issue) ---
        if _attach(conn, "multica_issue", "mi"):
            conn.execute("""
                INSERT INTO fact_issue
                  (issue_id, issue_number, identifier, title, status, priority,
                   created_at, workspace_id, updated_at, project_id)
                SELECT issue_id, issue_number, identifier, title, status, priority,
                       created_at, workspace_id, updated_at, project_id
                FROM mi.issue
            """)
            counts["fact_issue"] = conn.execute(
                "SELECT count(*) FROM fact_issue").fetchone()[0]
            _detach(conn, "mi")

        # --- fact_task: multica runs + claude jobs ---
        n_task = 0
        if _attach(conn, "multica_run", "mr"):
            conn.execute("""
                INSERT OR IGNORE INTO fact_task
                  (task_id, source, issue_id, ts_start, ts_end, status,
                   attempt, max_attempts, tokens, agent_id, session_id, pr_url,
                   error, trigger_summary)
                SELECT task_id, 'multica_run', issue_id, ts_start, ts_end, status,
                       attempt, max_attempts,
                       COALESCE(issue_input_tokens,0)+COALESCE(issue_output_tokens,0),
                       agent_id, session_id, pr_url,
                       error, trigger_summary
                FROM mr.run
            """)
            n_task = conn.execute("SELECT count(*) FROM fact_task").fetchone()[0]
            _detach(conn, "mr")
        if _attach(conn, "claude_job", "cjob"):
            conn.execute("""
                INSERT OR IGNORE INTO fact_task
                  (task_id, source, issue_id, ts_start, ts_end, status,
                   attempt, max_attempts, tokens, agent_id, session_id, pr_url,
                   error, trigger_summary)
                SELECT task_id, 'claude_job', NULL, ts_start, ts_end, state,
                       NULL, NULL, tokens, NULL, session_id, pr_url,
                       NULL, NULL
                FROM cjob.job
            """)
            n_task = conn.execute("SELECT count(*) FROM fact_task").fetchone()[0]
            _detach(conn, "cjob")
        counts["fact_task"] = n_task

        # --- fact_pr (pr_cache + job children) ---
        if _attach(conn, "pr_cache", "pc"):
            conn.execute("""
                INSERT OR IGNORE INTO fact_pr
                  (pr_url, number, title, state, checks_passed, checks_failed,
                   checks_pending, additions, deletions)
                SELECT pr_url, number, title, state, checks_passed, checks_failed,
                       checks_pending, additions, deletions
                FROM pc.pr
            """)
            _detach(conn, "pc")
        # backfill PR urls referenced by tasks but absent from cache (state unknown)
        conn.execute("""
            INSERT OR IGNORE INTO fact_pr (pr_url, state)
            SELECT DISTINCT pr_url, 'unknown' FROM fact_task
            WHERE pr_url IS NOT NULL AND pr_url != ''
        """)
        counts["fact_pr"] = conn.execute("SELECT count(*) FROM fact_pr").fetchone()[0]

        # --- fact_ado_pr (ado_pr) — separate table, NOT merged into fact_pr (ADR-13) ---
        if _attach(conn, "ado_pr", "ap"):
            conn.execute("""
                INSERT OR IGNORE INTO fact_ado_pr
                  (pr_id, title, status, created_date, closed_date, creator_id,
                   source_branch, target_branch, is_draft, reviewers, age_hours, repo)
                SELECT pr_id, title, status, created_date, closed_date, creator_id,
                       source_branch, target_branch, is_draft, reviewers, age_hours, repo
                FROM ap.pr
            """)
            counts["fact_ado_pr"] = conn.execute(
                "SELECT count(*) FROM fact_ado_pr").fetchone()[0]
            _detach(conn, "ap")

        # --- fact_repo_snapshot (github_repo) — daily star snapshots (radar) ---
        if _attach(conn, "github_repo", "gr"):
            conn.execute("""
                INSERT OR IGNORE INTO fact_repo_snapshot
                  (repo, snapshot_date, stars, forks, description, language,
                   topics, pushed_at, provenance)
                SELECT repo, snapshot_date, stars, forks, description, language,
                       topics, pushed_at, provenance
                FROM gr.repo_snapshot
            """)
            counts["fact_repo_snapshot"] = conn.execute(
                "SELECT count(*) FROM fact_repo_snapshot").fetchone()[0]
            _detach(conn, "gr")

        # --- fact_github_pr (github_pr) — my GitHub PRs, separate table (ADR-13) ---
        if _attach(conn, "github_pr", "gp"):
            conn.execute("""
                INSERT OR IGNORE INTO fact_github_pr
                  (repo, pr_number, title, state, created_date, merged_date,
                   closed_date, url, is_draft)
                SELECT repo, pr_number, title, state, created_date, merged_date,
                       closed_date, url, is_draft
                FROM gp.github_pr
            """)
            _detach(conn, "gp")
            counts["fact_github_pr"] = conn.execute(
                "SELECT count(*) FROM fact_github_pr").fetchone()[0]

        # --- dim_session rollup (from fact_request, claude-cli only) ---
        conn.execute("""
            INSERT OR REPLACE INTO dim_session
              (session_id, first_ts, last_ts, request_count, total_tokens,
               total_cost_usd, client)
            SELECT session_uuid, min(ts), max(ts), count(*),
                   sum(COALESCE(total_tokens,0)), sum(COALESCE(cost_usd,0)),
                   max(client)
            FROM fact_request
            WHERE session_uuid IS NOT NULL
            GROUP BY session_uuid
        """)
        counts["dim_session"] = conn.execute(
            "SELECT count(*) FROM dim_session").fetchone()[0]

        conn.commit()
    finally:
        conn.close()
    return counts
