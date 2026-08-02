"""browser_history adapter — local Chrome browsing history (domain-level signal).

The user wants a "what did I look up / which AI tools did I actually use" pulse
straight off the machine: which domains they visited and how often (github.com,
claude.ai, stackoverflow, docs sites …). Chrome stores this in a local SQLite
(`config.CHROME_HISTORY_DB`) whose `urls` table carries `url, title,
visit_count, last_visit_time`.

L1 collect: read-only SELECT of new `urls` rows past the watermark. Chrome holds
a write lock on the file while it runs, so a plain `mode=ro` open raises
"database is locked" — we open with `immutable=1` (via sqlite_ro's `immutable`
flag), which skips locking and reads the live file. `last_visit_time` is the
watermark; it is a Chrome/WebKit epoch (microseconds since 1601-01-01 UTC), NOT
a Unix time — see `chrome_to_unix`.

Privacy red line (STRICTER than any other source): a raw url can embed tokens in
its query string, internal hostnames, or private-page paths, and titles can leak
just as much. So even before rawio's mandatory redact pass, this adapter reduces
every url to `scheme://host/path` (query string + fragment DROPPED) and keeps
only a short, redacted title preview. Nothing with a `?query` ever reaches raw/.

L2 normalize: one row per reduced url (PK = the reduced url), carrying host,
path, title preview, visit_count, and last_visit as an ISO-8601 CST timestamp.
`host` is the core analysis dimension (group-by-domain). Last-write-wins per url.

Degrade-not-crash (ADR-23): Chrome not installed (no DB) → 0; a locked/corrupt DB
or any query failure → 0. collect() never raises.
"""

from __future__ import annotations

from typing import Any
from urllib.parse import urlsplit

from config import CHROME_HISTORY_DB
from timeutil import chrome_epoch_to_unix, chrome_epoch_to_cst_iso
from timeutil import CST as _CST  # noqa: F401 (re-export seam)
from rawio import write_raw, read_raw
from cleanio import write_clean
from sqlite_ro import query_ro
from state import get_watermark, set_watermark

SOURCE = "browser_history"

# Chrome-epoch constants + _CST re-exported from timeutil (seam). Chrome/WebKit
# epoch = µs since 1601; the µs offset + 1601->1970 gap live in timeutil now.

# Keep titles short and privacy-light; a preview is enough to eyeball a domain.
_TITLE_PREVIEW_MAX = 100

# Read-only SELECT of the only columns we need. immutable open handles the lock.
_SELECT = (
    "SELECT url, title, visit_count, last_visit_time "
    "FROM urls WHERE last_visit_time > ? ORDER BY last_visit_time ASC"
)


def chrome_to_unix(chrome_time: int | float | None) -> float | None:
    """Chrome/WebKit epoch (µs since 1601) -> Unix epoch seconds (thin wrapper; seam).

    Returns None for a missing/zero/negative/invalid stamp so downstream never
    fabricates a 1601 or 1970 date.
    """
    return chrome_epoch_to_unix(chrome_time)


def chrome_to_iso(chrome_time: int | float | None) -> str | None:
    """Chrome epoch -> ISO-8601 CST string (thin wrapper; seam)."""
    return chrome_epoch_to_cst_iso(chrome_time)


def reduce_url(url: str | None) -> tuple[str | None, str | None, str | None]:
    """Reduce a raw url to (reduced, host, path), dropping query + fragment.

    `reduced` is `scheme://host/path` — the privacy-safe key we store. The query
    string (where tokens/secrets hide) and fragment are discarded entirely. host
    is lower-cased for stable group-by. Returns (None, None, None) for a url with
    no web host (non-http(s) scheme like `chrome://`/`about:`, or malformed) so
    it is skipped.
    """
    if not url:
        return None, None, None
    try:
        parts = urlsplit(url)
    except ValueError:
        return None, None, None
    # Only real web pages. chrome://settings parses to hostname "settings"; the
    # scheme gate drops chrome://, about:, file://, javascript: etc. outright.
    if parts.scheme not in ("http", "https"):
        return None, None, None
    host = (parts.hostname or "").lower()
    if not host:
        return None, None, None
    path = parts.path or "/"
    return f"{parts.scheme}://{host}{path}", host, path


def _title_preview(title: str | None) -> str | None:
    """Trim a title to a short preview (redaction still happens in rawio)."""
    if not title:
        return None
    text = title.strip()
    return text[:_TITLE_PREVIEW_MAX] if text else None


def collect() -> int:
    """Collect new visits since the watermark. Returns count (0 on degrade)."""
    if not CHROME_HISTORY_DB.exists():
        return 0  # Chrome not installed / no default profile
    watermark = int(get_watermark(SOURCE) or 0)  # chrome epoch µs
    try:
        # immutable=1: Chrome locks the live file; this reads it anyway.
        rows = query_ro(CHROME_HISTORY_DB, _SELECT, (watermark,), immutable=True)
    except Exception:  # locked/corrupt/anything — degrade, never raise
        return 0
    if not rows:
        return 0

    records: list[dict[str, Any]] = []
    max_ts = watermark
    for r in rows:
        reduced, host, path = reduce_url(r.get("url"))
        if reduced is None:
            continue  # no host (chrome://, about:blank, malformed) — skip
        last_visit = r.get("last_visit_time")
        # Store ONLY the reduced url — the raw query string never lands in raw/.
        records.append({
            "url": reduced,
            "host": host,
            "path": path,
            "title_preview": _title_preview(r.get("title")),
            "visit_count": r.get("visit_count"),
            "last_visit_time": last_visit,  # chrome epoch µs (watermark source)
        })
        try:
            if last_visit is not None and int(last_visit) > max_ts:
                max_ts = int(last_visit)
        except (TypeError, ValueError):
            pass

    if not records:
        return 0
    n = write_raw(SOURCE, records)  # rawio.redact is the enforced red line
    if max_ts > watermark:
        set_watermark(SOURCE, max_ts)
    return n


_CLEAN_DDL = """
CREATE TABLE visit (
    url_id TEXT PRIMARY KEY,
    host TEXT,
    path TEXT,
    title_preview TEXT,
    visit_count INTEGER,
    last_visit_ts TEXT
)
"""
_CLEAN_COLS = ("url_id", "host", "path", "title_preview",
               "visit_count", "last_visit_ts")


def normalize() -> int:
    """One row per reduced url; last-write-wins; chrome epoch -> ISO CST."""
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        url_id = rec.get("url")
        if not url_id:
            continue
        rows[url_id] = {  # last write wins -> latest snapshot of each url
            "url_id": url_id,
            "host": rec.get("host"),
            "path": rec.get("path"),
            "title_preview": rec.get("title_preview"),
            "visit_count": rec.get("visit_count"),
            "last_visit_ts": chrome_to_iso(rec.get("last_visit_time")),
        }
    return write_clean(SOURCE, "visit", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS)
