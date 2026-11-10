import json
import sqlite3

import pytest
from L5_apps.digest import aidash, event_bridge, sources, verify
from L5_apps.digest.card_policy import DataProfile, choose_card


def _payload():
    hours = []
    citations = []
    for hour in range(24):
        if hour == 9:
            evidence_id = "H09-F1"
            hours.append({"hour": hour, "summary": "完成一项工作", "evidenceIds": [evidence_id]})
            citations.append({"id": evidence_id, "label": "GTT event"})
        else:
            hours.append({"hour": hour, "summary": "无采集数据。", "evidenceIds": []})
    return {"hours": hours, "citations": citations}


@pytest.mark.unit
def test_verify_hourly_timeline_and_policy():
    assert verify.verify_hourly_timeline(_payload()).ok
    assert choose_card(DataProfile("hourly_timeline", 4, 1)).card_type == "hourlyTimeline"


@pytest.mark.unit
def test_verify_hourly_timeline_rejects_cross_hour_evidence():
    payload = _payload()
    payload["hours"][9]["evidenceIds"] = ["H08-F1"]
    assert not verify.verify_hourly_timeline(payload).ok


@pytest.mark.unit
def test_jev_offline_degrades_to_ok():
    def offline(*_args, **_kwargs):
        raise OSError("offline")
    result = verify.verify_citations_with_jev(
        _payload(), {"H09-F1": "finished work"}, opener=offline)
    assert result.ok


@pytest.mark.unit
def test_event_bridge_latest_wins_and_falcon_star(tmp_path):
    proposals = tmp_path / "proposals.jsonl"
    proposals.write_text(json.dumps({
        "id": "p1", "ts": "2026-11-05T00:00:00Z", "agent": "a",
        "title": "Ship it", "detail": "because", "priority": "high",
        "status": "pending",
    }) + "\n", encoding="utf-8")
    falcon = tmp_path / "falcon.db"
    with sqlite3.connect(falcon) as conn:
        conn.execute("CREATE TABLE requests (id TEXT PRIMARY KEY, summary_json TEXT)")
        conn.execute("INSERT INTO requests VALUES ('r1', NULL)")
    calls = []
    result = event_bridge.process_user_events(
        [
            {"action": "done", "itemRef": "proposal://p1", "timestamp": "2026-11-05T01:00:00Z"},
            {"action": "undone", "itemRef": "gtt://goal/task", "timestamp": "2026-11-05T02:00:00Z"},
            {"action": "star", "itemRef": "proposal://p1"},
            {"action": "star", "itemRef": "falcon://request/r1"},
        ],
        proposals_path=proposals,
        falcon_db_path=falcon,
        linear_runner=lambda title, detail: calls.append((title, detail)) or 0,
    )
    assert result["promoted"] == 1
    assert result["falcon_starred"] == 1
    assert calls == [("Ship it", "because")]
    assert '"status": "approved"' in proposals.read_text(encoding="utf-8")
    with sqlite3.connect(falcon) as conn:
        assert json.loads(conn.execute("SELECT summary_json FROM requests").fetchone()[0])["starredAt"]


@pytest.mark.unit
def test_hourly_timeline_fetch_degrades_without_warehouse(tmp_path, monkeypatch):
    monkeypatch.setattr(sources, "WAREHOUSE_DB", tmp_path / "missing.db")
    bundle = sources.fetch_hourly_timeline("2026-11-04")
    assert bundle.health.state.startswith("skipped:")
    assert aidash._hourly_timeline_container("1104", "2026-11-04", bundle) is None


@pytest.mark.unit
def test_hourly_timeline_carries_event_metadata(tmp_path, monkeypatch):
    warehouse = tmp_path / "warehouse.db"
    with sqlite3.connect(warehouse) as conn:
        conn.execute(
            "CREATE TABLE fact_gtt_event (cst_day TEXT, ts TEXT, evt_type TEXT, "
            "goal_id TEXT, task_id TEXT, pr_number INTEGER, note_preview TEXT)"
        )
        conn.execute(
            "INSERT INTO fact_gtt_event VALUES (?, ?, ?, ?, ?, ?, ?)",
            ("2026-11-04", "2026-11-04T01:00:00+08:00", "TASK_BLOCKED",
             "goal-1", "task-1", 272, "needs review"),
        )
    monkeypatch.setattr(sources, "WAREHOUSE_DB", warehouse)
    bundle = sources.fetch_hourly_timeline("2026-11-04")
    assert bundle.health.state == "ok"
    assert "goal-1" in bundle.citations[0].label
    assert "task-1" in bundle.citations[0].label
    assert "272" in bundle.citations[0].label
    assert "needs review" in bundle.citations[0].label


