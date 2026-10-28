import io
import json
import os
import re
import sqlite3
import tarfile
from pathlib import Path

import pytest
from adapters import bot_tl, cloud_sync, gtt_ledger


@pytest.fixture
def watermarks(monkeypatch):
    values = {}
    for module in (bot_tl, cloud_sync):
        monkeypatch.setattr(module, "get_watermark", values.get)
        monkeypatch.setattr(module, "set_watermark", values.__setitem__)
    return values


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
    monkeypatch.setattr(bot_tl, "CLAUDE_QUOTA_CACHE", tmp_path / "missing-quota.json")
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


@pytest.mark.unit
def test_prmon_history_uses_complete_utf8_byte_offsets(monkeypatch, tmp_path, watermarks):
    monkeypatch.setattr(bot_tl, "PRMON_WATCH_DIR", tmp_path)
    history = tmp_path / "heartbeat-history.jsonl"
    first = (json.dumps({"status": "正常", "ts": "2026-10-28T01:00:00Z"}, ensure_ascii=False) + "\n").encode()
    second = (json.dumps({"status": "中文", "ts": "2026-10-28T02:00:00Z"}, ensure_ascii=False) + "\n").encode()
    split = second.index("中".encode()) + 1
    history.write_bytes(first + second[:split])
    records = bot_tl._prmon_records()
    assert [record["payload"]["status"] for record in records] == ["正常"]
    assert watermarks["bot_tl_prmon_history"]["offset"] == len(first)
    assert bot_tl._prmon_records() == []
    with history.open("ab") as fh:
        fh.write(second[split:])
    assert bot_tl._prmon_records()[0]["payload"]["status"] == "中文"
    assert watermarks["bot_tl_prmon_history"]["offset"] == len(first + second)
    assert bot_tl._prmon_records() == []


@pytest.mark.unit
@pytest.mark.parametrize("change", ["truncate", "rotate", "midline"])
def test_prmon_history_recovers_changed_file_or_bad_cursor(monkeypatch, tmp_path, watermarks, change):
    monkeypatch.setattr(bot_tl, "PRMON_WATCH_DIR", tmp_path)
    history = tmp_path / "heartbeat-history.jsonl"
    history.write_bytes(b'{"status":"original long heartbeat"}\n')
    assert len(bot_tl._prmon_records()) == 1
    expected = b'{"status":"new"}\n'
    if change == "rotate":
        replacement = tmp_path / "replacement"
        replacement.write_bytes(expected)
        replacement.replace(history)
    else:
        history.write_bytes(expected)
        if change == "midline":
            watermarks["bot_tl_prmon_history"]["offset"] = 3
    assert bot_tl._prmon_records()[0]["payload"] == {"status": "new"}
    assert watermarks["bot_tl_prmon_history"]["offset"] == len(expected)
    assert bot_tl._prmon_records() == []


@pytest.mark.unit
def test_bot_tl_collect_ignores_mtime_and_remembers_replayed_history(monkeypatch, tmp_path, watermarks):
    path = tmp_path / "heartbeat.json"
    path.write_text('{"status":"ok"}', encoding="utf-8")
    monkeypatch.setattr(cloud_sync, "pull_remote_batches", lambda: 0)
    monkeypatch.setattr(bot_tl, "_local_records", list)
    monkeypatch.setattr(bot_tl, "_prmon_records", list)
    monkeypatch.setattr(bot_tl, "_remote_records", list)
    written = []
    def write(_source, rows):
        written.extend(rows)
        return len(rows)
    monkeypatch.setattr(bot_tl, "write_raw", write)
    record = bot_tl._file_record(path, "prmon_heartbeat")
    monkeypatch.setattr(bot_tl, "_prmon_records", lambda: [record, record])
    assert bot_tl.collect() == 1
    monkeypatch.setattr(bot_tl, "_prmon_records", list)
    assert bot_tl.collect() == 0
    os.utime(path, (path.stat().st_atime, path.stat().st_mtime + 10))
    touched = bot_tl._file_record(path, "prmon_heartbeat")
    assert touched["mtime_iso"] != record["mtime_iso"]
    monkeypatch.setattr(bot_tl, "_prmon_records", lambda: [touched])
    assert bot_tl.collect() == 0
    path.write_text('{"status":"changed"}', encoding="utf-8")
    changed = bot_tl._file_record(path, "prmon_heartbeat")
    monkeypatch.setattr(bot_tl, "_prmon_records", lambda: [changed])
    assert bot_tl.collect() == 1
    assert len(written) == 2


@pytest.mark.unit
def test_bot_tl_redacts_local_and_remote_home_paths(monkeypatch, tmp_path):
    content = '{"detail":"/Users/example/private", "path":"/home/example/ledger.md"}'
    local = bot_tl._payload(Path("/Users/example/handoff/heartbeat.json"), "prmon_heartbeat", content)
    assert local["rel_path"] == "~/handoff/heartbeat.json"
    assert local["payload"] == {"detail": "~/private", "path": "~/ledger.md"}
    (tmp_path / "batch.jsonl").write_text(json.dumps({
        "collector": "prmon", "rel_path": "/Users/example/watch.json", "payload": json.loads(content),
    }) + "\n", encoding="utf-8")
    monkeypatch.setattr(bot_tl, "GTT_XFER_DIR", tmp_path)
    remote = bot_tl._remote_records()[0]
    assert remote["rel_path"] == "~/watch.json"
    assert remote["payload"] == local["payload"]


