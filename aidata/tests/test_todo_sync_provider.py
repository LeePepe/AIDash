"""Unit tests for the pluggable TodoSyncProvider architecture (TodoSyncProvider v1)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from L5_apps.digest import event_bridge, inbox
from L5_apps.digest.todo_sync_provider import (
    LinearTodoSyncProvider,
    LocalTodoSyncProvider,
    TodoSyncProvider,
    read_open_local_todos,
    resolve_todo_sync_provider,
)


@pytest.mark.unit
def test_local_provider_satisfies_protocol_and_lifecycle(tmp_path: Path):
    local_path = tmp_path / "local_todos.jsonl"
    provider = LocalTodoSyncProvider(local_todos_path=local_path)
    assert isinstance(provider, TodoSyncProvider)
    assert provider.name == "local"
    assert provider.is_enabled()

    rc1, ref1 = provider.promote_proposal("Fix standalone mode", "Zero Linear coupling")
    assert rc1 == 0
    assert ref1 == "local://LOCAL-1"
    assert provider.parse_ref("local://LOCAL-1") == "LOCAL-1"
    assert provider.parse_ref("LOCAL-1") == "LOCAL-1"
    assert provider.format_ref("LOCAL-1") == "local://LOCAL-1"

    rc2, ref2 = provider.promote_proposal("Second local task", "Details")
    assert rc2 == 0
    assert ref2 == "local://LOCAL-2"

    open_items = read_open_local_todos(local_path)
    assert [item.id for item in open_items] == ["LOCAL-1", "LOCAL-2"]

    assert provider.sync_status("local://LOCAL-1", "done") == 0
    open_after_done = read_open_local_todos(local_path)
    assert [item.id for item in open_after_done] == ["LOCAL-2"]

    assert provider.sync_status("LOCAL-1", "undone") == 0
    open_after_undone = read_open_local_todos(local_path)
    assert [item.id for item in open_after_undone] == ["LOCAL-1", "LOCAL-2"]


@pytest.mark.unit
def test_linear_provider_satisfies_protocol_and_formats_refs(tmp_path: Path):
    script = tmp_path / "linear-sync.py"
    script.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
    promoted: list[tuple[str, str]] = []
    statuses: list[tuple[str, str]] = []

    provider = LinearTodoSyncProvider(
        team_key="TIA",
        script_path=script,
        idea_runner=lambda title, detail: promoted.append((title, detail)) or (0, "TIA-101"),
        status_runner=lambda ident, state: statuses.append((ident, state)) or 0,
    )
    assert isinstance(provider, TodoSyncProvider)
    assert provider.name == "linear"
    assert provider.is_enabled()
    assert provider.format_ref("TIA-101") == "linear://TIA-101"
    assert provider.format_ref("MY-5") == "MY-5"
    assert provider.parse_ref("linear://TIA-101") == "TIA-101"
    assert provider.parse_ref("TIA-101") == "TIA-101"
    assert provider.parse_ref("local://LOCAL-1") is None

    rc, ext_id = provider.promote_proposal("Ship pluggable sync", "Spec v1")
    assert rc == 0
    assert ext_id == "TIA-101"
    assert promoted == [("Ship pluggable sync", "Spec v1")]

    assert provider.sync_status("linear://TIA-101", "done") == 0
    assert provider.sync_status("TIA-101", "undone") == 0
    assert statuses == [("TIA-101", "Done"), ("TIA-101", "Todo")]


@pytest.mark.unit
def test_resolve_todo_sync_provider_auto_and_config_override(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    monkeypatch.delenv("AIDASH_TODO_SYNC_PROVIDER", raising=False)
    monkeypatch.delenv("AIDASH_TODO_SYNC_TEAM_KEY", raising=False)

    missing_script = tmp_path / "missing-linear-sync.py"
    cfg_file = tmp_path / "todo-sync.json"

    # Auto mode without linear-sync.py falls back to LocalTodoSyncProvider
    auto_local = resolve_todo_sync_provider(
        config_path=cfg_file,
        linear_script_path=missing_script,
        local_todos_path=tmp_path / "local.jsonl",
    )
    assert auto_local.name == "local"

    # Auto mode with existing linear-sync.py selects LinearTodoSyncProvider
    present_script = tmp_path / "linear-sync.py"
    present_script.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
    auto_linear = resolve_todo_sync_provider(
        config_path=cfg_file,
        linear_script_path=present_script,
    )
    assert auto_linear.name == "linear"

    # Config file with {"provider": "local"} forces LocalTodoSyncProvider even if script exists
    cfg_file.write_text(
        json.dumps({"provider": "local", "teamKey": "TIA"}),
        encoding="utf-8",
    )
    forced_local = resolve_todo_sync_provider(
        config_path=cfg_file,
        linear_script_path=present_script,
        local_todos_path=tmp_path / "local.jsonl",
    )
    assert forced_local.name == "local"


@pytest.mark.unit
def test_event_bridge_and_inbox_work_in_standalone_local_mode(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    proposals = tmp_path / "proposals.jsonl"
    proposals.write_text(
        json.dumps(
            {
                "id": "p-local-1",
                "ts": "2026-11-09T00:00:00Z",
                "agent": "retro",
                "title": "Standalone local task",
                "detail": "Works without Linear",
                "priority": "high",
                "status": "pending",
            }
        )
        + "\n",
        encoding="utf-8",
    )
    local_todos = tmp_path / "local_todos.jsonl"
    local_provider = LocalTodoSyncProvider(local_todos_path=local_todos)

    # 1. Star proposal in local mode -> promotes to local://LOCAL-1
    res1 = event_bridge.process_user_events(
        [{"action": "star", "itemRef": "proposal://p-local-1"}],
        proposals_path=proposals,
        local_todos_path=local_todos,
        provider=local_provider,
    )
    assert res1["promoted"] == 1

    # 2. Inbox surfaces LOCAL-1 in standalone mode even when warehouse has no issues
    monkeypatch.setattr(inbox.serve, "run_query", lambda *a, **k: ([], []))
    items = inbox._pending_issues(
        provider=local_provider, local_todos_path=local_todos
    )
    assert len(items) == 1
    assert items[0].ref == "local://LOCAL-1"
    assert "Standalone local task" in items[0].title

    # 3. Marking local://LOCAL-1 done via event_bridge resolves it locally
    res2 = event_bridge.process_user_events(
        [
            {
                "action": "done",
                "itemRef": "local://LOCAL-1",
                "timestamp": "2026-11-09T01:00:00Z",
            }
        ],
        proposals_path=proposals,
        local_todos_path=local_todos,
        provider=local_provider,
    )
    assert res2["resolved"] == 1
    assert inbox._pending_issues(provider=local_provider, local_todos_path=local_todos) == []
