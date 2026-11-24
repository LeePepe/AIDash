"""Explicit, offline L1/L2 projection for skill behavior quality.

This adapter is not part of the scheduled source registry. Operators or tests
pass bounded source rows to :func:`normalize_records`, which writes only
metadata, hashes, timestamps, and closed classifier values. The helper for the
Copilot session store is read-only and never persists transcript text.
"""

from __future__ import annotations

import sqlite3
from collections.abc import Iterable, Mapping
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from config import CLEAN_DIR, COPILOT_SESSION_DB, clean_path
from quality_contracts import normalize_behavior_records, registry_rows
from rawio import read_raw, write_raw

SOURCE = "quality_behavior"

_PROMPT_DDL = """
CREATE TABLE prompt_signal (
    signal_uid TEXT PRIMARY KEY, source TEXT NOT NULL, session_id TEXT NOT NULL,
    event_id TEXT NOT NULL, skill TEXT NOT NULL, ts TEXT NOT NULL,
    source_kind TEXT NOT NULL, source_covered INTEGER NOT NULL,
    correction_class TEXT NOT NULL, confidence REAL NOT NULL,
    classifier_version TEXT NOT NULL, text_len INTEGER NOT NULL,
    text_sha256 TEXT NOT NULL
)
"""
_PROMPT_COLS = (
    "signal_uid", "source", "session_id", "event_id", "skill", "ts",
    "source_kind", "source_covered", "correction_class", "confidence",
    "classifier_version", "text_len", "text_sha256",
)
_ACTIVITY_DDL = """
CREATE TABLE activity_event (
    event_uid TEXT PRIMARY KEY, source TEXT NOT NULL, session_id TEXT NOT NULL,
    event_id TEXT NOT NULL, skill TEXT NOT NULL, ts TEXT NOT NULL,
    event_type TEXT NOT NULL, assistant_activity INTEGER NOT NULL,
    assistant_turn INTEGER NOT NULL, edit_tool_calls INTEGER NOT NULL,
    finish_reason TEXT, source_covered INTEGER NOT NULL
)
"""
_ACTIVITY_COLS = (
    "event_uid", "source", "session_id", "event_id", "skill", "ts",
    "event_type", "assistant_activity", "assistant_turn", "edit_tool_calls",
    "finish_reason", "source_covered",
)


def _rows(records: Iterable[Mapping[str, Any]]) -> list[Mapping[str, Any]]:
    return [record for record in records if isinstance(record, Mapping)]


def _write_db(db_path: Path, normalized: Mapping[str, Any]) -> int:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()
    connection = sqlite3.connect(db_path)
    try:
        connection.execute(_PROMPT_DDL)
        connection.execute(_ACTIVITY_DDL)
        prompt_rows = _rows(normalized.get("prompt_signals", []))
        activity_rows = _rows(normalized.get("activity_events", []))
        connection.executemany(
            f"INSERT OR REPLACE INTO prompt_signal ({', '.join(_PROMPT_COLS)}) VALUES ({', '.join('?' for _ in _PROMPT_COLS)})",
            [tuple(row.get(column) for column in _PROMPT_COLS) for row in prompt_rows],
        )
        connection.executemany(
            f"INSERT OR REPLACE INTO activity_event ({', '.join(_ACTIVITY_COLS)}) VALUES ({', '.join('?' for _ in _ACTIVITY_COLS)})",
            [tuple(row.get(column) for column in _ACTIVITY_COLS) for row in activity_rows],
        )
        connection.commit()
        return len(prompt_rows) + len(activity_rows)
    finally:
        connection.close()


def normalize_records(
    records: Iterable[Mapping[str, Any]],
    *,
    db_path: Path | None = None,
) -> dict[str, Any]:
    """Normalize source projections and optionally materialize the L2 DB."""
    normalized = normalize_behavior_records(records)
    _write_db(Path(db_path) if db_path is not None else clean_path(SOURCE), normalized)
    return normalized


def collect(*, now: datetime | None = None) -> int:
    """Run the opt-in behavior projection; never called by scheduled collect."""
    projection = collect_copilot_projection(COPILOT_SESSION_DB, now=now)
    normalized = normalize_behavior_records(projection)
    existing = read_raw(SOURCE)
    seen = {
        str(row.get("signal_uid") or row.get("event_uid"))
        for row in existing
        if row.get("kind") in {"prompt_signal", "activity_event"}
    }
    rows = [
        {"kind": "prompt_signal", **row}
        for row in normalized.get("prompt_signals", [])
        if str(row.get("signal_uid")) not in seen
    ]
    rows.extend(
        {"kind": "activity_event", **row}
        for row in normalized.get("activity_events", [])
        if str(row.get("event_uid")) not in seen
    )
    return write_raw(SOURCE, rows) if rows else 0


