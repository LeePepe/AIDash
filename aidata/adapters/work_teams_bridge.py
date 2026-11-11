"""work_teams_bridge adapter — cursor-watermarked Work-PC Teams & ADO digest collector (DSH Mechanism 4).

Implements the DeepSeek Harness `008-cookbook` bookmark-cursor (`pull --after <cursor>`)
and idempotency-key (`reply --key <key>`) contract for synced Work-PC Teams `@mentions`,
pending replies, and ADO reminders dropped under `WORK_TEAMS_DROP_DIR`
(`~/.aidash-state/work-teams-drop/`, synced via OneDrive / iCloud / private Blob).

Safety & idempotency guarantees:
  - Strictly read-only against the drop directory; degrades to 0 when absent/empty (ADR-23).
  - Redacts all strings via `redaction.redact_obj` before writing to L1 raw (`rawio.write_raw`).
  - Persists `cursor` and `replied_keys` in `state.json` under `work_teams_bridge` so
    restarts never replay already-ingested messages or re-notify handled threads.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections.abc import Sequence
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from cleanio import write_clean
from config import WORK_TEAMS_DROP_DIR
from rawio import read_raw, write_raw
from redaction import redact, redact_obj
from state import get_watermark, set_watermark
from timeutil import CST

SOURCE = "work_teams_bridge"
_REPLIED_LIMIT = 2048
_PREVIEW_CHARS = 240
_MENTION_RE = re.compile(r"(?:^|[\s(（\[【])@([A-Za-z0-9._-]+)")
_URGENT_RE = re.compile(
    r"(?i)(?:\b(?:mention|reply|blocker|ado|pr\s*review|build\s*broken|incident|icm|sev[0-2])\b|"
    r"待回复|提及|评审|催办|阻塞)"
)

_CLEAN_DDL = """
CREATE TABLE work_teams_item (
    item_id TEXT PRIMARY KEY,
    cursor TEXT,
    dedup_key TEXT,
    created_at TEXT,
    cst_day TEXT,
    channel_kind TEXT,
    thread_ref TEXT,
    sender_alias TEXT,
    title_preview TEXT,
    summary_preview TEXT,
    has_mention INTEGER,
    needs_reply INTEGER,
    priority TEXT,
    replied INTEGER
)
"""
_CLEAN_COLS = (
    "item_id",
    "cursor",
    "dedup_key",
    "created_at",
    "cst_day",
    "channel_kind",
    "thread_ref",
    "sender_alias",
    "title_preview",
    "summary_preview",
    "has_mention",
    "needs_reply",
    "priority",
    "replied",
)


def _load_source_state() -> dict[str, Any]:
    raw = get_watermark(SOURCE)
    if isinstance(raw, dict):
        cursor = str(raw.get("cursor") or "")
        keys = [str(k) for k in (raw.get("replied_keys") or []) if str(k).strip()]
        seen = [str(k) for k in (raw.get("ingested_keys") or []) if str(k).strip()]
        raw_sc = raw.get("shard_cursors")
        shard_cursors = (
            {str(k): str(v) for k, v in raw_sc.items() if str(k).strip() and str(v).strip()}
            if isinstance(raw_sc, dict)
            else {}
        )
        return {
            "cursor": cursor,
            "replied_keys": keys[-_REPLIED_LIMIT:],
            "ingested_keys": seen[-_REPLIED_LIMIT:],
            "shard_cursors": shard_cursors,
        }
    if isinstance(raw, str) and raw.strip():
        return {"cursor": raw.strip(), "replied_keys": [], "ingested_keys": [], "shard_cursors": {}}
    return {"cursor": "", "replied_keys": [], "ingested_keys": [], "shard_cursors": {}}


def _save_source_state(
    cursor: str,
    replied_keys: Sequence[str],
    ingested_keys: Sequence[str] = (),
    shard_cursors: dict[str, str] | None = None,
) -> dict[str, Any]:
    deduped_replied = list(dict.fromkeys(str(k) for k in replied_keys if str(k).strip()))
    deduped_ingested = list(dict.fromkeys(str(k) for k in ingested_keys if str(k).strip()))
    state_obj = {
        "cursor": str(cursor or ""),
        "replied_keys": deduped_replied[-_REPLIED_LIMIT:],
        "ingested_keys": deduped_ingested[-_REPLIED_LIMIT:],
        "shard_cursors": dict(shard_cursors or {}),
    }
    set_watermark(SOURCE, state_obj)
    return state_obj


def _parse_iso_ts(raw_ts: Any) -> datetime | None:
    if not isinstance(raw_ts, str) or not raw_ts.strip():
        return None
    val = raw_ts.strip().replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(val)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)  # noqa: UP017
    return dt.astimezone(timezone.utc)  # noqa: UP017


def _cursor_for_record(rec: dict[str, Any], index: int = 0) -> str:
    explicit = str(rec.get("cursor") or "").strip()
    if explicit:
        return explicit
    ts = _parse_iso_ts(rec.get("created_at") or rec.get("timestamp") or rec.get("ts"))
    ts_part = ts.strftime("%Y%m%dT%H%M%SZ") if ts else f"00000000T000000Z-{index:06d}"
    ident = str(
        rec.get("item_id")
        or rec.get("message_id")
        or rec.get("id")
        or hashlib.sha256(json.dumps(rec, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()[:12]
    ).strip()
    return f"{ts_part}#{ident}"


def _dedup_key_for_record(rec: dict[str, Any]) -> str:
    explicit = str(rec.get("dedup_key") or rec.get("reply_key") or "").strip()
    if explicit:
        return explicit
    ident = str(rec.get("item_id") or rec.get("message_id") or rec.get("id") or "").strip()
    if ident:
        return f"teams:{ident}"
    digest = hashlib.sha256(
        f"{rec.get('thread_ref','')}|{rec.get('title','')}|{rec.get('created_at','')}".encode()
    ).hexdigest()[:16]
    return f"teams:{digest}"


def _extract_signals(rec: dict[str, Any]) -> tuple[str, int, int, str]:
    raw_kind = str(rec.get("channel_kind") or rec.get("kind") or "teams_mention").strip().lower()
    if raw_kind not in {"teams_mention", "teams_reply", "ado_reminder", "work_watch"}:
        channel_kind = "ado_reminder" if "ado" in raw_kind else "teams_mention"
    else:
        channel_kind = raw_kind
    title = str(rec.get("title") or rec.get("title_preview") or "")
    summary = str(rec.get("summary") or rec.get("text") or rec.get("summary_preview") or "")
    combined = f"{title}\n{summary}"
    has_mention = int(
        bool(rec.get("has_mention"))
        or channel_kind == "teams_mention"
        or bool(_MENTION_RE.search(combined))
    )
    needs_reply = int(
        bool(rec.get("needs_reply"))
        or has_mention == 1
        or channel_kind in {"teams_reply", "ado_reminder"}
        or bool(_URGENT_RE.search(combined))
    )
    raw_prio = str(rec.get("priority") or "").lower()
    if raw_prio in {"high", "medium", "low"}:
        priority = raw_prio
    elif has_mention or channel_kind == "ado_reminder":
        priority = "high"
    elif needs_reply:
        priority = "medium"
    else:
        priority = "low"
    return channel_kind, has_mention, needs_reply, priority


def _read_drop_records(drop_dir: Path) -> list[dict[str, Any]]:
    if not drop_dir.exists() or not drop_dir.is_dir():
        return []
    records: list[dict[str, Any]] = []
    for path in sorted(drop_dir.rglob("*.jsonl")):
        try:
            shard_id = str(path.relative_to(drop_dir))
        except ValueError:
            shard_id = path.name
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            continue
        for line in lines:
            stripped = line.strip()
            if not stripped:
                continue
            try:
                obj = json.loads(stripped)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict):
                records.append({**obj, "_shard": shard_id})
    return records


def _persisted_raw_keys() -> set[str]:
    keys: set[str] = set()
    for rec in read_raw(SOURCE):
        if isinstance(rec, dict):
            keys.add(_dedup_key_for_record(rec))
    return keys


def pull(
    *,
    after: str | None = None,
    drop_dir: Path | None = None,
    commit_cursor: bool = False,
) -> dict[str, Any]:
    """Pull Work-PC Teams / ADO items strictly after `after` cursor (or persisted cursor)."""
    state = _load_source_state()
    explicit_after = after is not None
    effective_after = str(after) if explicit_after else state["cursor"]
    replied_set = set(state["replied_keys"])
    ingested_list = list(state["ingested_keys"])
    ingested_set = set(ingested_list) | (_persisted_raw_keys() if not explicit_after else set())
    shard_cursors: dict[str, str] = dict(state["shard_cursors"])

    target_dir = drop_dir if drop_dir is not None else WORK_TEAMS_DROP_DIR
    candidates = _read_drop_records(target_dir)

    enriched: list[tuple[str, str, dict[str, Any]]] = []
    for idx, rec in enumerate(candidates):
        shard_id = str(rec.get("_shard") or "_default")
        cur = _cursor_for_record(rec, idx)
        dedup_key = _dedup_key_for_record(rec)
        item_id = str(rec.get("item_id") or rec.get("message_id") or rec.get("id") or dedup_key)
        ts_dt = _parse_iso_ts(rec.get("created_at") or rec.get("timestamp") or rec.get("ts"))
        created_iso = ts_dt.astimezone(CST).isoformat() if ts_dt else str(rec.get("created_at") or "")
        cst_day = ts_dt.astimezone(CST).strftime("%Y-%m-%d") if ts_dt else str(rec.get("cst_day") or "")
        channel_kind, has_mention, needs_reply, priority = _extract_signals(rec)
        title_clean = redact(str(rec.get("title") or rec.get("title_preview") or ""))[:_PREVIEW_CHARS]
        summary_clean = redact(str(rec.get("summary") or rec.get("text") or rec.get("summary_preview") or ""))[:_PREVIEW_CHARS]
        sender_clean = redact(str(rec.get("sender_alias") or rec.get("sender") or "work-colleague"))[:60]
        thread_ref = redact(str(rec.get("thread_ref") or rec.get("thread_id") or item_id))[:120]
        normalized_rec = redact_obj(
            {
                "item_id": item_id,
                "cursor": cur,
                "dedup_key": dedup_key,
                "created_at": created_iso,
                "cst_day": cst_day,
                "channel_kind": channel_kind,
                "thread_ref": thread_ref,
                "sender_alias": sender_clean,
                "title_preview": title_clean,
                "summary_preview": summary_clean,
                "has_mention": has_mention,
                "needs_reply": needs_reply,
                "priority": priority,
                "replied": int(dedup_key in replied_set or bool(rec.get("replied"))),
            }
        )
        enriched.append((cur, shard_id, normalized_rec))

    enriched.sort(key=lambda triple: triple[0])
    seen_keys: set[str] = set()
    selected: list[dict[str, Any]] = []
    next_cursor = effective_after
    next_shard_cursors = dict(shard_cursors)
    for cur, shard_id, item in enriched:
        key = str(item["dedup_key"])
        shard_after = next_shard_cursors.get(shard_id, "")
        if explicit_after:
            if effective_after and cur <= effective_after:
                continue
        else:
            if key in ingested_set:
                next_cursor = max(next_cursor, cur)
                if cur > shard_after:
                    next_shard_cursors[shard_id] = cur
                continue
            if shard_after and cur <= shard_after:
                continue
            if not shard_cursors and not ingested_set and effective_after and cur <= effective_after:
                continue
        if key in seen_keys or key in replied_set:
            next_cursor = max(next_cursor, cur)
            if cur > shard_after:
                next_shard_cursors[shard_id] = cur
            continue
        seen_keys.add(key)
        selected.append(item)
        next_cursor = max(next_cursor, cur)
        if cur > shard_after:
            next_shard_cursors[shard_id] = cur

    if commit_cursor and (next_cursor != state["cursor"] or next_shard_cursors != shard_cursors or selected):
        _save_source_state(
            next_cursor,
            state["replied_keys"],
            [*ingested_list, *(str(it["dedup_key"]) for it in selected)],
            next_shard_cursors,
        )

    return {
        "ok": True,
        "source": SOURCE,
        "after": effective_after,
        "next_cursor": next_cursor,
        "shard_cursors": next_shard_cursors,
        "items": selected,
    }


def reply(*, key: str, note: str = "") -> dict[str, Any]:
    """Record an idempotent reply/ack key (`reply --key <key>`) so it is never re-triggered."""
    cleaned_key = str(key or "").strip()
    if not cleaned_key:
        raise ValueError("reply requires a non-empty --key")
    state = _load_source_state()
    replied_keys = list(state["replied_keys"])
    already_replied = cleaned_key in replied_keys
    if not already_replied:
        replied_keys.append(cleaned_key)
        _save_source_state(
            state["cursor"],
            replied_keys,
            state["ingested_keys"],
            state["shard_cursors"],
        )
    return {
        "ok": True,
        "source": SOURCE,
        "key": cleaned_key,
        "duplicate": already_replied,
        "note": redact(note) if note else "",
    }


def collect(*, drop_dir: Path | None = None) -> int:
    """L1 collect: pull new Work-PC Teams/ADO items after cursor, write to raw/, advance cursor."""
    try:
        batch = pull(after=None, drop_dir=drop_dir, commit_cursor=False)
    except Exception:  # noqa: BLE001 - ADR-23 degrade-not-crash
        return 0
    items = batch.get("items") or []
    state = _load_source_state()
    next_cursor = str(batch.get("next_cursor") or state["cursor"])
    next_shard_cursors = dict(batch.get("shard_cursors") or state["shard_cursors"])
    if not items:
        if next_cursor != state["cursor"] or next_shard_cursors != state["shard_cursors"]:
            _save_source_state(
                next_cursor,
                state["replied_keys"],
                state["ingested_keys"],
                next_shard_cursors,
            )
        return 0
    written = write_raw(SOURCE, items)
    _save_source_state(
        next_cursor,
        state["replied_keys"],
        [*state["ingested_keys"], *(str(it["dedup_key"]) for it in items)],
        next_shard_cursors,
    )
    return written


def normalize() -> int:
    """L2 normalize: rebuild clean/work_teams_bridge.db from raw shards."""
    state = _load_source_state()
    replied_set = set(state["replied_keys"])
    by_id: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        if not isinstance(rec, dict):
            continue
        dedup_key = _dedup_key_for_record(rec)
        item_id = str(rec.get("item_id") or dedup_key).strip()
        if not item_id:
            continue
        channel_kind, has_mention, needs_reply, priority = _extract_signals(rec)
        by_id[item_id] = {
            "item_id": item_id,
            "cursor": str(rec.get("cursor") or _cursor_for_record(rec)),
            "dedup_key": dedup_key,
            "created_at": str(rec.get("created_at") or ""),
            "cst_day": str(rec.get("cst_day") or ""),
            "channel_kind": channel_kind,
            "thread_ref": redact(str(rec.get("thread_ref") or item_id))[:120],
            "sender_alias": redact(str(rec.get("sender_alias") or rec.get("sender") or "work-colleague"))[:60],
            "title_preview": redact(str(rec.get("title_preview") or rec.get("title") or ""))[:_PREVIEW_CHARS],
            "summary_preview": redact(str(rec.get("summary_preview") or rec.get("summary") or ""))[:_PREVIEW_CHARS],
            "has_mention": has_mention,
            "needs_reply": needs_reply,
            "priority": priority,
            "replied": int(dedup_key in replied_set or bool(rec.get("replied"))),
        }
    rows = sorted(by_id.values(), key=lambda r: (r["cursor"], r["item_id"]))
    return write_clean(SOURCE, "work_teams_item", _CLEAN_DDL, rows, _CLEAN_COLS)


def _cli(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="work_teams_bridge.py")
    sub = parser.add_subparsers(dest="cmd", required=True)
    pull_p = sub.add_parser("pull")
    pull_p.add_argument("--after", default=None, help="Bookmark cursor to pull after.")
    pull_p.add_argument("--drop-dir", default=None, help="Optional override drop directory.")
    pull_p.add_argument("--commit", action="store_true", help="Persist advanced cursor.")

    reply_p = sub.add_parser("reply")
    reply_p.add_argument("--key", required=True, help="Idempotency key to mark replied.")
    reply_p.add_argument("--note", default="", help="Optional note.")

    args = parser.parse_args(argv)
    if args.cmd == "pull":
        res = pull(
            after=args.after,
            drop_dir=Path(args.drop_dir).expanduser() if args.drop_dir else None,
            commit_cursor=bool(args.commit),
        )
    else:
        res = reply(key=args.key, note=args.note)
    print(json.dumps(res, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(_cli())
