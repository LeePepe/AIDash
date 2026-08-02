"""L3 merge — build warehouse.db from mergeable clean sources.

Loads schema/warehouse.sql, the price map, then pulls each source's clean table
into the corresponding fact_* table. memory_* sources are NOT merged (they stop
at L2 and are queried directly).

Rebuild semantics: warehouse.db is a derived artifact — dropped and rebuilt from
clean/ each run, so merge is idempotent.
"""

from __future__ import annotations

import csv
import sqlite3

from config import (
    WAREHOUSE_DB, SCHEMA_DIR, clean_path,
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


def _attach(conn: sqlite3.Connection, source: str, alias: str) -> bool:
    """ATTACH a clean source DB if it exists. Returns success."""
    db = clean_path(source)
    if not db.exists():
        return False
    conn.execute(f"ATTACH DATABASE ? AS {alias}", (str(db),))
    return True


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

        # --- fact_request (raven) ---
        if _attach(conn, "raven", "rv"):
            conn.execute("""
                INSERT INTO fact_request
                  (request_id, ts, client, version, model, model_canon,
                   resolved_model, input_tokens, output_tokens, cache_read,
                   cache_write, total_tokens, latency_ms, ttft_ms, status,
                   cost_usd, session_uuid, has_session, tool_call_count)
                SELECT request_id, ts, client, version, model, model_canon,
                       resolved_model, input_tokens, output_tokens, NULL, NULL,
                       total_tokens, latency_ms, ttft_ms, status, cost_usd,
                       session_uuid, has_session, tool_call_count
                FROM rv.req
            """)
            counts["fact_request"] = conn.execute(
                "SELECT count(*) FROM fact_request").fetchone()[0]

        # --- fact_turn (claude_jsonl) ---
        if _attach(conn, "claude_jsonl", "cj"):
            conn.execute("""
                INSERT INTO fact_turn
                  (turn_uuid, session_id, parent_session_id, ts, project,
                   git_branch, role, model, attribution_skill, input_tokens,
                   output_tokens, cache_read, cache_creation, tool_calls,
                   finish_reason)
                SELECT turn_uuid, session_id, parent_session_id, ts, project,
                       git_branch, role, model, attribution_skill, input_tokens,
                       output_tokens, cache_read, cache_creation, tool_calls,
                       finish_reason
                FROM cj.turn
            """)
            counts["fact_turn"] = conn.execute(
                "SELECT count(*) FROM fact_turn").fetchone()[0]

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
