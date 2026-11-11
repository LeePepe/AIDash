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
        {
            "id": "evt-ack-undone",
            "timestamp": "2026-11-11T09:03:00Z",
            "cardId": "scheduled-pulse/aidata-digest",
            "cardType": "scheduledPulse",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "aidata-digest:linear-TIA-341|"
                + json.dumps(
                    [
                        {"controlID": "decision", "value": "undone"},
                        {"controlID": "note", "value": "Reopened"},
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
    assert summary["undone"] == 1
    assert summary["promoted"] == 1
    assert summary["ignored"] == 1
    assert summary["errors"] == 0
    assert status_calls == [("TIA-340", "Done"), ("TIA-341", "Todo")]
    assert comment_calls == [
        ("TIA-340", "[AIDash Action Items · Done] Verified on Mac mini"),
        ("TIA-341", "[AIDash Action Items · undone] Reopened"),
    ]
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

    # Verify knowledge:// Promote to Linear TIA creates a Linear issue without publishing blog
    proposals.write_text(
        json.dumps(
            {
                "id": "learn-spec-1",
                "ref": "knowledge://spec-1",
                "ts": "2026-11-11T00:00:00Z",
                "agent": "knowledge-digest",
                "title": "学习卡片：Spec 1",
                "detail": "Details",
                "priority": "medium",
                "status": "pending",
            },
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    blog_calls: list[str] = []
    know_promote_calls: list[tuple[str, str]] = []
    know_summary = event_bridge.process_user_events(
        [
            {
                "id": "evt-know-promote",
                "timestamp": "2026-11-11T09:05:00Z",
                "cardId": "scheduled-pulse/aidata-digest",
                "cardType": "scheduledPulse",
                "action": "acknowledgeJobAction",
                "itemRef": (
                    "aidata-digest:knowledge-spec-1|"
                    + json.dumps([{"controlID": "decision", "value": "Promote to Linear TIA"}])
                ),
            }
        ],
        proposals_path=proposals,
        linear_runner=lambda title, detail: know_promote_calls.append((title, detail)) or (0, "TIA-342"),
        blog_publish_runner=lambda slug, *a: blog_calls.append(slug) or 0,
    )
    assert know_summary["promoted"] == 1
    assert know_summary["blog_published"] == 0
    assert blog_calls == []
    assert know_promote_calls == [("学习卡片：Spec 1", "Details")]

    # Forged / cross-job receipts must be ignored without mutating Linear or proposals
    forged_events = [
        {
            "id": "forged-1",
            "timestamp": "2026-11-11T09:10:00Z",
            "cardId": "scheduled-pulse/my-pr-supervisor",
            "cardType": "scheduledPulse",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "my-pr-supervisor:linear-TIA-340|"
                + json.dumps([{"controlID": "decision", "value": "Done"}])
            ),
        },
        {
            "id": "forged-2",
            "timestamp": "2026-11-11T09:11:00Z",
            "cardId": "scheduled-pulse/aidata-digest",
            "cardType": "scheduledPulse",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "pr-auto-review:linear-TIA-340|"
                + json.dumps([{"controlID": "decision", "value": "Done"}])
            ),
        },
        {
            "id": "forged-3",
            "timestamp": "2026-11-11T09:12:00Z",
            "cardId": "scheduled-pulse/aidata-digest",
            "cardType": "otherCard",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "aidata-digest:linear-TIA-340|"
                + json.dumps([{"controlID": "decision", "value": "Done"}])
            ),
        },
    ]
    forged_calls: list[tuple[str, str]] = []
    forged_summary = event_bridge.process_user_events(
        forged_events,
        proposals_path=proposals,
        linear_status_runner=lambda ident, state: forged_calls.append((ident, state)) or 0,
    )
    assert forged_summary["resolved"] == 0
    assert forged_summary["ignored"] == 3
    assert forged_calls == []

    # Partial-failure batch persists consumed cursor per item so retry does not duplicate
    partial_cursor = tmp_path / "partial_cursor.json"
    local_todos = tmp_path / "partial_local.jsonl"
    local_prov = LocalTodoSyncProvider(local_todos_path=local_todos)
    batch_events = [
        {
            "id": "batch-ok-1",
            "timestamp": "2026-11-11T09:20:00Z",
            "cardId": "scheduled-pulse/aidata-digest",
            "cardType": "scheduledPulse",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "aidata-digest:work-watch-msg-1|"
                + json.dumps([{"controlID": "decision", "value": "Promote to Linear TIA"}])
            ),
        },
        {
            "id": "batch-fail-2",
            "timestamp": "2026-11-11T09:21:00Z",
            "cardId": "scheduled-pulse/aidata-digest",
            "cardType": "scheduledPulse",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "aidata-digest:proposal-missing-id|"
                + json.dumps([{"controlID": "decision", "value": "Promote to Linear TIA"}])
            ),
        },
    ]
    res_first = event_bridge.process_user_events(
        batch_events,
        proposals_path=proposals,
        provider=local_prov,
        cursor_path=partial_cursor,
    )
    assert res_first["promoted"] == 1
    assert len(read_open_local_todos(local_todos)) == 1
    # Replay same batch -> already-promoted item is skipped via per-item cursor and dedup_key
    res_retry = event_bridge.process_user_events(
        batch_events,
        proposals_path=proposals,
        provider=local_prov,
        cursor_path=partial_cursor,
    )
    assert res_retry["promoted"] == 0
    assert len(read_open_local_todos(local_todos)) == 1


