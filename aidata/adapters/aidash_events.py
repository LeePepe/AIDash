"""aidash_events adapter — user star/todo feedback events from the AIDash app.

The AIDash macOS app records the user's interactions with each daily-briefing
card — marking a todo `done` or `star`-ing a radar item (e.g. a GitHub repo) —
and exposes them via `aidash events pull`. This adapter is the L1 collector that
pulls those feedback events back into aidata as an L2-only source (它是「已采集
反馈事件」，不进 warehouse、暂无 L4/L5 消费者): aidata now also sees how the user
reacted to the briefing it produced.

L1 collect: `aidash events pull --since <watermark> --json`, parse the envelope
(`{"data":{"count":N,"events":[...]},"ok":true}`), redact + append each event,
advance the watermark to the newest event `timestamp`. A living source (like
news / github_repo): 0 events today is a perfectly valid empty result, and once
the user starts interacting the next run eats the backlog.

L2 normalize: one row per event id (last-write-wins). `item_ref` (the starred
repo URL for radar events; NULL for whole-card events) is preserved verbatim so
a FUTURE join against github_repo's radar is possible — this adapter does NOT do
that join. `card_type` (spec 005 D2: the card's `CardType.rawValue` at the time
of the event, e.g. "insight"/"todoList") is preserved the same way — verbatim,
NULL when the source event has no `cardType` key (older app builds / forward-
compat, same posture as `item_ref`). It exists so L4 can aggregate whole-card
star interest PER CARD TYPE without joining back through the date-scoped
`_kuid` card id, which does not encode type (see aidata/L5_apps/digest/aidash.py
`_kuid`).

Degrade-not-crash (ADR-23): `events pull` rides XPC, which depends on the AIDash
app being alive and its mach service healthy — historically the flakiest link.
A missing CLI, a dead/unreachable app (XPC down), a timeout, a non-zero exit, or
an `ok:false` envelope all yield 0 written and NEVER raise. The app not running
is a normal state (symmetric with the push side's health handling), not an
error that should crash the whole `collect`.
"""

from __future__ import annotations

import glob
import json
import os
import subprocess  # nosec B404 - only via the injected _run_json runner
from pathlib import Path
from typing import Any

from config import AIDASH_BIN_FIXED, AIDASH_BIN_GLOB
from rawio import write_raw, read_raw
from cleanio import write_clean
from state import get_watermark, set_watermark

SOURCE = "aidash_events"

# XPC can be slow to broker the mach service; give it generous headroom before
# treating a hang as a degrade (the app may be cold-launching).
_TIMEOUT_S = 60

# Earliest window floor for the very first collect (no watermark yet). AIDash
# has no events before this; a fixed early date keeps the CLI call cheap while
# still back-filling anything that exists.
_EPOCH_SINCE = "2020-01-01"

_ACTIONS = ("done", "star")


def _aidash_bin() -> str | None:
    """Resolve the `aidash` CLI path, or None to degrade.

    Mirrors L5_apps/digest/aidash.resolve_aidash_bin WITHOUT importing L5 (layer
    boundary): prefer the FIXED install (outside DerivedData, rebuild-proof),
    else the newest DerivedData build (recipe glob — never `which aidash`).
    Returns None (→ degrade) when neither resolves; never raises.
    """
    try:
        if os.path.exists(AIDASH_BIN_FIXED):
            return AIDASH_BIN_FIXED
        candidates = glob.glob(str(Path.home() / AIDASH_BIN_GLOB))
        if not candidates:
            return None
        return max(candidates, key=lambda p: os.stat(p).st_mtime)
    except OSError:
        return None


