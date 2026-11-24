"""Hermetic tests for local iCloud token shard sync and its L4 contract."""

import json
import sqlite3
from datetime import datetime

import pytest

from adapters import icloud_token_sync as sync
from aidata import serve


@pytest.fixture(autouse=True)
def isolated_sources(tmp_path, monkeypatch):
    monkeypatch.setattr(sync, "HOME", tmp_path / "home")
    monkeypatch.setattr(sync, "KIMI_SESSIONS_DIR", tmp_path / "kimi-sessions")
    monkeypatch.setattr(sync, "clean_path", lambda source: tmp_path / "clean" / f"{source}.db")
    monkeypatch.setattr(sync, "ICLOUD_TOKEN_SYNC_DIR", tmp_path / "icloud")
    monkeypatch.setattr(sync, "_device_identity", lambda: ("local", "Local"))


def _database(path, ddl, rows=()):
    path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(path) as conn:
        conn.execute(ddl)
        for row in rows:
            columns = ", ".join(row)
            placeholders = ", ".join("?" for _ in row)
            conn.execute(f"INSERT INTO assistant_usage_events ({columns}) VALUES ({placeholders})",
                         tuple(row.values()))
    return path


@pytest.fixture
def copilot_db():
    return _database(sync.HOME / ".copilot" / "session-store.db", """
        CREATE TABLE assistant_usage_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            model TEXT NOT NULL,
            input_tokens INTEGER, output_tokens INTEGER,
            cache_read_tokens INTEGER, cache_write_tokens INTEGER,
            created_at TEXT DEFAULT (datetime('now')),
            copilot_usage_model TEXT
        )
    """, [
        {"session_id": "s1", "created_at": "2026-11-08T15:59:59Z",
         "model": "routing-group", "copilot_usage_model": "resolved-model",
         "input_tokens": 100, "output_tokens": 20,
         "cache_read_tokens": 60, "cache_write_tokens": 5},
        {"session_id": "s1", "created_at": "2026-11-08 16:00:00",
         "model": "fallback-model", "copilot_usage_model": "",
         "input_tokens": 30, "output_tokens": 4,
         "cache_read_tokens": 10, "cache_write_tokens": 2},
        {"session_id": "s1", "created_at": "2026-11-09T00:30:00+08:00",
         "model": "fallback-model", "copilot_usage_model": None,
         "input_tokens": 7, "output_tokens": 3,
         "cache_read_tokens": None, "cache_write_tokens": None},
        {"session_id": "s2", "created_at": "invalid", "model": "ignored"},
        {"session_id": "s2", "created_at": "2026-11-09T01:00:00Z",
         "model": "ignored", "input_tokens": "invalid"},
    ])


def _wire(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(json.dumps(record) for record in records) + "\nnot-json\n",
                    encoding="utf-8")


def _kimi_usage(stamp, usage, model="kimi-model", **extra):
    return {
        "type": "usage.record", "agentId": "main", "model": model,
        "time": int(datetime.fromisoformat(stamp).timestamp() * 1000),
        "usageScope": "turn", "usage": usage, **extra,
    }


@pytest.fixture
def kimi_wire():
    path = sync.KIMI_SESSIONS_DIR / "workdir" / "session" / "agents" / "main" / "wire.jsonl"
    _wire(path, [
        _kimi_usage("2026-11-08T15:59:59+00:00", {
            "inputOther": 50, "output": 8, "inputCacheRead": 40, "inputCacheCreation": 6,
        }),
        _kimi_usage("2026-11-08T16:00:00+00:00", {
            "inputOther": 20, "output": 3, "inputCacheRead": 15, "inputCacheCreation": 2,
        }),
        {"type": "turn.prompt", "time": 1794153600000, "input": []},
        {"type": "token_counting.turn_recorded", "time": 1794153600000, "tokens": 9999},
        _kimi_usage("2026-11-08T16:00:00+00:00", {"output": 999}, usageScope="session"),
        _kimi_usage("2026-11-08T16:00:00+00:00", None),
        _kimi_usage("2026-11-08T16:00:00+00:00", {"output": "invalid"}),
        _kimi_usage("2026-11-08T16:00:00+00:00", {"output": 999}, time="invalid"),
        [],
    ])
    _wire(path.parent.parent / "child" / "wire.jsonl", [
        _kimi_usage("2026-11-09T00:30:00+08:00", {"inputOther": 4, "output": 1}),
    ])
    return path


