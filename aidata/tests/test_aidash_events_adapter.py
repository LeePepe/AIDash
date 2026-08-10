"""Hermetic unit tests for adapters/aidash_events — no live AIDash app / XPC.

The subprocess call, CLI resolution, and raw/clean IO are monkeypatched, so
these prove the envelope parsing, watermark advance, redaction path, and every
degrade-not-crash branch (missing CLI, ok:false, empty result, timeout / non-
zero exit) deterministically — without the app running.
"""

import json

import pytest

import adapters.aidash_events as ae


class _Proc:
    def __init__(self, rc: int, out: str):
        self.returncode = rc
        self.stdout = out
        self.stderr = ""


# A well-formed ok:true envelope: one star event carrying a repo itemRef, one
# whole-card done event whose itemRef is null. The star event also carries a
# cardType (whole-card star, spec 005 D2); the done event predates the field
# (no cardType key at all) to exercise the forward-compat default-to-NULL path.
_ENVELOPE = {
    "ok": True,
    "requestId": "req-1",
    "data": {
        "count": 2,
        "events": [
            {
                "id": "evt-star-1",
                "timestamp": "2026-07-20T09:00:00Z",
                "device": "Mac-1",
                "cardId": "github-radar",
                "action": "star",
                "itemRef": "https://github.com/TauricResearch/TradingAgents",
                "cardType": "trending",
            },
            {
                "id": "evt-done-1",
                "timestamp": "2026-07-21T10:30:00Z",
                "device": "Mac-1",
                "cardId": "todo-list",
                "action": "done",
                "itemRef": None,
            },
        ],
    },
}


def _ok_proc(*_a, **_k):
    return _Proc(0, json.dumps(_ENVELOPE))


# ---- CLI resolution --------------------------------------------------------
@pytest.mark.unit
def test_bin_prefers_fixed_install(monkeypatch):
    monkeypatch.setattr(ae.os.path, "exists", lambda p: p == ae.AIDASH_BIN_FIXED)
    assert ae._aidash_bin() == ae.AIDASH_BIN_FIXED


@pytest.mark.unit
def test_bin_falls_back_to_newest_derived_build(monkeypatch):
    monkeypatch.setattr(ae.os.path, "exists", lambda p: False)
    monkeypatch.setattr(ae.glob, "glob", lambda pat: ["/dd/old/aidash", "/dd/new/aidash"])
    mtimes = {"/dd/old/aidash": 1.0, "/dd/new/aidash": 2.0}
    monkeypatch.setattr(ae.os, "stat", lambda p: type("S", (), {"st_mtime": mtimes[p]})())
    assert ae._aidash_bin() == "/dd/new/aidash"


@pytest.mark.unit
def test_bin_none_when_nothing_resolves(monkeypatch):
    monkeypatch.setattr(ae.os.path, "exists", lambda p: False)
    monkeypatch.setattr(ae.glob, "glob", lambda pat: [])
    assert ae._aidash_bin() is None


# ---- collect: happy path ---------------------------------------------------
@pytest.mark.unit
def test_collect_parses_envelope_and_advances_watermark(monkeypatch):
    monkeypatch.setattr(ae, "_aidash_bin", lambda: "/usr/local/bin/aidash")
    monkeypatch.setattr(ae.subprocess, "run", _ok_proc)
    store: dict[str, object] = {}
    monkeypatch.setattr(ae, "get_watermark", lambda s: store.get(s))
    monkeypatch.setattr(ae, "set_watermark", lambda s, v: store.__setitem__(s, v))
    written: list[dict] = []

    def _cap(source, records):
        recs = list(records)
        written.extend(recs)
        return len(recs)

    monkeypatch.setattr(ae, "write_raw", _cap)

    n = ae.collect()
    assert n == 2
    by_id = {r["id"]: r for r in written}
    # star event carries the correct repo itemRef + cardType
    assert by_id["evt-star-1"]["action"] == "star"
    assert by_id["evt-star-1"]["itemRef"] == \
        "https://github.com/TauricResearch/TradingAgents"
    assert by_id["evt-star-1"]["cardType"] == "trending"
    # whole-card done event: itemRef is null, no cardType key at all (old event)
    assert by_id["evt-done-1"]["action"] == "done"
    assert by_id["evt-done-1"]["itemRef"] is None
    assert "cardType" not in by_id["evt-done-1"]
    # Cursor advanced to the MAX event timestamp, carrying the ids seen there.
    assert store[ae.SOURCE] == {
        "ts": "2026-07-21T10:30:00Z", "ids": ["evt-done-1"],
    }


