"""Collect and normalize bot/TL orchestration and PR monitor telemetry."""

from __future__ import annotations

import hashlib
import json
import re
import socket
from pathlib import Path
from typing import Any

from cleanio import write_clean
from config import (
    CLAUDE_QUOTA_CACHE,
    GTT_HANDOFF_ROOTS,
    GTT_XFER_DIR,
    PRMON_WATCH_DIR,
)
from rawio import read_raw, write_raw
from state import get_watermark, set_watermark

SOURCE = "bot_tl"
_HOME = re.compile(r"(?<![\w-])(?:/Users|/home)/[^/\s]+")
_EVENT = re.compile(r"^\s*-\s*(?P<ts>\S+)\s*\|\s*EVT=(?P<evt>\S+)\s*\|\s*(?P<rest>.*)$")
_KV = re.compile(r"(?P<key>[A-Za-z_]+)=(?P<value>.*?)(?=\s+[A-Za-z_]+=|$)")
_ACTION = {
    "SPAWN_TL", "QUOTA_PRECHECK", "HOT_APPEND", "UNBLOCK_PATH",
    "UNBLOCK_CMD_CONFIRM", "DESIGN_ROUTE_ARTIST", "S1_CONFLICT",
    "S2_COMMENT_RESOLVE", "S3_CI_FIX", "S4_DAG_NARROW", "PR_DAG_NODE",
    "NEED_GO",
}


def _machine_id() -> str:
    return socket.gethostname().split(".", 1)[0] or "unknown"


def _safe(value: str) -> str:
    return _HOME.sub("~", value)


def _payload(path: Path, record_type: str, content: str) -> dict[str, Any]:
    try:
        value: Any = json.loads(content)
    except json.JSONDecodeError:
        value = {"content": _safe(content)}
    return {
        "schema_version": 1,
        "collector": "prmon" if record_type.startswith("prmon") else "bot_tl",
        "record_type": record_type,
        "device_id": _machine_id(),
        "machine_alias": _machine_id(),
        "goal_id": path.parts[-2] if len(path.parts) > 1 else None,
        "rel_path": str(path),
        "payload": value,
    }


def _file_record(path: Path, record_type: str) -> dict[str, Any] | None:
    try:
        return _payload(path, record_type, path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError):
        return None


def _local_records() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for root in GTT_HANDOFF_ROOTS:
        try:
            goals = [p for p in root.iterdir() if p.is_dir() and not p.name.startswith("_")]
        except OSError:
            continue
        for goal in goals:
            for name, kind in (
                ("pr-dag.json", "pr_dag"),
                ("pr-watch-state.json", "pr_watch_state"),
            ):
                record = _file_record(goal / name, kind)
                if record:
                    record["goal_id"] = goal.name
                    records.append(record)
            ledger = goal / "ledger.md"
            try:
                text = ledger.read_text(encoding="utf-8")
            except OSError:
                text = ""
            for line in text.splitlines():
                match = _EVENT.match(line)
                if match and (
                    match.group("evt") in {"SPAWN_TL", "HOT_APPEND", "UNBLOCK", "UNBLOCK_PATH", "NEED_GO"}
                    or re.search(r"\bid=[BJ]\d+\b", line)
                ):
                    fields = {m.group("key"): m.group("value").strip() for m in _KV.finditer(match.group("rest"))}
                    event = {
                        "ts": match.group("ts"),
                        "evt": match.group("evt"),
                        **fields,
                        "goal_id": goal.name,
                    }
                    records.append(_payload(goal / "ledger.md", "bot_tl_event", json.dumps(event)))
    quota = _file_record(CLAUDE_QUOTA_CACHE, "quota_precheck")
    if quota:
        records.append(quota)
    return records


def _prmon_records() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    history = PRMON_WATCH_DIR / "heartbeat-history.jsonl"
    try:
        stat = history.stat()
        old = get_watermark("bot_tl_prmon_history") or {}
        offset = int(old.get("offset", 0)) if old.get("inode") == stat.st_ino else 0
        with history.open(encoding="utf-8") as fh:
            fh.seek(offset)
            for line in fh:
                try:
                    records.append(_payload(history, "prmon_heartbeat", line))
                except OSError:
                    break
            set_watermark("bot_tl_prmon_history", {"inode": stat.st_ino, "offset": fh.tell()})
    except OSError:
        pass
    for path, kind in (
        (PRMON_WATCH_DIR / "heartbeat.json", "prmon_heartbeat"),
        (PRMON_WATCH_DIR / "scheduler-state.json", "prmon_state"),
    ):
        record = _file_record(path, kind)
        if record:
            records.append(record)
    try:
        for path in sorted((PRMON_WATCH_DIR / "repair-queue").glob("*.json")):
            record = _file_record(path, "prmon_repair")
            if record:
                records.append(record)
    except OSError:
        pass
    return records


