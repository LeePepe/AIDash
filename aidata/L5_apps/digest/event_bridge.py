"""Bridge AIDash user events back into proposal, Linear, alert, and Falcon state."""

from __future__ import annotations

import json
import re
import sqlite3
import subprocess
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from config import LINEAR_SYNC_SCRIPT, PROPOSALS_PATH

from L5_apps.digest.proposals import read_pending

_LINEAR_REF_RE = re.compile(r"^(?:linear://)?(TIA-\d+)$", re.IGNORECASE)


def _extract_linear_id(ref: str) -> str | None:
    match = _LINEAR_REF_RE.match((ref or "").strip())
    return match.group(1).upper() if match else None


def _append_jsonl(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")


def _now() -> str:
    return (
        datetime.now(timezone.utc)  # noqa: UP017
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z")
    )


def _default_linear_runner(title: str, description: str) -> tuple[int, str | None]:
    script = Path(LINEAR_SYNC_SCRIPT)
    result = subprocess.run(
        [str(script), "idea", "--title", title, "--description", description,
         "--mode", "auto"],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    external_id: str | None = None
    if result.returncode == 0 and result.stdout.strip():
        try:
            payload = json.loads(result.stdout)
            if isinstance(payload, dict):
                issue_obj = payload.get("issue")
                ident = (
                    (issue_obj.get("identifier") if isinstance(issue_obj, dict) else None)
                    or payload.get("identifier")
                )
                if isinstance(ident, str) and ident.strip():
                    external_id = ident.strip()
        except json.JSONDecodeError:
            external_id = None
    return result.returncode, external_id


def _default_linear_status_runner(issue_id: str, state: str) -> int:
    script = Path(LINEAR_SYNC_SCRIPT)
    result = subprocess.run(
        [str(script), "update-issue", "--id", issue_id, "--state", state,
         "--mode", "auto"],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result.returncode


def _coerce_idea_result(raw: Any) -> tuple[int, str | None]:
    if isinstance(raw, tuple) and len(raw) == 2:
        rc, ident = raw
        return int(rc), (str(ident).strip() if ident else None)
    if isinstance(raw, dict):
        issue = raw.get("issue") if isinstance(raw.get("issue"), dict) else {}
        ident = issue.get("identifier") or raw.get("identifier")
        rc = 0 if raw.get("ok", True) else 1
        return rc, (str(ident).strip() if ident else None)
    return int(raw), None


def _latest_events(events: list[dict]) -> dict[str, dict]:
    latest: dict[str, dict] = {}
    for event in events:
        raw_ref = str(event.get("item_ref") or event.get("itemRef") or "").strip()
        action = str(event.get("action") or "").strip().lower()
        if raw_ref and action in {"done", "undone"}:
            linear_id = _extract_linear_id(raw_ref)
            ref = f"linear://{linear_id}" if linear_id else raw_ref
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
    linear_runner: Callable[[str, str], Any] | None = None,
    linear_status_runner: Callable[[str, str], int] | None = None,
) -> dict:
    """Apply latest-wins event reductions and return explicit bridge counts."""
    proposal_path = proposals_path or PROPOSALS_PATH
    runner = linear_runner or _default_linear_runner
    status_runner = linear_status_runner or _default_linear_status_runner
    result = {
        "resolved": 0, "undone": 0, "promoted": 0, "falcon_starred": 0,
        "ignored": 0, "errors": 0,
    }
    pending = {proposal.id: proposal for proposal in read_pending(proposal_path)}

    for ref, event in _latest_events(events).items():
        action = str(event.get("action") or "").lower()
        linear_id = _extract_linear_id(ref)
        if linear_id is not None:
            target_state = "Done" if action == "done" else "Todo"
            try:
                rc = status_runner(linear_id, target_state)
            except (OSError, subprocess.SubprocessError):
                rc = 1
            if rc == 0:
                if action == "done":
                    result["resolved"] += 1
                else:
                    result["undone"] += 1
            else:
                result["errors"] += 1
            continue
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
                rc, external_id = _coerce_idea_result(
                    runner(proposal.title, proposal.detail)
                )
            except (OSError, subprocess.SubprocessError):
                rc, external_id = 1, None
            if rc == 0:
                approved_record = {
                    "id": proposal.id, "status": "approved", "ts": _now(),
                    "source": "aidash",
                }
                if external_id:
                    approved_record["external_id"] = external_id
                _append_jsonl(proposal_path, approved_record)
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