def _metrics(row):
    return tuple(row[key] for key in (
        "cli", "model", "cst_day", "hour_bucket", "input_tokens", "output_tokens",
        "cache_read", "cache_write", "total_tokens", "invocations",
    ))


def _row(uid, device, alias, day, total, updated="2026-11-09T05:00:00+00:00"):
    return {
        "record_uid": uid, "device_id": device, "machine_alias": alias,
        "cst_day": day, "hour_bucket": f"{day}T10:00:00+08:00",
        "cli": "claude-code", "model": "model",
        "input_tokens": total, "output_tokens": 0, "cache_read": 0,
        "cache_write": 0, "total_tokens": total, "invocations": 1,
        "updated_at": updated,
    }


def test_collect_is_noop_when_sync_directory_is_missing(tmp_path, monkeypatch):
    monkeypatch.setattr(sync, "ICLOUD_TOKEN_SYNC_DIR", tmp_path / "missing")
    assert sync.collect() == 0


def test_export_is_atomic_and_pull_deduplicates_latest_record(tmp_path, monkeypatch):
    root = tmp_path / "icloud"
    monkeypatch.setattr(sync, "_device_identity", lambda: ("local", "Local"))
    sync._atomic_export([_row("local-uid", "local", "Local", "2026-11-09", 3)], root)
    path = root / "machines" / "local" / "token_usage.jsonl"
    assert path.read_text(encoding="utf-8").count("\n") == 1
    assert path.stat().st_mode & 0o077 == 0

    remote = root / "machines" / "remote"
    remote.mkdir(parents=True)
    remote.joinpath("token_usage.jsonl").write_text(
        json.dumps(_row("remote-uid", "remote", "Remote", "2026-11-09", 2))
        + "\n"
        + json.dumps(_row("remote-uid", "remote", "Remote", "2026-11-09", 7,
                          "2026-11-09T06:00:00+00:00"))
        + "\nnot-json\n",
        encoding="utf-8",
    )
    pulled = {row["record_uid"]: row for row in sync._pull(root)}
    assert pulled["remote-uid"]["total_tokens"] == 7
    assert set(pulled) == {"local-uid", "remote-uid"}


def test_normalize_deduplicates_and_query_reports_device_shares(tmp_path, monkeypatch):
    records = [_row("a", "a", "A", "2026-11-09", 70),
               _row("b", "b", "B", "2026-11-09", 30)]
    monkeypatch.setattr(sync, "read_raw", lambda source: records)
    import cleanio
    monkeypatch.setattr(cleanio, "CLEAN_DIR", tmp_path / "clean")
    def clean_path(source):
        return tmp_path / "clean" / f"{source}.db"

    monkeypatch.setattr(cleanio, "clean_path", clean_path)
    monkeypatch.setattr(sync, "clean_path", clean_path)
    assert sync.normalize() == 2

    warehouse = tmp_path / "warehouse.db"
    conn = sqlite3.connect(warehouse)
    conn.execute("""CREATE TABLE fact_device_token_daily (
        record_uid TEXT, device_id TEXT, machine_alias TEXT, cst_day TEXT,
        hour_bucket TEXT, cli TEXT, model TEXT, input_tokens INTEGER,
        output_tokens INTEGER, cache_read INTEGER, cache_write INTEGER,
        total_tokens INTEGER, invocations INTEGER, updated_at TEXT
    )""")
    conn.executemany(
        "INSERT INTO fact_device_token_daily VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [(r["record_uid"], r["device_id"], r["machine_alias"], r["cst_day"],
          r["hour_bucket"], r["cli"], r["model"], r["input_tokens"],
          r["output_tokens"], r["cache_read"], r["cache_write"],
          r["total_tokens"], r["invocations"], r["updated_at"]) for r in records],
    )
    conn.commit()
    conn.close()
    monkeypatch.setattr(serve, "WAREHOUSE_DB", warehouse)
    rows, columns = serve.run_query("tokens/by-device", {"day_from": "2026-11-09", "day_to": "2026-11-09"})
    by_device = {row[1]: dict(zip(columns, row)) for row in rows}
    assert by_device["__all__"]["total_tokens"] == 100
    assert by_device["a"]["share_pct"] == pytest.approx(70.0)
    assert by_device["b"]["share_pct"] == pytest.approx(30.0)


