"""Pluggable Todo/Issue Sync Provider interface for AIDash (TodoSyncProvider v1).

Allows AIDash (`aidata` L5 inbox + event_bridge) to operate in two modes with
zero hardcoded external dependency:

- `LocalTodoSyncProvider` (`name = "local"`): 100% standalone local-first mode.
  Promoted proposals and status transitions (`done` / `undone`) are appended to
  `local_todos.jsonl` (`local://LOCAL-<N>`), and active local todos are surfaced
  directly in the Action Inbox.
- `LinearTodoSyncProvider` (`name = "linear"`): Linear SSOT integration via
  `linear-sync.py` (`idea` / `update-issue`) using canonical `linear://TIA-xx`
  references.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Protocol, runtime_checkable

from config import (
    LINEAR_SYNC_SCRIPT,
    LINEAR_TEAM_KEY,
    LOCAL_TODOS_PATH,
    TODO_SYNC_CONFIG_PATH,
    TODO_SYNC_PROVIDER,
)

_LOCAL_REF_RE = re.compile(r"^(?:local://)?(LOCAL-[A-Za-z0-9_-]+)$", re.IGNORECASE)


def _now() -> str:
    return (
        datetime.now(timezone.utc)  # noqa: UP017
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z")
    )


def _append_jsonl(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")


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


@runtime_checkable
class TodoSyncProvider(Protocol):
    """Canonical pluggable external/local todo sync interface."""

    @property
    def name(self) -> str: ...

    def is_enabled(self) -> bool: ...

    def format_ref(self, identifier: str, workspace_id: str | None = None) -> str: ...

    def parse_ref(self, ref: str) -> str | None: ...

    def promote_proposal(
        self, title: str, detail: str, dedup_key: str | None = None
    ) -> tuple[int, str | None]: ...

    def sync_status(self, external_id: str, action: str) -> int: ...


@dataclass(frozen=True)
class LocalTodoItem:
    id: str
    title: str
    detail: str
    status: str
    priority: str
    ts: str


def read_open_local_todos(path: Path | None = None) -> list[LocalTodoItem]:
    """Read append-only local_todos.jsonl and return items whose latest status != 'done'."""
    target = path or LOCAL_TODOS_PATH
    if not target.exists():
        return []
    items: dict[str, dict[str, Any]] = {}
    try:
        lines = target.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []
    for line in lines:
        text = line.strip()
        if not text:
            continue
        try:
            rec = json.loads(text)
        except json.JSONDecodeError:
            continue
        if not isinstance(rec, dict):
            continue
        item_id = str(rec.get("id") or "").strip().upper()
        if not item_id:
            continue
        existing = items.get(item_id, {"id": item_id})
        for key in ("title", "detail", "status", "priority", "ts"):
            if key in rec and rec[key] is not None:
                existing[key] = rec[key]
        items[item_id] = existing

    out: list[LocalTodoItem] = []
    for item_id, data in items.items():
        status = str(data.get("status") or "todo").lower()
        if status in {"done", "cancelled", "canceled", "dismissed"}:
            continue
        out.append(
            LocalTodoItem(
                id=item_id,
                title=str(data.get("title") or item_id),
                detail=str(data.get("detail") or ""),
                status=status,
                priority=str(data.get("priority") or "medium"),
                ts=str(data.get("ts") or ""),
            )
        )
    return out


class LocalTodoSyncProvider:
    """Standalone local-only provider with zero external service dependency."""

    name = "local"

    def __init__(self, local_todos_path: Path | None = None) -> None:
        self.local_todos_path = local_todos_path or LOCAL_TODOS_PATH

    def is_enabled(self) -> bool:
        return True

    def format_ref(self, identifier: str, workspace_id: str | None = None) -> str:
        ident = (identifier or "").strip()
        match = _LOCAL_REF_RE.match(ident)
        if match:
            return f"local://{match.group(1).upper()}"
        return ident

    def parse_ref(self, ref: str) -> str | None:
        match = _LOCAL_REF_RE.match((ref or "").strip())
        return match.group(1).upper() if match else None

    def _next_local_id(self) -> str:
        if not self.local_todos_path.exists():
            return "LOCAL-1"
        max_num = 0
        try:
            for line in self.local_todos_path.read_text(encoding="utf-8").splitlines():
                if not line.strip():
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                raw_id = str(rec.get("id") or "").upper()
                if raw_id.startswith("LOCAL-"):
                    suffix = raw_id.removeprefix("LOCAL-")
                    if suffix.isdigit():
                        max_num = max(max_num, int(suffix))
        except OSError:
            pass
        return f"LOCAL-{max_num + 1}"

    def _find_by_dedup_key(self, dedup_key: str) -> str | None:
        if not dedup_key or not self.local_todos_path.exists():
            return None
        try:
            for line in self.local_todos_path.read_text(encoding="utf-8").splitlines():
                if not line.strip():
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(rec, dict) and rec.get("dedup_key") == dedup_key:
                    raw_id = str(rec.get("id") or "").upper()
                    if raw_id:
                        return f"local://{raw_id}"
        except OSError:
            pass
        return None

    def promote_proposal(
        self,
        title: str,
        detail: str,
        dedup_key: str | None = None,
        *,
        state: str | None = None,
    ) -> tuple[int, str | None]:
        if dedup_key:
            existing = self._find_by_dedup_key(dedup_key)
            if existing:
                return 0, existing
        target_status = "triage" if str(state or "").strip().casefold() == "triage" else "todo"
        try:
            local_id = self._next_local_id()
            record: dict[str, Any] = {
                "id": local_id,
                "title": title,
                "detail": detail,
                "status": target_status,
                "priority": "medium",
                "ts": _now(),
            }
            if dedup_key:
                record["dedup_key"] = dedup_key
            _append_jsonl(self.local_todos_path, record)
            return 0, f"local://{local_id}"
        except OSError:
            return 1, None

    def sync_status(self, external_id: str, action: str) -> int:
        parsed = self.parse_ref(external_id) or external_id.strip().upper()
        if not parsed:
            return 1
        norm = action.strip().casefold()
        if norm == "done":
            target_status = "done"
        elif norm in {"cancelled", "canceled", "dismiss", "dismissed"}:
            target_status = "cancelled"
        elif norm in {"in_progress", "in progress"}:
            target_status = "in_progress"
        elif norm == "triage":
            target_status = "triage"
        else:
            target_status = "todo"
        try:
            _append_jsonl(
                self.local_todos_path,
                {
                    "id": parsed,
                    "status": target_status,
                    "ts": _now(),
                },
            )
            return 0
        except OSError:
            return 1


class LinearTodoSyncProvider:
    """Linear SSOT provider backed by linear-sync.py CLI or injected test runners."""

    name = "linear"

    def __init__(
        self,
        *,
        team_key: str | None = None,
        script_path: Path | None = None,
        idea_runner: Callable[[str, str], Any] | None = None,
        status_runner: Callable[[str, str], int] | None = None,
    ) -> None:
        self.team_key = (team_key or LINEAR_TEAM_KEY or "TIA").strip().upper()
        self.script_path = Path(script_path or LINEAR_SYNC_SCRIPT)
        self._idea_runner = idea_runner
        self._status_runner = status_runner
        self._ref_re = re.compile(
            rf"^(?:linear://)?({re.escape(self.team_key)}-\d+)$",
            re.IGNORECASE,
        )

    def is_enabled(self) -> bool:
        if self._idea_runner is not None or self._status_runner is not None:
            return True
        return bool(self.team_key) and self.script_path.is_file()

    def format_ref(self, identifier: str, workspace_id: str | None = None) -> str:
        ident = (identifier or "").strip()
        if ident.lower().startswith("linear://"):
            return f"linear://{ident.split('://', 1)[1].upper()}"
        if self.team_key and ident.upper().startswith(f"{self.team_key}-"):
            return f"linear://{ident.upper()}"
        if workspace_id and str(workspace_id).lower().startswith("linear:"):
            return f"linear://{ident.upper()}"
        return ident

    def parse_ref(self, ref: str) -> str | None:
        match = self._ref_re.match((ref or "").strip())
        return match.group(1).upper() if match else None

    def _default_idea_runner(
        self,
        title: str,
        description: str,
        dedup_key: str | None = None,
        *,
        state: str | None = None,
    ) -> tuple[int, str | None]:
        cmd = [
            sys.executable,
            str(self.script_path),
            "idea",
            "--title",
            title,
            "--description",
            description,
            "--mode",
            "auto",
        ]
        if state:
            cmd.extend(["--state", state])
        if dedup_key:
            cmd.extend(["--dedup-key", dedup_key])
        result = subprocess.run(
            cmd,
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
                        issue_obj.get("identifier")
                        if isinstance(issue_obj, dict)
                        else None
                    ) or payload.get("identifier")
                    if isinstance(ident, str) and ident.strip():
                        external_id = ident.strip()
            except json.JSONDecodeError:
                external_id = None
        return result.returncode, external_id

    def _default_status_runner(self, issue_id: str, state: str) -> int:
        result = subprocess.run(
            [
                sys.executable,
                str(self.script_path),
                "update-issue",
                "--id",
                issue_id,
                "--state",
                state,
                "--mode",
                "auto",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
        return result.returncode

    def promote_proposal(
        self,
        title: str,
        detail: str,
        dedup_key: str | None = None,
        *,
        state: str | None = None,
    ) -> tuple[int, str | None]:
        if self._idea_runner is not None:
            return _coerce_idea_result(self._idea_runner(title, detail))
        return _coerce_idea_result(
            self._default_idea_runner(
                title, detail, dedup_key=dedup_key, state=state
            )
        )

    def sync_status(self, external_id: str, action: str) -> int:
        issue_id = self.parse_ref(external_id) or external_id.strip().upper()
        norm = action.strip().casefold()
        if norm == "done":
            target_state = "Done"
        elif norm in {"cancelled", "canceled", "dismiss", "dismissed"}:
            target_state = "Canceled"
        elif norm in {"in_progress", "in progress"}:
            target_state = "In Progress"
        elif norm == "triage":
            target_state = "Triage"
        else:
            target_state = "Todo"
        runner = self._status_runner or self._default_status_runner
        return int(runner(issue_id, target_state))


def read_configured_provider_mode(
    config_path: Path | None = None,
) -> tuple[str, str]:
    """Return `(mode, team_key)` from env -> todo-sync.json -> config defaults."""
    env_mode = os.environ.get("AIDASH_TODO_SYNC_PROVIDER", "").strip().lower()
    env_team = os.environ.get("AIDASH_TODO_SYNC_TEAM_KEY", "").strip().upper()

    file_mode = ""
    file_team = ""
    path = config_path or TODO_SYNC_CONFIG_PATH
    if path.is_file():
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(payload, dict):
                file_mode = str(payload.get("provider") or "").strip().lower()
                file_team = str(payload.get("teamKey") or "").strip().upper()
        except (OSError, json.JSONDecodeError):
            pass

    mode = env_mode or file_mode or str(TODO_SYNC_PROVIDER or "auto").strip().lower()
    if mode in {"none", "off", "disabled", "local_only", "local-only"}:
        mode = "local"
    if mode not in {"auto", "local", "linear"}:
        mode = "auto"

    team_key = env_team or file_team or str(LINEAR_TEAM_KEY or "TIA").strip().upper()
    return mode, team_key


def resolve_todo_sync_provider(
    provider: TodoSyncProvider | str | None = None,
    *,
    config_path: Path | None = None,
    local_todos_path: Path | None = None,
    linear_script_path: Path | None = None,
    team_key: str | None = None,
    linear_runner: Callable[[str, str], Any] | None = None,
    linear_status_runner: Callable[[str, str], int] | None = None,
) -> TodoSyncProvider:
    """Resolve the active TodoSyncProvider from explicit args, config file, or auto-detection."""
    if provider is not None and not isinstance(provider, str):
        return provider

    if linear_runner is not None or linear_status_runner is not None:
        _, configured_team = read_configured_provider_mode(config_path)
        return LinearTodoSyncProvider(
            team_key=team_key or configured_team,
            script_path=linear_script_path,
            idea_runner=linear_runner,
            status_runner=linear_status_runner,
        )

    configured_mode, configured_team = read_configured_provider_mode(config_path)
    effective_mode = (
        provider.strip().lower()
        if isinstance(provider, str) and provider.strip()
        else configured_mode
    )
    if effective_mode in {"none", "off", "disabled", "local_only", "local-only"}:
        effective_mode = "local"
    effective_team = (team_key or configured_team or "TIA").strip().upper()

    if effective_mode == "local":
        return LocalTodoSyncProvider(local_todos_path=local_todos_path)

    linear_provider = LinearTodoSyncProvider(
        team_key=effective_team,
        script_path=linear_script_path,
    )
    if effective_mode == "linear":
        return linear_provider

    # "auto" mode: prefer Linear when linear-sync.py is available, otherwise local-only.
    if linear_provider.is_enabled():
        return linear_provider
    return LocalTodoSyncProvider(local_todos_path=local_todos_path)
