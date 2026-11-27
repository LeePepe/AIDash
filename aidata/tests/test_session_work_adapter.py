from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone

import config
from adapters import session_work


def test_session_work_not_in_scheduled_or_automatic_sources():
    assert "session_work" not in config.SOURCES
    assert "session_work" not in config.SCHEDULED_SOURCES
    assert "session_work" not in config.MERGE_SOURCES


def test_normalize_records_persists_privacy_safe_session_receipts_and_action_split(tmp_path):
    db_path = tmp_path / "clean" / "session_work.db"
    synthetic_user_path = "/" + "Users" + "/fixture-operator/Development/worktrees/goal-alpha/aidata/cli.py"
    synthetic_token = "sk-" + "secret9876543210abcdef123456"
    records = [
        {
            "source": "copilot_cli",
            "session_id": "a1b2c3d4-9999-8888-7777-666655554444",
            "cwd": "/" + "Users" + "/fixture-operator/Development/worktrees/goal-alpha",
            "repository": "OwnerOrg/SampleRepo",
            "branch": "feat/goal-alpha",
            "role": "m1_steering",
            "model": "magpie/group/gpt-6.1-sol",
            "summary": (
                f"Implement Goal goal-alpha at {synthetic_user_path} for dev@example.com "
                f"with token={synthetic_token} and extra prose beyond eighty characters "
                "that must be cleanly truncated"
            ),
            "started_at": "2026-11-26T01:00:00Z",
            "ended_at": "2026-11-26T01:15:30Z",
            "turn_count": 12,
            "total_tokens": 48200,
            "skills": ["goal-target-task", "aidash-metrics"],
            "search_read_calls": 0,
            "code_edit_calls": 4,
            "verify_script_calls": 2,
            "spin_rework_calls": 1,
            "files_changed_count": 3,
            "commits_count": 2,
            "pr_number": "#345",
            "slow_or_failed_scripts": [
                {
                    "script_path": "/" + "Users" + "/fixture-operator/skills/team-lead/scripts/ci-monitor.py",
                    "skill": "goal-target-task",
                    "exit_code": 1,
                    "duration_ms": 6400,
                }
            ],
        },
        {
            "source": "copilot_cli",
            "session_id": "f0e1d2c3-1111-2222-3333-444455556666",
            "cwd": "/" + "Users" + "/fixture-operator/Development/SampleRepo",
            "repository": "OwnerOrg/SampleRepo",
            "branch": "main",
            "summary": "Quick local exploration without a dedicated goal",
            "started_at": "2026-11-26T02:00:00Z",
            "ended_at": "2026-11-26T02:03:00Z",
            "turn_count": 3,
            "total_tokens": 9100,
            "skills": [],
            "code_edit_calls": 0,
            "verify_script_calls": 0,
            "spin_rework_calls": 0,
            "files_changed_count": 0,
            "commits_count": 0,
        },
    ]

    result = session_work.normalize_records(records, db_path=db_path)
    assert db_path.is_file()
    assert len(result["sessions"]) == 2
    assert result["source_as_of"] == "2026-11-26T02:03:00Z"

    with sqlite3.connect(db_path) as conn:
        cols = [r[1] for r in conn.execute("PRAGMA table_info(session_work)")]
        rows = [
            dict(zip(cols, vals))
            for vals in conn.execute("SELECT * FROM session_work ORDER BY started_at ASC")
        ]

    first, second = rows
    assert first["session_id_short"] == "a1b2c3d4"
    assert len(first["session_id_short"]) == 8
    assert first["goal_id"] == "goal-alpha"
    assert first["repo_name"] == "OwnerOrg/SampleRepo"
    assert first["branch_name"] == "feat/goal-alpha"
    assert first["role_key"] == "m1"
    assert first["model_id"] == "gpt-6.1-sol"
    assert first["duration_sec"] == 930.0
    assert json.loads(first["skills_json"]) == ["aidash-metrics", "team-lead"]
    # Conservative read/search estimation: 12 - 4 - 2 - 1 = 5
    assert first["search_read_calls"] == 5
    assert first["code_edit_calls"] == 4
    assert first["verify_script_calls"] == 2
    assert first["spin_rework_calls"] == 1
    assert first["files_changed_count"] == 3
    assert first["commits_count"] == 2
    assert first["pr_number"] == 345
    assert len(first["summary_label"]) <= 80
    slow = json.loads(first["slow_or_failed_scripts_json"])
    assert slow == [{"script": "ci-monitor.py", "skill": "team-lead", "exit_code": 1, "duration_ms": 6400}]

    # Standalone session retains NULL goal_id in L2 so L4/L5 rolls into unassigned-daily
    assert second["session_id_short"] == "f0e1d2c3"
    assert second["goal_id"] is None
    assert second["search_read_calls"] == 3
    assert second["role_key"] == "writer"

    dumped = json.dumps(rows, ensure_ascii=False)
    for forbidden in ("fixture-operator", "dev@example.com", "sk-secret", "/Users/", "a1b2c3d4-9999"):
        assert forbidden not in dumped


