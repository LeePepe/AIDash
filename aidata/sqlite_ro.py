"""Read-only SQLite access that survives interpreter sqlite-version skew.

This machine's default `python3` bundles sqlite 3.19.3 (2017), too old to parse
some DBs written by modern sqlite (e.g. raven.db). The system `sqlite3` CLI
(3.51+) reads them fine. This helper prefers the CLI (JSON mode) and falls back
to the stdlib driver, so adapters don't care which interpreter runs them.

Always read-only: `mode=ro` URI for the driver, `file:...?mode=ro` for the CLI.

`immutable=True` additionally opens with `immutable=1`, which tells sqlite the
file will not change under it and to skip all locking/WAL checks. This is how we
read a LIVE application DB (e.g. Chrome's History) that another process holds a
lock on — a plain `mode=ro` open of a locked Chrome History raises "database is
locked", whereas the immutable open succeeds. Only pass immutable for a file you
know is append-mostly and where a torn read is acceptable (telemetry, not truth).
"""

from __future__ import annotations

import json
import shutil
import sqlite3
import subprocess
from pathlib import Path
from typing import Any, Iterator

_SQLITE_CLI = shutil.which("sqlite3")


def _ro_uri(db: Path, immutable: bool = False) -> str:
    uri = f"file:{db}?mode=ro"
    if immutable:
        uri += "&immutable=1"
    return uri


def query_ro(db: Path, sql: str, params: tuple = (),
             immutable: bool = False) -> list[dict[str, Any]]:
    """Run a read-only query, returning list-of-dict rows.

    Tries the system sqlite3 CLI first (newest engine, handles modern schemas);
    falls back to the stdlib driver if the CLI is absent. Params are inlined for
    the CLI path, so keep them simple scalars (ints/strs) — adequate for our
    watermark filters.

    Set `immutable=True` to read a DB another process has locked (opens with
    sqlite's `immutable=1`; see module docstring).
    """
    # Prefer CLI when available (avoids stdlib version skew).
    if _SQLITE_CLI:
        try:
            return list(_query_cli(db, sql, params, immutable))
        except _CliError:
            pass  # fall through to stdlib
    return _query_driver(db, sql, params, immutable)


class _CliError(RuntimeError):
    pass


def _inline(sql: str, params: tuple) -> str:
    """Substitute ? placeholders with literal values for the CLI path."""
    out = sql
    for p in params:
        if isinstance(p, (int, float)):
            lit = str(p)
        else:
            lit = "'" + str(p).replace("'", "''") + "'"
        out = out.replace("?", lit, 1)
    return out


def _query_cli(db: Path, sql: str, params: tuple,
               immutable: bool = False) -> Iterator[dict[str, Any]]:
    script = ".mode json\n" + _inline(sql, params) + ";\n"
    proc = subprocess.run(
        [_SQLITE_CLI, _ro_uri(db, immutable)],
        input=script, capture_output=True, text=True, timeout=300,
    )
    if proc.returncode != 0:
        raise _CliError(proc.stderr.strip()[:200])
    out = proc.stdout.strip()
    if not out:
        return iter(())
    # sqlite3 CLI emits one JSON array (or concatenated arrays for multi-stmt).
    try:
        data = json.loads(out)
        return iter(data if isinstance(data, list) else [data])
    except json.JSONDecodeError:
        rows: list[dict[str, Any]] = []
        for line in out.splitlines():
            line = line.strip().rstrip(",")
            if line and line not in ("[", "]"):
                rows.append(json.loads(line))
        return iter(rows)


def _query_driver(db: Path, sql: str, params: tuple,
                  immutable: bool = False) -> list[dict[str, Any]]:
    conn = sqlite3.connect(_ro_uri(db, immutable), uri=True)
    try:
        conn.row_factory = sqlite3.Row
        return [dict(r) for r in conn.execute(sql, params)]
    finally:
        conn.close()
