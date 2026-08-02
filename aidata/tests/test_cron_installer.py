"""Hermetic tests for the prepared-not-executed cron installer (ADR-12).

Uses a temp jobs.json fixture — NEVER the real ~/.hermes/cron/jobs.json. The
dry-run must not write anything.
"""

import json

import pytest

from scripts import aidata_digest_cron as cron

OLD_JOB_ID = "78d2b35a5693"

# Minimal jobs.json shaped like the real registry (old digest job + one other).
SAMPLE_JOBS = {
    "jobs": [
        {"id": OLD_JOB_ID, "name": "unified-daily-digest",
         "script": "daily_digest_collector.py", "enabled": True,
         "state": "scheduled",
         "schedule": {"kind": "cron", "expr": "0 4 * * *", "display": "0 4 * * *"}},
        {"id": "abc123", "name": "other-job", "enabled": True,
         "state": "scheduled",
         "schedule": {"kind": "cron", "expr": "0 9 * * *", "display": "0 9 * * *"}},
    ]
}


@pytest.fixture
def jobs_file(tmp_path):
    p = tmp_path / "jobs.json"
    p.write_text(json.dumps(SAMPLE_JOBS), encoding="utf-8")
    return p


@pytest.mark.unit
def test_new_job_entry_shape():
    entry = cron.build_new_job()
    assert entry["name"] == "aidata-digest"
    assert entry["schedule"]["expr"] == "0 4 * * *"
    assert entry["script"] == "aidata_digest_run.sh"
    assert entry["no_agent"] is True
    assert entry["enabled"] is True
    assert entry["id"] != OLD_JOB_ID


@pytest.mark.unit
def test_disable_targets_only_old_job(jobs_file):
    data = json.loads(jobs_file.read_text(encoding="utf-8"))
    updated = cron.plan_changes(data)
    by_id = {j["id"]: j for j in updated["jobs"]}
    # old job disabled
    assert by_id[OLD_JOB_ID]["enabled"] is False
    assert by_id[OLD_JOB_ID]["state"] == "paused"
    # other job untouched
    assert by_id["abc123"]["enabled"] is True
    # new job appended
    assert any(j["name"] == "aidata-digest" for j in updated["jobs"])


@pytest.mark.unit
def test_plan_changes_is_immutable(jobs_file):
    data = json.loads(jobs_file.read_text(encoding="utf-8"))
    original = json.dumps(data, sort_keys=True)
    cron.plan_changes(data)
    # input dict not mutated in place
    assert json.dumps(data, sort_keys=True) == original


@pytest.mark.unit
def test_dry_run_does_not_write(jobs_file, capsys):
    before = jobs_file.read_text(encoding="utf-8")
    rc = cron.main(["--dry-run", "--jobs-file", str(jobs_file)])
    assert rc == 0
    after = jobs_file.read_text(encoding="utf-8")
    assert before == after  # nothing written
    out = capsys.readouterr().out
    assert "aidata-digest" in out
    assert OLD_JOB_ID in out  # shows the disable


@pytest.mark.unit
def test_apply_writes_file(jobs_file):
    rc = cron.main(["--apply", "--jobs-file", str(jobs_file)])
    assert rc == 0
    data = json.loads(jobs_file.read_text(encoding="utf-8"))
    by_id = {j["id"]: j for j in data["jobs"]}
    assert by_id[OLD_JOB_ID]["enabled"] is False
    assert any(j["name"] == "aidata-digest" for j in data["jobs"])
