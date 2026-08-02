"""Unit tests for the multica_comment adapter (L1 collect + L2 normalize).

Hermetic: the multica CLI runner, raw IO, and watermark state are monkeypatched
so these run without a live CLI. Verifies mention_role extraction, redaction of
comment bodies on the way into raw, is_reply / resolution derivation, the
per-workspace incremental (--since) watermark, and degrade-to-zero when the CLI
is absent.
"""

import pytest

import adapters.multica_comment as mc


# Issue raw (as multica_issue writes it) across two workspaces.
RAW_ISSUES = [
    {"id": "iss-wsa", "identifier": "ABC-1", "number": 1, "workspace_id": "ws-wsa"},
    {"id": "iss-my", "identifier": "MY-1", "number": 1, "workspace_id": "ws-my"},
]

# A canned comment carrying a mention, a reply, a resolution, and a live-looking
# token embedded in the body (to prove redaction runs before raw landing).
FAKE_TOKEN = "ghp_" + "A" * 30
COMMENT_ROOT = {
    "id": "c-root", "issue_id": "iss-my", "parent_id": None,
    "author_type": "agent", "type": "comment", "reply_count": 1,
    "resolved_at": None, "created_at": "2026-07-06T13:00:00Z",
    "last_activity_at": "2026-07-06T13:30:00Z",
    "content": f"[@AI Reviewer](mention://agent/abc) review PR token={FAKE_TOKEN}",
}
COMMENT_REPLY = {
    "id": "c-reply", "issue_id": "iss-my", "parent_id": "c-root",
    "author_type": "agent", "type": "comment", "reply_count": 0,
    "resolved_at": "2026-07-06T13:45:00Z", "created_at": "2026-07-06T13:30:00Z",
    "last_activity_at": "2026-07-06T13:45:00Z",
    "content": "[@Team Lead](mention://agent/def) review complete, LGTM",
}


@pytest.fixture
def canned(monkeypatch):
    """Wire CLI responses + capture raw writes (through the REAL redactor)."""
    from rawio import redact_obj  # exercise the real red line
    calls: list[list[str]] = []
    store: dict[str, object] = {}
    written: list[dict] = []

    def fake_run_json(args):
        calls.append(args)
        # args: ["issue","comment","list", <iid>, "--workspace-id", ws, ...]
        iid = args[3]
        if iid == "iss-my":
            return [COMMENT_ROOT, COMMENT_REPLY]
        return []

    def fake_write_raw(src, recs):
        for r in recs:
            written.append(redact_obj(r))  # match rawio's real behavior
        return len(recs)

    monkeypatch.setattr(mc, "_run_json", fake_run_json)
    monkeypatch.setattr(mc, "_multica_bin", lambda: "/usr/bin/multica")
    monkeypatch.setattr(mc, "read_raw", lambda src: RAW_ISSUES)
    monkeypatch.setattr(mc, "write_raw", fake_write_raw)
    monkeypatch.setattr(mc, "get_watermark", lambda k: store.get(k))
    monkeypatch.setattr(mc, "set_watermark", lambda k, v: store.__setitem__(k, v))
    monkeypatch.setattr(mc, "MULTICA_WORKSPACES",
                        (("ws-wsa", "WorkspaceA"), ("ws-my", "my")))
    return calls, store, written


@pytest.mark.unit
def test_comments_fetched_per_issue_with_workspace_id(canned):
    calls, store, written = canned
    mc.collect()
    list_calls = [c for c in calls if c[1] == "comment"]
    by_iss = {c[3]: c for c in list_calls}
    assert "--workspace-id" in by_iss["iss-wsa"] and "ws-wsa" in by_iss["iss-wsa"]
    assert "--workspace-id" in by_iss["iss-my"] and "ws-my" in by_iss["iss-my"]


@pytest.mark.unit
def test_body_is_redacted_before_landing_in_raw(canned):
    calls, store, written = canned
    mc.collect()
    root = [r for r in written if r["id"] == "c-root"][0]
    assert FAKE_TOKEN not in root["content"]
    assert "<REDACTED>" in root["content"]


