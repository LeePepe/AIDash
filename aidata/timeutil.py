"""Shared CST / epoch time conversions (T2 dedup, top-level peer of config.py).

aidata reports on CST (Asia/Shanghai) calendar days with a FIXED +8h offset —
never the host's local timezone — so results are host-TZ-independent (ADR-22).
Six near-duplicate copies of these conversions lived in L5_apps/digest/cst.py,
L5_apps/digest/app.py, and adapters/{hermes_tools,gecko,github_repo,news,
browser_history}.py. This module is the single source of truth.

⚠️ These conversions are NOT interchangeable — each original had its own boundary
contract, and this module PRECISELY reproduces every one (the plan's hard
requirement). In particular:

  * ``epoch_ms_to_cst_day`` (was cst.cst_date_of_ms) takes **milliseconds** and
    **RAISES** on bad input (no guard) — matching the original.
  * ``epoch_s_to_cst_day`` (was hermes_tools._cst_day) takes **seconds**, returns
    ``None`` on bad input, and does **NOT** reject 0/negative (epoch 0 -> the
    1970 CST day) — matching the original.
  * ``epoch_s_to_cst_iso`` (was gecko.epoch_to_iso) takes **seconds**, returns
    ``None`` on bad input, and **DOES reject <= 0** — matching the original.
  * ``chrome_epoch_to_cst_iso`` (was browser_history.chrome_to_iso) does **NOT**
    apply the ``<= 0`` guard to the derived unix seconds (only chrome_to_unix's
    own guard applies) — matching the original, which differs from gecko's.

Adapters keep their existing public function names as thin wrappers over these
(``gk.epoch_to_iso``, ``bh.chrome_to_unix/chrome_to_iso``, ``gh._cst_today``,
``news._cst_today``, ``hermes._cst_day``, ``cst.cst_date_of_ms``, and each
module's ``_CST``) so test monkeypatch seams stay live.
"""

from __future__ import annotations

from datetime import datetime, timezone, timedelta

# CST = UTC+8, fixed (China has no DST).
CST = timezone(timedelta(hours=8))

# Chrome/WebKit epoch: microseconds since 1601-01-01 UTC (vs Unix's 1970). The
# gap is 11,644,473,600 seconds (369 years, incl. leap days). Verified against
# sqlite's datetime(t/1e6 - 11644473600,'unixepoch').
_CHROME_EPOCH_OFFSET_S = 11_644_473_600
_MICROS_PER_SEC = 1_000_000


def cst_today() -> str:
    """Current CST calendar day as 'YYYY-MM-DD' (real wall clock)."""
    return datetime.now(tz=CST).strftime("%Y-%m-%d")


def epoch_ms_to_cst_day(ts_ms: int) -> str:
    """UTC epoch **milliseconds** -> 'YYYY-MM-DD' in CST.

    No guard: RAISES on a missing/unparseable stamp (matches the original
    cst.cst_date_of_ms, whose only callers pass validated ints).
    """
    return datetime.fromtimestamp(ts_ms / 1000, tz=CST).strftime("%Y-%m-%d")


def epoch_s_to_cst_day(ts_s: float | int | str | None) -> str | None:
    """UTC epoch **seconds** (float) -> 'YYYY-MM-DD' in CST, or None if unparseable.

    Does NOT reject 0/negative (epoch 0 -> the 1970 CST day); matches the
    original hermes_tools._cst_day, which only guards against parse/range errors.
    """
    try:
        return datetime.fromtimestamp(float(ts_s), tz=CST).strftime("%Y-%m-%d")  # type: ignore[arg-type]
    except (TypeError, ValueError, OSError, OverflowError):
        return None


def epoch_s_to_cst_iso(epoch_s: int | float | None) -> str | None:
    """Unix epoch **seconds** -> ISO-8601 CST string, or None if invalid.

    e.g. 1785110400 -> '2026-07-27T08:00:00+08:00'. Returns None for a
    missing/zero/negative/unparseable stamp (matches gecko.epoch_to_iso — the
    ``<= 0`` rejection is deliberate so downstream never fabricates a 1970 date).
    """
    try:
        seconds = float(epoch_s)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    if seconds <= 0:
        return None
    try:
        return datetime.fromtimestamp(seconds, tz=CST).isoformat()
    except (OverflowError, OSError, ValueError):
        return None


def chrome_epoch_to_unix(chrome_time: int | float | None) -> float | None:
    """Chrome/WebKit epoch (µs since 1601) -> Unix epoch seconds (float).

    Returns None for a missing/zero/negative/invalid stamp so downstream never
    fabricates a 1601 or 1970 date (matches browser_history.chrome_to_unix).
    """
    try:
        micros = float(chrome_time)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None
    if micros <= 0:
        return None
    return micros / _MICROS_PER_SEC - _CHROME_EPOCH_OFFSET_S


def chrome_epoch_to_cst_iso(chrome_time: int | float | None) -> str | None:
    """Chrome epoch (µs since 1601) -> ISO-8601 CST string, or None.

    Matches browser_history.chrome_to_iso EXACTLY: the chrome->unix step applies
    its own ``<= 0`` guard, but the derived unix seconds are passed straight to
    fromtimestamp WITHOUT a second ``<= 0`` guard (unlike epoch_s_to_cst_iso).
    """
    unix = chrome_epoch_to_unix(chrome_time)
    if unix is None:
        return None
    try:
        return datetime.fromtimestamp(unix, tz=CST).isoformat()
    except (OverflowError, OSError, ValueError):
        return None