def test_copilot_reads_native_usage_schema_read_only(copilot_db):
    before = copilot_db.read_bytes()
    rows = sync._clean_rows("copilot", "local", "Local")
    assert [_metrics(row) for row in rows] == [
        ("copilot", "resolved-model", "2026-11-08", "2026-11-08T23:00:00+08:00",
         100, 20, 60, 5, 120, 1),
        ("copilot", "fallback-model", "2026-11-09", "2026-11-09T00:00:00+08:00",
         30, 4, 10, 2, 34, 1),
        ("copilot", "fallback-model", "2026-11-09", "2026-11-09T00:00:00+08:00",
         7, 3, 0, 0, 10, 1),
    ]
    assert rows[1]["record_uid"] == rows[2]["record_uid"]
    assert copilot_db.read_bytes() == before


def test_kimi_reads_usage_not_prompt_or_context_estimates(kimi_wire):
    from adapters import kimi_prompts

    prompt_db = _database(sync.clean_path("kimi_prompts"), kimi_prompts._CLEAN_DDL)
    with sqlite3.connect(prompt_db) as conn:
        conn.execute("INSERT INTO prompt (prompt_id, agent, ts, text_len) VALUES (?, ?, ?, ?)",
                     ("p1", "kimi", 1794153600, 500))
    before = kimi_wire.read_bytes(), prompt_db.read_bytes()
    rows = sync._clean_rows("kimi_prompts", "local", "Local")
    assert sorted(_metrics(row) for row in rows) == [
        ("kimi", "kimi-model", "2026-11-08", "2026-11-08T23:00:00+08:00",
         50, 8, 40, 6, 58, 1),
        ("kimi", "kimi-model", "2026-11-09", "2026-11-09T00:00:00+08:00",
         4, 1, 0, 0, 5, 1),
        ("kimi", "kimi-model", "2026-11-09", "2026-11-09T00:00:00+08:00",
         20, 3, 15, 2, 23, 1),
    ]
    assert (kimi_wire.read_bytes(), prompt_db.read_bytes()) == before


@pytest.mark.parametrize("ddl,records,expected", [
    ("CREATE TABLE assistant_usage_events (created_at TEXT, model TEXT, input_tokens INTEGER)",
     [{"created_at": "2026-11-09T00:00:00Z", "model": "legacy-model", "input_tokens": 9}],
     ("copilot", "legacy-model", "2026-11-09", "2026-11-09T08:00:00+08:00", 9, 0, 0, 0, 9, 1)),
    ("CREATE TABLE assistant_usage_events (created_at TEXT, output_tokens INTEGER)",
     [{"created_at": "2026-11-09T00:00:00Z", "output_tokens": 2}],
     ("copilot", "unknown", "2026-11-09", "2026-11-09T08:00:00+08:00", 0, 2, 0, 0, 2, 1)),
    ("CREATE TABLE assistant_usage_events (created_at TEXT, model TEXT)", [], None),
    ("CREATE TABLE assistant_usage_events (model TEXT)", [{"model": "no-timestamp"}], None),
    ("CREATE TABLE sessions (id TEXT)", [], None),
])
def test_copilot_legacy_or_empty_schema_degrades(ddl, records, expected):
    _database(sync.HOME / ".copilot" / "session-store.db", ddl, records)
    rows = sync._clean_rows("copilot", "local", "Local")
    assert [_metrics(row) for row in rows] == ([] if expected is None else [expected])


