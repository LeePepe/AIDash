from __future__ import annotations

from datetime import datetime, timezone
import sqlite3
import time
from threading import Thread

from L5_apps.digest.quality_snapshot import build_behavior_snapshot, load_snapshot_from_warehouse
from quality_contracts import (
    ACTIVE_GAP_CAP_SEC,
    ACTIVE_SKILLS,
    CORRECTION_WINDOW_SEC,
    aggregate_behavior,
    build_invocations,
    classify_correction,
    normalize_behavior_records,
    registry_rows,
    select_judge_samples,
)
from quality_judge import FakeJudgeAdapter, build_request, normalize_verdict, run_judge


NOW = datetime(2026, 11, 24, 12, tzinfo=timezone.utc)


def _records():
    return [
        {
            "source": "copilot_cli",
            "session_id": "session-a",
            "event_id": 1,
            "timestamp": "2026-11-24T10:00:00Z",
            "skill": "goal-task",
            "source_kind": "typed",
            "text": "Please use the team lead workflow",
        },
        {
            "source": "copilot_cli",
            "session_id": "session-a",
            "event_id": 1,
            "timestamp": "2026-11-24T10:00:00Z",
            "skill": "team-lead",
            "event_type": "assistant_activity",
            "assistant_activity": True,
            "assistant_turn": True,
            "tool_calls": '["Read", "Edit", "apply_patch"]',
        },
        {
            "source": "copilot_cli",
            "session_id": "session-a",
            "event_id": 2,
            "timestamp": "2026-11-24T10:05:00Z",
            "skill": "team-lead",
            "event_type": "assistant_activity",
            "assistant_activity": True,
            "assistant_turn": True,
            "tool_calls": '["Write"]',
            "finish_reason": "max_tokens",
        },
        {
            "source": "copilot_cli",
            "session_id": "session-a",
            "event_id": 3,
            "timestamp": "2026-11-24T10:06:00Z",
            "skill": "team-lead",
            "source_kind": "typed",
            "text": "That is wrong, please fix it",
        },
    ]


def test_registry_is_explicit_and_aliases_do_not_change_denominator():
    assert len(ACTIVE_SKILLS) == 25
    assert "aidash-content" in ACTIVE_SKILLS
    assert len(registry_rows()) == 25
    records = _records()
    records.append({**records[0], "event_id": 4})
    normalized = normalize_behavior_records(records)
    assert normalized["prompt_signals"][0]["skill"] == "team-lead"
    assert "text" not in normalized["prompt_signals"][0]
    assert any(row["correction_class"] == "repeat_request" for row in normalized["prompt_signals"])


def test_classifier_is_closed_and_excludes_non_human_wrappers():
    negative = classify_correction("This is wrong; please fix it")
    assert negative["correction_class"] == "negative_feedback"
    assert set(negative) == {
        "correction_class", "confidence", "classifier_version", "text_len", "text_sha256"
    }
    assert classify_correction("<task-notification>fix", source_kind="task_notification")["correction_class"] == "none"
    assert classify_correction("ordinary next request")["correction_class"] == "none"