@pytest.mark.unit
def test_collect_since_uses_watermark_and_json_flag(monkeypatch):
    monkeypatch.setattr(ae, "_aidash_bin", lambda: "/usr/local/bin/aidash")
    captured: dict = {}

    def _spy(cmd, *a, **k):
        captured["cmd"] = cmd
        return _Proc(0, json.dumps(_ENVELOPE))

    monkeypatch.setattr(ae.subprocess, "run", _spy)
    monkeypatch.setattr(ae, "get_watermark", lambda s: "2026-07-19T00:00:00Z")
    monkeypatch.setattr(ae, "set_watermark", lambda s, v: None)
    monkeypatch.setattr(ae, "write_raw", lambda s, r: len(list(r)))
    ae.collect()
    cmd = captured["cmd"]
    assert cmd[1:4] == ["events", "pull", "--since"]
    assert cmd[4] == "2026-07-19T00:00:00Z"  # watermark passed through
    assert "--json" in cmd  # envelope mode


@pytest.mark.unit
def test_collect_first_run_uses_epoch_floor(monkeypatch):
    monkeypatch.setattr(ae, "_aidash_bin", lambda: "/usr/local/bin/aidash")
    captured: dict = {}

    def _spy(cmd, *a, **k):
        captured["cmd"] = cmd
        return _Proc(0, json.dumps({"ok": True, "data": {"count": 0, "events": []}}))

    monkeypatch.setattr(ae.subprocess, "run", _spy)
    monkeypatch.setattr(ae, "get_watermark", lambda s: None)
    monkeypatch.setattr(ae, "write_raw", lambda s, r: pytest.fail("empty → no write"))
    assert ae.collect() == 0
    assert captured["cmd"][4] == ae._EPOCH_SINCE


@pytest.mark.unit
def test_collect_redacts_via_real_write_raw(monkeypatch, tmp_path):
    """Redaction runs on the REAL write_raw path (rawio's enforced red line).

    Points RAW_DIR at a tmp dir and calls through the actual write_raw, then
    reads the shard back to prove a secret embedded in itemRef was scrubbed.
    """
    import config
    import rawio
    monkeypatch.setattr(config, "RAW_DIR", tmp_path, raising=False)
    monkeypatch.setattr(rawio, "raw_source_dir",
                        lambda src: tmp_path / src, raising=False)

    monkeypatch.setattr(ae, "_aidash_bin", lambda: "/usr/local/bin/aidash")
    secret_env = {
        "ok": True,
        "data": {"count": 1, "events": [{
            "id": "evt-x", "timestamp": "2026-07-22T00:00:00Z",
            "device": "Mac", "cardId": "c", "action": "star",
            "itemRef": "token=abcdef0123456789ABCDEF",
        }]},
    }
    monkeypatch.setattr(ae.subprocess, "run",
                        lambda *a, **k: _Proc(0, json.dumps(secret_env)))
    monkeypatch.setattr(ae, "get_watermark", lambda s: None)
    monkeypatch.setattr(ae, "set_watermark", lambda s, v: None)

    assert ae.collect() == 1
    shard_dir = tmp_path / ae.SOURCE
    shards = list(shard_dir.glob("*.jsonl"))
    assert shards, "raw shard was written"
    body = shards[0].read_text(encoding="utf-8")
    assert "abcdef0123456789ABCDEF" not in body  # secret scrubbed
    assert "<REDACTED>" in body


