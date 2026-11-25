from __future__ import annotations

import json
import re
import sqlite3
from pathlib import Path

from L5_apps.digest import agent_efficiency_snapshot as aes
from L5_apps.digest import skills_roi_snapshot as srs

_BANNED_LABEL_PATTERNS = (
    re.compile(r"\bS(?:[1-9]|1[0-2])\b"),
    re.compile(r"\bM[1-5]\b"),
    re.compile(r"\bL[0-3]\b"),
    re.compile(r"\bR[1-4]\b"),
    re.compile(r"\bH[1-5]\b"),
    re.compile(r"\bHZN[1-5]\b"),
    re.compile(r"\bpython3\b"),
    re.compile(r"\bagent_retro\.py\b"),
    re.compile(r"\bskill_retro\.py\b"),
    re.compile(r"\bSKILL\.md\b"),
    re.compile(r"\bsession_id\b"),
)


def _assert_plain_language_labels(text: str) -> None:
    for pat in _BANNED_LABEL_PATTERNS:
        assert not pat.search(text), f"banned code {pat.pattern!r} leaked into plain-language label {text!r}"


def test_agent_efficiency_snapshot_emits_plain_language_agent_retro_and_watermarks(tmp_path):
    warehouse = tmp_path / "warehouse.db"
    with sqlite3.connect(warehouse) as conn:
        conn.executescript(
            """
            CREATE TABLE fact_agent_retro_finding (
                finding_uid TEXT PRIMARY KEY,
                source TEXT NOT NULL,
                session_id TEXT NOT NULL,
                goal_id TEXT,
                role_key TEXT NOT NULL,
                skill TEXT NOT NULL,
                layer_key TEXT NOT NULL,
                finding_code TEXT NOT NULL,
                severity TEXT NOT NULL,
                skill_version TEXT,
                is_post_fix INTEGER NOT NULL,
                occurrence_count INTEGER NOT NULL,
                ts TEXT NOT NULL,
                cst_day TEXT GENERATED ALWAYS AS (date(ts, '+8 hours')) STORED
            );
            """
        )
        conn.executemany(
            "INSERT INTO fact_agent_retro_finding "
            "(finding_uid, source, session_id, goal_id, role_key, skill, layer_key, finding_code, "
            "severity, skill_version, is_post_fix, occurrence_count, ts) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                ("f1", "copilot_cli", "s1", "g1", "m2", "m2-dispatcher", "role", "R2_m2_direct_code_edit", "critical", "v5@abc1234", 0, 3, "2026-11-20T04:00:00Z"),
                ("f2", "copilot_cli", "s2", "g2", "explorer", "agent-retro", "invoke", "I3_l2_exit2_and_output_bloat", "high", "v9@def5678", 1, 2, "2026-11-24T06:00:00Z"),
            ],
        )
        conn.commit()

    def fake_runner(name: str, params: dict | None = None):
        if name == aes.ROLE_QUERY:
            return (
                [("writer", "编码实现 (Writer)", 4, 2, 4, 3, 1, 0, 0.75, 120.0, 240.0, 5000)],
                [
                    "role_key", "role_label", "runs_count", "goals_count", "tasks_count",
                    "r1_count", "r2_count", "r3_plus_count", "r1_pass_rate",
                    "median_duration_sec", "p90_duration_sec", "estimated_tokens",
                ],
            )
        if name == aes.DAILY_QUERY:
            return (
                [("2026-11-24", 1, 2, 2, 0, 0, 1.0, 100.0, 180.0, 0, 1000, 4000, 5000)],
                [
                    "cst_day", "goals_completed", "tasks_completed", "r1_count",
                    "r2_count", "r3_plus_count", "r1_pass_rate", "median_duration_sec",
                    "p90_duration_sec", "blocked_events", "steering_tokens",
                    "coding_tokens", "total_tokens",
                ],
            )
        if name == aes.SIX_LAYER_QUERY:
            return (
                [
                    ("role", 1, 1, 1, 3, 0, 3, 0, "m2", "m2-dispatcher", "v5@abc1234", "2026-11-11", "2026-11-24", "14d", "2026-11-24", 2, "covered"),
                    ("handoff", 2, 0, 0, 0, 0, 0, 0, None, None, None, "2026-11-11", "2026-11-24", "14d", "2026-11-24", 2, "covered"),
                    ("invoke", 3, 1, 1, 0, 2, 2, 2, "explorer", "agent-retro", "v9@def5678", "2026-11-11", "2026-11-24", "14d", "2026-11-24", 2, "covered"),
                    ("exec", 4, 0, 0, 0, 0, 0, 0, None, None, None, "2026-11-11", "2026-11-24", "14d", "2026-11-24", 2, "covered"),
                    ("friction", 5, 0, 0, 0, 0, 0, 0, None, None, None, "2026-11-11", "2026-11-24", "14d", "2026-11-24", 2, "covered"),
                    ("horizon", 6, 0, 0, 0, 0, 0, 0, None, None, None, "2026-11-11", "2026-11-24", "14d", "2026-11-24", 2, "covered"),
                ],
                [
                    "layer_key", "sort_order", "finding_rows", "affected_sessions",
                    "pre_fix_count", "post_fix_count", "total_occurrences",
                    "high_severity_post_fix_count", "top_role_key", "top_skill",
                    "top_skill_version", "window_start", "window_end", "window_cst",
                    "source_as_of", "sample_size", "coverage_status",
                ],
            )
        if name == aes.HORIZON_WASTE_QUERY:
            return (
                [
                    ("context_carry", "m1", "agent-retro", 1, 1, 6, 18000, 42.0, 75.0, "2026-11-11", "2026-11-24", "14d", "2026-11-24", 1),
                    ("steering_overkill", "m1", "team-lead", 1, 1, 4, 6000, 20.0, 25.0, "2026-11-11", "2026-11-24", "14d", "2026-11-24", 1),
                ],
                [
                    "category_key", "role_key", "skill", "event_count", "affected_sessions",
                    "wasted_turns", "wasted_tokens", "duration_sec", "token_share_pct",
                    "window_start", "window_end", "window_cst", "source_as_of", "sample_size",
                ],
            )
        raise AssertionError(f"unexpected query: {name}")

    out_path = tmp_path / "agent-efficiency.json"
    payload = aes.write_snapshot(
        out_path,
        until_day="2026-11-24",
        magpie_path=tmp_path / "missing-magpie.jsonl",
        warehouse_db=warehouse,
        query_runner=fake_runner,
    )

    ar = payload["agent_retro"]
    assert ar["coverage_status"] == "healthy"
    assert ar["sample_size"] == 2
    assert ar["source_as_of"] == "2026-11-24"
    assert ar["window_cst"] == "14d"
    assert ar["pre_fix_total"] == 3
    assert ar["post_fix_total"] == 2

    layers = ar["layers"]
    assert [row["label_zh"] for row in layers] == [
        "角色边界",
        "交接完整度",
        "工具与参考调用",
        "执行与返工收敛",
        "人机协作摩擦",
        "长程上下文损耗",
    ]
    for row in layers:
        _assert_plain_language_labels(row["label_zh"])
        _assert_plain_language_labels(row["label_en"])

    hw = ar["horizon_waste"]
    assert hw["wasted_turns_total"] == 10
    assert hw["wasted_tokens_total"] == 24000
    assert len(hw["items"]) == 2
    for item in hw["items"]:
        _assert_plain_language_labels(item["label_zh"])
        _assert_plain_language_labels(item["label_en"])

    wm_by_skill = {w["skill"]: w for w in ar["skill_watermarks"]}
    assert wm_by_skill["m2-dispatcher"] == {
        "skill": "m2-dispatcher",
        "skill_version": "v5@abc1234",
        "pre_fix_count": 3,
        "post_fix_count": 0,
        "status": "improved",
    }
    assert wm_by_skill["agent-retro"] == {
        "skill": "agent-retro",
        "skill_version": "v9@def5678",
        "pre_fix_count": 0,
        "post_fix_count": 2,
        "status": "regressed",
    }