def test_invocationizer_caps_idle_gaps_and_closes_correction_window():
    normalized = normalize_behavior_records(_records())
    invocations = build_invocations(normalized, now=NOW)
    assert len(invocations) == 1
    invocation = invocations[0]
    assert invocation["skill"] == "team-lead"
    assert invocation["eligible"] is True
    assert invocation["correction_class"] == "negative_feedback"
    duration_fixture = normalize_behavior_records([
        {
            "source": "copilot_cli", "session_id": "duration", "event_id": 1,
            "timestamp": "2026-11-24T09:00:00Z", "skill": "team-lead",
            "event_type": "assistant_activity", "assistant_activity": True,
            "assistant_turn": True,
        },
        {
            "source": "copilot_cli", "session_id": "duration", "event_id": 2,
            "timestamp": "2026-11-24T09:30:00Z", "skill": "team-lead",
            "event_type": "assistant_activity", "assistant_activity": True,
            "assistant_turn": True,
        },
    ])
    duration_invocation = build_invocations(duration_fixture, now=NOW)[0]
    assert duration_invocation["active_duration_sec"] == ACTIVE_GAP_CAP_SEC
    assert invocation["edit_tool_calls"] == 3
    assert invocation["max_tokens"] is True
    assert CORRECTION_WINDOW_SEC == 1800
    repaired_records = _records() + [
        {
            "source": "copilot_cli",
            "session_id": "session-a",
            "event_id": 4,
            "timestamp": "2026-11-24T10:07:00Z",
            "skill": "team-lead",
            "event_type": "assistant_activity",
            "assistant_activity": True,
            "assistant_turn": True,
        }
    ]
    repaired = build_invocations(normalize_behavior_records(repaired_records), now=NOW)[0]
    assert repaired["correction_class"] == "negative_feedback"
    interleaved = normalize_behavior_records([
        {"source": "copilot_cli", "session_id": "s1", "event_id": 1, "timestamp": "2026-11-24T09:00:00Z", "skill": "team-lead", "source_kind": "typed", "text": "go", "event_type": "assistant_activity", "assistant_activity": True, "assistant_turn": True},
        {"source": "copilot_cli", "session_id": "s2", "event_id": 1, "timestamp": "2026-11-24T09:02:00Z", "skill": "howto", "source_kind": "typed", "text": "go", "event_type": "assistant_activity", "assistant_activity": True, "assistant_turn": True},
        {"source": "copilot_cli", "session_id": "s1", "event_id": 2, "timestamp": "2026-11-24T09:05:00Z", "skill": "team-lead", "event_type": "assistant_activity", "assistant_activity": True, "assistant_turn": True},
        {"source": "copilot_cli", "session_id": "s1", "event_id": 3, "timestamp": "2026-11-24T09:10:00Z", "skill": "howto", "source_kind": "typed", "text": "That is wrong, please fix it", "event_type": "assistant_activity", "assistant_activity": True, "assistant_turn": True},
    ])
    episodes = {(row["session_id"], row["skill"]): row for row in build_invocations(interleaved, now=NOW)}
    assert episodes[("s1", "team-lead")]["active_duration_sec"] == 300
    assert episodes[("s1", "team-lead")]["correction_class"] is None


def test_quality_behavior_manual_collect_and_normalize_are_explicit(monkeypatch):
    from adapters import quality_behavior

    projection = _records()
    stored = []
    monkeypatch.setattr(quality_behavior, "collect_copilot_projection", lambda *_args, **_kwargs: projection)
    monkeypatch.setattr(quality_behavior, "read_raw", lambda _source: list(stored))
    monkeypatch.setattr(quality_behavior, "write_raw", lambda _source, rows: stored.extend(rows) or len(rows))
    assert quality_behavior.collect(now=NOW) > 0
    assert all("text" not in row for row in stored)
    normalized = {}
    monkeypatch.setattr(quality_behavior, "_write_db", lambda _path, value: normalized.update(value) or 1)
    assert quality_behavior.normalize() == 1
    assert normalized["prompt_signals"]


def test_assistant_only_invocation_is_not_eligible_or_satisfied():
    normalized = normalize_behavior_records([{
        "source": "copilot_cli", "session_id": "assistant-only", "event_id": 1,
        "timestamp": "2026-11-24T09:00:00Z", "skill": "team-lead",
        "event_type": "assistant_activity", "assistant_activity": True,
        "assistant_turn": True,
    }])
    invocation = build_invocations(normalized, now=NOW)[0]
    assert invocation["prompt_linked"] is False
    assert invocation["eligible"] is False
    row = next(row for row in aggregate_behavior([invocation], now=NOW) if row["skill"] == "team-lead")
    assert row["first_pass_satisfaction_rate"] is None
    assert row["coverage_status"] == "partial"


def test_behavior_snapshot_keeps_all_skills_and_missing_evidence_null():
    normalized = normalize_behavior_records(_records())
    snapshot = build_behavior_snapshot(normalized, now=NOW)
    assert len(snapshot["skills"]) == 25
    team_lead = next(row for row in snapshot["skills"] if row["skill"] == "team-lead")
    idle = next(row for row in snapshot["skills"] if row["skill"] == "workflow-hub")
    assert team_lead["eligible"] is True
    assert team_lead["first_pass_satisfaction_rate"] is None
    assert team_lead["max_tokens_invocations"] == 1
    assert idle["coverage_status"] == "unknown"
    assert idle["first_pass_satisfaction_rate"] is None


