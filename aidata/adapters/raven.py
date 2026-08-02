"""raven adapter — the cross-tool request ledger (richest source).

L1 collect: read-only SELECT from raven.db `requests` where timestamp > watermark.
L2 normalize: parse the heterogeneous session_id, split client/version, derive
cost from dim_model, drop dead columns.

Key caveat (verified from samples): raven `session_id` is a JSON blob carrying a
real UUID ONLY for claude-cli; codex/multica use `client::account` with no
conversation identity -> session_uuid NULL, has_session 0.
"""

from __future__ import annotations

import json
from typing import Any

from adapters.model_canon import model_canon
from config import RAVEN_DB
from rawio import write_raw, read_raw
from cleanio import write_clean
from sqlite_ro import query_ro
from state import get_watermark, set_watermark

SOURCE = "raven"

# Columns we keep (dead columns dropped: client_version, upstream,
# upstream_format, translated_model).
_KEEP = (
    "id", "timestamp", "path", "client_format", "model", "resolved_model",
    "stream", "input_tokens", "output_tokens", "total_tokens",
    "latency_ms", "ttft_ms", "status", "status_code", "upstream_status",
    "error_message", "account_name", "session_id", "client_name",
    "processing_ms", "strategy", "copilot_model", "routing_path",
    "stop_reason", "tool_call_count",
)

_BATCH = 20000


def collect() -> int:
    if not RAVEN_DB.exists():
        return 0
    watermark = get_watermark(SOURCE) or 0
    total = 0
    max_ts = watermark
    cols = ", ".join(_KEEP)

    # Page by timestamp window to bound memory (597k+ rows). Each page fetches
    # the next _BATCH rows strictly after the previous page's max timestamp.
    cursor = watermark
    while True:
        rows = query_ro(
            RAVEN_DB,
            f"SELECT {cols} FROM requests WHERE timestamp > ? "
            f"ORDER BY timestamp ASC LIMIT {_BATCH}",
            (cursor,),
        )
        if not rows:
            break
        total += write_raw(SOURCE, rows)
        page_max = max(int(r["timestamp"] or 0) for r in rows)
        max_ts = max(max_ts, page_max)
        if len(rows) < _BATCH or page_max <= cursor:
            break  # last page, or no forward progress (guard against ties)
        cursor = page_max

    if total:
        set_watermark(SOURCE, max_ts)
    return total


def _parse_session(raw_sid: str, client: str) -> tuple[str | None, bool]:
    """Extract a reliable conversation UUID. Only claude-cli qualifies."""
    if not raw_sid:
        return None, False
    # claude-cli: JSON blob {"device_id":..,"session_id":"<uuid>"}
    if raw_sid.lstrip().startswith("{"):
        try:
            inner = json.loads(raw_sid).get("session_id") or None
            return (inner, True) if inner else (None, False)
        except (json.JSONDecodeError, AttributeError):
            return None, False
    # codex/multica: "client/version::account" — no conversation identity
    return None, False


def _split_client(client_name: str) -> tuple[str, str | None]:
    """`claude-cli/2.1.205` -> ('claude-cli', '2.1.205')."""
    if not client_name:
        return "", None
    if "/" in client_name:
        base, _, ver = client_name.partition("/")
        return base, ver or None
    return client_name, None


def _load_prices() -> dict[str, dict[str, float]]:
    import csv
    from config import SCHEMA_DIR

    prices: dict[str, dict[str, float]] = {}
    csv_path = SCHEMA_DIR / "dim_model.csv"
    if not csv_path.exists():
        return prices
    with csv_path.open(newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            prices[r["model"]] = {
                "in": float(r["input_per_mtok"]),
                "out": float(r["output_per_mtok"]),
                "cr": float(r["cache_read_per_mtok"]),
                "cw": float(r["cache_write_per_mtok"]),
            }
    return prices


def _cost(model, itok, otok, prices) -> float | None:
    """Derive notional USD cost, matching price by canonical model name.

    NULL tokens -> NULL cost (don't guess). Unknown canon -> NULL cost.
    """
    p = prices.get(model_canon(model))
    if p is None or itok is None or otok is None:
        return None
    return round(itok / 1e6 * p["in"] + otok / 1e6 * p["out"], 6)


_CLEAN_DDL = """
CREATE TABLE req (
    request_id TEXT PRIMARY KEY, ts INTEGER, client TEXT, version TEXT,
    model TEXT, model_canon TEXT, resolved_model TEXT,
    input_tokens INTEGER, output_tokens INTEGER,
    total_tokens INTEGER, latency_ms INTEGER, ttft_ms INTEGER, status TEXT,
    cost_usd REAL, session_uuid TEXT, has_session INTEGER, tool_call_count INTEGER,
    strategy TEXT, path TEXT
)
"""
_CLEAN_COLS = (
    "request_id", "ts", "client", "version", "model", "model_canon",
    "resolved_model", "input_tokens", "output_tokens", "total_tokens",
    "latency_ms", "ttft_ms", "status", "cost_usd", "session_uuid",
    "has_session", "tool_call_count", "strategy", "path",
)


def normalize() -> int:
    prices = _load_prices()
    rows: list[dict[str, Any]] = []
    for rec in read_raw(SOURCE):
        client, version = _split_client(rec.get("client_name", ""))
        sess, has = _parse_session(rec.get("session_id", ""), client)
        model = rec.get("model")
        resolved_model = rec.get("resolved_model")
        # A handful of OpenAI-format requests carry an empty-string `model`
        # (upstream never echoed the requested name) but do carry a real
        # `resolved_model`. Original `model` column is kept untouched
        # (immutable raw field); only the *derived* canon/cost lookup falls
        # back to resolved_model so these rows aren't silently priceless.
        canon_source = model or resolved_model
        rows.append({
            "request_id": rec.get("id"),
            "ts": rec.get("timestamp"),
            "client": client,
            "version": version,
            "model": model,
            "model_canon": model_canon(canon_source),
            "resolved_model": resolved_model,
            "input_tokens": rec.get("input_tokens"),
            "output_tokens": rec.get("output_tokens"),
            "total_tokens": rec.get("total_tokens"),
            "latency_ms": rec.get("latency_ms"),
            "ttft_ms": rec.get("ttft_ms"),
            "status": rec.get("status"),
            "cost_usd": _cost(
                canon_source, rec.get("input_tokens"), rec.get("output_tokens"), prices
            ),
            "session_uuid": sess,
            "has_session": 1 if has else 0,
            "tool_call_count": rec.get("tool_call_count"),
            "strategy": rec.get("strategy"),
            "path": rec.get("path"),
        })
    return write_clean(SOURCE, "req", _CLEAN_DDL, rows, _CLEAN_COLS)