def test_agent_retro_snapshot_reports_missing_and_unknown_honestly(tmp_path):
    # 1. Missing tables -> coverage_status == "missing"
    missing_sec = aes.build_agent_retro_section(table_present=False)
    assert missing_sec["coverage_status"] == "missing"
    assert missing_sec["sample_size"] == 0
    assert len(missing_sec["layers"]) == 6

    # 2. Empty tables (table exists, zero rows) -> coverage_status == "unknown"
    empty_sec = aes.build_agent_retro_section([], [], [], table_present=True)
    assert empty_sec["coverage_status"] == "unknown"
    assert empty_sec["sample_size"] == 0
    assert empty_sec["pre_fix_total"] == 0
    assert empty_sec["post_fix_total"] == 0


def test_skills_roi_snapshot_accepts_agent_retro_and_enriches_skill_retro_watermarks(tmp_path):
    assert "agent-retro" in srs._CANONICAL_SKILL_ALLOWLIST

    fixture = Path(__file__).parent / "fixtures" / "skills_roi_report.json"
    base_report = json.loads(fixture.read_text(encoding="utf-8"))
    report_path = tmp_path / "report.json"
    report_path.write_text(json.dumps(base_report), encoding="utf-8")

    warehouse = tmp_path / "warehouse.db"
    with sqlite3.connect(warehouse) as conn:
        conn.executescript(
            """
            CREATE TABLE fact_agent_retro_finding (
                finding_uid TEXT PRIMARY KEY,
                source TEXT NOT NULL,
                session_id TEXT NOT NULL,
                goal_id TEXT,
                role_key TEXT NOT NULL,
                skill TEXT NOT NULL,
                layer_key TEXT NOT NULL,
                finding_code TEXT NOT NULL,
                severity TEXT NOT NULL,
                skill_version TEXT,
                is_post_fix INTEGER NOT NULL,
                occurrence_count INTEGER NOT NULL,
                ts TEXT NOT NULL,
                cst_day TEXT GENERATED ALWAYS AS (date(ts, '+8 hours')) STORED
            );
            """
        )
        conn.executemany(
            "INSERT INTO fact_agent_retro_finding "
            "(finding_uid, source, session_id, goal_id, role_key, skill, layer_key, finding_code, "
            "severity, skill_version, is_post_fix, occurrence_count, ts) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                ("w1", "copilot_cli", "s1", "g1", "explorer", "agent-retro", "invoke", "I3_l2_exit2_and_output_bloat", "high", "v9@def5678", 0, 4, "2026-11-10T04:00:00Z"),
                ("w2", "copilot_cli", "s2", "g2", "m1", "team-lead", "handoff", "H3_r10_receipt_gap_or_dirty_schema", "high", "v22@1234abc", 1, 1, "2026-11-11T04:00:00Z"),
            ],
        )
        conn.commit()

    out_path = tmp_path / "skills-roi.json"
    snapshot = srs.write_snapshot(
        out_path,
        report_path,
        warehouse_db=warehouse,
        query_runner=lambda name, params: (
            [
                ("2026-11-11", "copilot_cli_skill", "agent-retro", 3, 2),
                ("2026-11-11", "copilot_cli_skill", "team-lead", 2, 1),
            ],
            ["day", "source", "skill", "n", "sessions"],
        ),
        icloud_sync_dir=tmp_path / "icloud",
    )

    assert snapshot["coverage_status"] == "healthy"
    assert [r["skill"] for r in snapshot["skills_daily"]] == ["agent-retro", "team-lead"]
    watermarks = snapshot["skill_retro"]["agent_retro_watermarks"]
    wm_map = {w["skill"]: w for w in watermarks}
    assert wm_map["agent-retro"]["skill_version"] == "v9@def5678"
    assert wm_map["agent-retro"]["pre_fix_count"] == 4
    assert wm_map["agent-retro"]["post_fix_count"] == 0
    assert wm_map["agent-retro"]["status"] == "improved"
    assert wm_map["team-lead"]["post_fix_count"] == 1
    assert wm_map["team-lead"]["status"] == "regressed"
