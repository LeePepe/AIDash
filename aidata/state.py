"""Watermark state — per-source incremental cursors, persisted to state.json.

Each source records the high-water mark it last collected through, so re-runs
only fetch new data (idempotency). Reads/writes are whole-file JSON; callers
get an immutable snapshot and commit an updated copy.
"""

from __future__ import annotations

import json
from typing import Any

from config import STATE_FILE


def load_state() -> dict[str, Any]:
    """Return the full state dict (empty if none yet)."""
    if not STATE_FILE.exists():
        return {}
    try:
        with STATE_FILE.open("r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except (json.JSONDecodeError, OSError):
        # Corrupt/unreadable state is treated as empty; collectors re-scan.
        return {}


def get_watermark(source: str) -> Any:
    """Return the stored watermark for a source, or None."""
    return load_state().get(source)


def set_watermark(source: str, value: Any) -> None:
    """Persist a new watermark for a source (merges into existing state).

    Builds a new dict rather than mutating the loaded one, then writes atomically.
    """
    current = load_state()
    updated = {**current, source: value}
    tmp = STATE_FILE.with_suffix(".json.tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(updated, fh, indent=2, ensure_ascii=False)
    tmp.replace(STATE_FILE)
