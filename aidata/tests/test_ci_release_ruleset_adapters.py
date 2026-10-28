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


@pytest.mark.unit
@pytest.mark.parametrize(
    ("name", "expected"),
    [
        ("codex-review-target", "ai_review_gate"),
        ("TestFlight", "release_tf"),
        ("nightly cron", "cron_bot"),
        ("CI", "ci_build"),
    ],
)
def test_github_ci_categories(name, expected):
    assert github_ci._category(name, None) == expected


@pytest.mark.unit
def test_github_ci_failure_category_prefers_build_test_and_runner_capacity():
    assert github_ci._failure_category("App target runner", "failure", "swift test") == (
        "build_or_test_failure"
    )
    assert github_ci._failure_category("CI", "timed_out", "Simulator boot timeout") == (
        "runner_capacity_or_sim"
    )
    assert github_ci._failure_category("review", "failure", "require-tests gate") == (
        "true_positive_gate"
    )


@pytest.mark.unit
def test_release_classification_covers_success_and_failure_paths():
    run = {"conclusion": "success", "head_sha": "new"}
    steps = [
        {"name": "Archive", "conclusion": "success"},
        {"name": "Upload to TestFlight", "conclusion": "success"},
        {"name": "Move last-released tag", "conclusion": "success"},
    ]
    assert release_tf._release_classification(steps, run, "old")[0] == "uploaded_verified"
    assert release_tf._release_classification(
        [{"name": "ASC secret preflight", "conclusion": "failure"}],
        {"conclusion": "failure", "head_sha": "new"},
        "old",
    )[0] == "failed_config"
    assert release_tf._release_classification(
        [{"name": "Archive", "conclusion": "failure"}],
        {"conclusion": "failure", "head_sha": "new"},
        "old",
    )[0] == "failed_signing_or_upload"


@pytest.mark.unit
def test_ruleset_helpers_parse_workflow_metadata(tmp_path):
    workflow = tmp_path / "review.yml"
    workflow.write_text("name: Review Gate\ntimeout-minutes: 17\n", encoding="utf-8")
    assert github_ruleset._yaml_value(workflow.read_text(), "name") == "Review Gate"
    assert github_ruleset._yaml_value(
        "on:\n  workflow_call:\n    inputs:\n      timeout-minutes:\n        type: number\n",
        "timeout-minutes",
    ) is None
    assert github_ruleset._workflow_category(workflow, workflow.read_text()) == "ai_review_gate"
    assert github_ruleset._required_checks(
        {"required_status_checks": {"contexts": ["Review Gate"]}}
    ) == (1, {"Review Gate"})


@pytest.mark.unit
def test_ruleset_helpers_parse_branch_rule_parameters():
    rules = [
        {
            "type": "required_status_checks",
            "parameters": {
                "strict_required_status_checks_policy": True,
                "required_status_checks": [
                    {"context": "build + test (macOS 26)"},
                    {"context": "codex-review-target"},
                ],
            },
        }
    ]
    assert github_ruleset._required_checks(rules) == (
        1,
        {"build + test (macOS 26)", "codex-review-target"},
    )


@pytest.mark.unit
def test_retro_queries_encode_grain_and_null_rules():
    root = Path(__file__).parents[1] / "L4_serve" / "queries" / "retro"
    hygiene = (root / "workspace_hygiene_reclaim.sql").read_text(encoding="utf-8")
    release = (root / "tf_release_deliveries.sql").read_text(encoding="utf-8")
    ci = (root / "ci_health_and_noise.sql").read_text(encoding="utf-8")
    assert "MAX(snapshot_date)" in hygiene
    assert "delivery_outcome != 'noop_skipped'" in release
    assert "event_trigger IS r.event_trigger" in ci