def test_kimi_legacy_usage_and_prompt_only_data_degrade():
    from adapters import kimi_prompts

    _database(sync.clean_path("kimi_prompts"), kimi_prompts._CLEAN_DDL)
    assert sync._clean_rows("kimi_prompts", "local", "Local") == []
    wire = sync.KIMI_SESSIONS_DIR / "session" / "agents" / "main" / "wire.jsonl"
    _wire(wire, [{
        "type": "usage.record", "time": 1794153600000, "usage": {"output": 2},
    }])
    rows = sync._clean_rows("kimi_prompts", "local", "Local")
    assert [_metrics(row) for row in rows] == [
        ("kimi", "unknown", "2026-11-09", "2026-11-09T00:00:00+08:00", 0, 2, 0, 0, 2, 1),
    ]


def test_collect_exports_both_sources_and_aggregates_atomically(copilot_db, kimi_wire, monkeypatch):
    snapshots = []
    monkeypatch.setattr(sync, "write_raw_snapshot", lambda source, rows: snapshots.extend(rows) or len(rows))
    assert sync.collect() == 4
    target = sync.ICLOUD_TOKEN_SYNC_DIR / "machines" / "local" / "token_usage.jsonl"
    exported = [json.loads(line) for line in target.read_text(encoding="utf-8").splitlines()]
    assert sorted(_metrics(row) for row in exported) == [
        ("copilot", "fallback-model", "2026-11-09", "2026-11-09T00:00:00+08:00",
         37, 7, 10, 2, 44, 2),
        ("copilot", "resolved-model", "2026-11-08", "2026-11-08T23:00:00+08:00",
         100, 20, 60, 5, 120, 1),
        ("kimi", "kimi-model", "2026-11-08", "2026-11-08T23:00:00+08:00",
         50, 8, 40, 6, 58, 1),
        ("kimi", "kimi-model", "2026-11-09", "2026-11-09T00:00:00+08:00",
         24, 4, 15, 2, 28, 2),
    ]
    assert snapshots == exported
    assert target.stat().st_mode & 0o077 == 0
    assert list(target.parent.glob(".token_usage.*")) == []
    first_export = target.read_bytes()
    monkeypatch.setattr(sync.os, "replace", lambda *args: (_ for _ in ()).throw(OSError("unavailable")))
    assert sync.collect() == 0
    assert target.read_bytes() == first_export
    assert list(target.parent.glob(".token_usage.*")) == []


@pytest.mark.parametrize("source,ddl,record,expected", [
    ("raven", "CREATE TABLE req (ts INTEGER, client TEXT, model_canon TEXT, input_tokens INTEGER)",
     (1794153600000, "raven-client", "raven-model", 5), ("raven-client", "raven-model", 5)),
    ("claude_jsonl", "CREATE TABLE turn (ts TEXT, role TEXT, model TEXT, input_tokens INTEGER)",
     ("2026-11-08T16:00:00Z", "assistant", "claude-model", 6), ("claude-code", "claude-model", 6)),
    ("state_db", "CREATE TABLE session (started_at REAL, model TEXT, input_tokens INTEGER)",
     (1794153600, "hermes-model", 7), ("hermes", "hermes-model", 7)),
])
def test_existing_clean_readers_discover_single_column_table_names(source, ddl, record, expected):
    path = _database(sync.clean_path(source), ddl)
    table = {"raven": "req", "claude_jsonl": "turn", "state_db": "session"}[source]
    with sqlite3.connect(path) as conn:
        conn.execute(f"INSERT INTO {table} VALUES ({', '.join('?' for _ in record)})", record)
    rows = sync._clean_rows(source, "local", "Local")
    assert len(rows) == 1
    assert (rows[0]["cli"], rows[0]["model"], rows[0]["input_tokens"]) == expected


def test_collect_does_not_create_sync_directory_without_local_data():
    assert sync.collect() == 0
    assert not sync.ICLOUD_TOKEN_SYNC_DIR.exists()
    assert not sync.HOME.exists()


def test_collect_degrades_when_icloud_export_is_unavailable(copilot_db, monkeypatch):
    monkeypatch.setattr(sync, "_atomic_export", lambda *args: (_ for _ in ()).throw(PermissionError()))
    assert sync.collect() == 0
