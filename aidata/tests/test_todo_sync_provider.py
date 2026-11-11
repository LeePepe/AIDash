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


@pytest.mark.unit
def test_export_job_actions_and_acknowledge_job_action_bridge(tmp_path: Path):
    proposals = tmp_path / "proposals.jsonl"
    proposals.write_text(
        json.dumps(
            {
                "id": "improve-m1-review-pingpong",
                "ts": "2026-11-11T00:00:00Z",
                "agent": "retro-loop",
                "title": "缩减审核返工拉锯",
                "detail": "H1-H5 root cause details",
                "priority": "high",
                "status": "pending",
            },
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    sample_items = [
        inbox.InboxItem(
            title="[in_progress] TIA-340 [Goal] dsh-action-items-unify",
            priority="high",
            bucket="卡顿",
            ref="linear://TIA-340",
            category="blocked",
            waiting_on="Owner",
        ),
        inbox.InboxItem(
            title="待决策（retro-loop）：缩减审核返工拉锯",
            priority="high",
            bucket="待决策",
            ref="proposal://improve-m1-review-pingpong",
            category="decision",
            waiting_on="Owner GO",
        ),
        inbox.InboxItem(
            title="[Teams @我] colleague: 请看 PR #303",
            priority="high",
            bucket="待决策",
            ref="teams-msg-1",
            category="work_watch",
            waiting_on="Owner",
        ),
    ]
    jobs_root = tmp_path / "jobs"
    exported = inbox.export_job_actions(
        sample_items,
        jobs_root=jobs_root,
        job_id="aidata-digest",
        created_at="2026-11-11T08:00:00Z",
        proposals_path=proposals,
    )
    assert exported is not None and exported.is_file()
    assert (jobs_root / "my-pr-supervisor" / "actions.jsonl").is_file()
    assert (jobs_root / "pr-auto-review" / "actions.jsonl").is_file()

    lines = [
        json.loads(line)
        for line in exported.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    assert [a["id"] for a in lines] == [
        "linear-TIA-340",
        "proposal-improve-m1-review-pingpong",
        "work-watch-teams-msg-1",
    ]
    assert "H1-H5 root cause details" in lines[1]["descriptionMd"]

    promoted_calls: list[tuple[str, str]] = []
    status_calls: list[tuple[str, str]] = []
    comment_calls: list[tuple[str, str]] = []

    events = [
        {
            "id": "evt-ack-1",
            "timestamp": "2026-11-11T09:00:00Z",
            "cardId": "scheduled-pulse/aidata-digest",
            "cardType": "scheduledPulse",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "aidata-digest:linear-TIA-340|"
                + json.dumps(
                    [
                        {"controlID": "decision", "value": "Done"},
                        {"controlID": "note", "value": "Verified on Mac mini"},
                    ],
                    ensure_ascii=False,
                )
            ),
        },
        {
            "id": "evt-ack-2",
            "timestamp": "2026-11-11T09:01:00Z",
            "cardId": "scheduled-pulse/aidata-digest",
            "cardType": "scheduledPulse",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "aidata-digest:proposal-improve-m1-review-pingpong|"
                + json.dumps(
                    [
                        {"controlID": "decision", "value": "Promote to Linear TIA"},
                        {"controlID": "note", "value": "Create TIA issue"},
                    ],
                    ensure_ascii=False,
                )
            ),
        },
        # Duplicate receipt in same batch should be ignored idempotently
        {
            "id": "evt-ack-2-dup",
            "timestamp": "2026-11-11T09:02:00Z",
            "cardId": "scheduled-pulse/aidata-digest",
            "cardType": "scheduledPulse",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "aidata-digest:proposal-improve-m1-review-pingpong|"
                + json.dumps(
                    [
                        {"controlID": "decision", "value": "Promote to Linear TIA"},
                        {"controlID": "note", "value": "Create TIA issue"},
                    ],
                    ensure_ascii=False,
                )
            ),
        },
    ]

    summary = event_bridge.process_user_events(
        events,
        proposals_path=proposals,
        linear_runner=lambda title, detail: promoted_calls.append((title, detail)) or (0, "TIA-341"),
        linear_status_runner=lambda ident, state: status_calls.append((ident, state)) or 0,
        linear_comment_runner=lambda ident, body: comment_calls.append((ident, body)) or 0,
    )
    assert summary["resolved"] == 1
    assert summary["promoted"] == 1
    assert summary["ignored"] == 1
    assert summary["errors"] == 0
    assert status_calls == [("TIA-340", "Done")]
    assert comment_calls == [("TIA-340", "[AIDash Action Items · Done] Verified on Mac mini")]
    assert promoted_calls == [("缩减审核返工拉锯", "H1-H5 root cause details")]

    cursor_file = tmp_path / "cursor.json"
    rc = event_bridge.main(
        [
            "--proposals-path",
            str(proposals),
            "--events-json",
            json.dumps(events[0]),
            "--cursor-path",
            str(cursor_file),
        ]
    )
    assert rc == 0
    assert cursor_file.is_file()
