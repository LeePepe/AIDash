"""L4 serve — run named .sql queries from L4_serve/queries/.

A query is a .sql file addressed by its path minus extension, e.g.
`issues/trend` -> L4_serve/queries/issues/trend.sql. Queries run against
warehouse.db. Sources that stop at L2 (un-merged clean DBs like `state_db`,
`memory_*`, `multica_comment`) are read directly from their clean DB, which
must be ATTACHed under the source name.

ATTACH is **on demand**: only the clean DBs a query actually needs are
attached, declared by an explicit header line in the .sql file:

    -- aidata-attach: state_db

This keeps the attach count well under SQLite's default limit of 10 — the old
"ATTACH every existing L2-only DB unconditionally" approach hit the limit once
the 11th L2-only clean DB appeared on disk ("too many attached databases"),
taking down *every* L4 query at connect time. Declaring dependencies per query
also avoids fragile source-name regexes over the SQL body (which false-match
source names inside comments/strings, e.g. a `state_db` mentioned only in a
comment).

Named bind params (:name) are supported via --param KEY=VALUE.
"""

from __future__ import annotations

import re
import sqlite3
from pathlib import Path
from typing import Any

from config import WAREHOUSE_DB, QUERIES_DIR, MERGE_SOURCES, SOURCES, clean_path

# Named bind params in a .sql file: `:since`, `:until`, `:id`, … Excludes `::`
# casts (not used here) by requiring a leading non-colon or start-of-string.
_NAMED_PARAM = re.compile(r"(?<![:\w]):([a-zA-Z_]\w*)")

# Explicit per-query ATTACH declaration. Only a line that *starts* with
# `-- aidata-attach:` counts (anchored via re.MULTILINE), so a source name
# appearing mid-comment or inside a string can't spoof a dependency. Payload is
# one or more L2-only source names, comma- and/or space-separated.
_ATTACH_DIRECTIVE = re.compile(r"^\s*--\s*aidata-attach:\s*(.+?)\s*$", re.MULTILINE)


def list_queries() -> list[str]:
    if not QUERIES_DIR.exists():
        return []
    return sorted(
        str(p.relative_to(QUERIES_DIR).with_suffix(""))
        for p in QUERIES_DIR.glob("**/*.sql")
    )


def parse_required_sources(sql: str) -> list[str]:
    """Extract the L2-only sources a query declares it needs ATTACHed.

    Reads `-- aidata-attach: <src>[, <src> ...]` header lines. Returns the
    de-duplicated source names in first-seen order. A query with no directive
    (i.e. one that only reads warehouse.db) yields an empty list.
    """
    seen: list[str] = []
    for match in _ATTACH_DIRECTIVE.finditer(sql):
        for token in re.split(r"[,\s]+", match.group(1)):
            src = token.strip()
            if src and src not in seen:
                seen.append(src)
    return seen


def _ro_uri(path: Path) -> str:
    """A read-only SQLite URI for `path` (mode=ro — never creates/writes)."""
    return f"{path.as_uri()}?mode=ro"


def _connect(required_sources: list[str] | None = None) -> sqlite3.Connection:
    """Open warehouse read-only and ATTACH only the declared L2-only DBs.

    `required_sources` names the L2-only (un-merged) sources this query reads
    directly from their clean DB. Each is validated to be a real, un-merged
    source before attaching; merged sources already live in warehouse.db as
    fact_* tables and must not be attached. All handles are opened read-only
    (mode=ro URIs). If any ATTACH fails, the partially-built connection is closed
    before the error propagates so we never leak a half-attached handle.
    """
    required = required_sources or []
    conn = sqlite3.connect(_ro_uri(WAREHOUSE_DB), uri=True, isolation_level=None)
    try:
        for src in required:
            if src not in SOURCES:
                raise ValueError(f"unknown attach source: {src!r}")
            if src in MERGE_SOURCES:
                raise ValueError(
                    f"cannot attach merged source {src!r}: it lives in "
                    "warehouse.db as fact_* tables, not an L2-only clean DB"
                )
            db = clean_path(src)
            if not db.exists():
                # Degrade-safe (ADR-23): a missing clean DB is not fatal at
                # connect time — the query itself surfaces "no such table" only
                # if it genuinely needs the source.
                continue
            conn.execute(f"ATTACH DATABASE ? AS {src}", (_ro_uri(db),))
    except Exception:
        conn.close()
        raise
    return conn


def run_query(name: str, params: dict[str, Any] | None = None) -> tuple[list[tuple], list[str]]:
    # Containment: resolve under QUERIES_DIR and reject any path that escapes it
    # (e.g. `../secrets`), so a query name can only ever address a .sql file
    # inside the queries tree.
    queries_root = QUERIES_DIR.resolve()
    sql_path = (QUERIES_DIR / f"{name}.sql").resolve()
    if not sql_path.is_relative_to(queries_root):
        raise ValueError(f"query path escapes queries dir: {name}")
    if not sql_path.exists():
        raise FileNotFoundError(f"no such query: {name} (try --list)")
    sql = sql_path.read_text(encoding="utf-8")
    # Auto-supply NULL for any :param declared in the SQL but not passed, so a
    # windowed query (e.g. cost/by-model-window with :since/:until) falls back
    # to its all-time branch when called bare instead of raising a binding
    # error. Only fills MISSING keys; explicit params are untouched.
    bound = dict(params or {})
    for match in _NAMED_PARAM.findall(sql):
        bound.setdefault(match, None)
    conn = _connect(parse_required_sources(sql))
    try:
        cur = conn.execute(sql, bound)
        rows = cur.fetchall()
        cols = [d[0] for d in cur.description] if cur.description else []
        return rows, cols
    finally:
        conn.close()