# ---- collect: degrade-not-crash -------------------------------------------
@pytest.mark.unit
def test_collect_degrades_when_cli_missing(monkeypatch):
    monkeypatch.setattr(ae, "_aidash_bin", lambda: None)
    monkeypatch.setattr(ae, "get_watermark", lambda s: None)
    monkeypatch.setattr(ae, "write_raw", lambda *a, **k: pytest.fail("no CLI → no write"))
    assert ae.collect() == 0  # degrade, not crash


@pytest.mark.unit
def test_collect_degrades_on_ok_false(monkeypatch):
    monkeypatch.setattr(ae, "_aidash_bin", lambda: "/usr/local/bin/aidash")
    monkeypatch.setattr(ae.subprocess, "run",
                        lambda *a, **k: _Proc(0, json.dumps({"ok": False, "data": {}})))
    monkeypatch.setattr(ae, "get_watermark", lambda s: None)
    monkeypatch.setattr(ae, "write_raw", lambda *a, **k: pytest.fail("ok:false → no write"))
    assert ae.collect() == 0


@pytest.mark.unit
def test_collect_empty_count_is_zero_not_error(monkeypatch):
    monkeypatch.setattr(ae, "_aidash_bin", lambda: "/usr/local/bin/aidash")
    monkeypatch.setattr(ae.subprocess, "run",
                        lambda *a, **k: _Proc(0, json.dumps({"ok": True, "data": {"count": 0, "events": []}})))
    monkeypatch.setattr(ae, "get_watermark", lambda s: None)
    monkeypatch.setattr(ae, "set_watermark", lambda s, v: pytest.fail("no advance on empty"))
    monkeypatch.setattr(ae, "write_raw", lambda *a, **k: pytest.fail("empty → no write"))
    assert ae.collect() == 0  # valid empty result, not a failure


@pytest.mark.unit
def test_collect_degrades_on_timeout(monkeypatch):
    monkeypatch.setattr(ae, "_aidash_bin", lambda: "/usr/local/bin/aidash")

    def _boom(*a, **k):
        raise ae.subprocess.TimeoutExpired(cmd="aidash", timeout=60)

    monkeypatch.setattr(ae.subprocess, "run", _boom)
    monkeypatch.setattr(ae, "get_watermark", lambda s: None)
    monkeypatch.setattr(ae, "write_raw", lambda *a, **k: pytest.fail("timeout → no write"))
    assert ae.collect() == 0  # XPC hang degrades, never raises


@pytest.mark.unit
def test_collect_degrades_on_nonzero_exit(monkeypatch):
    monkeypatch.setattr(ae, "_aidash_bin", lambda: "/usr/local/bin/aidash")
    monkeypatch.setattr(ae.subprocess, "run", lambda *a, **k: _Proc(1, ""))
    monkeypatch.setattr(ae, "get_watermark", lambda s: None)
    monkeypatch.setattr(ae, "write_raw", lambda *a, **k: pytest.fail("exit!=0 → no write"))
    assert ae.collect() == 0


# ---- normalize -------------------------------------------------------------
@pytest.mark.unit
def test_normalize_maps_fields_and_actions(monkeypatch):
    raw = [
        {"id": "e1", "timestamp": "2026-07-20T09:00:00Z", "device": "Mac",
         "cardId": "radar", "action": "star",
         "itemRef": "https://github.com/a/b", "cardType": "trending"},
        {"id": "e2", "timestamp": "2026-07-21T10:00:00Z", "device": "Mac",
         "cardId": "todo", "action": "done", "itemRef": None},
    ]
    monkeypatch.setattr(ae, "read_raw", lambda s: raw)
    captured: dict = {}

    def _cap(s, t, ddl, rows, cols):
        captured["rows"] = {r["event_id"]: r for r in rows}
        captured["cols"] = cols
        return len(rows)

    monkeypatch.setattr(ae, "write_clean", _cap)
    assert ae.normalize() == 2
    assert captured["cols"] == \
        ("event_id", "ts", "device", "card_id", "action", "item_ref",
         "card_type")
    r1 = captured["rows"]["e1"]
    assert r1["action"] == "star"
    assert r1["item_ref"] == "https://github.com/a/b"
    assert r1["card_type"] == "trending"
    r2 = captured["rows"]["e2"]
    assert r2["action"] == "done"
    assert r2["item_ref"] is None  # whole-card event stays NULL
    assert r2["card_type"] is None  # no cardType key on this (older) event


