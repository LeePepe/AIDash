"""memory_hermes_md adapter — Hermes markdown memory (~/.hermes/memories/*.md).

L1 collect: split MEMORY.md and USER.md on the `§` delimiter into positional
entries. L2 normalize: one row per entry. Native key: filename (MEMORY = facts,
USER = durable preferences/persona). No IDs, no timestamps — position is identity.
Secret-bearing (SSO accounts, tokens) — redaction in write_raw is the safety net.
Stays at L2 — NOT merged.
"""

from __future__ import annotations

from typing import Any

from config import HERMES_MEMORY_MD_DIR
from rawio import write_raw_snapshot, read_raw
from cleanio import write_clean

SOURCE = "memory_hermes_md"

_FILES = ("MEMORY.md", "USER.md")


def collect() -> int:
    if not HERMES_MEMORY_MD_DIR.exists():
        return 0
    records: list[dict[str, Any]] = []
    for fname in _FILES:
        path = HERMES_MEMORY_MD_DIR / fname
        if not path.exists():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        kind = "facts" if fname == "MEMORY.md" else "preferences"
        for idx, chunk in enumerate(text.split("§")):
            entry = chunk.strip()
            if entry:
                records.append({
                    "file": fname,
                    "kind": kind,
                    "position": idx,
                    "entry": entry[:2000],  # redaction applied in write_raw
                })
    return write_raw_snapshot(SOURCE, records)


_CLEAN_DDL = """
CREATE TABLE entry (
    file TEXT, kind TEXT, position INTEGER, entry TEXT,
    PRIMARY KEY (file, position)
)
"""
_CLEAN_COLS = ("file", "kind", "position", "entry")


def normalize() -> int:
    # Raw is fully re-snapshotted each collect; take the latest shard's view by
    # keying on (file, position) with last-write-wins.
    rows: dict[tuple, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        f, pos = rec.get("file"), rec.get("position")
        if f is None or pos is None:
            continue
        rows[(f, pos)] = {
            "file": f,
            "kind": rec.get("kind"),
            "position": pos,
            "entry": rec.get("entry"),
        }
    return write_clean(SOURCE, "entry", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS)