def _remote_records() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    try:
        paths = list(GTT_XFER_DIR.rglob("*.jsonl"))
    except OSError:
        return records
    for path in paths:
        try:
            for line in path.read_text(encoding="utf-8").splitlines():
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if item.get("collector") in {"bot_tl", "prmon"} or item.get("record_type") in {
                    "pr_dag", "pr_watch_state", "bot_tl_event", "quota_precheck",
                    "prmon_heartbeat", "prmon_state", "prmon_repair",
                }:
                    records.append(item)
        except (OSError, UnicodeDecodeError):
            continue
    return records


def collect() -> int:
    from adapters import cloud_sync

    cloud_sync.pull_remote_batches()
    records = _local_records() + _prmon_records() + _remote_records()
    old = dict(get_watermark(SOURCE) or {})
    changed: list[dict[str, Any]] = []
    current: dict[str, str] = {}
    for record in records:
        key = f"{record.get('device_id', 'unknown')}:{record.get('record_type')}:{record.get('rel_path', '')}"
        digest = hashlib.sha256(json.dumps(record, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        current[key] = digest
        if old.get(key) != digest:
            changed.append(record)
    count = write_raw(SOURCE, changed)
    set_watermark(SOURCE, current)
    return count


def _as_dict(record: dict[str, Any]) -> dict[str, Any]:
    payload = record.get("payload")
    return payload if isinstance(payload, dict) else record


def _action(value: str | None, record_type: str) -> str | None:
    value = (value or "").upper()
    if value == "UNBLOCK":
        return "UNBLOCK_PATH"
    if value in _ACTION:
        return value
    return "PR_DAG_NODE" if record_type == "pr_dag" else None


_SUPERVISION_DDL = """
CREATE TABLE supervision (
    supervision_uid TEXT PRIMARY KEY, device_id TEXT NOT NULL,
    machine_alias TEXT, goal_id TEXT NOT NULL, bot_name TEXT, tl_agent TEXT,
    action_kind TEXT NOT NULL, quota_precheck_result TEXT,
    weekly_remaining_pct INTEGER, repo_key TEXT, pr_number INTEGER,
    head_sha TEXT, status TEXT, detail_preview TEXT, ts TEXT NOT NULL
)
"""
_HEARTBEAT_DDL = """
CREATE TABLE prmon_heartbeat (
    heartbeat_uid TEXT PRIMARY KEY, device_id TEXT NOT NULL,
    machine_alias TEXT, ts TEXT NOT NULL, checked_pr_count INTEGER,
    stuck_pr_count INTEGER, repair_queued_count INTEGER, status TEXT
)
"""


def normalize() -> int:
    supervision: dict[str, dict[str, Any]] = {}
    heartbeat: dict[str, dict[str, Any]] = {}
    for record in read_raw(SOURCE):
        payload = _as_dict(record)
        record_type = str(record.get("record_type", ""))
        device = str(record.get("device_id") or record.get("machine_id") or "unknown")
        alias = record.get("machine_alias") or record.get("machine_id")
        ts = str(payload.get("ts") or payload.get("observed_at") or record.get("observed_at") or "")
        if record_type == "prmon_heartbeat":
            uid = f"{device}:{ts}:{hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()[:8]}"
            heartbeat[uid] = {
                "heartbeat_uid": uid, "device_id": device, "machine_alias": alias,
                "ts": ts, "checked_pr_count": payload.get("checked_pr_count"),
                "stuck_pr_count": payload.get("stuck_pr_count"),
                "repair_queued_count": payload.get("repair_queued_count"),
                "status": payload.get("status"),
            }
            continue
        action = _action(payload.get("action_kind") or payload.get("evt"), record_type)
        if not action or not ts:
            continue
        goal = str(payload.get("goal_id") or record.get("goal_id") or "unknown")
        uid = f"{device}:{goal}:{action}:{hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()[:8]}"
        supervision[uid] = {
            "supervision_uid": uid, "device_id": device, "machine_alias": alias,
            "goal_id": goal, "bot_name": payload.get("bot_name"),
            "tl_agent": payload.get("tl_agent"), "action_kind": action,
            "quota_precheck_result": payload.get("quota_precheck_result") or payload.get("result"),
            "weekly_remaining_pct": payload.get("weekly_remaining_pct"),
            "repo_key": payload.get("repo_key"), "pr_number": payload.get("pr_number"),
            "head_sha": payload.get("head_sha"), "status": payload.get("status"),
            "detail_preview": str(payload.get("detail") or payload.get("note") or "")[:300],
            "ts": ts,
        }
    write_clean(SOURCE, "supervision", _SUPERVISION_DDL, list(supervision.values()), (
        "supervision_uid", "device_id", "machine_alias", "goal_id", "bot_name", "tl_agent",
        "action_kind", "quota_precheck_result", "weekly_remaining_pct", "repo_key",
        "pr_number", "head_sha", "status", "detail_preview", "ts",
    ))
    return write_clean(SOURCE, "prmon_heartbeat", _HEARTBEAT_DDL, list(heartbeat.values()), (
        "heartbeat_uid", "device_id", "machine_alias", "ts", "checked_pr_count",
        "stuck_pr_count", "repair_queued_count", "status",
    ))
