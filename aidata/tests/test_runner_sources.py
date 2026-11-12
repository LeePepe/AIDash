"""Guard against the runner drifting out of sync with config.SOURCES (T0).

The 04:00 cron chain (scripts/aidata_digest_run.sh) keeps an *explicit*
`SOURCES="..."` collect list — explicit on purpose, so the collect order and
per-source budget stay controllable. The failure mode that motivated this test:
7 new L1 sources were added to config.SOURCES but the hardcoded runner list was
never updated, so cron silently never collected them.

This test parses the SOURCES= line out of the shell script and asserts its set
equals config.SOURCES, so any newly-added source that is not also wired into the
runner fails CI instead of silently missing the daily collect.
"""

import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

import config

RUNNER = Path(__file__).resolve().parent.parent / "scripts" / "aidata_digest_run.sh"


def _runner_sources() -> set[str]:
    """Extract the source names from the runner's SOURCES="..." assignment."""
    text = RUNNER.read_text()
    match = re.search(r'^SOURCES="([^"]*)"', text, re.MULTILINE)
    assert match is not None, f"no SOURCES=... line found in {RUNNER}"
    return set(match.group(1).split())


def test_runner_sources_match_config() -> None:
    assert _runner_sources() == set(config.SOURCES)


def _run_isolated_digest_chain(tmp_path, *, producer_present=True, report=None):
    home, root, bin_dir = tmp_path / "home", tmp_path / "aidata", tmp_path / "bin"
    home.mkdir()
    root.mkdir()
    bin_dir.mkdir()
    # Every external source, consumer and producer is fixture-owned. Only the
    # actual snapshot module and shell orchestration under test run unchanged.
    python = bin_dir / "python3"
    python.write_text(
        '#!/bin/bash\nif [[ "$1" == "-m" && "$2" == "L5_apps.digest.event_bridge" ]]; then exit 0; fi\n'
        + f'exec {shlex.quote(sys.executable)} "$@"\n'
    )
    python.chmod(0o755)
    (root / "cli.py").write_text("# Hermetic collect/normalize/merge/digest fixture\n")
    (root / "serve.py").write_text(
        'def run_query(name, params=None):\n'
        '    assert name == "skills/daily"\n'
        '    return ([("2026-11-11", "claude_attribution", "team-lead", 2, 1), '
        '("2026-11-11", "claude_skill_tool", "team-lead", 2, 1)], '
        '["day", "source", "skill", "n", "sessions"])\n'
    )
    fixture = Path(__file__).parent / "fixtures" / "skills_roi_report.json"
    report_file = root / "producer-report.json"
    report_file.write_text(json.dumps(report) if report is not None else fixture.read_text())
    engine = root / "retro.py"
    if producer_present:
        engine.write_text('import os, sys\nfrom pathlib import Path\nif sys.argv[1] == "skill-roi":\n    print(Path(os.environ["FIXTURE_REPORT"]).read_text())\n')
    vault = root / "vault.py"
    vault.write_text("# Discovery fixture; no materialization or publication\n")
    state = root / "job" / "state.json"
    state.parent.mkdir()
    state.write_text(json.dumps({"jobID": "aidata-digest", "schedulerField": "preserve-me"}))
    env = {
        **os.environ, "HOME": str(home), "AIDATA_HOME": str(root),
        "AIDASH_JOB_STATE_FILE": str(state), "AIDASH_JOB_OUTPUT_DIR": str(state.parent),
        "RETRO_ENGINE": str(engine), "DIGEST_VAULT_SCRIPT": str(vault),
        "FIXTURE_REPORT": str(report_file), "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
        "PYTHONPATH": str(RUNNER.parent.parent),
    }
    proc = subprocess.run(["bash", str(RUNNER)], env=env, capture_output=True, text=True, timeout=30, check=False)
    return proc, json.loads((state.parent / "skills-roi.json").read_text()), json.loads(state.read_text()), state.parent


def test_digest_runner_exports_real_full_report_and_disjoint_daily_grains(tmp_path):
    proc, snapshot, state, job_dir = _run_isolated_digest_chain(tmp_path)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    report = json.loads((Path(__file__).parent / "fixtures" / "skills_roi_report.json").read_text())
    assert snapshot["diagnostics"] == report
    assert snapshot["source_as_of"] == report["source_as_of"]
    assert snapshot["sample_size"] == 4
    assert snapshot["coverage_status"] == "healthy"
    assert snapshot["diagnostics"]["S10_skill_roi_ranking"][0]["roi_score"] is None
    assert len(snapshot["skills_daily"]) == 2
    assert {row["source"] for row in snapshot["skills_daily"]} == {"claude_attribution", "claude_skill_tool"}
    assert state["schedulerField"] == "preserve-me"
    assert state["stages"][2]["status"] == "ok"
    assert not list(job_dir.glob(".skills-roi-report.*"))


def test_digest_runner_missing_or_partial_producer_is_not_healthy(tmp_path):
    missing = tmp_path / "missing"
    partial = tmp_path / "partial"
    missing.mkdir()
    partial.mkdir()
    for directory, kwargs, expected in ((missing, {"producer_present": False}, "missing"),
                                        (partial, {"report": {"ok": True}}, "error")):
        proc, snapshot, state, _ = _run_isolated_digest_chain(directory, **kwargs)
        assert proc.returncode != 0
        assert snapshot["coverage_status"] == expected
        assert snapshot["errors"]
        assert snapshot["source_as_of"] is None
        assert snapshot["skills_daily"] == []
        assert state["stages"][2]["status"] == "warning"
        assert state["lastExitCode"] != 0


def test_export_work_teams_digest_script_redacts_and_writes_jsonl(tmp_path: Path) -> None:
    import json
    import subprocess
    import sys

    exporter = Path(__file__).resolve().parent.parent / "scripts" / "export_work_teams_digest.py"
    input_file = tmp_path / "raw-teams.json"
    out_dir = tmp_path / "drop"
    input_file.write_text(
        json.dumps(
            [
                {
                    "item_id": "msg-501",
                    "created_at": "2026-11-11T06:00:00Z",
                    "channel_kind": "teams_mention",
                    "sender": "lead.user@corp.example.com",
                    "title": "@tianpei Check deployment",
                    "summary": "Use sk-1234567890abcdefghijklmnop and ghp_1234567890abcdefghijkl and token=abcdefghijkl1234567890",
                }
            ]
        ),
        encoding="utf-8",
    )
    proc = subprocess.run(
        [
            sys.executable,
            str(exporter),
            "--input",
            str(input_file),
            "--out-dir",
            str(out_dir),
            "--shard-name",
            "test-shard.jsonl",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    payload = json.loads(proc.stdout)
    assert payload["ok"] is True
    assert payload["exported"] == 1
    shard_text = (out_dir / "test-shard.jsonl").read_text(encoding="utf-8")
    record = json.loads(shard_text.strip())
    assert record["item_id"] == "msg-501"
    assert record["dedup_key"] == "teams:msg-501"
    assert "<REDACTED>@corp.example.com" in record["sender_alias"]
    assert "sk-1234567890" not in record["summary"]
    assert "ghp_1234567890" not in record["summary"]
    assert "abcdefghijkl1234567890" not in record["summary"]