@pytest.mark.unit
def test_cross_device_actionable_item_schema_and_approve_done_dismiss_flows(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    proposals = tmp_path / "proposals.jsonl"
    proposals.write_text(
        json.dumps(
            {
                "id": "retro-lock-1",
                "ts": "2026-11-11T00:00:00Z",
                "agent": "retro-loop",
                "title": "锁定跨设备待办契约",
                "detail": "H1 root cause: unify DSH and AIDash via Linear TIA.",
                "priority": "high",
                "status": "pending",
            },
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    items = [
        inbox.InboxItem(
            title="[triage] TIA-76 [Bing] iOS Smart Banner / SERP",
            priority="high",
            bucket="待决策",
            ref="linear://TIA-76",
            category="decision",
            waiting_on="Owner",
            status="triage",
            source="Linear",
            url="https://linear.app/tianpeili/issue/TIA-76",
            sub_items=("item-a", "item-b"),
        ),
        inbox.InboxItem(
            title="[blocked] TIA-77 GTT blocked on owner decision",
            priority="high",
            bucket="卡顿",
            ref="linear://TIA-77",
            category="blocked",
            waiting_on="Owner",
        ),
        inbox.InboxItem(
            title="待决策（retro-loop）：锁定跨设备待办契约",
            priority="high",
            bucket="待决策",
            ref="proposal://retro-lock-1",
            category="decision",
            waiting_on="Owner GO",
        ),
    ]
    actions = inbox.build_job_actions(
        items,
        job_id="aidata-digest",
        created_at="2026-11-11T16:00:00Z",
        proposals_path=proposals,
    )
    assert len(actions) == 3

    a0 = actions[0]
    assert a0["id"] == "linear-TIA-76"
    assert a0["title"] == "[Bing] iOS Smart Banner / SERP"
    assert a0["status"] == "triage"
    assert a0["source"] == "Linear"
    assert a0["priority"] == "P0"
    assert a0["ref"] == "linear://TIA-76"
    assert a0["url"] == "https://linear.app/tianpeili/issue/TIA-76"
    assert a0["description"] == a0["descriptionMd"]
    assert "来源分类" not in str(a0["description"])
    controls0 = a0["controls"]
    assert [c["id"] for c in controls0] == ["decision", "targets", "note"]
    assert controls0[0]["options"] == ["Approve", "Done", "Dismiss"]
    assert controls0[1]["kind"] == "multiSelect"
    assert controls0[1]["options"] == ["item-a", "item-b"]
    assert controls0[2]["kind"] == "textInput"
    assert controls0[2]["maxLength"] == 80

    a1 = actions[1]
    assert a1["id"] == "linear-TIA-77"
    assert a1["status"] == "blocked"
    assert a1["source"] == "Linear"
    assert [c["id"] for c in a1["controls"]] == ["decision", "note"]

    a2 = actions[2]
    assert a2["id"] == "proposal-retro-lock-1"
    assert a2["title"] == "锁定跨设备待办契约"
    assert a2["status"] == "triage"
    assert a2["source"] == "Retro"
    assert a2["priority"] == "P0"
    assert "H1 root cause: unify DSH and AIDash via Linear TIA." in str(a2["description"])

    monkeypatch.setattr(
        inbox.serve,
        "run_query",
        lambda name, params=None: (
            (
                [
                    ("TIA-76", "[Bing] iOS Smart Banner / SERP", "triage", "high"),
                    ("TIA-77", "GTT blocked on owner decision", "blocked", "high"),
                    ("TIA-78", "Obsolete triage item", "triage", "low"),
                ],
                ["identifier", "title", "status", "priority"],
            )
            if name == "inbox/pending-issues"
            else ([], [])
        ),
    )

    promoted_calls: list[tuple[str, str]] = []
    status_calls: list[tuple[str, str]] = []
    comment_calls: list[tuple[str, str]] = []

    ack_events = [
        # 1) Approve on triage Linear issue -> Todo + comment with targets & note
        {
            "id": "ack-triage-approve",
            "timestamp": "2026-11-11T16:01:00Z",
            "cardId": "scheduled-pulse/aidata-digest",
            "cardType": "scheduledPulse",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "aidata-digest:linear-TIA-76|"
                + json.dumps(
                    [
                        {"controlID": "decision", "value": "Approve"},
                        {"controlID": "targets", "value": "item-a,item-b"},
                        {"controlID": "note", "value": "Ship in wave 1"},
                    ],
                    ensure_ascii=False,
                )
            ),
        },
        # 2) Approve on blocked Linear issue -> In Progress + comment
        {
            "id": "ack-blocked-approve",
            "timestamp": "2026-11-11T16:02:00Z",
            "cardId": "scheduled-pulse/aidata-digest",
            "cardType": "scheduledPulse",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "aidata-digest:linear-TIA-77|"
                + json.dumps(
                    [
                        {"controlID": "decision", "value": "Approve"},
                        {"controlID": "note", "value": "GO approved"},
                    ],
                    ensure_ascii=False,
                )
            ),
        },
        # 3) Dismiss on Linear issue -> Canceled
        {
            "id": "ack-linear-dismiss",
            "timestamp": "2026-11-11T16:03:00Z",
            "cardId": "scheduled-pulse/aidata-digest",
            "cardType": "scheduledPulse",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "aidata-digest:linear-TIA-78|"
                + json.dumps(
                    [
                        {"controlID": "decision", "value": "Dismiss"},
                        {"controlID": "note", "value": "Not needed"},
                    ],
                    ensure_ascii=False,
                )
            ),
        },
        # 4) Approve on unpromoted proposal -> promote_proposal + Todo + comment
        {
            "id": "ack-prop-approve",
            "timestamp": "2026-11-11T16:04:00Z",
            "cardId": "scheduled-pulse/aidata-digest",
            "cardType": "scheduledPulse",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "aidata-digest:proposal-retro-lock-1|"
                + json.dumps(
                    [
                        {"controlID": "decision", "value": "Approve"},
                        {"controlID": "note", "value": "Promote to TIA Todo"},
                    ],
                    ensure_ascii=False,
                )
            ),
        },
    ]

    summary = event_bridge.process_user_events(
        ack_events,
        proposals_path=proposals,
        linear_runner=lambda title, detail: promoted_calls.append((title, detail)) or (0, "TIA-350"),
        linear_status_runner=lambda ident, state: status_calls.append((ident, state)) or 0,
        linear_comment_runner=lambda ident, body: comment_calls.append((ident, body)) or 0,
    )
    assert summary["promoted"] == 1
    assert summary["undone"] == 2
    assert summary["resolved"] == 1
    assert summary["errors"] == 0
    assert status_calls == [
        ("TIA-76", "Todo"),
        ("TIA-77", "In Progress"),
        ("TIA-78", "Canceled"),
        ("TIA-350", "Todo"),
    ]
    assert comment_calls == [
        ("TIA-76", "[AIDash Action Items · Approve] targets=item-a,item-b | Ship in wave 1"),
        ("TIA-77", "[AIDash Action Items · Approve] GO approved"),
        ("TIA-78", "[AIDash Action Items · Dismiss] Not needed"),
        ("TIA-350", "[AIDash Action Items · Approve] Promote to TIA Todo"),
    ]

    # 5) If Approve creates issue but sync_status(Todo) fails, do not consume event;
    #    retry reuses the created issue ID without creating a duplicate and completes Todo sync.
    retry_proposals = tmp_path / "retry_proposals.jsonl"
    retry_proposals.write_text(
        json.dumps(
            {
                "id": "retry-prop-1",
                "ts": "2026-11-11T00:00:00Z",
                "agent": "retro-loop",
                "title": "Retryable proposal",
                "detail": "Details",
                "priority": "high",
                "status": "pending",
            }
        )
        + "\n",
        encoding="utf-8",
    )
    retry_cursor = tmp_path / "retry_cursor.json"
    retry_ideas: list[tuple[str, str]] = []
    retry_statuses: list[tuple[str, str]] = []
    fail_todo = {"should_fail": True}

    def flaky_status(ident: str, state: str) -> int:
        retry_statuses.append((ident, state))
        if fail_todo["should_fail"]:
            return 1
        return 0

    retry_event = [
        {
            "id": "ack-retry-prop",
            "timestamp": "2026-11-11T16:10:00Z",
            "cardId": "scheduled-pulse/aidata-digest",
            "cardType": "scheduledPulse",
            "action": "acknowledgeJobAction",
            "itemRef": (
                "aidata-digest:proposal-retry-prop-1|"
                + json.dumps([{"controlID": "decision", "value": "Approve"}])
            ),
        }
    ]
    res_fail = event_bridge.process_user_events(
        retry_event,
        proposals_path=retry_proposals,
        cursor_path=retry_cursor,
        linear_runner=lambda title, detail: retry_ideas.append((title, detail)) or (0, "TIA-360"),
        linear_status_runner=flaky_status,
    )
    assert res_fail["promoted"] == 0
    assert res_fail["errors"] == 1
    assert len(retry_ideas) == 1
    assert retry_statuses == [("TIA-360", "Todo")]

    fail_todo["should_fail"] = False
    res_recover = event_bridge.process_user_events(
        retry_event,
        proposals_path=retry_proposals,
        cursor_path=retry_cursor,
        linear_runner=lambda title, detail: retry_ideas.append((title, detail)) or (0, "TIA-361"),
        linear_status_runner=flaky_status,
    )
    assert res_recover["promoted"] == 1
    assert res_recover["errors"] == 0
    assert len(retry_ideas) == 1
    assert retry_statuses == [("TIA-360", "Todo"), ("TIA-360", "Todo")]

    # 6) sync_triage=True promotes unpromoted items to Linear Triage, rewrites action["id"]
    #    to linear-TIA-xx, and subsequent Done/Approve/Dismiss routes to that Linear issue.
    triage_proposals = tmp_path / "triage_proposals.jsonl"
    triage_proposals.write_text(
        json.dumps(
            {
                "id": "triage-prop-1",
                "ts": "2026-11-11T00:00:00Z",
                "agent": "retro-loop",
                "title": "Sync to Linear Triage",
                "detail": "Triage detail",
                "priority": "high",
                "status": "pending",
            }
        )
        + "\n",
        encoding="utf-8",
    )
    triage_provider = LinearTodoSyncProvider(
        team_key="TIA",
        script_path=tmp_path / "linear-sync.py",
        idea_runner=lambda title, detail: (0, "TIA-370"),
        status_runner=lambda ident, state: 0,
    )
    synced_actions = inbox.build_job_actions(
        [
            inbox.InboxItem(
                title="待决策（retro-loop）：Sync to Linear Triage",
                priority="high",
                bucket="待决策",
                ref="proposal://triage-prop-1",
                category="decision",
            )
        ],
        proposals_path=triage_proposals,
        provider=triage_provider,
        sync_triage=True,
    )
    assert len(synced_actions) == 1
    assert synced_actions[0]["id"] == "linear-TIA-370"
    assert synced_actions[0]["ref"] == "linear://TIA-370"
    assert synced_actions[0]["url"] == "https://linear.app/tianpeili/issue/TIA-370"
    assert synced_actions[0]["status"] == "triage"