def _run_json(args: list[str]) -> Any | None:
    """Run `aidash <args> --json` and return the parsed `data` payload, or None.

    None signals "degrade this collect" for EVERY non-happy path — a missing
    binary, a launch/XPC failure (non-zero exit or timeout: the app isn't up),
    unparseable output, or an `ok:false` envelope. This is deliberately
    indistinguishable to the caller: whether XPC is down or the app returned a
    logical error, the correct L1 behavior is the same — write nothing, don't
    crash (ADR-23). A well-formed `ok:true` envelope with 0 events returns the
    payload (its `events` list is empty) — that is success, not degrade.
    """
    binp = _aidash_bin()
    if not binp:
        return None
    try:
        proc = subprocess.run(  # nosec B603
            [binp, *args, "--json"],
            capture_output=True, text=True, timeout=_TIMEOUT_S,
        )
    except (OSError, subprocess.SubprocessError):
        # XPC not reachable / app not running / timed out → app-down is normal.
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    try:
        env = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None
    if not isinstance(env, dict) or not env.get("ok"):
        return None  # ok:false (or malformed) → treat as this run failing
    data = env.get("data")
    return data if isinstance(data, dict) else None


def _events_since(watermark: str | None) -> list[dict[str, Any]] | None:
    """Pull events with timestamp >= watermark (or the epoch floor). None=degrade."""
    since = watermark or _EPOCH_SINCE
    data = _run_json(["events", "pull", "--since", since])
    if data is None:
        return None
    events = data.get("events")
    return events if isinstance(events, list) else []


def collect() -> int:
    """Pull new feedback events, redact+append, advance the timestamp watermark.

    Returns records written (0 on any degrade path: no CLI, XPC down, timeout,
    ok:false, OR a legitimately empty result). Never raises — the app being
    down is the common case and must not fail the whole `collect` run.
    """
    watermark = get_watermark(SOURCE)
    events = _events_since(watermark)
    if not events:  # None (degrade) or [] (empty) → nothing to write
        return 0

    # Keep only well-formed events carrying an id + timestamp we can key/window on.
    batch = [e for e in events
             if isinstance(e, dict) and e.get("id") and e.get("timestamp")]
    if not batch:
        return 0

    # write_raw redacts every string value (rawio's enforced red line) before
    # append — itemRef is a public repo URL, but the red line stays uniform.
    written = write_raw(SOURCE, batch)

    newest = max(str(e["timestamp"]) for e in batch)  # ISO8601 sorts lexically
    if watermark is None or newest > watermark:
        set_watermark(SOURCE, newest)
    return written


_CLEAN_DDL = """
CREATE TABLE user_event (
    event_id TEXT PRIMARY KEY,
    ts TEXT,
    device TEXT,
    card_id TEXT,
    action TEXT,
    item_ref TEXT,
    card_type TEXT
)
"""
_CLEAN_COLS = ("event_id", "ts", "device", "card_id", "action", "item_ref",
              "card_type")


def _norm_action(action: Any) -> str | None:
    """Keep only the known actions (done/star); anything else → NULL."""
    return action if action in _ACTIONS else None


def normalize() -> int:
    """One row per event id (last-write-wins). item_ref/card_type preserved
    verbatim.

    item_ref is the starred repo URL for radar events and NULL for whole-card
    events; it is kept as-is to enable a FUTURE join with github_repo's radar —
    NOT performed here. card_type (spec 005 D2) is the emitting card's type
    (e.g. "insight"), NULL for events from app builds that predate the field —
    forward-compat, same posture as item_ref.
    """
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        eid = rec.get("id")
        if not eid:
            continue
        rows[eid] = {  # last write wins → latest snapshot of each event
            "event_id": eid,
            "ts": rec.get("timestamp"),
            "device": rec.get("device"),
            "card_id": rec.get("cardId"),
            "action": _norm_action(rec.get("action")),
            "item_ref": rec.get("itemRef"),  # None stays None (whole-card event)
            "card_type": rec.get("cardType"),  # None on events without the key
        }
    return write_clean(SOURCE, "user_event", _CLEAN_DDL, list(rows.values()),
                       _CLEAN_COLS)
