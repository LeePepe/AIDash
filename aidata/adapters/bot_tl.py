"""Collect and normalize bot/TL orchestration and PR monitor telemetry."""

from __future__ import annotations

import hashlib
import json
import os
import re
import socket
import tarfile
from datetime import datetime, timezone
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
_REPLAY_LIMIT = 2048
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
        value: Any = json.loads(_safe(content))
    except json.JSONDecodeError:
        value = {"content": _safe(content)}
    try:
        mtime_iso = datetime.fromtimestamp(path.stat().st_mtime, timezone.utc)  # noqa: UP017
        mtime_iso = mtime_iso.isoformat()
    except OSError:
        mtime_iso = None
    return {
        "schema_version": 1,
        "collector": "prmon" if record_type.startswith("prmon") else "bot_tl",
        "record_type": record_type,
        "device_id": _machine_id(),
        "machine_alias": _machine_id(),
        "goal_id": path.parts[-2] if len(path.parts) > 1 else None,
        "rel_path": _safe(str(path)),
        "mtime_iso": mtime_iso,
        "observed_at": value.get("observed_at") or value.get("generated_at") if isinstance(value, dict) else mtime_iso,
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
                if match:
                    if not (
                        match.group("evt") in {"SPAWN_TL", "HOT_APPEND", "UNBLOCK", "UNBLOCK_PATH", "NEED_GO"}
                        or re.search(r"\bid=[BJ]\d+\b", line)
                    ):
                        continue
                    ts, rest, evt = match.group("ts"), match.group("rest"), match.group("evt")
                elif re.search(r"\b(?:TL_PROFILE|quota_precheck)\b", line, re.IGNORECASE):
                    ts_match = re.search(r"\b\d{4}-\d{2}-\d{2}T\S+", line)
                    ts, rest, evt = (ts_match.group(0) if ts_match else ""), line, (
                        "QUOTA_PRECHECK" if "quota_precheck" in line.lower() else "SPAWN_TL"
                    )
                else:
                    continue
                fields = {m.group("key"): m.group("value").strip() for m in _KV.finditer(rest)}
                fields.setdefault("action_kind", evt)
                if "UNBLOCK_CMD_CONFIRM" in line:
                    fields["action_kind"] = "UNBLOCK_CMD_CONFIRM"
                elif "DESIGN_ROUTE_ARTIST" in line or "艺术家" in line:
                    fields["action_kind"] = "DESIGN_ROUTE_ARTIST"
                elif stage := re.search(r"\bS[1-4]_[A-Z_]+\b", line):
                    fields["action_kind"] = stage.group(0)
                if ts or not match:
                    event = {
                        "ts": ts,
                        "timestamp_source": "inline" if ts else "unknown",
                        "evt": evt,
                        **fields,
                        "goal_id": goal.name,
                    }
                    records.append(_payload(goal / "ledger.md", "bot_tl_event", json.dumps(event)))
    quota = _file_record(CLAUDE_QUOTA_CACHE, "quota_precheck")
    if quota:
        records.append(quota)
    return records


def _prmon_records() -> tuple[list[dict[str, Any]], dict[str, int] | None]:
    records: list[dict[str, Any]] = []
    cursor = None
    history = PRMON_WATCH_DIR / "heartbeat-history.jsonl"
    try:
        old = get_watermark("bot_tl_prmon_history") or {}
        with history.open("rb") as fh:
            stat = os.fstat(fh.fileno())
            offset = int(old.get("offset", 0)) if old.get("inode") == stat.st_ino else 0
            if not 0 <= offset <= stat.st_size:
                offset = 0
            if offset:
                fh.seek(offset - 1)
                if fh.read(1) != b"\n":
                    # Recover cursors left mid-line by an older reader.
                    offset = 0
            fh.seek(offset)
            while line := fh.readline():
                if not line.endswith(b"\n"):
                    break  # An append may still be writing this UTF-8 line.
                offset = fh.tell()
                try:
                    records.append(_payload(history, "prmon_heartbeat", line.decode("utf-8")))
                except UnicodeDecodeError:
                    continue
            cursor = {"inode": stat.st_ino, "offset": offset}
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
    return records, cursor


def _remote_records() -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    try:
        paths = list(GTT_XFER_DIR.rglob("*.jsonl"))
        paths.extend(GTT_XFER_DIR.rglob("*.tgz"))
    except OSError:
        return records
    def add_line(line: str) -> None:
        try:
            item = json.loads(_safe(line))
        except json.JSONDecodeError:
            return
        if not isinstance(item, dict):
            return
        if item.get("collector") in {"bot_tl", "prmon"} or item.get("record_type") in {
            "pr_dag", "pr_watch_state", "bot_tl_event", "quota_precheck",
            "prmon_heartbeat", "prmon_state", "prmon_repair",
        }:
            records.append(item)

    for path in paths:
        try:
            if path.suffix == ".tgz":
                with tarfile.open(path, "r:gz") as archive:
                    for member in archive.getmembers():
                        if not member.isfile() or Path(member.name).suffix != ".jsonl":
                            continue
                        content = archive.extractfile(member)
                        if content:
                            for line in content.read().decode("utf-8").splitlines():
                                add_line(line)
            else:
                for line in path.read_text(encoding="utf-8").splitlines():
                    add_line(line)
        except (OSError, UnicodeDecodeError, tarfile.TarError):
            continue
    return records


def collect() -> int:
    from adapters import cloud_sync

    cloud_sync.pull_remote_batches()
    prmon_records, history_cursor = _prmon_records()
    records = _local_records() + prmon_records + _remote_records()
    old = get_watermark(SOURCE) or {}
    # Versioned state drops the old unbounded digest-in-key map. A migration
    # may replay records once; normalization uses content identities.
    old_files = old.get("files", {})
    replay = list(dict.fromkeys(old.get("replay", [])))[-_REPLAY_LIMIT:]
    seen = set(replay)
    files: dict[str, str] = {}
    changed: list[dict[str, Any]] = []
    for record in records:
        digest = hashlib.sha256(
            json.dumps(record.get("payload", record), sort_keys=True, ensure_ascii=False).encode()
        ).hexdigest()
        key = json.dumps([record.get("device_id", "unknown"), record.get("record_type"),
                          record.get("rel_path", "")])
        # Ledger events and heartbeat histories are append-only. Mutable
        # snapshots keep only the latest digest so A -> B -> A is observable.
        is_event = record.get("record_type") == "bot_tl_event" or (
            record.get("record_type") == "prmon_heartbeat"
            and Path(record.get("rel_path", "")).name != "heartbeat.json"
        )
        if is_event:
            replay_key = hashlib.sha256(f"{key}:{digest}".encode()).hexdigest()
            if replay_key not in seen:
                changed.append(record)
                seen.add(replay_key)
                replay.append(replay_key)
        else:
            if files.get(key, old_files.get(key)) != digest:
                changed.append(record)
            files[key] = digest
    count = write_raw(SOURCE, changed)
    # Neither cursor may advance until raw append succeeds. A later state
    # failure can replay data, but cannot skip unwritten history.
    set_watermark(SOURCE, {"files": files, "replay": replay[-_REPLAY_LIMIT:]})
    if history_cursor is not None:
        set_watermark("bot_tl_prmon_history", history_cursor)
    return count


def _as_dict(record: dict[str, Any]) -> dict[str, Any]:
    payload = record.get("payload")
    if isinstance(payload, dict):
        line = payload.get("line")
        if isinstance(line, dict):
            return line
        if isinstance(line, str):
            try:
                parsed = json.loads(line)
            except json.JSONDecodeError:
                parsed = None
            if isinstance(parsed, dict):
                return parsed
        return payload
    return record


def _iso_ts(value: Any) -> str:
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, timezone.utc).isoformat()  # noqa: UP017
    text = str(value or "")
    if not text:
        return ""
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).isoformat()  # noqa: FURB162
    except ValueError:
        return text