@pytest.mark.unit
def test_normalize_last_write_wins_by_event_id(monkeypatch):
    raw = [
        {"id": "e1", "timestamp": "2026-07-20T09:00:00Z", "action": "star",
         "itemRef": "https://github.com/a/old"},
        {"id": "e1", "timestamp": "2026-07-20T09:00:00Z", "action": "star",
         "itemRef": "https://github.com/a/new"},  # same id, later shard wins
    ]
    monkeypatch.setattr(ae, "read_raw", lambda s: raw)
    captured: dict = {}

    def _cap(s, t, ddl, rows, cols):
        captured["rows"] = rows
        return len(rows)

    monkeypatch.setattr(ae, "write_clean", _cap)
    assert ae.normalize() == 1
    assert captured["rows"][0]["item_ref"] == "https://github.com/a/new"


@pytest.mark.unit
def test_normalize_skips_events_without_id(monkeypatch):
    monkeypatch.setattr(ae, "read_raw",
                        lambda s: [{"timestamp": "x", "action": "star"}])
    monkeypatch.setattr(ae, "write_clean",
                        lambda s, t, ddl, rows, cols: len(rows))
    assert ae.normalize() == 0


@pytest.mark.unit
def test_normalize_unknown_action_becomes_null(monkeypatch):
    monkeypatch.setattr(ae, "read_raw",
                        lambda s: [{"id": "e1", "timestamp": "t", "action": "bogus"}])
    captured: dict = {}

    def _cap(s, t, ddl, rows, cols):
        captured["rows"] = rows
        return len(rows)

    monkeypatch.setattr(ae, "write_clean", _cap)
    ae.normalize()
    assert captured["rows"][0]["action"] is None


# --- inclusive-watermark re-pull guard (BUG B) ------------------------------
#
# `events pull --since` is INCLUSIVE on the app side (XPCHandlers predicate is
# `timestamp >= since`, and the CLI documents "Lower bound, inclusive"). The
# watermark we persist is the timestamp of an event we ALREADY wrote, so the
# boundary event comes back on every subsequent run. Before the fix that event
# was re-appended to a NEW day's raw shard each time — one real star ended up
# duplicated across the 08-03 / 08-06 / 08-07 shards on disk.
#
# Raw is append-only and is the source of truth, so a duplicate there is a real
# integrity defect even though L2's id-keying happens to mask it.

@pytest.mark.unit
def test_collect_drops_boundary_event_already_at_watermark(monkeypatch):
    """Re-pull that returns ONLY the boundary event writes nothing."""
    monkeypatch.setattr(ae, "_aidash_bin", lambda: "/usr/local/bin/aidash")
    monkeypatch.setattr(ae.subprocess, "run", _ok_proc)
    # Watermark sits at the NEWEST event in _ENVELOPE, so both events in the
    # envelope are at-or-before it — exactly the steady state after a prior run.
    store: dict[str, object] = {ae.SOURCE: "2026-07-21T10:30:00Z"}
    monkeypatch.setattr(ae, "get_watermark", lambda s: store.get(s))
    monkeypatch.setattr(ae, "set_watermark", lambda s, v: store.__setitem__(s, v))
    written: list[dict] = []
    monkeypatch.setattr(ae, "write_raw",
                        lambda s, recs: written.extend(recs) or len(written))

    assert ae.collect() == 0
    assert written == []  # nothing re-appended to raw
    assert store[ae.SOURCE] == "2026-07-21T10:30:00Z"  # watermark unmoved