def test_l5_loader_publishes_quality_behavior_and_judge_sections(tmp_path):
    db_path = tmp_path / "warehouse.db"
    with sqlite3.connect(db_path) as connection:
        connection.executescript("""
            CREATE TABLE fact_skill_invocation (
                invocation_id TEXT, source TEXT, session_id TEXT, skill TEXT,
                start_ts TEXT, end_ts TEXT, observation_end_ts TEXT,
                assistant_turn_count INTEGER, edit_tool_calls INTEGER,
                normalized_edit_churn REAL, active_duration_sec INTEGER,
                max_tokens INTEGER, source_covered INTEGER, prompt_linked INTEGER,
                closed INTEGER, eligible INTEGER, invocationizer_version TEXT
            );
            CREATE TABLE fact_skill_correction (
                correction_signal_uid TEXT, invocation_id TEXT, correction_class TEXT, confidence REAL
            );
            CREATE TABLE fact_skill_judgement (
                judgement_uid TEXT, invocation_id TEXT, skill TEXT, status TEXT,
                abstained INTEGER, overall_score REAL, judge_model TEXT, sampled_at TEXT
            );
        """)
        connection.execute(
            "INSERT INTO fact_skill_invocation VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            ("inv", "copilot_cli", "s", "team-lead", "2026-11-24T09:00:00Z", "2026-11-24T09:01:00Z", "2026-11-24T09:31:00Z", 1, 0, 0.0, 60, 0, 1, 1, 1, 1, "v1"),
        )
        connection.executemany("INSERT INTO fact_skill_judgement VALUES (?, ?, ?, ?, ?, ?, ?, ?)", [
            ("j-1", "inv", "team-lead", "valid", 0, 4.5, "fake", "2026-11-24T02:00:00Z"),
            ("j-2", "inv", "team-lead", "valid", 0, 4.0, "fake", "2026-11-24T03:00:00Z"),
        ])
        connection.commit()
    snapshot = load_snapshot_from_warehouse(db_path, now=NOW)
    assert "behavior" in snapshot and "judge" in snapshot
    assert any(row["skill"] == "team-lead" for row in snapshot["behavior"]["skills"])
    row = next(row for row in snapshot["judge"]["skills"] if row["skill"] == "team-lead")
    assert snapshot["judge"]["coverage_label"] == "1/1"
    assert row["sampled"] == 1
    assert row["rejudged_count"] == 1
    assert row["coverage_pct"] == 100.0
    assert row["source_as_of"] == "2026-11-24T03:00:00Z"


def test_judge_runner_dry_run_and_fake_adapter_are_offline():
    normalized = normalize_behavior_records(_records())
    invocation = build_invocations(normalized, now=NOW)[0]
    request = build_request(invocation, prompt="bounded prompt", response="bounded response")
    dry = run_judge([request])
    assert dry["status"] == "dry_run"
    assert dry["valid"] == 0
    assert "prompt_preview" not in dry["manifest"][0]
    done = run_judge([request], adapter=FakeJudgeAdapter(), dry_run=False)
    assert done["valid"] == 1
    assert done["verdicts"][0]["pass_flag"] is True
    assert done["verdicts"][0]["overall_score"] >= 4.0


def test_sampler_is_deterministic_and_reserves_one_sample_per_eligible_skill():
    normalized = normalize_behavior_records(_records())
    invocation = build_invocations(normalized, now=NOW)[0]
    invocations = [
        {**invocation, "skill": skill, "invocation_id": f"{skill}-inv"}
        for skill in ACTIVE_SKILLS[:3]
    ]
    first = select_judge_samples(invocations, now=NOW, local_salt="fixture")
    second = select_judge_samples(invocations, now=NOW, local_salt="fixture")
    assert first == second
    assert {row["skill"] for row in first} == set(ACTIVE_SKILLS[:3])
    assert all(row["eligible"] is True for row in first)


def test_judge_rubric_components_are_zero_to_three_and_overall_is_five_point():
    normalized = normalize_behavior_records(_records())
    invocation = build_invocations(normalized, now=NOW)[0]
    request = build_request(invocation, prompt="p", response="r")
    verdict, error = normalize_verdict(
        FakeJudgeAdapter()(request), request, judge_run_uid="run", judge_provider="local", judge_model="fake"
    )
    assert error is None
    assert verdict["correctness_score"] == 3.0
    assert verdict["overall_score"] == 4.5
    assert verdict["pass_flag"] is True
    invalid, invalid_error = normalize_verdict(
        {**FakeJudgeAdapter()(request), "correctness_score": 4}, request,
        judge_run_uid="run", judge_provider="local", judge_model="fake",
    )
    assert invalid is None
    assert invalid_error == "malformed_json"
    abstain, abstain_error = normalize_verdict(
        {**FakeJudgeAdapter()(request), "abstained": "false"}, request,
        judge_run_uid="run", judge_provider="local", judge_model="fake",
    )
    assert abstain is None
    assert abstain_error == "malformed_json"