def _repo_measure(repos: Any, keys: tuple[str, ...]) -> int | None:
    if not isinstance(repos, list):
        return None
    total = 0
    found = False
    for repo in repos:
        if not isinstance(repo, dict):
            continue
        for key in keys:
            if key in repo:
                try:
                    total += int(repo[key])
                    found = True
                except (TypeError, ValueError):
                    pass
                break
    return total if found else None


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
        ts = _iso_ts(
            payload.get("ts") or payload.get("observed_at") or payload.get("generated_at")
            or record.get("observed_at") or record.get("mtime_iso")
        )
        if record_type == "prmon_heartbeat":
            repos = payload.get("repos")
            checked = payload.get("checked_pr_count")
            checked = checked if checked is not None else _repo_measure(
                repos, ("checked_pr_count", "checked_prs", "checked")
            )
            if checked is None and isinstance(repos, list):
                checked = len(repos)
            stuck = payload.get("stuck_pr_count")
            stuck = stuck if stuck is not None else _repo_measure(
                repos, ("stuck_pr_count", "stuck_prs", "stuck")
            )
            if stuck is None and isinstance(repos, list):
                stuck = sum(
                    1 for repo in repos
                    if isinstance(repo, dict)
                    and (
                        str(repo.get("health", "")).upper() in {"UNAVAILABLE", "UNKNOWN", "STUCK"}
                        or repo.get("stuck") is True
                    )
                )
            queued = payload.get("repair_queued_count")
            queued = queued if queued is not None else _repo_measure(
                repos, ("repair_queued_count", "repair_queued", "queued_repairs")
            )
            if queued is None and isinstance(repos, list):
                queued = sum(
                    1 for repo in repos
                    if isinstance(repo, dict) and repo.get("repair_queued") is True
                )
            status = payload.get("status")
            if status is None and "coverage_complete" in payload:
                status = "complete" if payload["coverage_complete"] else "incomplete"
            uid = f"{device}:{ts}:{hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()[:8]}"
            heartbeat[uid] = {
                "heartbeat_uid": uid, "device_id": device, "machine_alias": alias,
                "ts": ts, "checked_pr_count": checked,
                "stuck_pr_count": stuck, "repair_queued_count": queued,
                "status": status,
            }
            continue
        if record_type == "quota_precheck":
            payload = {**payload, "action_kind": "QUOTA_PRECHECK",
                       "ts": _iso_ts(payload.get("measured_at") or payload.get("observed_at") or ts)}
            ts = payload["ts"]
        action = _action(payload.get("action_kind") or payload.get("evt"), record_type)
        if record_type == "bot_tl_event" and payload.get("timestamp_source") == "unknown":
            continue
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
