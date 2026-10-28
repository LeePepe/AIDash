import io
import json
import os
import re
import sqlite3
import tarfile
from pathlib import Path

import pytest
from adapters import bot_tl, cloud_sync, gtt_ledger


def _read_and_commit_prmon(module):
    records, cursor = module._prmon_records()
    if cursor is not None:
        module.set_watermark("bot_tl_prmon_history", cursor)
    return records


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
    assert cloud_sync._blob_parts(dated) == ("device-1", "2026-10-28/010203_deadbeef1234.jsonl")
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
    (tmp_path / "scalars.jsonl").write_text('null\n[]\n42\n"text"\n', encoding="utf-8")
    assert bot_tl._remote_records() == records


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
@pytest.mark.parametrize("new_ts,old_ts", [
    ("2026-10-28T02:00:00+00:00", "2026-10-28T01:00:00+00:00"),
    ("2026-10-28T02:00:00Z", "2026-10-28T09:00:00+08:00"),
    ("2026-10-28T02:00:00.500Z", "2026-10-28T02:00:00Z"),
    ("2026-10-28T02:00:00", "2026-10-28T01:00:00Z"),
    (None, None),
])
def test_gtt_ledger_keeps_newer_goal_record(monkeypatch, new_ts, old_ts):
    raw = [
        {"record_type": "ledger", "machine_id": "m", "goal_id": "g",
         "content": "- 2026-10-28T02:00:00Z | EVT=DONE | id=B2\n",
         "mtime_iso": new_ts},
        {"record_type": "ledger", "machine_id": "m", "goal_id": "g",
         "content": "- 2026-10-28T01:00:00Z | EVT=START | id=B1\n",
         "mtime_iso": old_ts},
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
    records = _read_and_commit_prmon(bot_tl)
    assert [record["payload"]["status"] for record in records] == ["正常"]
    assert watermarks["bot_tl_prmon_history"]["offset"] == len(first)
    assert _read_and_commit_prmon(bot_tl) == []
    with history.open("ab") as fh:
        fh.write(second[split:])
    assert _read_and_commit_prmon(bot_tl)[0]["payload"]["status"] == "中文"
    assert watermarks["bot_tl_prmon_history"]["offset"] == len(first + second)
    assert _read_and_commit_prmon(bot_tl) == []


@pytest.mark.unit
@pytest.mark.parametrize("change", ["truncate", "rotate", "midline"])
def test_prmon_history_recovers_changed_file_or_bad_cursor(monkeypatch, tmp_path, watermarks, change):
    monkeypatch.setattr(bot_tl, "PRMON_WATCH_DIR", tmp_path)
    history = tmp_path / "heartbeat-history.jsonl"
    history.write_bytes(b'{"status":"original long heartbeat"}\n')
    assert len(_read_and_commit_prmon(bot_tl)) == 1
    expected = b'{"status":"new"}\n'
    if change == "rotate":
        replacement = tmp_path / "replacement"
        replacement.write_bytes(expected)
        replacement.replace(history)
    else:
        history.write_bytes(expected)
        if change == "midline":
            watermarks["bot_tl_prmon_history"]["offset"] = 3
    assert _read_and_commit_prmon(bot_tl)[0]["payload"] == {"status": "new"}
    assert watermarks["bot_tl_prmon_history"]["offset"] == len(expected)
    assert _read_and_commit_prmon(bot_tl) == []


@pytest.mark.unit
def test_bot_tl_collect_ignores_mtime_and_remembers_replayed_history(monkeypatch, tmp_path, watermarks):
    path = tmp_path / "heartbeat-history.jsonl"
    path.write_text('{"status":"ok"}', encoding="utf-8")
    monkeypatch.setattr(cloud_sync, "pull_remote_batches", lambda: 0)
    monkeypatch.setattr(bot_tl, "_local_records", list)
    monkeypatch.setattr(bot_tl, "_prmon_records", lambda: ([], None))
    monkeypatch.setattr(bot_tl, "_remote_records", list)
    written = []
    def write(_source, rows):
        written.extend(rows)
        return len(rows)
    monkeypatch.setattr(bot_tl, "write_raw", write)
    record = bot_tl._file_record(path, "prmon_heartbeat")
    monkeypatch.setattr(bot_tl, "_prmon_records", lambda: ([record, record], None))
    assert bot_tl.collect() == 1
    monkeypatch.setattr(bot_tl, "_prmon_records", lambda: ([], None))
    assert bot_tl.collect() == 0
    os.utime(path, (path.stat().st_atime, path.stat().st_mtime + 10))
    touched = bot_tl._file_record(path, "prmon_heartbeat")
    assert touched["mtime_iso"] != record["mtime_iso"]
    monkeypatch.setattr(bot_tl, "_prmon_records", lambda: ([touched], None))
    assert bot_tl.collect() == 0
    path.write_text('{"status":"changed"}', encoding="utf-8")
    changed = bot_tl._file_record(path, "prmon_heartbeat")
    monkeypatch.setattr(bot_tl, "_prmon_records", lambda: ([changed], None))
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

    def source_event_count():
        with sqlite3.connect(clean / "gtt_ledger.db") as conn:
            return conn.execute("SELECT COUNT(*) FROM gtt_event").fetchone()[0]

    expected_source_count = 6 if mixed_keys else 4
    assert source_event_count() == expected_source_count

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
    assert source_event_count() == expected_source_count
    if mixed_keys:
        assert [event[1] for event in initial] == [1, 2]
    raw = {"record_type": "ledger", "machine_id": "m", "goal_id": "g"}
    rawio.write_raw("gtt_ledger", [{**raw, "content": "\n".join(lines), "mtime_iso": "2026-10-28T02:00:00Z"}], "2026-10-27")
    # The latest snapshot repeats an identical event and shifts source lines.
    rawio.write_raw("gtt_ledger", [{**raw, "content": "\n\n" + "\n".join([*lines, lines[0]]),
                                    "mtime_iso": "2026-10-28T03:00:00Z"}], "2026-10-28")
    before = rawio.read_raw("gtt_ledger")
    assert gtt_ledger.normalize() == 2
    assert source_event_count() == 2
    normalized = merged_events()
    expected = [f"m:g:{gtt_ledger._parse_event(line, 1, 'g')['event_uid']}" for line in lines]
    assert [event[0] for event in normalized] == expected
    assert gtt_ledger.normalize() == 2
    assert merged_events() == normalized
    assert rawio.read_raw("gtt_ledger") == before


@pytest.mark.unit
@pytest.mark.parametrize("failure", ["raw", "remote", "state"])
def test_history_cursor_commits_after_raw_and_retries(monkeypatch, tmp_path, watermarks, failure):
    import config
    import rawio

    monkeypatch.setattr(config, "RAW_DIR", tmp_path / "raw")
    monkeypatch.setattr(bot_tl, "PRMON_WATCH_DIR", tmp_path)
    monkeypatch.setattr(bot_tl, "GTT_XFER_DIR", tmp_path / "remote")
    monkeypatch.setattr(bot_tl, "_local_records", list)
    monkeypatch.setattr(cloud_sync, "pull_remote_batches", lambda: 0)
    history = tmp_path / "heartbeat-history.jsonl"
    first = b'{"ts":"2026-10-28T01:00:00Z"}\n'
    second = b'{"ts":"2026-10-28T02:00:00Z"}\n'
    history.write_bytes(first)
    assert bot_tl.collect() == 1
    old = dict(watermarks["bot_tl_prmon_history"])
    history.write_bytes(first + second)

    def fail(*_args):
        raise OSError("injected failure")

    target = {"raw": "write_raw", "remote": "_remote_records", "state": "set_watermark"}[failure]
    with monkeypatch.context() as patch:
        patch.setattr(bot_tl, target, fail)
        with pytest.raises(OSError, match="injected failure"):
            bot_tl.collect()
    assert watermarks["bot_tl_prmon_history"] == old
    assert bot_tl.collect() == 1
    assert watermarks["bot_tl_prmon_history"]["offset"] == len(first + second)
    assert bot_tl.collect() == 0
    rows = rawio.read_raw("bot_tl")
    # A failed state write may replay an already durable record, never lose it.
    assert {row["payload"]["ts"] for row in rows} == {
        "2026-10-28T01:00:00Z", "2026-10-28T02:00:00Z",
    }
    assert len(rows) == (3 if failure == "state" else 2)


@pytest.mark.unit
def test_bot_tl_snapshot_rollback_and_bounded_replay(monkeypatch, tmp_path, watermarks):
    monkeypatch.setattr(bot_tl, "_REPLAY_LIMIT", 3)
    monkeypatch.setattr(bot_tl, "_local_records", list)
    monkeypatch.setattr(bot_tl, "_prmon_records", lambda: ([], None))
    monkeypatch.setattr(cloud_sync, "pull_remote_batches", lambda: 0)
    monkeypatch.setattr(bot_tl, "write_raw", lambda _source, rows: len(rows))
    # Legacy unbounded maps are discarded safely on the first successful write.
    watermarks["bot_tl"] = {f"old:{i}": "digest" for i in range(10)}
    record = bot_tl._payload(tmp_path / "heartbeat.json", "prmon_heartbeat", '{"status":"A"}')
    monkeypatch.setattr(bot_tl, "_remote_records", lambda: [record])
    assert bot_tl.collect() == 1
    for status in ("B", "A"):
        record["payload"]["status"] = status
        assert bot_tl.collect() == 1
    assert bot_tl.collect() == 0
    assert len(watermarks["bot_tl"]["files"]) == 1
    events = [{**record, "rel_path": "heartbeat-history.jsonl", "payload": {"ts": i}} for i in range(10)]
    monkeypatch.setattr(bot_tl, "_remote_records", lambda: events)
    assert bot_tl.collect() == 10
    assert len(watermarks["bot_tl"]["replay"]) == 3
    assert watermarks["bot_tl"]["files"] == {}
    monkeypatch.setattr(bot_tl, "_remote_records", lambda: events[-3:])
    assert bot_tl.collect() == 0
    monkeypatch.setattr(bot_tl, "_remote_records", lambda: events[:1])
    assert bot_tl.collect() == 1  # Evicted events can replay; L2 deduplicates.


@pytest.mark.unit
@pytest.mark.parametrize("legacy_watermark", [False, True])
def test_cloud_sync_keeps_same_named_batches_on_different_dates(monkeypatch, tmp_path, watermarks, legacy_watermark):
    monkeypatch.setattr(cloud_sync, "AIDATA_SYNC_STORAGE_ACCOUNT", "testaccount")
    monkeypatch.setattr(cloud_sync, "GTT_XFER_DIR", tmp_path)
    monkeypatch.setattr(bot_tl, "GTT_XFER_DIR", tmp_path)
    monkeypatch.setattr(cloud_sync.shutil, "which", lambda *_args, **_kwargs: "/test/az")
    names = ["aidata-sync/v1/machines/device-1/batches/batch.jsonl",
             *[f"aidata-sync/v1/machines/device-1/batches/{day}/batch.jsonl"
               for day in ("2026-10-27", "2026-10-28")]]
    contents = {name: json.dumps({"collector": "prmon", "record_type": "prmon_heartbeat",
                                "payload": {"ts": f"2026-10-{26 + index}T01:00:00Z"}}) + "\n"
                for index, name in enumerate(names)}
    monkeypatch.setattr(cloud_sync, "_run_json", lambda *_args: [
        {"name": name, "etag": "same-etag"} for name in names
    ])
    if legacy_watermark:
        watermarks["cloud_sync_batches"] = dict.fromkeys(names, "same-etag")
        watermarks["cloud_sync_refresh"] = {
            "scope": ["testaccount", cloud_sync.AIDATA_SYNC_CONTAINER,
                      cloud_sync.AIDATA_SYNC_PREFIX, str(tmp_path.resolve())],
            "completed_at": cloud_sync.time.time(),
        }
        old = tmp_path / "azure/device-1/batch.jsonl"
        old.parent.mkdir(parents=True)
        old.write_text(contents[names[-1]], encoding="utf-8")
    calls = []
    def download(_executable, _env, name, target):
        calls.append(name)
        target.write_text(contents[name], encoding="utf-8")
        return True
    monkeypatch.setattr(cloud_sync, "_download", download)
    assert cloud_sync.pull_remote_batches() == 3
    for name in names:
        relative = name.split("/batches/", 1)[1]
        assert (tmp_path / "azure/device-1" / relative).read_text() == contents[name]
        assert watermarks["cloud_sync_batches_v2"][name] == "same-etag"
    assert {row["payload"]["ts"] for row in bot_tl._remote_records()} == {
        "2026-10-26T01:00:00Z", "2026-10-27T01:00:00Z", "2026-10-28T01:00:00Z",
    }
    watermarks.pop("cloud_sync_refresh")
    assert cloud_sync.pull_remote_batches() == 0
    assert calls == names


@pytest.mark.unit
@pytest.mark.parametrize("failure", ["symlink-device", "symlink-date", "symlink-file", "hash"])
def test_cloud_sync_failed_target_never_advances_watermark(monkeypatch, tmp_path, watermarks, failure):
    monkeypatch.setattr(cloud_sync, "AIDATA_SYNC_STORAGE_ACCOUNT", "testaccount")
    monkeypatch.setattr(cloud_sync, "GTT_XFER_DIR", tmp_path / "xfer")
    monkeypatch.setattr(cloud_sync.shutil, "which", lambda *_args, **_kwargs: "/test/az")
    name = "aidata-sync/v1/machines/device-1/batches/2026-10-28/batch_deadbeef1234.jsonl"
    monkeypatch.setattr(cloud_sync, "_run_json", lambda *_args: [{"name": name, "etag": "v1"}])
    outside = tmp_path / "outside"
    outside.mkdir()
    root = tmp_path / "xfer/azure"
    root.mkdir(parents=True)
    target = root / "device-1/2026-10-28/batch_deadbeef1234.jsonl"
    if failure.startswith("symlink"):
        link = {"symlink-device": target.parent.parent,
                "symlink-date": target.parent, "symlink-file": target}[failure]
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(outside / "file" if failure == "symlink-file" else outside)
    def download(_executable, _env, _name, target):
        target.write_bytes(b"corrupt")
        return True
    monkeypatch.setattr(cloud_sync, "_download", download)
    assert cloud_sync.pull_remote_batches() == 0
    assert name not in watermarks.get("cloud_sync_batches_v2", {})
    assert "cloud_sync_refresh" not in watermarks
    assert list(outside.iterdir()) == []
    assert not list(root.rglob(".*.jsonl.*"))


@pytest.mark.unit
def test_untimed_ledger_header_does_not_acquire_rewrite_time(monkeypatch, tmp_path):
    goal = tmp_path / "goal"
    goal.mkdir()
    ledger = goal / "ledger.md"
    ledger.write_text("TL_PROFILE=example quota_precheck=pass\n", encoding="utf-8")
    monkeypatch.setattr(bot_tl, "GTT_HANDOFF_ROOTS", [tmp_path])
    monkeypatch.setattr(bot_tl, "CLAUDE_QUOTA_CACHE", tmp_path / "missing")
    before = bot_tl._local_records()
    os.utime(ledger, (ledger.stat().st_atime, ledger.stat().st_mtime + 100))
    after = bot_tl._local_records()
    assert before[0]["payload"] == after[0]["payload"]
    assert after[0]["payload"]["ts"] == ""
    monkeypatch.setattr(bot_tl, "read_raw", lambda _source: after)
    captured = {}
    def capture(_source, table, _ddl, rows, _columns):
        captured[table] = rows
        return len(rows)
    monkeypatch.setattr(bot_tl, "write_clean", capture)
    assert bot_tl.normalize() == 0
    assert captured["supervision"] == []


@pytest.mark.unit
def test_bot_tl_normalize_merge_preserves_all_fact_columns(monkeypatch, tmp_path):
    import cleanio
    import config
    import merge

    clean = tmp_path / "clean"
    monkeypatch.setattr(cleanio, "CLEAN_DIR", clean)
    monkeypatch.setattr(config, "CLEAN_DIR", clean)
    monkeypatch.setattr(merge, "WAREHOUSE_DB", tmp_path / "warehouse.db")
    raw = [
        {"record_type": "bot_tl_event", "device_id": "device-1", "machine_alias": "example",
         "goal_id": "goal-1", "payload": {
             "ts": "2026-10-28T01:00:00Z", "action_kind": "S3_CI_FIX",
             "bot_name": "example-bot", "tl_agent": "example-tl", "result": "pass",
             "weekly_remaining_pct": 80, "repo_key": "example/repo", "pr_number": 1,
             "head_sha": "abc123", "status": "done", "detail": "example detail"}},
        {"record_type": "prmon_heartbeat", "device_id": "device-1", "machine_alias": "example",
         "payload": {"ts": "2026-10-28T01:00:00Z", "checked_pr_count": 3,
                     "stuck_pr_count": 2, "repair_queued_count": 1, "status": "complete"}},
    ]
    monkeypatch.setattr(bot_tl, "read_raw", lambda _source: raw)
    assert bot_tl.normalize() == 1
    for _ in range(2):
        counts = merge.run_merge()
        assert counts["fact_bot_tl_supervision"] == counts["fact_prmon_heartbeat"] == 1
        with sqlite3.connect(merge.WAREHOUSE_DB) as warehouse, sqlite3.connect(clean / "bot_tl.db") as source:
            for table, fact in (("supervision", "fact_bot_tl_supervision"),
                                ("prmon_heartbeat", "fact_prmon_heartbeat")):
                columns = [row[1] for row in source.execute(f"PRAGMA table_info({table})")]
                projection = ", ".join(columns)
                assert warehouse.execute(f"SELECT {projection} FROM {fact}").fetchall() == source.execute(
                    f"SELECT {projection} FROM {table}").fetchall()
                assert warehouse.execute(f"SELECT cst_day FROM {fact}").fetchone() == ("2026-10-28",)
