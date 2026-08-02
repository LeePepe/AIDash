"""multica_run adapter — execution history + per-issue token usage.

L1 collect: for each known issue (from multica_issue raw), fetch `issue runs`
(execution records) and `issue usage` (aggregated token totals). Both via CLI.
L2 normalize: one row per execution (fact_task grain); token totals attached
per-issue in a side table.

Update to design: `multica issue usage <id>` gives real per-issue token totals
directly — better than the session-bridge workaround. We still keep the session
bridge available via run.result.session_id for request-level joins.
"""

from __future__ import annotations

from typing import Any

from config import MULTICA_WORKSPACES
from adapters._multica import multica_bin, run_json
from rawio import write_raw, read_raw
from cleanio import write_clean
from state import get_watermark, set_watermark
from adapters.multica_issue import SOURCE as ISSUE_SOURCE

SOURCE = "multica_run"


def _multica_bin() -> str | None:
    """Thin wrapper over the shared resolver (kept as a monkeypatch seam)."""
    return multica_bin()


def _run_json(args: list[str]) -> Any:
    """Thin wrapper over shared run_json; passes LOCAL _multica_bin() so that
    patching this module's _multica_bin still drives the CLI resolution."""
    return run_json(args, binp=_multica_bin())


def _known_issues_by_workspace(ws_id: str) -> list[tuple[str, int]]:
    """(identifier, number) seen in multica_issue raw for one workspace, newest first."""
    seen: dict[str, int] = {}
    for rec in read_raw(ISSUE_SOURCE):
        if rec.get("workspace_id") != ws_id:
            continue
        ident = rec.get("identifier")
        num = int(rec.get("number") or 0)
        if ident:
            seen[ident] = num
    return sorted(seen.items(), key=lambda kv: kv[1], reverse=True)


def collect() -> int:
    """Fetch runs+usage per known issue, across BOTH workspaces (EXT-2).

    Each workspace keeps its own watermark (highest issue number pulled). Runs
    and usage are fetched with that workspace's --workspace-id so each
    workspace's issues resolve against its own backend, not the config default.
    """
    total = 0
    for ws_id, _name in MULTICA_WORKSPACES:
        key = f"{SOURCE}:{ws_id}"
        watermark = int(get_watermark(key) or 0)
        max_num = watermark
        batch: list[dict[str, Any]] = []

        for ident, num in _known_issues_by_workspace(ws_id):
            if num <= watermark:
                continue  # already collected in a prior run
            try:
                runs = _run_json(
                    ["issue", "runs", ident, "--workspace-id", ws_id, "--output", "json"])
            except RuntimeError:
                continue
            if isinstance(runs, dict):
                runs = runs.get("runs", [])
            try:
                usage = _run_json(
                    ["issue", "usage", ident, "--workspace-id", ws_id, "--output", "json"])
            except RuntimeError:
                usage = {}
            for r in (runs or []):
                rec = dict(r)
                rec["_issue_identifier"] = ident
                rec["_workspace_id"] = ws_id
                rec["_issue_usage"] = usage  # per-issue totals, repeated per run
                batch.append(rec)
            max_num = max(max_num, num)
            if len(batch) >= 500:
                total += write_raw(SOURCE, batch)
                batch = []

        if batch:
            total += write_raw(SOURCE, batch)
        if max_num > watermark:
            set_watermark(key, max_num)
    return total


_CLEAN_DDL = """
CREATE TABLE run (
    task_id TEXT PRIMARY KEY, issue_id TEXT, issue_identifier TEXT,
    agent_id TEXT, runtime_id TEXT, kind TEXT, status TEXT,
    attempt INTEGER, max_attempts INTEGER,
    ts_start TEXT, ts_end TEXT, session_id TEXT, pr_url TEXT,
    issue_input_tokens INTEGER, issue_output_tokens INTEGER,
    issue_cache_read INTEGER, issue_cache_write INTEGER,
    trigger_summary TEXT, trigger_comment_id TEXT, error TEXT
)
"""
_CLEAN_COLS = ("task_id", "issue_id", "issue_identifier", "agent_id", "runtime_id",
               "kind", "status", "attempt", "max_attempts", "ts_start", "ts_end",
               "session_id", "pr_url", "issue_input_tokens", "issue_output_tokens",
               "issue_cache_read", "issue_cache_write",
               "trigger_summary", "trigger_comment_id", "error")


def _norm_error(e: Any) -> str | None:
    """Absent errors arrive as the literal string "None" (or ""); make them NULL."""
    return None if e in (None, "None", "") else e


def normalize() -> int:
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        tid = rec.get("id")
        if not tid:
            continue
        result = rec.get("result") or {}
        usage = rec.get("_issue_usage") or {}
        rows[tid] = {
            "task_id": tid,
            "issue_id": rec.get("issue_id"),
            "issue_identifier": rec.get("_issue_identifier"),
            "agent_id": rec.get("agent_id"),
            "runtime_id": rec.get("runtime_id"),
            "kind": rec.get("kind"),
            "status": rec.get("status"),
            "attempt": rec.get("attempt"),
            "max_attempts": rec.get("max_attempts"),
            "ts_start": rec.get("started_at") or rec.get("created_at"),
            "ts_end": rec.get("completed_at"),
            "session_id": result.get("session_id"),
            "pr_url": result.get("pr_url") or None,
            "issue_input_tokens": usage.get("total_input_tokens"),
            "issue_output_tokens": usage.get("total_output_tokens"),
            "issue_cache_read": usage.get("total_cache_read_tokens"),
            "issue_cache_write": usage.get("total_cache_write_tokens"),
            # Workflow-signal columns (raw already redacted upstream; read as-is).
            # "None" is a real string value the CLI emits for absent errors —
            # normalize it to SQL NULL so downstream root-cause counts are clean.
            "trigger_summary": rec.get("trigger_summary"),
            "trigger_comment_id": rec.get("trigger_comment_id"),
            "error": _norm_error(rec.get("error")),
        }
    return write_clean(SOURCE, "run", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS)
