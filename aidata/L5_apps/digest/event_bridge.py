"""Bridge AIDash user events back into proposal, alert, and Falcon state."""

from __future__ import annotations

import json
import sqlite3
import subprocess
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path

from config import PROPOSALS_PATH

from L5_apps.digest.proposals import read_pending


def _append_jsonl(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _default_linear_runner(title: str, description: str) -> int:
    script = Path.home() / "Development/user-skills/skills/goal-task/scripts/linear-sync.py"
    result = subprocess.run(
        [str(script), "idea", "--title", title, "--description", description,
         "--mode", "auto"],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result.returncode


def _latest_events(events: list[dict]) -> dict[str, dict]:
    latest: dict[str, dict] = {}
    for event in events:
        ref = str(event.get("item_ref") or event.get("itemRef") or "").strip()
        action = str(event.get("action") or "").strip().lower()
        if ref and action in {"done", "undone"}:
            stamp = str(event.get("timestamp") or event.get("ts") or "")
            current = latest.get(ref)
            if current is None or stamp >= str(current.get("_stamp", "")):
                latest[ref] = {**event, "_stamp": stamp}
    return latest


def _resolve_attention(path: Path, ref: str) -> bool:
    if not path.exists():
        return False
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    changed = False
    items = data.get("items", []) if isinstance(data, dict) else data
    if isinstance(items, list):
        for item in items:
            if isinstance(item, dict) and item.get("ref") == ref:
                item["status"] = "resolved"
                item["resolvedAt"] = _now()
                changed = True
    if changed:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8")
    return changed


def _star_falcon(path: Path, request_id: str, timestamp: str) -> bool:
    if not path.exists():
        return False
    try:
        with sqlite3.connect(path) as conn:
            columns = {
                row[1] for row in conn.execute("PRAGMA table_info(requests)")
            }
            if "summary_json" not in columns:
                return False
            key_columns = [name for name in ("id", "request_id") if name in columns]
            if not key_columns:
                return False
            where = " OR ".join(f"{name} = ?" for name in key_columns)
            conn.execute(
                "UPDATE requests SET summary_json = json_set("
                "COALESCE(summary_json, '{}'), '$.starredAt', ?) WHERE "
                + where,
                (timestamp, *(request_id for _ in key_columns)),
            )
            return conn.total_changes > 0
    except sqlite3.Error:
        return False


def process_user_events(
    events: list[dict],
    *,
    proposals_path: Path | None = None,
    falcon_db_path: Path | None = None,
    attention_status_path: Path | None = None,
    linear_runner: Callable[[str, str], int] | None = None,
) -> dict:
    """Apply latest-wins event reductions and return explicit bridge counts."""
    proposal_path = proposals_path or PROPOSALS_PATH
    runner = linear_runner or _default_linear_runner
    result = {
        "resolved": 0, "undone": 0, "promoted": 0, "falcon_starred": 0,
        "ignored": 0, "errors": 0,
    }
    pending = {proposal.id: proposal for proposal in read_pending(proposal_path)}

    for ref, event in _latest_events(events).items():
        action = str(event.get("action") or "").lower()
        if action == "undone":
            result["undone"] += 1
            continue
        if ref.startswith("proposal://"):
            if action == "done":
                proposal = pending.get(ref.removeprefix("proposal://"))
                if proposal is not None:
                    _append_jsonl(proposal_path, {
                        "id": proposal.id, "ts": proposal.ts,
                        "agent": proposal.agent, "title": proposal.title,
                        "detail": proposal.detail, "priority": proposal.priority,
                        "status": "dismissed",
                    })
                    result["resolved"] += 1
                else:
                    result["ignored"] += 1
            continue
        if (
            ref.startswith("gtt://")
            and action == "done"
            and attention_status_path
            and _resolve_attention(attention_status_path, ref)
        ):
            result["resolved"] += 1

    for event in events:
        if str(event.get("action") or "").lower() != "star":
            continue
        ref = str(event.get("item_ref") or event.get("itemRef") or "").strip()
        if not ref:
            result["ignored"] += 1
        elif ref.startswith("proposal://"):
            proposal = pending.get(ref.removeprefix("proposal://"))
            if proposal is None:
                result["ignored"] += 1
                continue
            try:
                rc = runner(proposal.title, proposal.detail)
            except (OSError, subprocess.SubprocessError):
                rc = 1
            if rc == 0:
                _append_jsonl(proposal_path, {
                    "id": proposal.id, "status": "approved", "ts": _now(),
                    "source": "aidash",
                })
                result["promoted"] += 1
            else:
                result["errors"] += 1
        elif ref.startswith("falcon://request/"):
            request_id = ref.removeprefix("falcon://request/")
            if _star_falcon(falcon_db_path, request_id, _now()) if falcon_db_path else False:
                result["falcon_starred"] += 1
            else:
                result["ignored"] += 1
        else:
            result["ignored"] += 1
    return result
