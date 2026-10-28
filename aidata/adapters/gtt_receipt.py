"""Collect and normalize GTT R10 receipts and runtime role profiles."""

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
from config import GTT_HANDOFF_ROOTS, GTT_RUNTIME_PROFILES_YAML, GTT_XFER_DIR
from rawio import read_raw, write_raw
from state import get_watermark, set_watermark

SOURCE = "gtt_receipt"
_FILE = re.compile(r"^(?P<prefix>.+?)-r(?P<round>\d+)\.md$")
_KEY_RE = re.compile(
    r"(?im)^\s*(?:[-*]\s*)?(?:\*\*)?(?P<key>[^:|]+?)(?:\*\*)?\s*[:|]\s*(?P<value>.+?)\s*$"
)


def _machine_id() -> str:
    return socket.gethostname().split(".", 1)[0] or "unknown"


def _bundle_records(path: Path) -> Iterable[dict[str, Any]]:
    machine_id = path.stem.removeprefix("gtt-bundle-") or "bundle"
    if path.suffix == ".tgz":
        try:
            with tarfile.open(path, "r:gz") as archive:
                for member in archive.getmembers():
                    if not member.isfile() or Path(member.name).parent.name != "receipts":
                        continue
                    content = archive.extractfile(member)
                    if content is None:
                        continue
                    rel_path = member.name.lstrip("./")
                    yield {
                        "machine_id": machine_id,
                        "goal_id": Path(rel_path).parts[0],
                        "rel_path": rel_path,
                        "record_type": "receipt",
                        "content": content.read().decode("utf-8"),
                    }
        except (OSError, tarfile.TarError, UnicodeDecodeError):
            return
        return
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            if item.get("collector") in (None, "gtt") and item.get("record_type") == "receipt" and item.get("content"):
                yield {
                    "machine_id": item.get("machine_id") or "unknown",
                    "goal_id": item.get("goal_id") or "unknown",
                    "rel_path": item.get("rel_path", ""),
                    "record_type": "receipt",
                    "content": str(item["content"]),
                }
    except OSError:
        return


def collect() -> int:
    from adapters import cloud_sync

    cloud_sync.pull_remote_batches()
    records: list[dict[str, Any]] = []
    for root in GTT_HANDOFF_ROOTS:
        try:
            goals = [p for p in root.iterdir() if p.is_dir() and not p.name.startswith("_")]
        except OSError:
            continue
        for goal in goals:
            try:
                receipts = sorted((goal / "receipts").glob("*.md"))
            except OSError:
                continue
            for path in receipts:
                try:
                    content = path.read_text(encoding="utf-8")
                except OSError:
                    continue
                records.append({"machine_id": _machine_id(), "goal_id": goal.name,
                                "rel_path": f"{goal.name}/receipts/{path.name}",
                                "record_type": "receipt", "content": _normalize_path(content)})
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


_HOME = re.compile(r"(?<![\w-])(?:/Users|/home)/[^/\s]+")


def _normalize_path(value: str) -> str:
    return _HOME.sub("~", value)


def _field(text: str, names: tuple[str, ...]) -> str | None:
    wanted = {name.lower().replace("_", " ") for name in names}
    for match in _KEY_RE.finditer(text):
        key = re.sub(r"\s+", " ", match.group("key").strip().lower().replace("_", " "))
        if key in wanted or any(name in key for name in wanted):
            return match.group("value").strip().strip("`")
    return None


def _role_from_name(role: str) -> str:
    role = role.lower()
    return {"analyst": "planner", "explorer": "explorer", "reviewer": "reviewer",
            "writer": "writer", "pr-monitor": "pr_monitor"}.get(role, role)


_TASK_DDL = """
CREATE TABLE task_run (
    receipt_uid TEXT PRIMARY KEY, goal_uid TEXT NOT NULL, machine_id TEXT NOT NULL,
    goal_id TEXT NOT NULL, task_id TEXT NOT NULL, role_name TEXT NOT NULL,
    round_no INTEGER NOT NULL, agent_name TEXT, cli_tool TEXT, model_id TEXT,
    vendor TEXT, status TEXT, v5_verdict TEXT, head_sha TEXT,
    receipt_sha256 TEXT NOT NULL, completed_at TEXT
)
"""
_ROLE_DDL = """
CREATE TABLE model_role (
    role_model_key TEXT PRIMARY KEY, role_name TEXT, tier TEXT, cli_tool TEXT,
    model_id TEXT, vendor TEXT, is_escalated INTEGER
)
"""