def test_judge_enforces_timeout_output_bound_and_persists_atomically(tmp_path):
    normalized = normalize_behavior_records(_records())
    invocation = build_invocations(normalized, now=NOW)[0]
    request = build_request(invocation, prompt="p", response="r")

    def slow(_request):
        time.sleep(0.05)
        return FakeJudgeAdapter()(_request)

    timeout = run_judge([request], adapter=slow, dry_run=False, adapter_timeout_sec=0.01)
    assert timeout["exclusion_reasons"]["timeout"] == 1
    huge = run_judge(
        [request], adapter=lambda _request: {"rationale": "x" * 100, **FakeJudgeAdapter()(request)},
        dry_run=False, max_output_bytes=32,
    )
    assert huge["exclusion_reasons"]["output_too_large"] == 1
    db_path = tmp_path / "quality_judge.db"
    valid = run_judge([request], adapter=FakeJudgeAdapter(), dry_run=False, persist_path=db_path)
    assert valid["persisted_judgements"] == 1
    with sqlite3.connect(db_path) as connection:
        assert connection.execute("SELECT count(*) FROM run").fetchone()[0] == 1
        assert connection.execute("SELECT count(*) FROM judgement").fetchone()[0] == 1
        row = connection.execute("SELECT correctness_score, overall_score FROM judgement").fetchone()
        assert row == (3.0, 4.5)


def test_timed_out_off_main_adapter_blocks_main_thread_overlap():
    normalized = normalize_behavior_records(_records())
    invocation = build_invocations(normalized, now=NOW)[0]
    request = build_request(invocation, prompt="p", response="r")
    result = {}

    def slow(_request):
        time.sleep(1.0)
        return FakeJudgeAdapter()(_request)

    def worker():
        result.update(run_judge([request], adapter=slow, dry_run=False, adapter_timeout_sec=0.05))

    thread = Thread(target=worker)
    thread.start()
    time.sleep(0.01)
    overlap = run_judge([request], adapter=FakeJudgeAdapter(), dry_run=False)
    assert overlap.get("error_code") == "judge_busy" or overlap.get("exclusion_reasons", {}).get("judge_busy") == 1
    thread.join(timeout=2)
    assert not thread.is_alive()
    assert result["exclusion_reasons"]["timeout"] == 1
    recovered = run_judge([request], adapter=FakeJudgeAdapter(), dry_run=False)
    assert recovered["valid"] == 1


def test_judge_partial_batch_counts_abstain_timeout_malformed_and_duplicate():
    normalized = normalize_behavior_records(_records())
    invocation = build_invocations(normalized, now=NOW)[0]
    requests = [
        build_request({**invocation, "skill": skill, "invocation_id": f"{invocation['invocation_id']}-{index}"}, prompt="p", response="r")
        for index, skill in enumerate(("team-lead", "howto", "workflow-hub"))
    ]
    requests.append(dict(requests[0]))

    def adapter(request):
        if request["skill"] == "howto":
            raise TimeoutError
        if request["skill"] == "workflow-hub":
            return {"abstained": False, "confidence": 0.9}
        return FakeJudgeAdapter()(request)

    result = run_judge(requests, adapter=adapter, dry_run=False)
    assert result["valid"] == 1
    assert result["abstained"] == 0
    assert result["excluded"] == 3
    assert result["exclusion_reasons"]["timeout"] == 1
    assert result["exclusion_reasons"]["duplicate_sample"] == 1
    assert result["exclusion_reasons"]["malformed_json"] == 1


def test_judge_coverage_uses_explicit_eligible_population():
    from quality_contracts import aggregate_judge_coverage

    invocations = []
    verdicts = []
    for index, skill in enumerate(ACTIVE_SKILLS[:19]):
        row = {
            "invocation_id": f"inv-{index}", "skill": skill, "eligible": True,
            "sampled": True,
        }
        invocations.append(row)
        if index < 4:
            verdicts.append({
                "invocation_id": row["invocation_id"], "status": "valid", "abstained": False,
                "overall_score": 4.5, "judge_model": "offline-fake",
            })
    coverage = aggregate_judge_coverage(invocations, verdicts, now=NOW)
    assert coverage["coverage_label"] == "4/19"
    assert coverage["eligible_skill_count"] == 19
    assert coverage["judged_skill_count"] == 4
    assert next(row for row in coverage["skills"] if row["skill"] == ACTIVE_SKILLS[19])["coverage_status"] == "unknown"
    complete = aggregate_judge_coverage(invocations, [
        {"invocation_id": row["invocation_id"], "status": "valid", "abstained": False, "overall_score": 4.0}
        for row in invocations
    ], now=NOW)
    assert complete["coverage_label"] == "19/19"
