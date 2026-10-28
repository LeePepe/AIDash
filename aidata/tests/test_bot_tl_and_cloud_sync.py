from pathlib import Path

import pytest
from adapters import bot_tl, cloud_sync


@pytest.mark.unit
def test_bot_tl_normalizes_supervision_and_heartbeat(monkeypatch):
    raw = [
        {
            "collector": "bot_tl",
            "record_type": "bot_tl_event",
            "device_id": "d1",
            "machine_alias": "mini",
            "goal_id": "g1",
            "payload": {
                "ts": "2026-10-28T01:00:00+08:00",
                "evt": "HOT_APPEND",
                "status": "active",
            },
        },
        {
            "collector": "prmon",
            "record_type": "prmon_heartbeat",
            "device_id": "d1",
            "machine_alias": "mini",
            "payload": {
                "ts": "2026-10-28T01:01:00+08:00",
                "checked_pr_count": 3,
                "stuck_pr_count": 1,
                "repair_queued_count": 1,
                "status": "ok",
            },
        },
    ]
    captured = {}
    monkeypatch.setattr(bot_tl, "read_raw", lambda _source: raw)

    def capture(_source, table, _ddl, rows, _columns):
        captured[table] = rows
        return len(rows)

    monkeypatch.setattr(bot_tl, "write_clean", capture)
    assert bot_tl.normalize() == 1
    assert captured["supervision"][0]["action_kind"] == "HOT_APPEND"
    assert captured["prmon_heartbeat"][0]["stuck_pr_count"] == 1


@pytest.mark.unit
def test_cloud_sync_disabled_is_noop(monkeypatch):
    monkeypatch.setattr(cloud_sync, "AIDATA_SYNC_STORAGE_ACCOUNT", "")
    assert cloud_sync.pull_remote_batches() == 0


@pytest.mark.unit
def test_cloud_sync_blob_parts_and_hash_suffix():
    name = "aidata-sync/v1/machines/device-1/batches/2026-10-28_deadbeef1234.jsonl"
    assert cloud_sync._blob_parts(name) == ("device-1", "2026-10-28_deadbeef1234.jsonl")
    assert cloud_sync._sha_suffix(Path(name).name) == "deadbeef1234"