@pytest.mark.unit
def test_star_preferences_boost_direct_and_similar_items():
    from L5_apps.digest.repo_radar import RepoCard

    starred = RepoCard("owner/starred", 10, 1, "", "", ("swift",), "", "",
                       category="tools", related_project="AIDash")
    similar = RepoCard("owner/similar", 9, 1, "", "", ("swift",), "", "",
                       category="tools", related_project="AIDash")
    other = RepoCard("owner/other", 8, 1, "", "", ("python",), "", "",
                     category="data")
    ordered = sources.apply_star_preferences([other, similar, starred], ["owner/starred"])
    assert [item.repo for item in ordered] == ["owner/starred", "owner/similar", "owner/other"]


@pytest.mark.unit
def test_starred_refs_are_read_from_normalized_events(tmp_path, monkeypatch):
    db = tmp_path / "aidash_events.db"
    with sqlite3.connect(db) as conn:
        conn.execute("CREATE TABLE user_event (action TEXT, item_ref TEXT)")
        conn.executemany(
            "INSERT INTO user_event VALUES (?, ?)",
            [("star", "owner/starred"), ("done", "proposal://p1")],
        )
    monkeypatch.setattr(
        sources, "clean_path",
        lambda name: db if name == "aidash_events" else tmp_path / name,
    )
    assert sources._fetch_starred_refs() == ("owner/starred",)


