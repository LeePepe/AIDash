from __future__ import annotations

import sqlite3

import serve


def test_l4_quality_query_normalizes_iso_timestamps_and_includes_current_day(tmp_path, monkeypatch):
    warehouse = tmp_path / "warehouse.db"
    with sqlite3.connect(warehouse) as connection:
        connection.executescript("""
            CREATE TABLE dim_skill_registry (
                skill TEXT PRIMARY KEY, registry_source TEXT, active INTEGER,
                registry_version TEXT, observed_at TEXT
            );
            CREATE TABLE fact_skill_invocation (
                invocation_id TEXT PRIMARY KEY, source TEXT, session_id TEXT, skill TEXT,
                start_ts TEXT, eligible INTEGER
            );
            CREATE TABLE fact_skill_judgement (
                judgement_uid TEXT PRIMARY KEY, invocation_id TEXT, skill TEXT,
                status TEXT, abstained INTEGER, overall_score REAL, pass_flag INTEGER,
                rubric_version TEXT, judge_model TEXT, sampled_at TEXT
            );
        """)
        connection.execute("INSERT INTO dim_skill_registry VALUES ('team-lead', 'fixture', 1, 'v1', NULL)")
        connection.execute(
            "INSERT INTO fact_skill_invocation VALUES (?, ?, ?, ?, ?, ?)",
            ("inv-1", "copilot_cli", "session", "team-lead", "2026-11-24T01:00:00Z", 1),
        )
        connection.execute(
            "INSERT INTO fact_skill_judgement VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            ("judge-1", "inv-1", "team-lead", "valid", 0, 4.5, 1, "rubric", "fake", "2026-11-24T01:02:00Z"),
        )
        connection.commit()
    monkeypatch.setattr(serve, "WAREHOUSE_DB", warehouse)
    rows, columns = serve.run_query(
        "quality/judge-coverage-by-skill",
        {"since": "2026-11-24T00:00:00Z", "until": "2026-11-25T00:00:00Z"},
    )
    row = dict(zip(columns, rows[0]))
    assert row["eligible_invocations"] == 1
    assert row["valid_judgements"] == 1
    assert row["coverage_pct"] == 100.0


def test_l4_behavior_rates_exclude_max_tokens_from_satisfaction(tmp_path, monkeypatch):
    warehouse = tmp_path / "warehouse.db"
    with sqlite3.connect(warehouse) as connection:
        connection.executescript("""
            CREATE TABLE dim_skill_registry (
                skill TEXT PRIMARY KEY, registry_source TEXT, active INTEGER,
                registry_version TEXT, observed_at TEXT
            );
            CREATE TABLE fact_skill_invocation (
                invocation_id TEXT PRIMARY KEY, skill TEXT, start_ts TEXT, eligible INTEGER,
                max_tokens INTEGER, edit_tool_calls INTEGER, assistant_turn_count INTEGER,
                active_duration_sec INTEGER
            );
            CREATE TABLE fact_skill_correction (
                correction_signal_uid TEXT PRIMARY KEY, invocation_id TEXT,
                correction_class TEXT
            );
        """)
        connection.execute("INSERT INTO dim_skill_registry VALUES ('team-lead', 'fixture', 1, 'v1', NULL)")
        connection.execute(
            "INSERT INTO fact_skill_invocation VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            ("inv-1", "team-lead", "2026-11-24T01:00:00Z", 1, 1, 2, 1, 10),
        )
        connection.execute(
            "INSERT INTO fact_skill_correction VALUES (?, ?, ?)",
            ("corr-1", "inv-1", "negative_feedback"),
        )
        connection.commit()
    monkeypatch.setattr(serve, "WAREHOUSE_DB", warehouse)
    rows, columns = serve.run_query(
        "quality/behavior",
        {"since": "2026-11-24T00:00:00Z", "until": "2026-11-25T00:00:00Z"},
    )
    row = dict(zip(columns, rows[0]))
    assert row["eligible_invocations"] == 1
    assert row["max_tokens_invocations"] == 1
    assert row["satisfaction_invocations"] == 0
    assert row["first_pass_satisfaction_rate"] is None


