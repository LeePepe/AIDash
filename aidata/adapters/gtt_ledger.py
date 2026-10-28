"""Collect and normalize goal-task ledgers, including exported bundles."""

from __future__ import annotations

import hashlib
import json
import re
import socket
import tarfile
from collections.abc import Iterable
from pathlib import Path
from typing import Any

from cleanio import write_clean
from config import GTT_HANDOFF_ROOTS, GTT_XFER_DIR
from rawio import read_raw, write_raw
from redaction import redact
from state import get_watermark, set_watermark

SOURCE = "gtt_ledger"
_EVENT = re.compile(r"^\s*-\s*(?P<ts>\S+)\s*\|\s*EVT=(?P<evt>\S+)\s*\|\s*(?P<rest>.*)$")
_KV = re.compile(r"(?P<key>[A-Za-z_]+)=(?P<value>.*?)(?=\s+[A-Za-z_]+=|$)")
_HOME = re.compile(r"(?<![\w-])(?:/Users|/home)/[^/\s]+")


def _machine_id() -> str:
    return socket.gethostname().split(".", 1)[0] or "unknown"


def _normalize_path(value: str) -> str:
    return _HOME.sub("~", value)


def _bundle_records(path: Path) -> Iterable[dict[str, Any]]:
    machine_id = path.stem.removeprefix("gtt-bundle-") or "bundle"
    if path.suffix == ".tgz":
        try:
            with tarfile.open(path, "r:gz") as archive:
                for member in archive.getmembers():
                    if not member.isfile() or Path(member.name).name not in {"ledger.md", "goal.md", "queue.json"}:
                        continue
                    content = archive.extractfile(member)
                    if content is None:
                        continue
                    rel_path = member.name.lstrip("./")
                    record_type = {
                        "ledger.md": "ledger",
                        "goal.md": "goal",
                        "queue.json": "queue",
                    }[Path(rel_path).name]
                    yield {
                        "machine_id": machine_id,
                        "goal_id": Path(rel_path).parts[0],
                        "rel_path": rel_path,
                        "record_type": record_type,
                        "content": _normalize_path(content.read().decode("utf-8")),
                    }
        except (OSError, tarfile.TarError, UnicodeDecodeError):
            return
        return
    try:
        with path.open(encoding="utf-8") as fh:
            for line in fh:
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if (
                    item.get("collector") in (None, "gtt")
                    and item.get("record_type") in {"ledger", "goal", "queue"}
                    and item.get("content")
                ):
                    yield {
                        "machine_id": item.get("machine_id") or "unknown",
                        "goal_id": item.get("goal_id") or Path(item.get("rel_path", "")).parts[0],
                        "rel_path": item.get("rel_path", ""),
                        "record_type": item["record_type"],
                        "content": _normalize_path(str(item["content"])),
                    }
    except OSError:
        return


def _local_records() -> Iterable[dict[str, Any]]:
    for root in GTT_HANDOFF_ROOTS:
        try:
            children = sorted(p for p in root.iterdir() if p.is_dir() and not p.name.startswith("_"))
        except OSError:
            continue
        for goal_dir in children:
            for name, record_type in (("ledger.md", "ledger"), ("goal.md", "goal"), ("queue.json", "queue")):
                path = goal_dir / name
                try:
                    content = _normalize_path(path.read_text(encoding="utf-8"))
                except OSError:
                    continue
                yield {
                    "machine_id": _machine_id(),
                    "goal_id": goal_dir.name,
                    "rel_path": f"{goal_dir.name}/{name}",
                    "record_type": record_type,
                    "content": content,
                }


def collect() -> int:
    from adapters import cloud_sync

    cloud_sync.pull_remote_batches()
    records = list(_local_records())
    try:
        bundles = sorted(GTT_XFER_DIR.rglob("*.jsonl"))
        bundles.extend(sorted(GTT_XFER_DIR.rglob("*.tgz")))
    except OSError:
        bundles = []
    for bundle in bundles:
        records.extend(_bundle_records(bundle))
    old = dict(get_watermark(SOURCE) or {})
    changed = []
    current: dict[str, str] = {}
    for record in records:
        key = f"{record['machine_id']}:{record['rel_path']}"
        digest = hashlib.sha256(str(record["content"]).encode()).hexdigest()
        current[key] = digest
        if old.get(key) != digest:
            changed.append(record)
    count = write_raw(SOURCE, changed)
    set_watermark(SOURCE, current)
    return count