@pytest.mark.unit
def test_event_bridge_linear_done_undone_and_star_external_id(tmp_path):
    proposals = tmp_path / "proposals.jsonl"
    proposals.write_text(json.dumps({
        "id": "p2", "ts": "2026-11-09T00:00:00Z", "agent": "retro",
        "title": "Unify Todo SSOT", "detail": "Promote to Linear", "priority": "high",
        "status": "pending",
    }) + "\n", encoding="utf-8")
    status_calls: list[tuple[str, str]] = []

    def fake_status_runner(issue_id: str, state: str) -> int:
        status_calls.append((issue_id, state))
        return 0 if issue_id != "TIA-999" else 1

    result = event_bridge.process_user_events(
        [
            {"action": "done", "itemRef": "linear://TIA-90", "timestamp": "2026-11-09T01:00:00Z"},
            {"action": "done", "itemRef": "TIA-91", "timestamp": "2026-11-09T01:00:00Z"},
            {"action": "undone", "itemRef": "linear://TIA-91", "timestamp": "2026-11-09T02:00:00Z"},
            {"action": "done", "itemRef": "linear://TIA-999", "timestamp": "2026-11-09T03:00:00Z"},
            {"action": "star", "itemRef": "proposal://p2"},
        ],
        proposals_path=proposals,
        linear_runner=lambda title, detail: (0, "TIA-95"),
        linear_status_runner=fake_status_runner,
    )
    assert result["resolved"] == 1
    assert result["undone"] == 1
    assert result["promoted"] == 1
    assert result["errors"] == 1
    assert ("TIA-90", "Done") in status_calls
    assert ("TIA-91", "Todo") in status_calls
    assert ("TIA-999", "Done") in status_calls
    lines = [
        json.loads(line)
        for line in proposals.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    assert lines[-1]["status"] == "approved"
    assert lines[-1]["external_id"] == "TIA-95"


@pytest.mark.unit
def test_default_linear_runner_parses_issue_identifier(monkeypatch, tmp_path):
    script = tmp_path / "linear-sync.py"
    script.write_text("#!/usr/bin/env python3\n", encoding="utf-8")
    monkeypatch.setattr(event_bridge, "LINEAR_SYNC_SCRIPT", script)

    class FakeProc:
        returncode = 0
        stdout = json.dumps({
            "ok": True,
            "command": "idea",
            "issue": {"identifier": "TIA-96"},
        })

    monkeypatch.setattr(event_bridge.subprocess, "run", lambda *a, **k: FakeProc())
    rc, external_id = event_bridge._default_linear_runner("Title", "Desc")
    assert rc == 0
    assert external_id == "TIA-96"


@pytest.mark.unit
def test_event_bridge_crash_perf_star_and_auto_mode_with_dispatch(monkeypatch, tmp_path):
    proposals = tmp_path / "proposals.jsonl"
    proposals.write_text(
        "\n".join(
            [
                json.dumps(
                    {
                        "id": "crash-vitalstride-1",
                        "ts": "2026-11-10T00:00:00Z",
                        "agent": "retro-loop",
                        "title": "[Crash] VitalStride 新增 Crash: EXC_BAD_ACCESS",
                        "detail": "stack_top_symbol=HealthSync.fetch; layer=Packages/VitalCore; verify=swift test",
                        "priority": "high",
                        "status": "pending",
                        "app_name": "VitalStride",
                        "event_kind": "crash",
                        "signature": "EXC_BAD_ACCESS:HealthSync",
                        "stack_top_symbol": "HealthSync.fetch",
                        "recommended_layer": "Packages/VitalCore",
                        "verify_cmd": "swift test",
                    }
                ),
                json.dumps(
                    {
                        "id": "perf-aidash-1",
                        "ts": "2026-11-10T01:00:00Z",
                        "agent": "retro-loop",
                        "title": "[Perf] AIDash P95 退化 +45%",
                        "detail": "stack_top_symbol=BriefingScene.onAppear; layer=Packages/AIDashUI; verify=scripts/context/run AIDashUI --mode local",
                        "priority": "high",
                        "status": "pending",
                        "app_name": "AIDash",
                        "event_kind": "perf",
                        "signature": "aidash.performance.ready_scene",
                        "stack_top_symbol": "BriefingScene.onAppear",
                        "recommended_layer": "Packages/AIDashUI",
                        "verify_cmd": "scripts/context/run AIDashUI --mode local",
                    }
                ),
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    linear_calls: list[tuple[str, str]] = []
    dispatched_calls: list[tuple[str, str, str | None]] = []

    def fake_linear(title: str, detail: str):
        linear_calls.append((title, detail))
        return 0, f"TIA-{200 + len(linear_calls)}"

    def fake_dispatch(prop, ext_id):
        dispatched_calls.append((prop.app_name, prop.stack_top_symbol, ext_id))
        return 0

    # Star first proposal with auto_dispatch=True, and let mode="auto" promote+dispatch the second
    summary = event_bridge.process_user_events(
        [{"action": "star", "itemRef": "proposal://crash-vitalstride-1"}],
        proposals_path=proposals,
        linear_runner=fake_linear,
        mode="auto",
        auto_dispatch=True,
        dispatch_runner=fake_dispatch,
    )
    assert summary["promoted"] == 2
    assert summary["dispatched"] == 2
    assert summary["errors"] == 0
    assert len(linear_calls) == 2
    assert dispatched_calls == [
        ("VitalStride", "HealthSync.fetch", "TIA-201"),
        ("AIDash", "BriefingScene.onAppear", "TIA-202"),
    ]

    # Verify _default_dispatch_runner invokes herdr-dispatch.sh with target app repo
    recorded_cmds: list[list[str]] = []
    app_repo = tmp_path / "Development" / "VitalStride"
    app_repo.mkdir(parents=True)
    monkeypatch.setattr(event_bridge, "HOME", tmp_path)

    class FakeDispatchProc:
        returncode = 0

    monkeypatch.setattr(
        event_bridge.subprocess,
        "run",
        lambda cmd, **kw: recorded_cmds.append(list(cmd)) or FakeDispatchProc(),
    )
    sample_prop = event_bridge.Proposal(
        id="crash-vs",
        ts="2026-11-10T00:00:00Z",
        agent="retro-loop",
        title="Crash in VitalStride",
        detail="detail",
        priority="high",
        status="pending",
        app_name="VitalStride",
        event_kind="crash",
        stack_top_symbol="HealthSync.fetch",
        recommended_layer="Packages/VitalCore",
        verify_cmd="swift test",
    )
    assert event_bridge._default_dispatch_runner(sample_prop, "TIA-201") == 0
    assert len(recorded_cmds) == 1
    assert "--new-workspace" in recorded_cmds[0]
    assert str(app_repo) in recorded_cmds[0]

