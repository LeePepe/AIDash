"""Unit tests for bookmark-cursor mail_inbox and work_teams_bridge adapters (DSH Mechanism 4)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
from adapters import mail_inbox, work_teams_bridge


@pytest.fixture
def isolated_watermarks(monkeypatch: pytest.MonkeyPatch) -> dict[str, Any]:
    store: dict[str, Any] = {}
    for mod in (mail_inbox, work_teams_bridge):
        monkeypatch.setattr(mod, "get_watermark", lambda key, _s=store: _s.get(key))
        monkeypatch.setattr(mod, "set_watermark", lambda key, val, _s=store: _s.__setitem__(key, val))
    return store


@pytest.mark.unit
def test_mail_inbox_pull_cursor_redaction_and_reply_idempotency(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    isolated_watermarks: dict[str, Any],
) -> None:
    drop_dir = tmp_path / "mail-drop"
    drop_dir.mkdir(parents=True)
    shard = drop_dir / "2026-11-11.jsonl"
    shard.write_text(
        "\n".join(
            [
                json.dumps(
                    {
                        "id": "m1",
                        "message_id": "msg-001",
                        "received_at": "2026-11-11T01:00:00Z",
                        "sender": "alice@corp.example.com",
                        "subject": "Urgent: please review architecture spec @tianpei",
                        "snippet": "Token is sk-1234567890abcdefghijklmnop and needs action",
                    }
                ),
                json.dumps(
                    {
                        "id": "m2",
                        "message_id": "msg-002",
                        "received_at": "2026-11-11T02:00:00Z",
                        "sender": "bob@newsletter.example.com",
                        "subject": "Weekly digest newsletter",
                        "snippet": "General FYI summary",
                    }
                ),
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    raw_store: list[dict[str, Any]] = []
    monkeypatch.setattr(mail_inbox, "MAIL_INBOX_DROP_DIR", drop_dir)
    monkeypatch.setattr(mail_inbox, "MAIL_INBOX_ENABLE_JXA", False)
    monkeypatch.setattr(
        mail_inbox,
        "write_raw",
        lambda _source, records: raw_store.extend(records) or len(list(records)),
    )
    monkeypatch.setattr(mail_inbox, "read_raw", lambda _source: list(raw_store))

    captured_clean: dict[str, list[dict[str, Any]]] = {}

    def _capture_mail_clean(_src: str, table: str, _ddl: str, rows: list[dict[str, Any]], _cols: Any) -> int:
        captured_clean[table] = list(rows)
        return len(rows)

    monkeypatch.setattr(mail_inbox, "write_clean", _capture_mail_clean)

    # First collect ingests both records and advances cursor
    written = mail_inbox.collect()
    assert written == 2
    assert len(raw_store) == 2
    assert "<REDACTED>" in raw_store[0]["snippet_preview"]
    assert "sk-1234567890" not in raw_store[0]["snippet_preview"]
    assert raw_store[0]["sender_domain"] == "corp.example.com"
    assert raw_store[0]["has_mention"] == 1
    assert raw_store[0]["is_todo"] == 1
    assert raw_store[0]["priority"] == "high"

    # Second collect with no new messages returns 0 (no replay on restart)
    assert mail_inbox.collect() == 0

    # Pull with explicit --after cursor returns only strictly newer items
    first_cursor = raw_store[0]["cursor"]
    after_first = mail_inbox.pull(after=first_cursor, drop_dir=drop_dir)
    assert [item["item_id"] for item in after_first["items"]] == ["msg-002"]

    # Mark msg-001 as replied via reply --key; verify idempotency and normalize reflection
    ack1 = mail_inbox.reply(key="mail:msg-001", note="handled by agent")
    assert ack1["ok"] is True
    assert ack1["duplicate"] is False
    ack2 = mail_inbox.reply(key="mail:msg-001")
    assert ack2["duplicate"] is True

    assert mail_inbox.normalize() == 2
    rows_by_id = {row["item_id"]: row for row in captured_clean["mail_inbox_item"]}
    assert rows_by_id["msg-001"]["replied"] == 1
    assert rows_by_id["msg-002"]["replied"] == 0

    # Out-of-order / late-arriving older shard record (timestamp < current cursor) is still ingested once
    late_shard = drop_dir / "2026-11-10-late.jsonl"
    late_shard.write_text(
        json.dumps(
            {
                "id": "m0",
                "message_id": "msg-000",
                "received_at": "2026-11-11T00:30:00Z",
                "sender": "late@corp.example.com",
                "subject": "Urgent: delayed sync message @tianpei",
                "snippet": "Needs review",
            }
        )
        + "\n",
        encoding="utf-8",
    )
    assert mail_inbox.collect() == 1
    assert any(r["item_id"] == "msg-000" for r in raw_store)
    assert mail_inbox.collect() == 0


@pytest.mark.unit
def test_work_teams_bridge_cursor_and_reply_idempotency(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    isolated_watermarks: dict[str, Any],
) -> None:
    drop_dir = tmp_path / "work-teams-drop"
    drop_dir.mkdir(parents=True)
    shard = drop_dir / "work-teams-2026-11-11.jsonl"
    shard.write_text(
        "\n".join(
            [
                json.dumps(
                    {
                        "item_id": "wt-101",
                        "created_at": "2026-11-11T03:00:00Z",
                        "channel_kind": "teams_mention",
                        "thread_ref": "teams://thread/101",
                        "sender_alias": "pm_lead@company.example.com",
                        "title": "@tianpei Please sign off on release readiness",
                        "summary": "Bearer secretTokenValue1234567890 in thread",
                        "has_mention": True,
                        "needs_reply": True,
                        "priority": "high",
                    }
                ),
                json.dumps(
                    {
                        "item_id": "wt-102",
                        "created_at": "2026-11-11T04:00:00Z",
                        "channel_kind": "ado_reminder",
                        "thread_ref": "ado://pr/8899",
                        "sender_alias": "ado-bot",
                        "title": "ADO PR #8899 review reminder",
                        "summary": "Waiting on your approval",
                        "has_mention": False,
                        "needs_reply": True,
                        "priority": "high",
                    }
                ),
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    raw_store: list[dict[str, Any]] = []
    monkeypatch.setattr(work_teams_bridge, "WORK_TEAMS_DROP_DIR", drop_dir)
    monkeypatch.setattr(
        work_teams_bridge,
        "write_raw",
        lambda _source, records: raw_store.extend(records) or len(list(records)),
    )
    monkeypatch.setattr(work_teams_bridge, "read_raw", lambda _source: list(raw_store))

    captured_clean: dict[str, list[dict[str, Any]]] = {}

    def _capture_teams_clean(_src: str, table: str, _ddl: str, rows: list[dict[str, Any]], _cols: Any) -> int:
        captured_clean[table] = list(rows)
        return len(rows)

    monkeypatch.setattr(work_teams_bridge, "write_clean", _capture_teams_clean)

    assert work_teams_bridge.collect() == 2
    assert len(raw_store) == 2
    assert "<REDACTED>" in raw_store[0]["summary_preview"]
    assert "<REDACTED>@company.example.com" in raw_store[0]["sender_alias"]
    assert work_teams_bridge.collect() == 0

    first_cursor = raw_store[0]["cursor"]
    delta = work_teams_bridge.pull(after=first_cursor, drop_dir=drop_dir)
    assert [item["item_id"] for item in delta["items"]] == ["wt-102"]

    reply_res = work_teams_bridge.reply(key="teams:wt-101", note="replied on Work PC")
    assert reply_res["ok"] is True
    assert reply_res["duplicate"] is False
    assert work_teams_bridge.reply(key="teams:wt-101")["duplicate"] is True

    assert work_teams_bridge.normalize() == 2
    rows_by_id = {row["item_id"]: row for row in captured_clean["work_teams_item"]}
    assert rows_by_id["wt-101"]["replied"] == 1
    assert rows_by_id["wt-102"]["replied"] == 0

    # Late-arriving older shard record (created_at < current cursor) is still ingested once
    late_shard = drop_dir / "work-teams-2026-11-10-late.jsonl"
    late_shard.write_text(
        json.dumps(
            {
                "item_id": "wt-100",
                "created_at": "2026-11-11T01:00:00Z",
                "channel_kind": "teams_reply",
                "thread_ref": "teams://thread/100",
                "sender_alias": "late_colleague",
                "title": "Delayed sync thread",
                "summary": "Waiting on reply",
                "has_mention": False,
                "needs_reply": True,
                "priority": "high",
            }
        )
        + "\n",
        encoding="utf-8",
    )
    assert work_teams_bridge.collect() == 1
    assert any(r["item_id"] == "wt-100" for r in raw_store)
    assert work_teams_bridge.collect() == 0
