"""mail_inbox adapter — cursor-watermarked local mail digest collector (DSH Mechanism 4).

Implements the DeepSeek Harness `008-cookbook` bookmark-cursor (`pull --after <cursor>`)
and idempotency-key (`reply --key <key>`) contract for local mail summaries:
  - Incrementally reads JSONL drop shards from `MAIL_INBOX_DROP_DIR`
    (`~/.aidash-state/mail-inbox-drop/`) and optionally macOS `Mail.app` JXA
    when `MAIL_INBOX_ENABLE_JXA` is enabled.
  - Passes all string fields through `redaction.redact_obj` before writing to L1
    raw (`rawio.write_raw`).
  - Extracts high-priority todos (`is_todo=1`) and `@mentions` (`has_mention=1`).
  - Persists `cursor` and bounded `replied_keys` in `state.json` under `mail_inbox`
    so restarts never replay old messages or duplicate handled replies.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess  # nosec B404 - optional macOS osascript JXA probe
from collections.abc import Callable, Sequence
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from cleanio import write_clean
from config import MAIL_INBOX_DROP_DIR, MAIL_INBOX_ENABLE_JXA
from rawio import read_raw, write_raw
from redaction import redact, redact_obj
from state import get_watermark, set_watermark
from timeutil import CST

SOURCE = "mail_inbox"
_REPLIED_LIMIT = 2048
_PREVIEW_CHARS = 240
_MENTION_RE = re.compile(r"(?:^|[\s(（\[【])@([A-Za-z0-9._-]+)")
_TODO_RE = re.compile(
    r"(?i)(?:\b(?:todo|action\s*required|urgent|asap|please\s+review|blocker|p0|p1)\b|"
    r"待办|请处理|需处理|尽快|紧急|待回复|请确认|审批)"
)

_CLEAN_DDL = """
CREATE TABLE mail_inbox_item (
    item_id TEXT PRIMARY KEY,
    cursor TEXT,
    dedup_key TEXT,
    received_at TEXT,
    cst_day TEXT,
    sender_domain TEXT,
    subject_preview TEXT,
    snippet_preview TEXT,
    has_mention INTEGER,
    is_todo INTEGER,
    priority TEXT,
    replied INTEGER
)
"""
_CLEAN_COLS = (
    "item_id",
    "cursor",
    "dedup_key",
    "received_at",
    "cst_day",
    "sender_domain",
    "subject_preview",
    "snippet_preview",
    "has_mention",
    "is_todo",
    "priority",
    "replied",
)

_JXA_SCRIPT = """
ObjC.import('stdlib');
function run() {
  try {
    const Mail = Application('Mail');
    if (!Mail.running()) return JSON.stringify([]);
    const inbox = Mail.inbox();
    const msgs = inbox.messages();
    const limit = Math.min(msgs.length, 25);
    const out = [];
    for (let i = 0; i < limit; i++) {
      const m = msgs[i];
      out.push({
        id: String(m.id()),
        message_id: String(m.messageId ? m.messageId() : m.id()),
        subject: String(m.subject ? m.subject() : ''),
        sender: String(m.sender ? m.sender() : ''),
        received_at: m.dateReceived ? m.dateReceived().toISOString() : '',
        snippet: String(m.content ? m.content() : '').slice(0, 300),
        flagged: Boolean(m.flaggedStatus ? m.flaggedStatus() : false),
        unread: !Boolean(m.readStatus ? m.readStatus() : true)
      });
    }
    return JSON.stringify(out);
  } catch (e) {
    return JSON.stringify([]);
  }
}
"""


def _load_source_state() -> dict[str, Any]:
    raw = get_watermark(SOURCE)
    if isinstance(raw, dict):
        cursor = str(raw.get("cursor") or "")
        keys = [str(k) for k in (raw.get("replied_keys") or []) if str(k).strip()]
        seen = [str(k) for k in (raw.get("ingested_keys") or []) if str(k).strip()]
        return {
            "cursor": cursor,
            "replied_keys": keys[-_REPLIED_LIMIT:],
            "ingested_keys": seen[-_REPLIED_LIMIT:],
        }
    if isinstance(raw, str) and raw.strip():
        return {"cursor": raw.strip(), "replied_keys": [], "ingested_keys": []}
    return {"cursor": "", "replied_keys": [], "ingested_keys": []}


def _save_source_state(
    cursor: str,
    replied_keys: Sequence[str],
    ingested_keys: Sequence[str] = (),
) -> dict[str, Any]:
    deduped_replied = list(dict.fromkeys(str(k) for k in replied_keys if str(k).strip()))
    deduped_ingested = list(dict.fromkeys(str(k) for k in ingested_keys if str(k).strip()))
    state_obj = {
        "cursor": str(cursor or ""),
        "replied_keys": deduped_replied[-_REPLIED_LIMIT:],
        "ingested_keys": deduped_ingested[-_REPLIED_LIMIT:],
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
    ts = _parse_iso_ts(rec.get("received_at") or rec.get("timestamp") or rec.get("ts"))
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
    ident = str(rec.get("message_id") or rec.get("item_id") or rec.get("id") or "").strip()
    if ident:
        return f"mail:{ident}"
    digest = hashlib.sha256(
        f"{rec.get('sender','')}|{rec.get('subject','')}|{rec.get('received_at','')}".encode()
    ).hexdigest()[:16]
    return f"mail:{digest}"


def _sender_domain(sender: Any) -> str:
    if not isinstance(sender, str) or not sender.strip():
        return ""
    match = re.search(r"@([A-Za-z0-9.\-]+\.[A-Za-z]{2,})", sender)
    return match.group(1).lower() if match else redact(sender.strip())[:60]


def _extract_signals(rec: dict[str, Any]) -> tuple[int, int, str]:
    subject = str(rec.get("subject") or rec.get("subject_preview") or "")
    snippet = str(rec.get("snippet") or rec.get("body") or rec.get("snippet_preview") or "")
    combined = f"{subject}\n{snippet}"
    has_mention = int(bool(rec.get("has_mention")) or bool(_MENTION_RE.search(combined)))
    is_todo = int(
        bool(rec.get("is_todo"))
        or bool(rec.get("flagged"))
        or has_mention == 1
        or bool(_TODO_RE.search(combined))
    )
    raw_prio = str(rec.get("priority") or "").lower()
    if raw_prio in {"high", "medium", "low"}:
        priority = raw_prio
    elif has_mention or bool(rec.get("flagged")) or bool(_TODO_RE.search(subject)):
        priority = "high"
    elif is_todo:
        priority = "medium"
    else:
        priority = "low"
    return has_mention, is_todo, priority


def _read_drop_records(drop_dir: Path) -> list[dict[str, Any]]:
    if not drop_dir.exists() or not drop_dir.is_dir():
        return []
    records: list[dict[str, Any]] = []
    for path in sorted(drop_dir.glob("*.jsonl")):
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
                records.append(obj)
    return records


def _read_jxa_records(
    jxa_runner: Callable[[], Sequence[dict[str, Any]]] | None = None,
) -> list[dict[str, Any]]:
    if jxa_runner is not None:
        try:
            return [dict(item) for item in jxa_runner() if isinstance(item, dict)]
        except Exception:  # noqa: BLE001
            return []
    if not MAIL_INBOX_ENABLE_JXA:
        return []
    try:
        proc = subprocess.run(
            ["/usr/bin/osascript", "-l", "JavaScript", "-e", _JXA_SCRIPT],
            capture_output=True,
            text=True,
            timeout=4,
            check=False,
        )
        if proc.returncode != 0 or not proc.stdout.strip():
            return []
        parsed = json.loads(proc.stdout.strip())
        return [item for item in parsed if isinstance(item, dict)] if isinstance(parsed, list) else []
    except Exception:  # noqa: BLE001
        return []


def pull(
    *,
    after: str | None = None,
    drop_dir: Path | None = None,
    jxa_runner: Callable[[], Sequence[dict[str, Any]]] | None = None,
    commit_cursor: bool = False,
) -> dict[str, Any]:
    """Pull mail summary items strictly after `after` cursor (or persisted cursor)."""
    state = _load_source_state()
    explicit_after = after is not None
    effective_after = str(after) if explicit_after else state["cursor"]
    replied_set = set(state["replied_keys"])
    ingested_list = list(state["ingested_keys"])
    ingested_set = set(ingested_list)

    target_dir = drop_dir if drop_dir is not None else MAIL_INBOX_DROP_DIR
    candidates = _read_drop_records(target_dir) + _read_jxa_records(jxa_runner)

    enriched: list[tuple[str, dict[str, Any]]] = []
    for idx, rec in enumerate(candidates):
        cur = _cursor_for_record(rec, idx)
        dedup_key = _dedup_key_for_record(rec)
        item_id = str(rec.get("item_id") or rec.get("message_id") or rec.get("id") or dedup_key)
        ts_dt = _parse_iso_ts(rec.get("received_at") or rec.get("timestamp") or rec.get("ts"))
        received_iso = ts_dt.astimezone(CST).isoformat() if ts_dt else str(rec.get("received_at") or "")
        cst_day = ts_dt.astimezone(CST).strftime("%Y-%m-%d") if ts_dt else str(rec.get("cst_day") or "")
        has_mention, is_todo, priority = _extract_signals(rec)
        subject_clean = redact(str(rec.get("subject") or rec.get("subject_preview") or ""))[:_PREVIEW_CHARS]
        snippet_clean = redact(str(rec.get("snippet") or rec.get("body") or rec.get("snippet_preview") or ""))[:_PREVIEW_CHARS]
        normalized_rec = redact_obj(
            {
                "item_id": item_id,
                "cursor": cur,
                "dedup_key": dedup_key,
                "received_at": received_iso,
                "cst_day": cst_day,
                "sender_domain": _sender_domain(rec.get("sender") or rec.get("from") or rec.get("sender_domain")),
                "subject_preview": subject_clean,
                "snippet_preview": snippet_clean,
                "has_mention": has_mention,
                "is_todo": is_todo,
                "priority": priority,
                "replied": int(dedup_key in replied_set or bool(rec.get("replied"))),
            }
        )
        enriched.append((cur, normalized_rec))

    enriched.sort(key=lambda pair: pair[0])
    seen_keys: set[str] = set()
    selected: list[dict[str, Any]] = []
    next_cursor = effective_after
    for cur, item in enriched:
        key = str(item["dedup_key"])
        if explicit_after:
            if effective_after and cur <= effective_after:
                continue
        elif key in ingested_set:
            next_cursor = max(next_cursor, cur)
            continue
        elif effective_after and cur <= effective_after and not ingested_set:
            # Legacy string-cursor state without ingested_keys: honor watermark cutoff
            continue
        if key in seen_keys or key in replied_set:
            next_cursor = max(next_cursor, cur)
            continue
        seen_keys.add(key)
        selected.append(item)
        next_cursor = max(next_cursor, cur)

    if commit_cursor and (next_cursor != state["cursor"] or selected):
        _save_source_state(
            next_cursor,
            state["replied_keys"],
            [*ingested_list, *(str(it["dedup_key"]) for it in selected)],
        )

    return {
        "ok": True,
        "source": SOURCE,
        "after": effective_after,
        "next_cursor": next_cursor,
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
        _save_source_state(state["cursor"], replied_keys, state["ingested_keys"])
    return {
        "ok": True,
        "source": SOURCE,
        "key": cleaned_key,
        "duplicate": already_replied,
        "note": redact(note) if note else "",
    }


def collect(
    *,
    drop_dir: Path | None = None,
    jxa_runner: Callable[[], Sequence[dict[str, Any]]] | None = None,
) -> int:
    """L1 collect: pull new items after watermark cursor, write to raw/, advance cursor."""
    try:
        batch = pull(after=None, drop_dir=drop_dir, jxa_runner=jxa_runner, commit_cursor=False)
    except Exception:  # noqa: BLE001 - ADR-23 degrade-not-crash
        return 0
    items = batch.get("items") or []
    state = _load_source_state()
    next_cursor = str(batch.get("next_cursor") or state["cursor"])
    if not items:
        if next_cursor != state["cursor"]:
            _save_source_state(next_cursor, state["replied_keys"], state["ingested_keys"])
        return 0
    written = write_raw(SOURCE, items)
    _save_source_state(
        next_cursor,
        state["replied_keys"],
        [*state["ingested_keys"], *(str(it["dedup_key"]) for it in items)],
    )
    return written


def normalize() -> int:
    """L2 normalize: rebuild clean/mail_inbox.db from raw shards."""
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
        has_mention, is_todo, priority = _extract_signals(rec)
        by_id[item_id] = {
            "item_id": item_id,
            "cursor": str(rec.get("cursor") or _cursor_for_record(rec)),
            "dedup_key": dedup_key,
            "received_at": str(rec.get("received_at") or ""),
            "cst_day": str(rec.get("cst_day") or ""),
            "sender_domain": _sender_domain(rec.get("sender_domain") or rec.get("sender") or ""),
            "subject_preview": redact(str(rec.get("subject_preview") or rec.get("subject") or ""))[:_PREVIEW_CHARS],
            "snippet_preview": redact(str(rec.get("snippet_preview") or rec.get("snippet") or ""))[:_PREVIEW_CHARS],
            "has_mention": has_mention,
            "is_todo": is_todo,
            "priority": priority,
            "replied": int(dedup_key in replied_set or bool(rec.get("replied"))),
        }
    rows = sorted(by_id.values(), key=lambda r: (r["cursor"], r["item_id"]))
    return write_clean(SOURCE, "mail_inbox_item", _CLEAN_DDL, rows, _CLEAN_COLS)


def _cli(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="mail_inbox.py")
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
