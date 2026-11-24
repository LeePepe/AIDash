"""L5 snapshots for behavioral proxy and offline judge coverage.

These snapshots are separate from the existing ROI sections. Every active
registry skill remains present, and missing evidence is represented by explicit
coverage states rather than zero-valued quality claims.
"""

from __future__ import annotations

import sqlite3
from collections.abc import Iterable, Mapping
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from quality_contracts import aggregate_behavior, aggregate_judge_coverage, build_invocations


def _rows(connection: sqlite3.Connection, table: str) -> list[dict[str, Any]]:
    cursor = connection.execute(f"SELECT * FROM {table}")
    columns = [str(column[0]) for column in cursor.description or ()]
    return [dict(zip(columns, values)) for values in cursor.fetchall()]


def build_behavior_snapshot(
    normalized: Mapping[str, Any],
    *,
    now: Any | None = None,
    source_status: str = "covered",
) -> dict[str, Any]:
    invocations = build_invocations(normalized, now=now)
    source_as_of = normalized.get("source_as_of")
    return {
        "schema_version": 1,
        "metric": "skill_quality_behavior",
        "window_cst": "30d",
        "skills": aggregate_behavior(invocations, now=now, source_as_of=source_as_of, source_status=source_status),
        "source_as_of": source_as_of,
        "estimated": False,
    }


def build_judge_snapshot(
    invocations: Iterable[Mapping[str, Any]],
    verdicts: Iterable[Mapping[str, Any]],
    *,
    now: Any | None = None,
) -> dict[str, Any]:
    result = aggregate_judge_coverage(invocations, verdicts, now=now)
    return {
        "schema_version": 1,
        "metric": "skill_quality_judge",
        **result,
    }


def load_snapshot_from_warehouse(
    warehouse_db: Path,
    *,
    now: Any | None = None,
) -> dict[str, Any]:
    """Read only the quality facts required for both L5 sections."""
    if not warehouse_db.is_file():
        return {
            "behavior": build_behavior_snapshot({}, now=now, source_status="missing"),
            "judge": build_judge_snapshot([], [], now=now),
        }
    connection = sqlite3.connect(f"file:{warehouse_db.resolve()}?mode=ro", uri=True)
    try:
        tables = {
            str(row[0]) for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        invocations = _rows(connection, "fact_skill_invocation") if "fact_skill_invocation" in tables else []
        corrections = _rows(connection, "fact_skill_correction") if "fact_skill_correction" in tables else []
        for invocation in invocations:
            match = next((row for row in corrections if row.get("invocation_id") == invocation.get("invocation_id")), None)
            if match:
                invocation["correction_class"] = match.get("correction_class")
                invocation["correction_confidence"] = match.get("confidence")
        verdicts = _rows(connection, "fact_skill_judgement") if "fact_skill_judgement" in tables else []
        behavior = {
            "schema_version": 1,
            "metric": "skill_quality_behavior",
            "window_cst": "30d",
            "skills": aggregate_behavior(invocations, now=now, source_status="covered" if invocations else "missing"),
            "source_as_of": max((row.get("end_ts") for row in invocations if row.get("end_ts")), default=None),
            "estimated": False,
        }
        return {"behavior": behavior, "judge": build_judge_snapshot(invocations, verdicts, now=now)}
    finally:
        connection.close()
