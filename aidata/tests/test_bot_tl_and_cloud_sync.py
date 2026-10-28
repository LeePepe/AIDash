import io
import tarfile
from pathlib import Path

import pytest
from adapters import bot_tl, cloud_sync, gtt_ledger


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
                "generated_at": "2026-10-28T01:01:00+08:00",
                "repos": [
                    {"health": "UNAVAILABLE", "repair_queued": True},
                    {"health": "HEALTHY"},
                ],
                "coverage_complete": True,
            },
        },
        {
            "record_type": "quota_precheck",
            "device_id": "d1",
            "machine_alias": "mini",
            "payload": {"measured_at": "2026-10-28T01:02:00+08:00", "result": "pass"},
        },
        {
            "record_type": "bot_tl_event",
            "device_id": "d1",
            "payload": {
                "line": {
                    "ts": "2026-10-28T01:03:00+08:00",
                    "action_kind": "S3_CI_FIX",
                    "goal_id": "g1",
                }
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
    heartbeat = captured["prmon_heartbeat"][0]
    assert heartbeat["ts"] == "2026-10-28T01:01:00+08:00"
    assert heartbeat["checked_pr_count"] == 2
    assert heartbeat["stuck_pr_count"] == 1
    assert heartbeat["repair_queued_count"] == 1
    assert heartbeat["status"] == "complete"
    actions = {row["action_kind"] for row in captured["supervision"]}
    assert {"QUOTA_PRECHECK", "S3_CI_FIX"} <= actions


@pytest.mark.unit
def test_cloud_sync_disabled_is_noop(monkeypatch):
    monkeypatch.setattr(cloud_sync, "AIDATA_SYNC_STORAGE_ACCOUNT", "")
    assert cloud_sync.pull_remote_batches() == 0


@pytest.mark.unit
def test_cloud_sync_blob_parts_and_hash_suffix():
    name = "aidata-sync/v1/machines/device-1/batches/2026-10-28_deadbeef1234.jsonl"
    assert cloud_sync._blob_parts(name) == ("device-1", "2026-10-28_deadbeef1234.jsonl")
    dated = "aidata-sync/v1/machines/device-1/batches/2026-10-28/010203_deadbeef1234.jsonl"
    assert cloud_sync._blob_parts(dated) == ("device-1", "010203_deadbeef1234.jsonl")
    traversal = "aidata-sync/v1/machines/../../outside/batches/data.jsonl"
    assert cloud_sync._blob_parts(traversal) is None
    assert cloud_sync._sha_suffix(Path(name).name) == "deadbeef1234"


@pytest.mark.unit
def test_remote_records_scans_tgz_jsonl(monkeypatch, tmp_path):
    bundle = tmp_path / "bundle.tgz"
    payload = b'{"collector":"prmon","record_type":"prmon_heartbeat","payload":{"generated_at":"2026-10-28T01:00:00+08:00"}}\n'
    with tarfile.open(bundle, "w:gz") as archive:
        info = tarfile.TarInfo("export/heartbeat.jsonl")
        info.size = len(payload)
        archive.addfile(info, io.BytesIO(payload))
    monkeypatch.setattr(bot_tl, "GTT_XFER_DIR", tmp_path)
    records = bot_tl._remote_records()
    assert records[0]["record_type"] == "prmon_heartbeat"


@pytest.mark.unit
def test_local_ledger_headers_are_collected(monkeypatch, tmp_path):
    goal = tmp_path / "goal-1"
    goal.mkdir()
    (goal / "ledger.md").write_text(
        "TL_PROFILE=copilot/gemini-4-argon | quota_precheck=pass\n", encoding="utf-8"
    )
    monkeypatch.setattr(bot_tl, "GTT_HANDOFF_ROOTS", [tmp_path])
    records = bot_tl._local_records()
    events = [record for record in records if record["record_type"] == "bot_tl_event"]
    assert events[0]["payload"]["action_kind"] == "QUOTA_PRECHECK"


@pytest.mark.unit
def test_gtt_ledger_keeps_newer_goal_record(monkeypatch):
    raw = [
        {"record_type": "ledger", "machine_id": "m", "goal_id": "g",
         "content": "- 2026-10-28T02:00:00Z | EVT=DONE | id=B2\n",
         "mtime_iso": "2026-10-28T02:00:00+00:00"},
        {"record_type": "ledger", "machine_id": "m", "goal_id": "g",
         "content": "- 2026-10-28T01:00:00Z | EVT=START | id=B1\n",
         "mtime_iso": "2026-10-28T01:00:00+00:00"},
    ]
    captured = {}
    monkeypatch.setattr(gtt_ledger, "read_raw", lambda _source: raw)
    def capture(_source, table, _ddl, rows, _columns):
        captured[table] = rows
        return len(rows)

    monkeypatch.setattr(gtt_ledger, "write_clean", capture)
    gtt_ledger.normalize()
    assert captured["goal"][0]["last_event_at"] == "2026-10-28T02:00:00Z"
