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