@pytest.mark.unit
def test_watermark_advances_per_workspace_and_drives_since(canned):
    calls, store, written = canned
    mc.collect()
    # my's newest activity (the reply's last_activity_at) becomes the watermark;
    # workspace-a had no comments so it stays unset.
    assert store["multica_comment:ws-my"] == "2026-07-06T13:45:00Z"
    assert "multica_comment:ws-wsa" not in store
    # A second collect passes --since with that watermark for my.
    calls.clear()
    mc.collect()
    my_call = [c for c in calls if c[1] == "comment" and c[3] == "iss-my"][0]
    assert "--since" in my_call
    assert my_call[my_call.index("--since") + 1] == "2026-07-06T13:45:00Z"


@pytest.mark.unit
def test_normalize_derives_mention_thread_and_resolution(monkeypatch):
    # Feed the (already-redacted) comments straight into normalize.
    monkeypatch.setattr(mc, "read_raw", lambda src: [COMMENT_ROOT, COMMENT_REPLY])
    captured: dict = {}

    def fake_write_clean(source, table, ddl, rows, cols):
        captured["rows"] = {r["comment_id"]: r for r in rows}
        captured["cols"] = cols
        return len(rows)

    monkeypatch.setattr(mc, "write_clean", fake_write_clean)
    n = mc.normalize()
    assert n == 2
    root = captured["rows"]["c-root"]
    reply = captured["rows"]["c-reply"]
    # mention target pulled from the body
    assert root["mention_role"] == "AI Reviewer"
    assert reply["mention_role"] == "Team Lead"
    # threading + resolution derivations
    assert root["is_reply"] == 0 and reply["is_reply"] == 1
    assert reply["parent_id"] == "c-root"
    assert root["resolved_at"] is None
    assert reply["resolved_at"] == "2026-07-06T13:45:00Z"
    # body is landed only as a bounded preview, not unbounded prose
    assert len(root["content_preview"]) <= mc._PREVIEW_LEN


@pytest.mark.unit
def test_normalize_no_mention_yields_none(monkeypatch):
    plain = {**COMMENT_ROOT, "id": "c-plain",
             "content": "just a status note, no mention here"}
    monkeypatch.setattr(mc, "read_raw", lambda src: [plain])
    captured: dict = {}
    monkeypatch.setattr(
        mc, "write_clean",
        lambda s, t, d, rows, c: captured.update(rows=rows) or len(rows))
    mc.normalize()
    assert captured["rows"][0]["mention_role"] is None


@pytest.mark.unit
def test_collect_degrades_to_zero_without_cli(monkeypatch):
    monkeypatch.setattr(mc, "_multica_bin", lambda: None)
    called = {"n": 0}
    monkeypatch.setattr(mc, "read_raw",
                        lambda src: called.__setitem__("n", called["n"] + 1) or [])
    assert mc.collect() == 0
    assert called["n"] == 0  # never even enumerates issues


@pytest.mark.unit
def test_collect_skips_issue_whose_query_fails(monkeypatch):
    written: list[dict] = []
    store: dict[str, object] = {}

    def boom_or_ok(args):
        if args[3] == "iss-my":
            raise RuntimeError("boom")
        return []

    monkeypatch.setattr(mc, "_multica_bin", lambda: "/usr/bin/multica")
    monkeypatch.setattr(mc, "_run_json", boom_or_ok)
    monkeypatch.setattr(mc, "read_raw", lambda src: RAW_ISSUES)
    monkeypatch.setattr(mc, "write_raw",
                        lambda s, recs: (written.extend(recs) or len(recs)))
    monkeypatch.setattr(mc, "get_watermark", lambda k: store.get(k))
    monkeypatch.setattr(mc, "set_watermark", lambda k, v: store.__setitem__(k, v))
    monkeypatch.setattr(mc, "MULTICA_WORKSPACES",
                        (("ws-wsa", "WorkspaceA"), ("ws-my", "my")))
    # iss-my raises, iss-wsa returns [] — collect completes without propagating.
    assert mc.collect() == 0