def test_collect_reads_copilot_store_readonly_links_goals_and_enriches_clean_facts(tmp_path, monkeypatch):
    raw_store: list[dict] = []
    monkeypatch.setattr(session_work, "read_raw", lambda _src: list(raw_store))
    monkeypatch.setattr(
        session_work,
        "write_raw",
        lambda _src, rows: raw_store.extend(rows) or len(rows),
    )

    # Absent copilot session-store.db degrades to 0
    assert session_work.collect(copilot_db=tmp_path / "missing-store.db") == 0

    handoff_dir = tmp_path / "handoff"
    (handoff_dir / "goal-beta").mkdir(parents=True)

    copilot_db = tmp_path / "session-store.db"
    with sqlite3.connect(copilot_db) as conn:
        conn.executescript(
            """
            CREATE TABLE sessions (
                id TEXT PRIMARY KEY,
                cwd TEXT,
                repository TEXT,
                branch TEXT,
                summary TEXT,
                created_at TEXT,
                updated_at TEXT
            );
            CREATE TABLE turns (
                id INTEGER PRIMARY KEY,
                session_id TEXT,
                turn_index INTEGER,
                user_message TEXT,
                assistant_response TEXT,
                timestamp TEXT
            );
            CREATE TABLE session_files (
                id INTEGER PRIMARY KEY,
                session_id TEXT,
                file_path TEXT,
                tool_name TEXT,
                turn_index INTEGER,
                first_seen_at TEXT
            );
            CREATE TABLE session_refs (
                id INTEGER PRIMARY KEY,
                session_id TEXT,
                ref_type TEXT,
                ref_value TEXT,
                turn_index INTEGER,
                created_at TEXT
            );
            CREATE TABLE assistant_usage_events (
                id INTEGER PRIMARY KEY,
                session_id TEXT,
                model TEXT,
                copilot_usage_model TEXT,
                input_tokens INTEGER,
                output_tokens INTEGER,
                cache_read_tokens INTEGER,
                cache_write_tokens INTEGER,
                created_at TEXT
            );
            """
        )
        s1 = "1234abcd-0000-1111-2222-333344445555"
        s2 = "9876fedc-0000-1111-2222-333344445555"
        conn.execute(
            "INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                s1,
                "/" + "Users" + "/fixture-dev/Development/worktrees/goal-beta",
                "OwnerOrg/DemoApp",
                "feat/goal-beta",
                "Deliver telemetry pipeline for " + "/" + "Users" + "/fixture-dev/secret.txt",
                "2026-11-25T10:00:00Z",
                "2026-11-25T10:20:00Z",
            ),
        )
        conn.execute(
            "INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                s2,
                "/" + "Users" + "/fixture-dev/Development/DemoApp",
                "OwnerOrg/DemoApp",
                "main",
                "Goal goal-summary-linked verification pass",
                "2026-11-25T11:00:00Z",
                "2026-11-25T11:05:00Z",
            ),
        )
        conn.executemany(
            "INSERT INTO turns (session_id, turn_index, user_message, assistant_response, timestamp) VALUES (?, ?, ?, ?, ?)",
            [
                (s1, 0, '<skill-context name="aidash-metrics">\nSensitive prompt body NEVER_PERSIST_PROMPT', "ok NEVER_PERSIST_REPLY", "2026-11-25T10:01:00Z"),
                (s1, 1, "/skill team-lead follow up", "done", "2026-11-25T10:10:00Z"),
                (s1, 2, "final check", "shipped", "2026-11-25T10:19:00Z"),
                (s2, 0, '<skill-context name="code-review">', "PASS", "2026-11-25T11:04:00Z"),
            ],
        )
        conn.executemany(
            "INSERT INTO session_files (session_id, file_path, tool_name, turn_index, first_seen_at) VALUES (?, ?, ?, ?, ?)",
            [
                (s1, "/repo/aidata/a.py", "create", 0, "2026-11-25T10:05:00Z"),
                (s1, "/repo/aidata/a.py", "edit", 1, "2026-11-25T10:12:00Z"),
                (s1, "/repo/aidata/b.py", "apply_patch", 2, "2026-11-25T10:15:00Z"),
            ],
        )
        conn.executemany(
            "INSERT INTO session_refs (session_id, ref_type, ref_value, turn_index, created_at) VALUES (?, ?, ?, ?, ?)",
            [
                (s1, "commit", "abc1234", 1, "2026-11-25T10:13:00Z"),
                (s1, "commit", "def5678", 2, "2026-11-25T10:18:00Z"),
                (s1, "pr", "350", 2, "2026-11-25T10:19:00Z"),
            ],
        )
        conn.executemany(
            "INSERT INTO assistant_usage_events (session_id, model, copilot_usage_model, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            [
                (s1, "gpt-5.6-luna", None, 2000, 500, 10000, 1000, "2026-11-25T10:05:00Z"),
                (s2, "", "gemini-4-argon", 1500, 300, 4000, 0, "2026-11-25T11:03:00Z"),
            ],
        )
        conn.commit()

    # Optional clean enrichment DB (reference_hit + script_call)
    cp_clean_db = tmp_path / "copilot_cli.db"
    with sqlite3.connect(cp_clean_db) as conn:
        conn.executescript(
            """
            CREATE TABLE reference_hit (
                hit_uid TEXT PRIMARY KEY, session_id TEXT, skill TEXT, reference_path TEXT
            );
            CREATE TABLE script_call (
                call_uid TEXT PRIMARY KEY, session_id TEXT, skill TEXT, script_path TEXT,
                exit_code INTEGER, duration_ms INTEGER
            );
            """
        )
        conn.execute(
            "INSERT INTO reference_hit VALUES ('h1', ?, 'aidash-metrics', 'skills/aidash-metrics/references/aidata-l1-l5-lineage.md')",
            (s1,),
        )
        conn.executemany(
            "INSERT INTO script_call VALUES (?, ?, ?, ?, ?, ?)",
            [
                ("c1", s1, "aidash-metrics", "skills/aidash-metrics/scripts/inspect_aidata_pipeline.py", 0, 420),
                ("c2", s1, "team-lead", "skills/team-lead/scripts/feedback_guard.py", 2, 1200),
            ],
        )
        conn.commit()

    out_db = tmp_path / "clean" / "session_work.db"
    fixed_now = datetime(2026, 11, 26, 8, 0, tzinfo=timezone.utc)  # noqa: UP017
    written_first = session_work.collect(
        copilot_db=copilot_db,
        handoff_root=handoff_dir,
        copilot_clean_db=cp_clean_db,
        db_path=out_db,
        now=fixed_now,
    )
    assert written_first == 2
    assert out_db.is_file()

    # Second run with unchanged store appends 0 new raw records
    written_second = session_work.collect(
        copilot_db=copilot_db,
        handoff_root=handoff_dir,
        copilot_clean_db=cp_clean_db,
        db_path=out_db,
        now=fixed_now,
    )
    assert written_second == 0

    with sqlite3.connect(out_db) as conn:
        cols = [r[1] for r in conn.execute("PRAGMA table_info(session_work)")]
        by_short = {
            vals[cols.index("session_id_short")]: dict(zip(cols, vals))
            for vals in conn.execute("SELECT * FROM session_work")
        }

    r1 = by_short["1234abcd"]
    assert r1["goal_id"] == "goal-beta"
    assert r1["repo_name"] == "OwnerOrg/DemoApp"
    assert r1["turn_count"] == 3
    assert r1["total_tokens"] == 13500
    assert r1["model_id"] == "gpt-5.6-luna"
    assert json.loads(r1["skills_json"]) == ["aidash-metrics", "team-lead"]
    assert r1["search_read_calls"] == 1
    assert r1["code_edit_calls"] == 3
    assert r1["verify_script_calls"] == 2
    assert r1["spin_rework_calls"] == 1
    assert r1["files_changed_count"] == 2  # 2 distinct files (a.py, b.py) across 3 edit calls
    assert r1["commits_count"] == 2
    assert r1["pr_number"] == 350
    slow_scripts = json.loads(r1["slow_or_failed_scripts_json"])
    assert slow_scripts == [{"script": "feedback_guard.py", "skill": "team-lead", "exit_code": 2, "duration_ms": 1200}]

    r2 = by_short["9876fedc"]
    assert r2["goal_id"] == "goal-summary-linked"
    assert r2["role_key"] == "reviewer"
    assert r2["model_id"] == "gemini-4-argon"

    raw_text = json.dumps(raw_store, ensure_ascii=False)
    for secret_marker in ("NEVER_PERSIST_PROMPT", "NEVER_PERSIST_REPLY", "fixture-dev", "/Users/"):
        assert secret_marker not in raw_text


def test_collect_gracefully_degrades_with_minimal_sessions_schema(tmp_path, monkeypatch):
    monkeypatch.setattr(session_work, "read_raw", lambda _src: [])
    monkeypatch.setattr(session_work, "write_raw", lambda _src, rows: len(rows))

    minimal_db = tmp_path / "minimal-session-store.db"
    with sqlite3.connect(minimal_db) as conn:
        conn.execute("CREATE TABLE sessions (id TEXT PRIMARY KEY, created_at TEXT)")
        conn.execute("INSERT INTO sessions VALUES ('abcdef12-3456-7890', '2026-11-26T05:00:00Z')")
        conn.commit()

    out_db = tmp_path / "clean" / "session_work.db"
    count = session_work.collect(
        copilot_db=minimal_db,
        handoff_root=tmp_path / "no-handoff",
        db_path=out_db,
        now=datetime(2026, 11, 26, 8, 0, tzinfo=timezone.utc),  # noqa: UP017
    )
    assert count == 1
    with sqlite3.connect(out_db) as conn:
        row = conn.execute("SELECT session_id_short, goal_id, duration_sec FROM session_work").fetchone()
    assert row == ("abcdef12", None, 0.0)
