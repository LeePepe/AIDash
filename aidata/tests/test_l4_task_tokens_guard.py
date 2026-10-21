"""Guards for the issue-wide ``fact_task.tokens`` contract."""

from __future__ import annotations

import re
import sqlite3
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
QUERIES = ROOT / "L4_serve" / "queries"
GUARDS = {
    "health/wasted-tokens": QUERIES / "health" / "wasted-tokens.sql",
    "health/agent-scorecard": QUERIES / "health" / "agent-scorecard.sql",
    "attribution/rework-relationship": (
        QUERIES / "attribution" / "rework-relationship.sql"
    ),
    "attribution/rework-by-workspace": (
        QUERIES / "attribution" / "rework-by-workspace.sql"
    ),
}

# Every non-comment ``tokens`` use in an L4 query that reads fact_task must be
# one of these reviewed shapes.  The cause picker is intentionally allowed:
# it is not an output value and is only used to choose the dominant cause;
# rework-relationship.sql documents that contract immediately above it.
TOKEN_USAGE_ALLOWLIST = {
    "issues/drill.sql": {
        "t.tokens                                    AS issue_tokens":
            "per-run detail projection",
    },
    "issues/trend.sql": {
        "max(t.tokens)": "per-issue de-duplication",
    },
    "attribution/rework-relationship.sql": {
        "max(t.tokens)": "per-issue de-duplication",
        "sum(COALESCE(t.tokens, 0))": "non-output dominant-cause picker",
        "r.tokens": "post-dedup projection",
        "sum(tokens)                                     AS rework_tokens":
            "post-dedup output aggregation",
    },
    "attribution/rework-by-workspace.sql": {
        "max(t.tokens)": "per-issue de-duplication",
        "THEN tokens ELSE 0 END": "post-dedup output aggregation",
    },
    "health/wasted-tokens.sql": {
        "CAST(NULL AS INTEGER)                            AS tokens":
            "stable unavailable output column",
    },
}

WS = "workspace-a"


def _warehouse(tmp_path: Path) -> Path:
    db = tmp_path / "warehouse.db"
    con = sqlite3.connect(db)
    con.execute(
        "CREATE TABLE fact_issue (issue_id TEXT PRIMARY KEY, workspace_id TEXT)"
    )
    con.execute(
        "CREATE TABLE fact_task ("
        "task_id TEXT PRIMARY KEY, source TEXT, issue_id TEXT, "
        "ts_start TEXT, ts_end TEXT, status TEXT, tokens INTEGER, "
        "agent_id TEXT, error TEXT)"
    )
    con.executemany(
        "INSERT INTO fact_issue VALUES (?, ?)", [("i1", WS), ("i2", WS)]
    )
    # i1 repeats one issue-wide value (2000) across mixed statuses/agents.
    con.executemany(
        "INSERT INTO fact_task VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
            ("t1", "multica_run", "i1", "2026-10-20T01:00:00Z",
             "2026-10-20T01:01:00Z", "cancelled", 2000, "agent-a",
             "runtime went offline"),
            ("t2", "multica_run", "i1", "2026-10-20T02:00:00Z",
             "2026-10-20T02:01:00Z", "cancelled", 2000, "agent-b",
             "task expired abc"),
            ("t3", "multica_run", "i1", "2026-10-20T03:00:00Z",
             "2026-10-20T03:01:00Z", "completed", 2000, "agent-a", None),
            ("t4", "multica_run", "i2", "2026-10-20T04:00:00Z",
             "2026-10-20T04:01:00Z", "failed", 500, "agent-a", "other"),
        ],
    )
    con.commit()
    con.close()
    return db


def _run(path: Path, db: Path):
    con = sqlite3.connect(db)
    try:
        cur = con.execute(path.read_text(encoding="utf-8"), {"since": None})
        return cur.fetchall(), [column[0] for column in cur.description]
    finally:
        con.close()


@pytest.mark.unit
def test_guard_queries_keep_columns_and_deduplicate_issue_values(tmp_path):
    db = _warehouse(tmp_path)
    wasted, wasted_cols = _run(GUARDS["health/wasted-tokens"], db)
    assert wasted_cols == ["status", "runs", "tokens", "pct_of_tokens"]
    assert {row[0]: row[1:] for row in wasted} == {
        "cancelled": (2, None, None),
        "completed": (1, None, None),
        "failed": (1, None, None),
    }

    scorecard, scorecard_cols = _run(GUARDS["health/agent-scorecard"], db)
    token_index = scorecard_cols.index("avg_tokens")
    assert all(row[token_index] is None for row in scorecard)
    assert {row[0]: row[1] for row in scorecard} == {"agent-a": 3, "agent-b": 1}

    relationship, relationship_cols = _run(
        GUARDS["attribution/rework-relationship"], db
    )
    row = dict(zip(relationship_cols, relationship[0]))
    assert row["issues"] == 1
    assert row["rework_tokens"] == 2000

    by_workspace, by_workspace_cols = _run(
        GUARDS["attribution/rework-by-workspace"], db
    )
    row = dict(zip(by_workspace_cols, by_workspace[0]))
    assert row["issues"] == 2
    assert row["rework_issues"] == 1
    assert row["rework_ktok"] == 2


@pytest.mark.unit
def test_guard_sql_documents_issue_level_deduplication():
    wasted = GUARDS["health/wasted-tokens"].read_text(encoding="utf-8")
    scorecard = GUARDS["health/agent-scorecard"].read_text(encoding="utf-8")
    relationship = GUARDS["attribution/rework-relationship"].read_text(
        encoding="utf-8"
    )
    workspace = GUARDS["attribution/rework-by-workspace"].read_text(
        encoding="utf-8"
    )
    assert "unavailable: fact_task.tokens is issue-wide, merge.py:116" in (
        wasted + scorecard
    )
    assert "max(t.tokens)" in relationship
    assert "max(t.tokens)" in workspace
    assert "max(t.tokens)                                          AS tokens" in workspace
    assert "max(t.tokens)                                           AS tokens" in relationship


@pytest.mark.unit
def test_all_l4_fact_task_token_uses_are_reviewed():
    """Reject new fact_task token uses outside the reviewed allow-list."""
    observed = set()
    violations = []
    for path in sorted(QUERIES.rglob("*.sql")):
        text = path.read_text(encoding="utf-8")
        code_lines = [line.split("--", 1)[0] for line in text.splitlines()]
        code_text = "\n".join(code_lines)
        if not re.search(r"\b(?:FROM|JOIN)\s+fact_task\b", code_text, re.IGNORECASE):
            continue
        relative = path.relative_to(QUERIES).as_posix()
        allowed = TOKEN_USAGE_ALLOWLIST.get(relative, {})
        for line_number, (line, code) in enumerate(
            zip(text.splitlines(), code_lines), start=1
        ):
            if not re.search(r"\btokens\b", code, re.IGNORECASE):
                continue
            matches = [fragment for fragment in allowed if fragment in code]
            if not matches:
                violations.append(f"{relative}:{line_number}: {line.strip()}")
            else:
                observed.update((relative, fragment) for fragment in matches)

    expected = {
        (relative, fragment)
        for relative, entries in TOKEN_USAGE_ALLOWLIST.items()
        for fragment in entries
    }
    assert not violations, "unreviewed fact_task token use(s): " + "; ".join(
        violations
    )
    assert observed == expected
