"""gecko adapter — macOS menu-bar screen-time tracker (app-focus time signal).

gecko (ai.hexly.gecko) sits in the menu bar and logs one row per foreground
"focus session": which app held focus, its window title, an optional URL/tab
(when the app is a browser), and how long the session lasted. That fills the one
dimension every existing L1 source lacks — ATTENTION / TIME ALLOCATION: where the
hours actually went, per app, per day. Everything else measures *output* (commits,
PRs, tokens, requests); this measures *where focus was spent*.

L1 collect: read-only SELECT of new `focus_sessions` rows past the watermark
(`start_time`, epoch SECONDS float — same clock as state_db.started_at). One row
per session.

READ MODE — the critical, easy-to-get-wrong bit (opposite of browser_history):
gecko writes in WAL mode. Opening with `immutable=1` (the way browser_history
opens Chrome to dodge Chrome's write lock) reads the *base* file only and MISSES
everything still sitting in the -wal file — verified on this machine: an immutable
open saw an EMPTY table while a plain `mode=ro` open read all 12 live rows. So this
adapter MUST use a plain `mode=ro` open (query_ro's default `immutable=False`).
Do NOT "unify" this to immutable=True — that silently drops the newest sessions.
A plain ro open of the live WAL DB is fine in practice; any "database is locked"
or corruption is caught and degraded to 0 (never raises).

Privacy red line (as strict as browser_history): `window_title`, `tab_title` and
any URL can leak. URLs get reduced to host + path (query string + fragment
DROPPED — that's where tokens hide) BEFORE anything is written to raw/, mirroring
browser_history. `window_title` / `tab_title` are kept (they are the analysis
payload, not pure risk like a query string) but every record still passes through
rawio's mandatory redact() pass. `synced_at` (gecko's cloud-sync bookkeeping) is
never read — no analytic value, pure noise.

L2 normalize: one row per session (PK = gecko's `id`), last-write-wins by id.
`ts` is start_time rendered as an ISO-8601 CST string (matches browser_history /
news for human-readable clean output); `duration_sec` is the raw seconds.

Degrade-not-crash (ADR-23): gecko not installed (no DB) → 0; locked/corrupt DB or
any query failure → 0; empty result → 0. collect() never raises.
"""

from __future__ import annotations

from typing import Any
from urllib.parse import urlsplit

from config import GECKO_DB
from timeutil import epoch_s_to_cst_iso
from timeutil import CST as _CST  # noqa: F401 (re-export seam)
from rawio import write_raw, read_raw
from cleanio import write_clean
from sqlite_ro import query_ro
from state import get_watermark, set_watermark

SOURCE = "gecko"

# _CST re-exported from timeutil for any importer that referenced it (seam).

# Read-only SELECT of the columns we need. `synced_at` is deliberately NOT read
# (cloud-sync bookkeeping, no analytic value). start_time is the watermark.
# NOTE: opened via a PLAIN mode=ro (immutable=False) — see module docstring for
# why immutable would drop WAL-resident rows.
_SELECT = (
    "SELECT id, app_name, window_title, url, start_time, end_time, duration, "
    "bundle_id, tab_title, tab_count "
    "FROM focus_sessions WHERE start_time > ? ORDER BY start_time ASC"
)


def epoch_to_iso(epoch_s: int | float | None) -> str | None:
    """Unix epoch SECONDS -> ISO-8601 CST string, or None (thin wrapper; seam).

    e.g. 1785110400 -> '2026-07-27T08:00:00+08:00'. Rejects zero/negative so
    downstream never fabricates a 1970 date.
    """
    return epoch_s_to_cst_iso(epoch_s)


def reduce_url(url: str | None) -> tuple[str | None, str | None]:
    """Reduce a raw URL to (host, path), dropping query + fragment.

    Same privacy reduction as browser_history: the query string (where
    tokens/secrets hide) and fragment are discarded entirely; host is
    lower-cased for stable group-by. Returns (None, None) for a falsy URL, a
    non-http(s) scheme, or a malformed/hostless URL.
    """
    if not url:
        return None, None
    try:
        parts = urlsplit(url)
    except ValueError:
        return None, None
    if parts.scheme not in ("http", "https"):
        return None, None
    host = (parts.hostname or "").lower()
    if not host:
        return None, None
    return host, (parts.path or "/")


def _new_watermark(rows: list[dict[str, Any]], start: float) -> float:
    """Max start_time across rows, floored at the current watermark."""
    hi = start
    for r in rows:
        try:
            st = float(r.get("start_time"))  # type: ignore[arg-type]
        except (TypeError, ValueError):
            continue
        if st > hi:
            hi = st
    return hi


def collect() -> int:
    """Collect new focus sessions since the watermark. Returns count (0 on degrade)."""
    if not GECKO_DB.exists():
        return 0  # gecko not installed
    watermark = float(get_watermark(SOURCE) or 0)  # epoch seconds
    try:
        # PLAIN mode=ro (immutable=False, the default) — a WAL-mode live DB;
        # immutable would miss rows still in the -wal file. See module docstring.
        rows = query_ro(GECKO_DB, _SELECT, (watermark,))
    except Exception:  # locked/corrupt/anything — degrade, never raise
        return 0
    if not rows:
        return 0

    records: list[dict[str, Any]] = []
    for r in rows:
        sid = r.get("id")
        if not sid:
            continue  # no primary key — cannot key the session
        host, path = reduce_url(r.get("url"))  # query string never reaches raw/
        records.append({
            "id": sid,
            "app_name": r.get("app_name"),
            "window_title": r.get("window_title"),  # redacted by rawio
            "url_host": host,
            "url_path": path,
            "start_time": r.get("start_time"),  # epoch seconds (watermark source)
            "duration": r.get("duration"),      # seconds
            "bundle_id": r.get("bundle_id"),
            "tab_title": r.get("tab_title"),     # redacted by rawio
            "tab_count": r.get("tab_count"),
        })

    if not records:
        return 0
    n = write_raw(SOURCE, records)  # rawio.redact is the enforced red line
    max_ts = _new_watermark(rows, watermark)
    if max_ts > watermark:
        set_watermark(SOURCE, max_ts)
    return n


_CLEAN_DDL = """
CREATE TABLE focus_session (
    session_id TEXT PRIMARY KEY,
    ts TEXT,
    app_name TEXT,
    bundle_id TEXT,
    window_title TEXT,
    url_host TEXT,
    url_path TEXT,
    tab_title TEXT,
    tab_count INTEGER,
    duration_sec REAL
)
"""
_CLEAN_COLS = ("session_id", "ts", "app_name", "bundle_id", "window_title",
               "url_host", "url_path", "tab_title", "tab_count", "duration_sec")


def normalize() -> int:
    """One row per session (PK = id); last-write-wins; start_time -> ISO CST."""
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        sid = rec.get("id")
        if not sid:
            continue
        rows[sid] = {  # last write wins -> latest snapshot of each session id
            "session_id": sid,
            "ts": epoch_to_iso(rec.get("start_time")),
            "app_name": rec.get("app_name"),
            "bundle_id": rec.get("bundle_id"),
            "window_title": rec.get("window_title"),
            "url_host": rec.get("url_host"),
            "url_path": rec.get("url_path"),
            "tab_title": rec.get("tab_title"),
            "tab_count": rec.get("tab_count"),
            "duration_sec": rec.get("duration"),
        }
    return write_clean(SOURCE, "focus_session", _CLEAN_DDL,
                       list(rows.values()), _CLEAN_COLS)
