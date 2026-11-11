#!/usr/bin/env python3
"""One-click Work-PC exporter template for redacted Teams @mentions / pending replies / ADO reminders.

Exports cursor-ordered, redacted JSONL digest records into `~/.aidash-state/work-teams-drop/`
(or a custom OneDrive / iCloud / shared folder) for `adapters/work_teams_bridge.py` to
ingest incrementally via `pull --after <cursor>`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections.abc import Sequence
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_SECRET_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"\brvn_[A-Za-z0-9]{8,}"),
    re.compile(r"\bmul_[A-Za-z0-9]{8,}"),
    re.compile(r"\bsk-[A-Za-z0-9\-_]{16,}"),
    re.compile(r"\bghp_[A-Za-z0-9]{20,}"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"x-access-token:[^@\s/]+@"),
    re.compile(r"https://[^:@\s/]+:[^@\s/]+@github\.com"),
    re.compile(r"(?i)\bBearer\s+[A-Za-z0-9\-._~+/]{16,}=*"),
    re.compile(
        r'(?i)\b(token|password|passwd|secret|api[_-]?key|access[_-]?token)'
        r'\b\s*[:=]\s*["\']?[A-Za-z0-9\-._~+/]{12,}=*["\']?'
    ),
)
_EMAIL_RE = re.compile(r"\b[A-Za-z0-9._%+\-]+@([A-Za-z0-9.\-]+\.[A-Za-z]{2,})\b")


def sanitize_text(text: str) -> str:
    """Redact credentials and email local-parts before leaving the Work PC."""
    if not text:
        return ""
    cleaned = text
    for pat in _SECRET_PATTERNS:
        cleaned = pat.sub("<REDACTED>", cleaned)
    cleaned = _EMAIL_RE.sub(r"<REDACTED>@\1", cleaned)
    return cleaned.strip()


def build_export_record(raw: dict[str, Any], index: int = 0) -> dict[str, Any]:
    created_at = str(
        raw.get("created_at")
        or raw.get("timestamp")
        or datetime.now(timezone.utc).isoformat(timespec="seconds")  # noqa: UP017
    )
    raw_id = str(raw.get("item_id") or raw.get("id") or "").strip()
    if not raw_id:
        digest = hashlib.sha256(
            f"{created_at}|{raw.get('title','')}|{raw.get('summary','')}".encode()
        ).hexdigest()[:12]
        raw_id = f"wt-{digest}"
    cursor = str(raw.get("cursor") or f"{created_at.replace(':', '').replace('-', '')}#{raw_id}-{index:04d}")
    dedup_key = str(raw.get("dedup_key") or f"teams:{raw_id}")
    channel_kind = str(raw.get("channel_kind") or raw.get("kind") or "teams_mention")
    return {
        "item_id": raw_id,
        "cursor": cursor,
        "dedup_key": dedup_key,
        "created_at": created_at,
        "channel_kind": channel_kind,
        "thread_ref": sanitize_text(str(raw.get("thread_ref") or raw_id))[:120],
        "sender_alias": sanitize_text(str(raw.get("sender_alias") or raw.get("sender") or "work-colleague"))[:60],
        "title": sanitize_text(str(raw.get("title") or ""))[:200],
        "summary": sanitize_text(str(raw.get("summary") or raw.get("text") or ""))[:240],
        "has_mention": bool(raw.get("has_mention", True)),
        "needs_reply": bool(raw.get("needs_reply", True)),
        "priority": str(raw.get("priority") or "high"),
    }


def export_records(
    records: Sequence[dict[str, Any]],
    out_dir: Path,
    *,
    shard_name: str | None = None,
) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    day = datetime.now(timezone.utc).strftime("%Y-%m-%d")  # noqa: UP017
    target = out_dir / (shard_name or f"work-teams-{day}.jsonl")
    with target.open("a", encoding="utf-8") as fh:
        for idx, item in enumerate(records):
            if not isinstance(item, dict):
                continue
            built = build_export_record(item, idx)
            fh.write(json.dumps(built, ensure_ascii=False) + "\n")
    return target


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="export_work_teams_digest.py",
        description="Export redacted Work-PC Teams @mentions and ADO reminders to JSONL drop directory.",
    )
    parser.add_argument(
        "--input",
        default="-",
        help="Input JSON / JSONL file path or '-' for stdin.",
    )
    parser.add_argument(
        "--out-dir",
        default=str(Path.home() / ".aidash-state" / "work-teams-drop"),
        help="Target drop directory synced to personal Mac.",
    )
    parser.add_argument("--shard-name", default=None, help="Optional output JSONL filename.")
    args = parser.parse_args(argv)

    raw_text = (
        sys.stdin.read()
        if args.input == "-"
        else Path(args.input).expanduser().read_text(encoding="utf-8")
    )
    items: list[dict[str, Any]] = []
    stripped = raw_text.strip()
    if stripped.startswith("["):
        loaded = json.loads(stripped)
        if isinstance(loaded, list):
            items = [x for x in loaded if isinstance(x, dict)]
    else:
        for line in stripped.splitlines():
            if line.strip():
                obj = json.loads(line)
                if isinstance(obj, dict):
                    items.append(obj)

    out_path = export_records(items, Path(args.out_dir).expanduser(), shard_name=args.shard_name)
    print(json.dumps({"ok": True, "exported": len(items), "path": str(out_path)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
