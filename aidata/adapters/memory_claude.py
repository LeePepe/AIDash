"""memory_claude adapter — Claude Code memory notes (~/.claude/.../memory/*.md).

L1 collect: parse YAML frontmatter + body of each .md (skip MEMORY.md index).
L2 normalize: one row per memory file. Native key: metadata.type.
Stays at L2 — NOT merged into the warehouse.
"""

from __future__ import annotations

from typing import Any

from config import CLAUDE_MEMORY_DIR
from rawio import write_raw_snapshot, read_raw
from cleanio import write_clean

SOURCE = "memory_claude"


def _parse_frontmatter(text: str) -> tuple[dict[str, Any], str]:
    """Minimal YAML-frontmatter parser (avoids a PyYAML dependency).

    Handles the flat + one-level-nested `metadata:` block these files use.
    """
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    fm_block = text[3:end].strip("\n")
    body = text[end + 4:].lstrip("\n")

    meta: dict[str, Any] = {}
    nested: dict[str, Any] | None = None
    for line in fm_block.splitlines():
        if not line.strip():
            continue
        indented = line[0] in (" ", "\t")
        key, _, val = line.strip().partition(":")
        key, val = key.strip(), val.strip().strip('"').strip("'")
        if key == "metadata" and not val:
            nested = {}
            meta["metadata"] = nested
        elif indented and nested is not None:
            nested[key] = val
        else:
            nested = None
            meta[key] = val
    return meta, body


def collect() -> int:
    if not CLAUDE_MEMORY_DIR.exists():
        return 0
    records: list[dict[str, Any]] = []
    for md in CLAUDE_MEMORY_DIR.glob("*.md"):
        if md.name == "MEMORY.md":
            continue  # index, not a memory
        try:
            text = md.read_text(encoding="utf-8")
        except OSError:
            continue
        meta, body = _parse_frontmatter(text)
        metadata = meta.get("metadata") or {}
        records.append({
            "file": md.name,
            "name": meta.get("name"),
            "description": meta.get("description"),
            "type": metadata.get("type"),
            "node_type": metadata.get("node_type"),
            "origin_session_id": metadata.get("originSessionId"),
            "body": body[:2000],  # trimmed; redaction applied in write_raw
        })
    return write_raw_snapshot(SOURCE, records)


_CLEAN_DDL = """
CREATE TABLE mem (
    file TEXT PRIMARY KEY, name TEXT, description TEXT, type TEXT,
    origin_session_id TEXT, body TEXT
)
"""
_CLEAN_COLS = ("file", "name", "description", "type", "origin_session_id", "body")


def normalize() -> int:
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        f = rec.get("file")
        if not f:
            continue
        rows[f] = {
            "file": f,
            "name": rec.get("name"),
            "description": rec.get("description"),
            "type": rec.get("type"),
            "origin_session_id": rec.get("origin_session_id"),
            "body": rec.get("body"),
        }
    return write_clean(SOURCE, "mem", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS)
