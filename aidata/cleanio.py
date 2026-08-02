"""Shared helper for L2 normalize: write cleaned rows into clean/<source>.db.

Each normalizer defines a table DDL and a list of row dicts; this rebuilds the
source's clean table idempotently (drop + recreate + insert). Clean DBs are
derived artifacts — safe to rebuild from raw at any time.
"""

from __future__ import annotations

import sqlite3
from typing import Any, Sequence

from config import CLEAN_DIR, clean_path


def write_clean(source: str, table: str, ddl: str, rows: Sequence[dict[str, Any]],
                columns: Sequence[str]) -> int:
    """Rebuild `table` in clean/<source>.db from rows. Returns row count.

    Idempotent: drops and recreates the table so re-running normalize yields
    the same result (no duplicate accumulation).
    """
    CLEAN_DIR.mkdir(parents=True, exist_ok=True)
    db = clean_path(source)
    conn = sqlite3.connect(db)
    try:
        conn.execute(f"DROP TABLE IF EXISTS {table}")
        conn.execute(ddl)
        if rows:
            placeholders = ", ".join("?" for _ in columns)
            collist = ", ".join(columns)
            conn.executemany(
                f"INSERT INTO {table} ({collist}) VALUES ({placeholders})",
                [tuple(r.get(c) for c in columns) for r in rows],
            )
        conn.commit()
        return len(rows)
    finally:
        conn.close()
