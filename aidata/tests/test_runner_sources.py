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
from typing import Optional

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


def _run_isolated_digest_chain(tmp_path, *, producer_present=True, report=None, producer_exit_code=0):
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
        engine.write_text('import os, sys\nfrom pathlib import Path\nif sys.argv[1] == "skill-roi":\n    print(Path(os.environ["FIXTURE_REPORT"]).read_text())\n    raise SystemExit(int(os.environ["FIXTURE_PRODUCER_EXIT"]))\n')
    vault = root / "vault.py"
    vault.write_text(
        'import json, os, sys\nfrom pathlib import Path\n'
        'args_file = Path(os.environ["AIDASH_JOB_OUTPUT_DIR"]) / "learning-topics-args.json"\n'
        'args_file.write_text(json.dumps(sys.argv[1:]))\n'
    )
    state = root / "job" / "state.json"
    state.parent.mkdir()
    state.write_text(json.dumps({"jobID": "aidata-digest", "schedulerField": "preserve-me"}))
    env = {
        **os.environ, "HOME": str(home), "AIDATA_HOME": str(root),
        "AIDASH_JOB_STATE_FILE": str(state), "AIDASH_JOB_OUTPUT_DIR": str(state.parent),
        "RETRO_ENGINE": str(engine), "DIGEST_VAULT_SCRIPT": str(vault),
        "FIXTURE_REPORT": str(report_file), "FIXTURE_PRODUCER_EXIT": str(producer_exit_code),
        "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
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
    assert state["stages"][2]["sourceAsOf"] == report["source_as_of"]
    assert not list(job_dir.glob(".skills-roi-report.*"))


def _run_job_wrapper(
    script_name: str,
    tmp_path: Path,
    fixture_body: str,
    *,
    exit_code: int = 0,
    state_path: Optional[Path] = None,
):
    script = Path(__file__).resolve().parent.parent / "scripts" / script_name
    fixture = tmp_path / "fixture.py"
    fixture.write_text(fixture_body, encoding="utf-8")
    state = state_path or (tmp_path / "state.json")
    env = {
        **os.environ,
        "HOME": str(tmp_path / "home"),
        "AIDASH_JOB_STATE_FILE": str(state),
        "PATH": "/usr/bin:/bin",
        "FIXTURE_EXIT": str(exit_code),
        "CALLS_FILE": str(tmp_path / "calls.txt"),
    }
    if script_name == "daily_learning_run.sh":
        env["DIGEST_VAULT_SCRIPT"] = str(fixture)
    else:
        env["LINEAR_BOT_BRIDGE_SCRIPT"] = str(fixture)
    proc = subprocess.run(["bash", str(script)], env=env, capture_output=True, text=True, timeout=30)
    payload = json.loads(state.read_text(encoding="utf-8")) if state.is_file() else None
    return proc, payload


def test_daily_learning_wrapper_falls_back_when_linear_option_is_unsupported(tmp_path: Path):
    proc, state = _run_job_wrapper(
        "daily_learning_run.sh",
        tmp_path,
        """import sys
if '--propose-linear' in sys.argv:
    print('error: unrecognized arguments: --propose-linear', file=sys.stderr)
    raise SystemExit(2)
print('fallback proposal complete')
""",
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert state["id"] == state["jobID"] == "daily-learning"
    assert state["lastResult"] == "succeeded"
    assert "AIDash-only; Linear unsupported" in state["overviewMd"]
    assert "fallback proposal complete" in state["overviewMd"]


def test_daily_learning_does_not_fallback_for_unrelated_failure(tmp_path: Path):
    proc, state = _run_job_wrapper(
        "daily_learning_run.sh",
        tmp_path,
        """from pathlib import Path
import os, sys
count = Path(os.environ['CALLS_FILE'])
count.write_text(str(int(count.read_text()) + 1) if count.exists() else '1')
print('unknown option: --other-flag', file=sys.stderr)
raise SystemExit(2)
""",
    )
    assert proc.returncode == 2
    assert state["lastResult"] == "failed"
    assert (tmp_path / "calls.txt").read_text() == "1"


def test_linear_bot_bridge_wrapper_preserves_nonzero_exit_and_state(tmp_path: Path):
    proc, state = _run_job_wrapper(
        "linear_bot_bridge_run.sh",
        tmp_path,
        """import os
print('bridge failed')
raise SystemExit(int(os.environ['FIXTURE_EXIT']))
""",
        exit_code=7,
    )
    assert proc.returncode == 7
    assert state["id"] == state["jobID"] == "linear-bot-bridge"
    assert state["lastResult"] == "failed"
    assert "bridge failed" in state["overviewMd"]


def test_linear_bot_bridge_preserves_pretty_structured_output(tmp_path: Path):
    proc, state = _run_job_wrapper(
        "linear_bot_bridge_run.sh",
        tmp_path,
        """import json
print(json.dumps({'scanned': 2, 'triggered': 1}, indent=2))
""",
    )
    assert proc.returncode == 0
    assert '"scanned": 2' in state["overviewMd"]
    assert '"triggered": 1' in state["overviewMd"]


def test_wrapper_reports_state_write_failure_and_cleans_temp(tmp_path: Path):
    state_target = tmp_path / "state-target"
    state_target.mkdir()
    proc, _ = _run_job_wrapper(
        "linear_bot_bridge_run.sh",
        tmp_path,
        "print('upstream succeeded')\n",
        state_path=state_target,
    )
    assert proc.returncode != 0
    assert not list(tmp_path.glob(".state-target.*.tmp"))


def test_digest_runner_proposes_three_learning_topics_to_linear_and_aidash(tmp_path):
    proc, _, state, job_dir = _run_isolated_digest_chain(tmp_path)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert json.loads((job_dir / "learning-topics-args.json").read_text()) == [
        "discover-topics", "--top", "3", "--propose-aidash", "--propose-linear", "--no-materialize",
    ]
    learning_stage = state["stages"][3]
    assert learning_stage["id"] == "learning_topics"
    assert learning_stage["status"] == "ok"
    assert learning_stage["detail"] == "每日 3 题候选 → Linear & AIDash"


def test_digest_runner_failed_producer_preserves_report_but_never_claims_healthy(tmp_path):
    proc, snapshot, state, _ = _run_isolated_digest_chain(tmp_path, producer_exit_code=1)
    assert proc.returncode != 0
    assert snapshot["coverage_status"] == "error"
    assert snapshot["diagnostics"]["S2_gate_catch"]["sample_size"] == 4
    assert "retro producer exited 1" in snapshot["errors"]
    assert state["stages"][2]["status"] == "warning"


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