@pytest.mark.unit
@pytest.mark.parametrize("fail_first", [False, True])
def test_cloud_sync_shares_successful_refresh_and_retries_failures(monkeypatch, tmp_path, watermarks, fail_first):
    monkeypatch.setattr(cloud_sync, "AIDATA_SYNC_STORAGE_ACCOUNT", "testaccount")
    monkeypatch.setattr(cloud_sync, "GTT_XFER_DIR", tmp_path)
    monkeypatch.setattr(cloud_sync.shutil, "which", lambda *_args, **_kwargs: "/test/az")
    now = [100.0]
    monkeypatch.setattr(cloud_sync.time, "time", lambda: now[0])
    calls = []
    name = "aidata-sync/v1/machines/device-1/batches/batch.jsonl"
    def listing(*_args):
        calls.append("list")
        return [{"name": name, "etag": "version1"}]
    def download(_executable, _env, _name, target):
        calls.append("download")
        if fail_first and calls.count("download") == 1:
            return False
        target.write_bytes(b'{"collector":"prmon"}\n')
        return True
    monkeypatch.setattr(cloud_sync, "_run_json", listing)
    monkeypatch.setattr(cloud_sync, "_download", download)
    if fail_first:
        assert cloud_sync.pull_remote_batches() == 0
        assert "cloud_sync_refresh" not in watermarks
    assert cloud_sync.pull_remote_batches() == 1
    successful_calls = list(calls)
    # These are independent adapter calls; only persisted state is shared.
    assert cloud_sync.pull_remote_batches() == 0
    assert cloud_sync.pull_remote_batches() == 0
    assert calls == successful_calls
    assert (tmp_path / "azure/device-1/batch.jsonl").read_bytes() == b'{"collector":"prmon"}\n'
    now[0] += 61
    assert cloud_sync.pull_remote_batches() == 0
    assert calls == [*successful_calls, "list"]


@pytest.mark.unit
@pytest.mark.parametrize("mixed_keys", [False, True])
def test_gtt_legacy_merge_and_historical_raw_replay(monkeypatch, tmp_path, mixed_keys):
    import cleanio
    import config
    import merge
    import rawio

    clean = tmp_path / "clean"
    clean.mkdir()
    warehouse = tmp_path / "warehouse.db"
    monkeypatch.setattr(config, "CLEAN_DIR", clean)
    monkeypatch.setattr(cleanio, "CLEAN_DIR", clean)
    monkeypatch.setattr(config, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(merge, "WAREHOUSE_DB", warehouse)
    lines = [
        "- 2026-10-28T01:00:00Z | EVT=DONE | id=E1 task=tk1 note=first",
        "- 2026-10-28T02:00:00Z | EVT=DONE | id=E1 task=tk1 note=second",
    ]
    rows = []
    for index, line in enumerate(lines, 1):
        event = gtt_ledger._parse_event(line, index, "g")
        event.update(machine_id="m", goal_uid="m:g")
        canonical = {**event, "event_uid": f"m:g:{event['event_uid']}"}
        rows.extend({**event, "event_uid": f"m:g:L{no}:E1", "line_no": no}
                    for no in (index, index + 20))
        if mixed_keys:
            rows.append(canonical)
    cleanio.write_clean("gtt_ledger", "goal", gtt_ledger._GOAL_DDL, [], ())
    cleanio.write_clean("gtt_ledger", "gtt_event", gtt_ledger._EVENT_DDL, rows, tuple(rows[0]))

    def merged_events():
        assert merge.run_merge()["fact_gtt_event"] == 2
        with sqlite3.connect(warehouse) as conn:
            events = conn.execute("SELECT event_uid, line_no, note_preview FROM fact_gtt_event ORDER BY ts").fetchall()
        assert not any(re.search(r":L\d+:", event[0]) for event in events)
        assert [event[2] for event in events] == ["first", "second"]
        return events

    # Covers old clean-only and mixed clean databases, including shifted rows.
    initial = merged_events()
    assert merged_events() == initial
    if mixed_keys:
        assert [event[1] for event in initial] == [1, 2]
    raw = {"record_type": "ledger", "machine_id": "m", "goal_id": "g"}
    rawio.write_raw("gtt_ledger", [{**raw, "content": "\n".join(lines), "mtime_iso": "2026-10-28T02:00:00Z"}], "2026-10-27")
    # The latest snapshot repeats an identical event and shifts source lines.
    rawio.write_raw("gtt_ledger", [{**raw, "content": "\n\n" + "\n".join([*lines, lines[0]]),
                                    "mtime_iso": "2026-10-28T03:00:00Z"}], "2026-10-28")
    before = rawio.read_raw("gtt_ledger")
    assert gtt_ledger.normalize() == 2
    normalized = merged_events()
    expected = [f"m:g:{gtt_ledger._parse_event(line, 1, 'g')['event_uid']}" for line in lines]
    assert [event[0] for event in normalized] == expected
    assert gtt_ledger.normalize() == 2
    assert merged_events() == normalized
    assert rawio.read_raw("gtt_ledger") == before
