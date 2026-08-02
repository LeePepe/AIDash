"""Digest source-freshness gate — the integrity alarm (D).

The 04:00 digest chain builds from whatever landed, and always writes the local
archive (ADR-16 必成 sink). That resilience has a blind spot: when a source
silently degraded (multica watermark stuck → "0 issue"; github_repo skipped that
day → stale radar), the digest still renders, just with wrong/empty numbers, and
nobody notices for days.

This gate never blocks generation. After sources are fetched, it collects every
source whose `SourceHealth.state` is not "ok" and, if any, appends ONE loud line
to the shared cron-errors.log (the same log the snapshot cron uses) plus a
best-effort desktop notification — so an incomplete digest is visible the same
day and can be re-run.

Kept dependency-light and pure (`degraded_sources` / `format_alarm`) so it is
hermetically testable; the effectful `alarm_if_degraded` wires the log + notify.
"""

from __future__ import annotations

import os
from pathlib import Path

# The health-bearing DigestSources fields we gate on. Attribute name → the
# human label used in the alarm. Only sources whose staleness materially
# corrupts a headline number are listed (numbers users read + act on).
_GATED_FIELDS = ("multica", "ado", "repo_radar", "automation")

_AIDASH_STATE = Path(os.path.expanduser("~")) / "Development" / "AIDash" / ".aidash-state"
_CRON_ERR_LOG = _AIDASH_STATE / "cron-errors.log"


def degraded_sources(sources) -> list:
    """Return the SourceHealth of every gated source whose state isn't 'ok'.

    A state like 'stale' / 'error' / 'skipped:未采集' means a headline number in
    the digest is missing or wrong. 'ok' is the only healthy state.
    """
    out = []
    for field in _GATED_FIELDS:
        src = getattr(sources, field, None)
        health = getattr(src, "health", None)
        if health is None:
            continue
        if health.state != "ok":
            out.append(health)
    return out


def format_alarm(degraded: list, report_date: str) -> str:
    """One actionable line naming the report date + each degraded source.

    Empty string when nothing is degraded (caller writes nothing).
    """
    if not degraded:
        return ""
    parts = []
    for h in degraded:
        detail = f"({h.detail})" if getattr(h, "detail", None) else ""
        parts.append(f"{h.name}={h.state}{detail}")
    return (f"digest {report_date} 数据不全 — 以下源降级,日报数字可能缺失/过期: "
            + "; ".join(parts) + " — 建议重采后重跑 digest")


def alarm_if_degraded(sources, report_date: str,
                      *, log_path: Path | None = None,
                      notifier=None) -> str:
    """Write a loud line + notify when any gated source degraded. Best-effort.

    Never raises (a monitoring hiccup must not break the digest) and never
    blocks generation — returns the alarm string (or "" if all healthy) so
    callers/tests can observe what fired.
    """
    degraded = degraded_sources(sources)
    msg = format_alarm(degraded, report_date)
    if not msg:
        return ""
    path = log_path or _CRON_ERR_LOG
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        from datetime import datetime, timezone
        stamp = datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        with path.open("a", encoding="utf-8") as fh:
            fh.write(f"{stamp} — {msg}\n")
    except OSError:
        pass  # a log-write failure must not break the digest
    if notifier is not None:
        try:
            notifier("AIDash digest 数据不全", msg)
        except Exception:  # noqa: BLE001 - notify is a nicety, never a gate
            pass
    return msg
