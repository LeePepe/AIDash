"""Best-effort iCloud Drive token shard export and pull.

The iCloud Drive directory is a local filesystem boundary only.  Each device
publishes one atomic JSONL snapshot; normalization deduplicates records by the
stable record UID before L3 consumes the clean database.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import socket
import sqlite3
import subprocess  # nosec B404 - fixed executable, no shell
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from cleanio import write_clean
from config import ICLOUD_TOKEN_SYNC_DIR, clean_path, raw_source_dir
from rawio import read_raw, write_raw_snapshot

SOURCE = "icloud_token_sync"
_CST_OFFSET_HOURS = 8
_SAFE_NAME = re.compile(r"[^A-Za-z0-9._-]+")

_CLEAN_DDL = """
CREATE TABLE device_token_usage (
    record_uid TEXT PRIMARY KEY,
    device_id TEXT NOT NULL,
    machine_alias TEXT NOT NULL,
    cst_day TEXT NOT NULL,
    hour_bucket TEXT NOT NULL,
    cli TEXT NOT NULL,
    model TEXT NOT NULL,
    input_tokens INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL,
    cache_read INTEGER NOT NULL,
    cache_write INTEGER NOT NULL,
    total_tokens INTEGER NOT NULL,
    invocations INTEGER NOT NULL,
    updated_at TEXT NOT NULL
)
"""
_CLEAN_COLS = (
    "record_uid", "device_id", "machine_alias", "cst_day", "hour_bucket",
    "cli", "model", "input_tokens", "output_tokens", "cache_read",
    "cache_write", "total_tokens", "invocations", "updated_at",
)


def _record_uid(device_id: str, cst_day: str, hour_bucket: str, cli: str, model: str) -> str:
    value = "|".join((device_id, cst_day, hour_bucket, cli, model))
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def local_device_id() -> str:
    """Return the stable local device key used for merge backfill."""
    return _device_identity()[0]


def _device_identity() -> tuple[str, str]:
    hostname = os.environ.get("AIDATA_MACHINE_ID") or socket.gethostname() or "unknown-device"
    device_id = _SAFE_NAME.sub("-", hostname).strip(".-")[:96] or "unknown-device"
    alias = os.environ.get("AIDATA_MACHINE_ALIAS")
    if not alias:
        try:
            result = subprocess.run(
                ["scutil", "--get", "ComputerName"],
                capture_output=True, text=True, check=False, shell=False,
            )
            alias = result.stdout.strip() if result.returncode == 0 else ""
        except OSError:
            alias = ""
    alias = (alias or hostname).strip()[:128] or device_id
    return device_id, alias


def _cst_parts(value: Any, epoch_seconds: bool = False) -> tuple[str, str] | None:
    try:
        if epoch_seconds:
            stamp = datetime.fromtimestamp(float(value), timezone.utc)
        elif isinstance(value, (int, float)):
            stamp = datetime.fromtimestamp(float(value) / 1000, timezone.utc)
        else:
            stamp = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
            if stamp.tzinfo is None:
                stamp = stamp.replace(tzinfo=timezone.utc)
        shifted = stamp.astimezone(timezone.utc) + timedelta(hours=_CST_OFFSET_HOURS)
        return shifted.date().isoformat(), shifted.strftime("%Y-%m-%dT%H:00:00+08:00")
    except (TypeError, ValueError, OverflowError, OSError):
        return None


def _clean_rows(source: str, device_id: str, alias: str) -> list[dict[str, Any]]:
    db = clean_path(source)
    if not db.exists():
        return []
    rows: list[dict[str, Any]] = []
    try:
        conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        try:
            table = {row[1] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            table_name = "req" if source == "raven" and "req" in table else "turn" if source == "claude_jsonl" and "turn" in table else "session" if source == "state_db" and "session" in table else None
            if table_name is None:
                return []
            columns = {row[1] for row in conn.execute(f"PRAGMA table_info({table_name})")}
            if source == "raven":
                selected = [name for name in ("ts", "client", "model_canon", "model", "input_tokens", "output_tokens", "cache_read", "cache_write", "total_tokens") if name in columns]
                for row in conn.execute(f"SELECT {', '.join(selected)} FROM req"):
                    item = dict(zip(selected, row))
                    parts = _cst_parts(item.get("ts"))
                    if parts:
                        rows.append(_usage(device_id, alias, parts, item.get("client") or "raven", item.get("model_canon") or item.get("model"), item))
            elif source == "claude_jsonl":
                selected = [name for name in ("ts", "role", "model", "input_tokens", "output_tokens", "cache_read", "cache_creation") if name in columns]
                for row in conn.execute(f"SELECT {', '.join(selected)} FROM turn"):
                    item = dict(zip(selected, row))
                    if item.get("role") not in (None, "assistant"):
                        continue
                    parts = _cst_parts(item.get("ts"))
                    if parts:
                        item["cache_write"] = item.get("cache_creation")
                        rows.append(_usage(device_id, alias, parts, "claude-code", item.get("model"), item))
            else:
                selected = [name for name in ("started_at", "source", "model", "input_tokens", "output_tokens", "cache_read_tokens", "cache_write_tokens") if name in columns]
                for row in conn.execute(f"SELECT {', '.join(selected)} FROM session"):
                    item = dict(zip(selected, row))
                    parts = _cst_parts(item.get("started_at"), epoch_seconds=True)
                    if parts:
                        item["cache_read"] = item.get("cache_read_tokens")
                        item["cache_write"] = item.get("cache_write_tokens")
                        rows.append(_usage(device_id, alias, parts, "hermes", item.get("model"), item))
        finally:
            conn.close()
    except (OSError, sqlite3.Error):
        return []
    return rows


def _usage(device_id: str, alias: str, parts: tuple[str, str], cli: Any, model: Any, item: dict[str, Any]) -> dict[str, Any]:
    cst_day, hour_bucket = parts
    cli_value = str(cli or "unknown")
    model_value = str(model or "unknown")
    input_tokens = int(item.get("input_tokens") or 0)
    output_tokens = int(item.get("output_tokens") or 0)
    cache_read = int(item.get("cache_read") or 0)
    cache_write = int(item.get("cache_write") or 0)
    total = int(item.get("total_tokens") or (input_tokens + output_tokens))
    return {
        "record_uid": _record_uid(device_id, cst_day, hour_bucket, cli_value, model_value),
        "device_id": device_id, "machine_alias": alias, "cst_day": cst_day,
        "hour_bucket": hour_bucket, "cli": cli_value, "model": model_value,
        "input_tokens": input_tokens, "output_tokens": output_tokens,
        "cache_read": cache_read, "cache_write": cache_write,
        "total_tokens": total, "invocations": 1,
        "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def _aggregate(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, dict[str, Any]] = {}
    for row in rows:
        key = row["record_uid"]
        if key not in grouped:
            grouped[key] = dict(row)
            continue
        current = grouped[key]
        for field in (
            "input_tokens", "output_tokens", "cache_read", "cache_write",
            "total_tokens", "invocations",
        ):
            current[field] += int(row[field] or 0)
        current["updated_at"] = max(current["updated_at"], row["updated_at"])
    return sorted(grouped.values(), key=lambda row: row["record_uid"])


def _atomic_export(rows: list[dict[str, Any]], root: Path) -> None:
    device_id, _ = _device_identity()
    target_dir = root / "machines" / device_id
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / "token_usage.jsonl"
    fd, temporary = tempfile.mkstemp(prefix=".token_usage.", dir=target_dir, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            for row in rows:
                handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, target)
        directory_fd = os.open(target_dir, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except OSError:
        Path(temporary).unlink(missing_ok=True)
        raise


def _pull(root: Path) -> list[dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    try:
        paths = sorted((root / "machines").glob("*/token_usage.jsonl"))
    except OSError:
        return []
    for path in paths:
        try:
            with path.open(encoding="utf-8") as handle:
                for line in handle:
                    try:
                        value = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if isinstance(value, dict) and isinstance(value.get("record_uid"), str):
                        previous = records.get(value["record_uid"])
                        if previous is None or str(value.get("updated_at", "")) >= str(previous.get("updated_at", "")):
                            records[value["record_uid"]] = value
        except OSError:
            continue
    return list(records.values())


def collect() -> int:
    """Export local summaries, then pull all available device shards."""
    root = Path(ICLOUD_TOKEN_SYNC_DIR).expanduser()
    try:
        device_id, alias = _device_identity()
        local = []
        for source in ("raven", "claude_jsonl", "state_db", "copilot", "kimi_prompts"):
            local.extend(_clean_rows(source, device_id, alias))
        rows = _aggregate(local)
        if rows:
            _atomic_export(rows, root)
        pulled = _pull(root) if root.exists() else []
        if not pulled:
            return 0
        return write_raw_snapshot(SOURCE, pulled)
    except (OSError, ValueError, sqlite3.Error):
        return 0


def normalize() -> int:
    """Rebuild the clean device-token table, deduplicating by record UID."""
    rows: dict[str, dict[str, Any]] = {}
    for record in read_raw(SOURCE):
        uid = record.get("record_uid")
        if isinstance(uid, str) and uid:
            rows[uid] = {column: record.get(column) for column in _CLEAN_COLS}
    return write_clean(SOURCE, "device_token_usage", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS)