def test_l4_judge_quality_keeps_registry_skills_without_current_verdict(tmp_path, monkeypatch):
    warehouse = tmp_path / "warehouse.db"
    with sqlite3.connect(warehouse) as connection:
        connection.executescript("""
            CREATE TABLE dim_skill_registry (
                skill TEXT PRIMARY KEY, registry_source TEXT, active INTEGER,
                registry_version TEXT, observed_at TEXT
            );
            CREATE TABLE fact_skill_invocation (
                invocation_id TEXT PRIMARY KEY, skill TEXT, start_ts TEXT, eligible INTEGER
            );
            CREATE TABLE fact_skill_judgement (
                judgement_uid TEXT PRIMARY KEY, invocation_id TEXT, skill TEXT,
                status TEXT, abstained INTEGER, overall_score REAL, pass_flag INTEGER,
                rubric_version TEXT, judge_model TEXT, sampled_at TEXT
            );
        """)
        connection.executemany("INSERT INTO dim_skill_registry VALUES (?, 'fixture', 1, 'v1', NULL)", [("team-lead",), ("howto",)])
        connection.execute("INSERT INTO fact_skill_invocation VALUES (?, ?, ?, ?)", ("current", "team-lead", "2026-11-24T01:00:00Z", 1))
        connection.execute("INSERT INTO fact_skill_invocation VALUES (?, ?, ?, ?)", ("old", "howto", "2026-10-01T01:00:00Z", 1))
        connection.execute(
            "INSERT INTO fact_skill_judgement VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            ("old-judge", "old", "howto", "valid", 0, 5.0, 1, "rubric", "fake", "2026-10-01T01:02:00Z"),
        )
        connection.commit()
    monkeypatch.setattr(serve, "WAREHOUSE_DB", warehouse)
    rows, columns = serve.run_query(
        "quality/judge-quality-by-skill",
        {"since": "2026-11-24T00:00:00Z", "until": "2026-11-25T00:00:00Z"},
    )
    by_skill = {row[columns.index("skill")]: dict(zip(columns, row)) for row in rows}
    assert set(by_skill) == {"team-lead", "howto"}
    assert by_skill["howto"]["valid_judgements"] == 0


def test_l4_judge_trend_qualifies_joined_skill_columns(tmp_path, monkeypatch):
    warehouse = tmp_path / "warehouse.db"
    with sqlite3.connect(warehouse) as connection:
        connection.executescript("""
            CREATE TABLE fact_skill_invocation (
                invocation_id TEXT PRIMARY KEY, source TEXT, session_id TEXT, skill TEXT,
                start_ts TEXT, eligible INTEGER
            );
            CREATE TABLE fact_skill_judgement (
                judgement_uid TEXT PRIMARY KEY, invocation_id TEXT, skill TEXT,
                status TEXT, abstained INTEGER, overall_score REAL, pass_flag INTEGER,
                rubric_version TEXT, judge_model TEXT, sampled_at TEXT
            );
        """)
        connection.execute(
            "INSERT INTO fact_skill_invocation VALUES (?, ?, ?, ?, ?, ?)",
            ("inv-1", "copilot_cli", "session", "team-lead", "2026-11-24T01:00:00Z", 1),
        )
        connection.execute(
            "INSERT INTO fact_skill_judgement VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            ("judge-1", "inv-1", "team-lead", "valid", 0, 4.5, 1, "rubric-v1", "judge-model-v1", "2026-11-24T01:02:00Z"),
        )
        connection.commit()
    monkeypatch.setattr(serve, "WAREHOUSE_DB", warehouse)
    rows, columns = serve.run_query(
        "quality/judge-trend",
        {"since": "2026-11-24T00:00:00Z", "until": "2026-11-25T00:00:00Z"},
    )
    assert len(rows) == 1
    row = dict(zip(columns, rows[0]))
    assert row["day"] == "2026-11-24"
    assert row["skill"] == "team-lead"
    assert row["valid_judgements"] == 1
    assert row["score_mean"] == 4.5
    assert row["pass_count"] == 1
    assert row["rubric_version"] == "rubric-v1"
    assert row["judge_model"] == "judge-model-v1"
    assert row["estimated"] == 0

