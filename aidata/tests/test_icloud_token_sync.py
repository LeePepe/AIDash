"""Hermetic tests for local iCloud token shard sync and its L4 contract."""

import json
import sqlite3
from pathlib import Path

import pytest

from adapters import icloud_token_sync as sync
from aidata import serve


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
    clean_path = lambda source: tmp_path / "clean" / f"{source}.db"
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
    conn.commit(); conn.close()
    monkeypatch.setattr(serve, "WAREHOUSE_DB", warehouse)
    rows, columns = serve.run_query("tokens/by-device", {"day_from": "2026-11-09", "day_to": "2026-11-09"})
    by_device = {row[1]: dict(zip(columns, row)) for row in rows}
    assert by_device["__all__"]["total_tokens"] == 100
    assert by_device["a"]["share_pct"] == pytest.approx(70.0)
    assert by_device["b"]["share_pct"] == pytest.approx(30.0)