def normalize() -> int:
    """Materialize the explicit L2 clean store from redacted L1 records."""
    raw = read_raw(SOURCE)
    prompts = [row for row in raw if row.get("kind") == "prompt_signal"]
    activity = [row for row in raw if row.get("kind") == "activity_event"]
    timestamps = [str(row.get("ts")) for row in (*prompts, *activity) if row.get("ts")]
    normalized = {
        "registry": registry_rows(max(timestamps) if timestamps else None),
        "prompt_signals": prompts,
        "activity_events": activity,
        "source_as_of": max(timestamps) if timestamps else None,
    }
    return _write_db(clean_path(SOURCE), normalized)


def _table_columns(connection: sqlite3.Connection, table: str) -> set[str]:
    return {str(row[1]) for row in connection.execute(f"PRAGMA table_info({table})")}


def collect_copilot_projection(
    db_path: Path,
    *,
    now: datetime | None = None,
) -> list[dict[str, Any]]:
    """Read Copilot turns into redacted behavior candidates.

    This is an explicit seam for a bounded/offline materialization. It does
    not alter the existing Copilot collector or enter the scheduled registry.
    """
    if not db_path.is_file():
        return []
    rows: list[dict[str, Any]] = []
    cutoff = (now or datetime.now(timezone.utc)).timestamp() - (30 * 86400)
    try:
        with sqlite3.connect(f"file:{db_path.resolve()}?mode=ro", uri=True) as connection:
            connection.execute("PRAGMA query_only=ON")
            if not _table_columns(connection, "turns"):
                return []
            columns = _table_columns(connection, "turns")
            required = {"session_id", "timestamp"}
            if not required.issubset(columns):
                return []
            selected = ["session_id", "timestamp"]
            selected.append("turn_index" if "turn_index" in columns else "id" if "id" in columns else "rowid")
            selected.extend(column for column in ("user_message", "assistant_response", "tool_calls", "finish_reason") if column in columns)
            query = "SELECT " + ", ".join(selected) + " FROM turns ORDER BY timestamp"
            for values in connection.execute(query):
                row = dict(zip(selected, values))
                stamp = row.get("timestamp")
                try:
                    parsed = datetime.fromisoformat(str(stamp).replace("Z", "+00:00"))
                    if parsed.tzinfo is None:
                        parsed = parsed.replace(tzinfo=timezone.utc)
                    if parsed.timestamp() < cutoff:
                        continue
                except (TypeError, ValueError, OverflowError):
                    continue
                skill = _skill_from_text(row.get("user_message"), row.get("assistant_response"))
                if not skill:
                    continue
                common = {
                    "source": "copilot_cli",
                    "session_id": row.get("session_id"),
                    "event_id": row.get("turn_index", row.get("id")),
                    "timestamp": stamp,
                    "skill": skill,
                    "source_covered": True,
                }
                user_text = row.get("user_message")
                if isinstance(user_text, str) and user_text:
                    rows.append({**common, "text": user_text, "source_kind": "typed"})
                assistant_text = row.get("assistant_response")
                if isinstance(assistant_text, str) and assistant_text:
                    rows.append({
                        **common,
                        "event_type": "assistant_activity",
                        "assistant_activity": True,
                        "assistant_turn": True,
                        "tool_calls": row.get("tool_calls"),
                        "finish_reason": row.get("finish_reason"),
                    })
    except (OSError, sqlite3.Error):
        return []
    return rows


def _skill_from_text(*values: Any) -> str | None:
    import re

    pattern = re.compile(
        r"(?:<skill-context\s+name=[\"']|(?:^|[/\\])skills[/\\])"
        r"([A-Za-z0-9][A-Za-z0-9._-]{0,127})",
        re.IGNORECASE,
    )
    for value in values:
        if not isinstance(value, str):
            continue
        match = pattern.search(value)
        if match:
            return match.group(1)
    return None


def clean_db_path() -> Path:
    """Return the derived L2 path without creating or touching it."""
    return CLEAN_DIR / f"{SOURCE}.db"