@pytest.mark.unit
def test_collect_keeps_only_events_strictly_after_watermark(monkeypatch):
    """A mixed re-pull writes the new event only, and advances the watermark."""
    monkeypatch.setattr(ae, "_aidash_bin", lambda: "/usr/local/bin/aidash")
    monkeypatch.setattr(ae.subprocess, "run", _ok_proc)
    # Watermark at the OLDER event: the star is a re-pull, the done is genuinely new.
    store: dict[str, object] = {ae.SOURCE: "2026-07-20T09:00:00Z"}
    monkeypatch.setattr(ae, "get_watermark", lambda s: store.get(s))
    monkeypatch.setattr(ae, "set_watermark", lambda s, v: store.__setitem__(s, v))
    written: list[dict] = []

    def _cap(source, records):
        recs = list(records)
        written.extend(recs)
        return len(recs)

    monkeypatch.setattr(ae, "write_raw", _cap)

    assert ae.collect() == 1
    assert [r["id"] for r in written] == ["evt-done-1"]
    assert store[ae.SOURCE] == {
        "ts": "2026-07-21T10:30:00Z", "ids": ["evt-done-1"],
    }


# --- same-second distinct event must survive (id-based cursor) ---------------
#
# A pure timestamp `>` cursor drops a DISTINCT event that shares the boundary
# event's exact second. Timestamps are second-granularity and a `done` + a
# `star` can easily land in the same second, so that is a real loss window, not
# a theoretical one: once the watermark records that second, the sibling event
# is never written to raw and never comes back.
#
# The cursor is therefore (timestamp, seen-ids-at-that-second): exclude only the
# ids already collected at the boundary second, not the whole second.

_SAME_SECOND_ENVELOPE = {
    "ok": True,
    "data": {
        "count": 2,
        "events": [
            {   # already collected on a previous run
                "id": "evt-star-boundary",
                "timestamp": "2026-07-21T10:30:00Z",
                "device": "Mac-1", "cardId": "github-radar",
                "action": "star", "itemRef": "https://github.com/a/b",
            },
            {   # DISTINCT event, same second — must NOT be dropped
                "id": "evt-done-same-second",
                "timestamp": "2026-07-21T10:30:00Z",
                "device": "Mac-1", "cardId": "todo-list",
                "action": "done", "itemRef": None,
            },
        ],
    },
}


@pytest.mark.unit
def test_collect_keeps_distinct_event_in_the_boundary_second(monkeypatch):
    monkeypatch.setattr(ae, "_aidash_bin", lambda: "/usr/local/bin/aidash")
    monkeypatch.setattr(ae.subprocess, "run",
                        lambda *a, **k: _Proc(0, json.dumps(_SAME_SECOND_ENVELOPE)))
    # Prior run collected ONLY the star at that second.
    store: dict[str, object] = {
        ae.SOURCE: {"ts": "2026-07-21T10:30:00Z", "ids": ["evt-star-boundary"]}
    }
    monkeypatch.setattr(ae, "get_watermark", lambda s: store.get(s))
    monkeypatch.setattr(ae, "set_watermark", lambda s, v: store.__setitem__(s, v))
    written: list[dict] = []

    def _cap(source, records):
        recs = list(records)
        written.extend(recs)
        return len(recs)

    monkeypatch.setattr(ae, "write_raw", _cap)

    assert ae.collect() == 1
    assert [r["id"] for r in written] == ["evt-done-same-second"]
    # BOTH ids at that second are now recorded, so neither returns next run.
    assert store[ae.SOURCE]["ts"] == "2026-07-21T10:30:00Z"
    assert set(store[ae.SOURCE]["ids"]) == {"evt-star-boundary", "evt-done-same-second"}


@pytest.mark.unit
def test_collect_reads_legacy_bare_string_watermark(monkeypatch):
    """A plain-string watermark from before the cursor change still works."""
    monkeypatch.setattr(ae, "_aidash_bin", lambda: "/usr/local/bin/aidash")
    monkeypatch.setattr(ae.subprocess, "run", _ok_proc)
    store: dict[str, object] = {ae.SOURCE: "2026-07-20T09:00:00Z"}  # old format
    monkeypatch.setattr(ae, "get_watermark", lambda s: store.get(s))
    monkeypatch.setattr(ae, "set_watermark", lambda s, v: store.__setitem__(s, v))
    written: list[dict] = []

    def _cap(source, records):
        recs = list(records)
        written.extend(recs)
        return len(recs)

    monkeypatch.setattr(ae, "write_raw", _cap)

    assert ae.collect() == 1
    assert [r["id"] for r in written] == ["evt-done-1"]
