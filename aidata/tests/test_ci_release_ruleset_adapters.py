from pathlib import Path

import pytest
from adapters import github_ci, github_ruleset, release_tf


@pytest.mark.unit
def test_github_ci_normalize_separates_run_and_job(monkeypatch):
    raw = [
        {
            "record_type": "workflow_run",
            "run_id": 7,
            "repo_key": "LeePepe/AIDash",
            "workflow_name": "CI",
            "workflow_category": "ci_build",
            "head_sha": "abc",
            "status": "completed",
            "conclusion": "failure",
            "created_at": "2026-10-28T00:00:00Z",
        },
        {
            "record_type": "job_run",
            "job_id": 8,
            "run_id": 7,
            "repo_key": "LeePepe/AIDash",
            "job_name": "tests",
            "status": "completed",
            "conclusion": "failure",
            "failure_category": "build_or_test_failure",
        },
    ]
    monkeypatch.setattr(github_ci, "read_raw", lambda _source: raw)
    captured = {}

    def capture(source, table, ddl, rows, columns):
        captured[table] = (rows, columns)
        return len(rows)

    monkeypatch.setattr(github_ci, "write_clean", capture)
    assert github_ci.normalize() == 2
    assert captured["workflow_run"][0][0]["run_id"] == 7
    assert captured["job_run"][0][0]["job_id"] == 8


@pytest.mark.unit
def test_ruleset_normalize_keeps_repo_and_gate_grains(monkeypatch):
    raw = [
        {"repo_key": "LeePepe/AIDash", "repo_name": "AIDash"},
        {"workflow_gate_key": "LeePepe/AIDash:ci.yml", "repo_key": "LeePepe/AIDash",
         "workflow_file": "ci.yml"},
    ]
    monkeypatch.setattr(github_ruleset, "read_raw", lambda _source: raw)
    captured = {}
    def capture(source, table, ddl, rows, columns):
        captured[table] = rows
        return len(rows)

    monkeypatch.setattr(github_ruleset, "write_clean", capture)
    assert github_ruleset.normalize() == 2
    assert len(captured["repo"]) == 1
    assert len(captured["workflow_gate"]) == 1


@pytest.mark.unit
def test_release_normalize_deduplicates_delivery_uid(monkeypatch):
    raw = [
        {"delivery_uid": "repo:1", "repo_key": "LeePepe/VitalStride",
         "workflow_name": "TestFlight", "head_sha": "a",
         "delivery_outcome": "noop_skipped", "started_at": "2026-01-01"},
        {"delivery_uid": "repo:1", "repo_key": "LeePepe/VitalStride",
         "workflow_name": "TestFlight", "head_sha": "b",
         "delivery_outcome": "uploaded_unverified_asc", "started_at": "2026-01-01"},
    ]
    monkeypatch.setattr(release_tf, "read_raw", lambda _source: raw)
    captured = {}
    def capture(source, table, ddl, rows, columns):
        captured[table] = rows
        return len(rows)

    monkeypatch.setattr(release_tf, "write_clean", capture)
    assert release_tf.normalize() == 1
    assert captured["delivery"][0]["head_sha"] == "b"


@pytest.mark.unit
def test_new_tables_are_present_in_warehouse_schema():
    schema = Path(__file__).parents[1] / "schema" / "warehouse.sql"
    text = schema.read_text(encoding="utf-8")
    for table in (
        "dim_workflow_gate",
        "fact_ci_workflow_run",
        "fact_ci_job_run",
        "fact_release_delivery",
    ):
        assert f"CREATE TABLE IF NOT EXISTS {table}" in text