def _pairs(text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    if "|" in text:
        for segment in text.split("|"):
            matches = list(_KV.finditer(segment))
            if matches:
                for match in matches:
                    fields[match.group("key")] = match.group("value").strip()
            else:
                match = re.match(r"\s*([A-Za-z_]+)=(.*?)\s*$", segment)
                if match:
                    fields[match.group(1)] = match.group(2).strip()
        return fields
    return {m.group("key"): m.group("value").strip().rstrip("|").strip() for m in _KV.finditer(text)}


def _static_status(content: str) -> str:
    statuses = [
        match.group(2).strip().lower()
        for match in re.finditer(
            r"(?im)^\s*\|\s*([A-Za-z][\w-]*)\s*\|\s*([^|]+)\|", content
        )
        if match.group(1).lower() not in {"task", "id", "tasks", "goal"}
        and match.group(2).strip().lower() not in {"status", "state"}
    ]
    if statuses:
        if all(status in {"done", "completed", "merged"} for status in statuses):
            return "done"
        if any(status in {"blocked", "paused", "hold"} for status in statuses):
            return "blocked"
        return "active"
    match = re.search(r"(?im)^\s*[-*]?\s*(?:status|状态)\s*[:|：]\s*`?([A-Za-z_]+)", content)
    if not match:
        match = re.search(r"(?im)^\s*\|\s*status\s*\|\s*([A-Za-z_]+)", content)
    status = (match.group(1).lower() if match else "")
    return "done" if status in {"done", "completed"} else "active" if status in {"active", "in_progress"} else "unknown"


def _task_ids(content: str) -> set[str]:
    return {
        match.group(1)
        for match in re.finditer(r"(?im)^\s*\|\s*([A-Za-z][\w-]*)\s*\|", content)
        if match.group(1).lower() not in {"id", "task", "tasks", "goal"}
    }


def _header_value(content: str, *names: str) -> str | None:
    wanted = {name.lower() for name in names}
    for line in content.splitlines():
        match = re.match(r"\s*[-*]?\s*(?:\*\*)?([^:*|]+)(?:\*\*)?\s*[:|]\s*(.+)", line)
        if match and match.group(1).strip().lower() in wanted:
            return match.group(2).strip().strip("`")
    return None


def _parse_event(line: str, line_number: int, goal_id: str) -> dict[str, Any] | None:
    match = _EVENT.match(line)
    if not match:
        return None
    fields = _pairs(match.group("rest"))
    event_id = fields.get("id")
    note = fields.get("note")
    ref = fields.get("ref")
    text = f"{ref or ''} {note or ''}"
    sha = re.search(r"\b[0-9a-f]{7,40}\b", text, re.IGNORECASE)
    pr = re.search(r"\bPR#?(\d+)\b", text, re.IGNORECASE)
    return {
        "event_uid": f"{event_id or 'none'}:"
        f"{hashlib.sha256(line.encode()).hexdigest()[:8]}",
        "goal_uid": goal_id,
        "machine_id": fields.get("machine", "unknown"),
        "goal_id": goal_id,
        "line_no": line_number,
        "event_id": event_id or "none",
        "ts": match.group("ts"),
        "evt_type": match.group("evt"),
        "task_id": fields.get("task"),
        "actor_from": fields.get("from"),
        "actor_to": fields.get("to"),
        "ref_artifact": ref,
        "head_sha": sha.group(0) if sha else None,
        "pr_number": int(pr.group(1)) if pr else None,
        "model_id": fields.get("model"),
        "contract_sha": fields.get("contract"),
        "is_bot_bypass": 1 if fields.get("bypass", "").lower() in {"1", "true", "yes"} else 0,
        "blocker_class": fields.get("blocker_class") or fields.get("blocker"),
        "note_preview": redact(note or "")[:300] or None,
    }


def _derived_status(content: str, events: list[dict[str, Any]]) -> str:
    open_blockers: set[str | None] = set()
    for event in events:
        task = event["task_id"]
        if event["evt_type"] in {"TASK_BLOCKED", "REVIEW_FAIL", "PAUSE", "HOLD"}:
            open_blockers.add(task)
        elif event["evt_type"] == "RESOLVED":
            if task:
                open_blockers.discard(task)
            else:
                open_blockers.clear()
        elif event["evt_type"] in {"DONE", "MERGED", "REVIEW_PASS"}:
            open_blockers.discard(task)
    if open_blockers:
        return "blocked"
    if any(e["evt_type"] == "GOAL_DONE" for e in events):
        return "done"
    tasks = _task_ids(content)
    completed = {e["task_id"] for e in events if e["evt_type"] in {"DONE", "MERGED"} and e["task_id"]}
    return "done" if tasks and tasks <= completed else "in_progress"


_GOAL_DDL = """
CREATE TABLE goal (
    goal_uid TEXT PRIMARY KEY, machine_id TEXT NOT NULL, goal_id TEXT NOT NULL,
    title TEXT, owner TEXT, coordinator_bot TEXT, tl_agent TEXT, tl_model TEXT,
    contract_sha TEXT, static_header_status TEXT, derived_actual_status TEXT,
    is_status_drifted INTEGER, task_total_count INTEGER, task_done_count INTEGER,
    task_blocked_count INTEGER, created_at TEXT, last_event_at TEXT, ledger_sha256 TEXT
)
"""
_EVENT_DDL = """
CREATE TABLE gtt_event (
    event_uid TEXT PRIMARY KEY, goal_uid TEXT NOT NULL, machine_id TEXT NOT NULL,
    goal_id TEXT NOT NULL, line_no INTEGER NOT NULL, event_id TEXT NOT NULL,
    ts TEXT NOT NULL, evt_type TEXT NOT NULL, task_id TEXT, actor_from TEXT,
    actor_to TEXT, ref_artifact TEXT, head_sha TEXT, pr_number INTEGER,
    model_id TEXT, contract_sha TEXT, is_bot_bypass INTEGER, blocker_class TEXT,
    note_preview TEXT
)
"""


def normalize() -> int:
    latest: dict[tuple[str, str], dict[str, Any]] = {}
    for record in read_raw(SOURCE):
        if record.get("record_type") != "ledger" or not record.get("goal_id"):
            continue
        key = (record.get("machine_id", "unknown"), record["goal_id"])
        candidate_ts = str(record.get("last_event_at") or record.get("mtime_iso")
                           or record.get("exported_at") or "")
        existing_ts = str(latest.get(key, {}).get("last_event_at")
                          or latest.get(key, {}).get("mtime_iso")
                          or latest.get(key, {}).get("exported_at") or "")
        if candidate_ts >= existing_ts:
            latest[key] = record
    goals: list[dict[str, Any]] = []
    events: list[dict[str, Any]] = []
    for (machine_id, goal_id), record in latest.items():
        content = str(record.get("content", ""))
        parsed = [_parse_event(line, no, goal_id) for no, line in enumerate(content.splitlines(), 1)]
        parsed_events = [event for event in parsed if event]
        for event in parsed_events:
            event["machine_id"] = machine_id
            event["event_uid"] = f"{machine_id}:{goal_id}:{event['event_uid']}"
            event["goal_uid"] = f"{machine_id}:{goal_id}"
            events.append(event)
        derived = _derived_status(content, parsed_events)
        static = _static_status(content)
        title = next((line[2:].strip() for line in content.splitlines() if line.startswith("# Goal:")), goal_id)
        task_ids = _task_ids(content)
        done_count = len({e["task_id"] for e in parsed_events if e["task_id"] and e["evt_type"] in {"DONE", "MERGED"}})
        goals.append({
            "goal_uid": f"{machine_id}:{goal_id}", "machine_id": machine_id, "goal_id": goal_id,
            "title": title, "owner": _header_value(content, "owner"),
            "coordinator_bot": _header_value(content, "coordinator", "coordinator_bot"),
            "tl_agent": _header_value(content, "tl_agent", "tl agent"),
            "tl_model": _header_value(content, "tl_model", "tl model"),
            "contract_sha": next((e["contract_sha"] for e in parsed_events if e["contract_sha"]), None),
            "static_header_status": static, "derived_actual_status": derived,
            "is_status_drifted": int(static != derived), "task_total_count": len(task_ids),
            "task_done_count": done_count,
            "task_blocked_count": len({e["task_id"] for e in parsed_events if e["task_id"] and e["evt_type"] == "TASK_BLOCKED"}),
            "created_at": parsed_events[0]["ts"] if parsed_events else None,
            "last_event_at": parsed_events[-1]["ts"] if parsed_events else None,
            "ledger_sha256": hashlib.sha256(content.encode()).hexdigest(),
        })
    write_clean(SOURCE, "goal", _GOAL_DDL, goals, tuple(goals[0]) if goals else (
        "goal_uid", "machine_id", "goal_id", "title", "owner", "coordinator_bot", "tl_agent",
        "tl_model", "contract_sha", "static_header_status", "derived_actual_status",
        "is_status_drifted", "task_total_count", "task_done_count", "task_blocked_count",
        "created_at", "last_event_at", "ledger_sha256"))
    return write_clean(SOURCE, "gtt_event", _EVENT_DDL, events, (
        "event_uid", "goal_uid", "machine_id", "goal_id", "line_no", "event_id", "ts",
        "evt_type", "task_id", "actor_from", "actor_to", "ref_artifact", "head_sha",
        "pr_number", "model_id", "contract_sha", "is_bot_bypass", "blocker_class", "note_preview"))