def _profiles() -> list[dict[str, Any]]:
    fallback = [
        ("writer", "copilot", "gpt-5.6-luna", "openai"),
        ("explorer", "copilot", "mai-code-2-flash", "microsoft"),
        ("pr_monitor", "copilot", "mai-code-2-flash", "microsoft"),
        ("planner", "codex", "gpt-6.1-sol", "openai"),
        ("planner_reviewer", "copilot", "gemini-4-argon", "google"),
        ("code_reviewer", "copilot", "gemini-4-argon", "google"),
        ("writer_escalated", "codex", "gpt-6.1-sol", "openai"),
        ("research_primary", "copilot", "gemini-4-argon", "google"),
    ]
    try:
        text = GTT_RUNTIME_PROFILES_YAML.read_text(encoding="utf-8")
    except OSError:
        text = ""
    rows: list[dict[str, Any]] = []
    for role, cli, model, vendor in fallback:
        rows.append({"role_model_key": f"{role}:{cli}:{model}", "role_name": role,
                     "tier": "escalated" if "escalated" in role else "standard",
                     "cli_tool": cli, "model_id": model, "vendor": vendor,
                     "is_escalated": int("escalated" in role)})
    if not text:
        return rows
    for role, body in re.findall(
        r"(?m)^\s{6}([A-Za-z0-9_.-]+):\s*(.*)$", text
    ):
        for cli, model, vendor in re.findall(
            r"cli:\s*([A-Za-z0-9_.-]+).*?model:\s*([A-Za-z0-9_.-]+).*?vendor:\s*([A-Za-z0-9_.-]+)",
            body,
        ):
            rows.append({"role_model_key": f"{role}:{cli}:{model}", "role_name": role,
                         "tier": "escalated" if "escalated" in role else "standard",
                         "cli_tool": cli, "model_id": model, "vendor": vendor,
                         "is_escalated": int("escalated" in role)})
    return rows


def normalize() -> int:
    task_rows: dict[str, dict[str, Any]] = {}
    for record in read_raw(SOURCE):
        if record.get("record_type") != "receipt":
            continue
        rel = str(record.get("rel_path", ""))
        name = Path(rel).name
        match = _FILE.match(name)
        if not match:
            continue
        content = str(record.get("content", ""))
        model = _field(content, ("Model",))
        head = _field(content, ("head", "PR"))
        head_match = re.search(r"\b[0-9a-f]{7,40}\b", head or "", re.IGNORECASE)
        prefix = match.group("prefix")
        role_from_name = prefix.rsplit("-", 1)[-1] if "-" in prefix else prefix
        task_id = prefix.rsplit("-", 1)[0] if "-" in prefix else prefix
        known_roles = {"writer", "explorer", "reviewer", "pr-monitor", "planner", "code-reviewer"}
        if role_from_name not in known_roles:
            role_from_name = "unknown"
            task_id = prefix
        role = _field(content, ("Role", "Role / Model")) or _role_from_name(role_from_name)
        status = (_field(content, ("Status",)) or "completed").lower()
        v5 = _field(content, ("V5",))
        goal = str(record.get("goal_id", "unknown"))
        machine_id = str(record.get("machine_id", "unknown"))
        uid = f"{machine_id}:{rel or name}"
        task_rows[uid] = {
            "receipt_uid": uid, "goal_uid": f"{record.get('machine_id', 'unknown')}:{goal}",
            "machine_id": machine_id, "goal_id": goal,
            "task_id": task_id, "role_name": role, "round_no": int(match.group("round")),
            "agent_name": _field(content, ("Agent",)),             "cli_tool": _field(content, ("CLI", "Role / Model")),
            "model_id": model, "vendor": None, "status": status, "v5_verdict": v5,
            "head_sha": head_match.group(0) if head_match else None,
            "receipt_sha256": hashlib.sha256(content.encode()).hexdigest(),
            "completed_at": _field(content, ("Timestamp",)),
        }
    task_cols = ("receipt_uid", "goal_uid", "machine_id", "goal_id", "task_id", "role_name",
                 "round_no", "agent_name", "cli_tool", "model_id", "vendor", "status",
                 "v5_verdict", "head_sha", "receipt_sha256", "completed_at")
    role_map = {row["role_model_key"]: row for row in _profiles()}
    roles = list(role_map.values())
    role_cols = ("role_model_key", "role_name", "tier", "cli_tool", "model_id", "vendor", "is_escalated")
    write_clean(SOURCE, "model_role", _ROLE_DDL, roles, role_cols)
    write_clean(SOURCE, "task_run", _TASK_DDL, list(task_rows.values()), task_cols)
    return len(task_rows)
