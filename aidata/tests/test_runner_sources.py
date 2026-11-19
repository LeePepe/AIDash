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
from datetime import timezone
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
    state_path: Optional[Path] = None,  # noqa: UP045 - Python 3.9 gate
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
    proc = subprocess.run(["bash", str(script)], check=False, env=env, capture_output=True, text=True, timeout=30)
    payload = json.loads(state.read_text(encoding="utf-8")) if state.is_file() else None
    return proc, payload


def _run_teams_digest_wrapper(
    tmp_path: Path,
    *,
    deliver_output: str,
    deliver_exit: int = 0,
    read_output: str = "",
    read_exit: int = 0,
):
    script = Path(__file__).resolve().parent.parent / "scripts" / "teams_digest_run.sh"
    fake_node = tmp_path / "node"
    cli_script = tmp_path / "cli.js"
    deliver_file = tmp_path / "deliver.txt"
    read_file = tmp_path / "read.txt"
    calls_file = tmp_path / "calls.txt"
    deliver_file.write_text(deliver_output, encoding="utf-8")
    read_file.write_text(read_output, encoding="utf-8")
    cli_script.write_text("// fixture\n", encoding="utf-8")
    fake_node.write_text(
        "#!/bin/bash\n"
        "printf '%s\\n' \"$@\" >> \"$CALLS_FILE\"\n"
        "if [[ \" $* \" == *\" --deliver-self-meeting \"* ]]; then\n"
        "  cat \"$DELIVER_FILE\"\n"
        f"  exit {deliver_exit}\n"
        "fi\n"
        "cat \"$READ_FILE\"\n"
        f"exit {read_exit}\n",
        encoding="utf-8",
    )
    fake_node.chmod(0o755)
    state = tmp_path / "jobs" / "teams-digest" / "state.json"
    env = {
        **os.environ,
        "HOME": str(tmp_path / "home"),
        "AIDASH_JOB_STATE_FILE": str(state),
        "AIDASH_JOB_OUTPUT_DIR": str(state.parent),
        "TEAMS_DIGEST_CLI_SCRIPT": str(cli_script),
        "NODE_BIN": str(fake_node),
        "DELIVER_FILE": str(deliver_file),
        "READ_FILE": str(read_file),
        "CALLS_FILE": str(calls_file),
        "PATH": "/usr/bin:/bin",
    }
    proc = subprocess.run(["bash", str(script)], check=False, env=env, capture_output=True, text=True, timeout=30)
    payload = json.loads(state.read_text(encoding="utf-8")) if state.is_file() else None
    calls = calls_file.read_text(encoding="utf-8").splitlines() if calls_file.is_file() else []
    return proc, payload, calls


def test_teams_digest_wrapper_runs_deliver_self_meeting_and_parses_4_stages(tmp_path: Path):
    output = """[Stage 1/4] Auth Check: passed\n[Stage 2/4] Unread Sync: 3 unread\n[Stage 3/4] Jev & Draft: draft ready\n[Stage 4/4] Self-Meeting Delivery: delivered\n"""
    proc, state, calls = _run_teams_digest_wrapper(tmp_path, deliver_output=output)
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert calls[-1] == "--deliver-self-meeting"
    assert [stage["id"] for stage in state["stages"]] == [
        "auth_check", "unread_sync", "jev_draft", "self_meeting_delivery"
    ]
    assert all(stage["status"] == "passed" for stage in state["stages"])
    assert all(f"- [Stage {index}/4]" in state["overviewMd"] for index in range(1, 5))


def test_teams_digest_wrapper_falls_back_to_read_only_when_deliver_flag_unsupported(tmp_path: Path):
    unsupported = "only `run --read-only` is supported\n"
    readonly = "[Stage 1/4] Auth Check: passed\n[Stage 2/4] Unread Sync: passed\n"
    proc, state, calls = _run_teams_digest_wrapper(
        tmp_path, deliver_output=unsupported, deliver_exit=2, read_output=readonly
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert calls[-1] == "--read-only"
    assert "- Compatibility fallback: --read-only" in state["overviewMd"]
    assert state["lastResult"] == "succeeded"


def test_teams_digest_wrapper_preserves_nonzero_exit_and_failed_state(tmp_path: Path):
    output = "[Stage 1/4] Auth Check: failed\n"
    proc, state, calls = _run_teams_digest_wrapper(tmp_path, deliver_output=output, deliver_exit=7)
    assert proc.returncode == 7
    assert calls[-1] == "--deliver-self-meeting"
    assert state["lastResult"] == "failed"
    assert state["stages"][0]["status"] == "failed"


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





def _load_self_heal_module():
    import importlib.util

    path = Path(__file__).resolve().parents[1] / "scripts" / "aidata_telemetry_self_heal.py"
    spec = importlib.util.spec_from_file_location("aidata_telemetry_self_heal", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _telemetry_fixture(tmp_path: Path):
    mod = _load_self_heal_module()
    root = tmp_path / "aidata"
    shared = tmp_path / "shared"
    vault = tmp_path / "vault"
    raw = root / "L1_collect" / "raw" / "raven"
    raw.mkdir(parents=True)
    (root / "state.json").write_text(json.dumps({"raven": 1795020000000}))
    (raw / "2026-11-19.jsonl").write_text(
        json.dumps({"id": "request-1", "timestamp": 1795020000000, "model": "model-a", "input_tokens": 10, "output_tokens": 5}) + "\n"
    )
    (vault).mkdir()
    (vault / "topic-ledger.json").write_text(json.dumps({"topics": [{"topic_key": "topic-a", "learning_state": "learned", "revision": 4}]}))
    state_dir = root / "L5_apps" / "digest" / "state"
    state_dir.mkdir(parents=True)
    (state_dir / "learning-topics-state.json").write_text(json.dumps({"topics": {"topic-a": {"topic_key": "topic-a", "learning_state": "proposed", "revision": 1}}}))
    (state_dir / "proposals.jsonl").write_text(json.dumps({"id": "learning-topic-topic-a", "topic_key": "topic-a", "status": "pending", "learning_state": "proposed", "revision": 1}) + "\n")
    (root.parent / "Apps" / "AIDashApp" / "Sources" / "Telemetry").mkdir(parents=True)
    telemetry_dir = root.parent / "Apps" / "AIDashApp" / "Sources" / "Telemetry"
    (telemetry_dir / "AIDashTelemetryCoordinator.swift").write_text("enum AIDashTelemetryAction { case briefing_viewed } establishedEnabled")
    (telemetry_dir / "AIDashTelemetryPreferences.swift").write_text("consent establishedEnabled")
    (telemetry_dir / "AIDashTelemetryFactory.swift").write_text("AzureBlobPrivacyPolicy")
    (root / "adapters").mkdir()
    (root / "adapters" / "product_blob.py").write_text("AZURE_CORE_COLLECT_TELEMETRY = 'false'\ndef _preflight(): pass\n# privacy allowlist\n")
    for rel in ("sdks/swift", "sdks/web", "sdks/python", "docs/architecture"):
        (shared / rel).mkdir(parents=True)
    (shared / "sdks/swift" / "Telemetry.swift").write_text("telemetry consent privacy")
    (shared / "sdks/web" / "telemetry.ts").write_text("export const telemetry = true")
    (shared / "sdks/python" / "telemetry.py").write_text("def emit_event(): pass")
    (shared / "docs/architecture/tech-context.md").write_text("telemetry contract privacy")
    return mod, root, shared, vault


def _healer_that_builds_tables(root: Path):
    def healer(aidata_home, sources, *, need_merge):
        clean = aidata_home / "L2_normalize" / "clean"
        clean.mkdir(parents=True, exist_ok=True)
        db = clean / "raven.db"
        with __import__("sqlite3").connect(db) as conn:
            conn.execute("CREATE TABLE req (request_id TEXT PRIMARY KEY, ts INTEGER, cost_usd REAL)")
            conn.execute("INSERT INTO req VALUES ('request-1', 1795020000000, 0.1)")
        warehouse = aidata_home / "L3_merge" / "warehouse.db"
        warehouse.parent.mkdir(parents=True, exist_ok=True)
        with __import__("sqlite3").connect(warehouse) as conn:
            conn.execute("CREATE TABLE fact_request (request_id TEXT, ts INTEGER, cst_day TEXT, cost_usd REAL)")
            conn.execute("INSERT INTO fact_request VALUES ('request-1', 1795020000000, '2026-11-19', 0.1)")
        return [{"action": "normalize_source", "source": "raven", "ok": True}, {"action": "merge_warehouse", "ok": True}]
    return healer


def test_loop6a_heals_with_injected_real_commands_and_is_idempotent(tmp_path: Path) -> None:
    from datetime import datetime

    mod, root, shared, vault = _telemetry_fixture(tmp_path)
    first = mod.inspect_and_self_heal(
        aidata_home=root,
        shared_telemetry_dir=shared,
        vault_dir=vault,
        core_sources=("raven",),
        now=datetime(2026, 11, 19, 12, tzinfo=timezone.utc),  # noqa: UP017 - Python 3.9 gate
        dry_run=True,
    )
    assert first["has_delta"]
    assert not (root / "L2_normalize").exists()
    healed = mod.inspect_and_self_heal(
        aidata_home=root,
        shared_telemetry_dir=shared,
        vault_dir=vault,
        core_sources=("raven",),
        normalize_merge_healer=_healer_that_builds_tables(root),
        now=datetime(2026, 11, 19, 12, tzinfo=timezone.utc),  # noqa: UP017 - Python 3.9 gate
    )
    assert healed["status"] == "HEALED_LOCALLY_NO_ALERT"
    assert healed["residual_unhealable_items"] == []
    state = json.loads((root / "L5_apps/digest/state/learning-topics-state.json").read_text())
    assert state["topics"]["topic-a"]["learning_state"] == "learned"
    proposal = json.loads((root / "L5_apps/digest/state/proposals.jsonl").read_text().splitlines()[-1])
    assert proposal["status"] == "dismissed"
    assert proposal["outcome"] == "reconciled_from_ledger"
    assert proposal["exploration_authorized"] is False
    again = mod.inspect_and_self_heal(aidata_home=root, shared_telemetry_dir=shared, vault_dir=vault, core_sources=("raven",), now=datetime(2026, 11, 19, 12, tzinfo=timezone.utc))  # noqa: UP017 - Python 3.9 gate
    assert again["status"] == "SKIPPED_NO_DELTA"
    assert (vault / "topic-ledger.json").read_text().count("topic-a") == 1


def test_loop6a_failed_normalize_is_residual_and_never_fabricates_rows(tmp_path: Path) -> None:
    mod, root, shared, vault = _telemetry_fixture(tmp_path)
    result = mod.inspect_and_self_heal(
        aidata_home=root,
        shared_telemetry_dir=shared,
        vault_dir=vault,
        core_sources=("raven",),
        normalize_merge_healer=lambda *_args, **_kwargs: [{"action": "normalize_source", "source": "raven", "ok": False}],
    )
    assert result["has_delta"]
    assert any(item["kind"] == "self_heal_failed" for item in result["residual_anomalies"])
    assert not (root / "L2_normalize").exists()


def test_loop6a_streams_all_shards_and_respects_source_grain(tmp_path: Path) -> None:
    mod = _load_self_heal_module()
    raw = tmp_path / "raw"
    raw.mkdir()
    lines = [{"id": f"request-{i}", "timestamp": 1795020000000} for i in range(5001)]
    lines.append({"id": "request-0", "timestamp": 1795020000000})
    (raw / "2026-11-19.jsonl").write_text("\n".join(json.dumps(item) for item in lines) + "\n")
    report = mod._scan_raw_shards(raw, pk_fields=("id",))
    assert report["relevant_record_count"] == 5002
    assert report["duplicate_pk_count"] == 0
    later = raw / "2026-11-20.jsonl"
    later.write_text(json.dumps({"id": "request-5001", "timestamp": 1795020000000}) + "\n")
    report = mod._scan_raw_shards(raw, pk_fields=("id",))
    assert report["duplicate_pk_count"] == 0
    copilot = tmp_path / "copilot_cli"
    copilot.mkdir()
    (copilot / "2026-11-20.jsonl").write_text(json.dumps({"event_id": "tool-only"}) + "\n")
    assert mod._scan_raw_shards(copilot, pk_fields=("event_id",))["relevant_record_count"] == 0


def test_loop6a_jev_boundaries_and_missing_match_do_not_suppress(tmp_path: Path) -> None:
    mod, root, shared, vault = _telemetry_fixture(tmp_path)
    collected = mod.inspect_and_self_heal(aidata_home=root, shared_telemetry_dir=shared, vault_dir=vault, core_sources=("raven",), dry_run=True)
    def decision(prob, route, match):
        return {"answers": {"actionable_probability": {"noul": prob}, "delivery_route": {"choice": route}, "delivery_route_match": {"noul": match}}}
    assert mod.evaluate_jev_decision(collected, jev_fn=lambda **_: decision(0.70, "ignore", 0.50))["actionable"] is False
    assert mod.evaluate_jev_decision(collected, jev_fn=lambda **_: decision(0.70, "ignore", None))["actionable"] is True
    assert mod.evaluate_jev_decision(collected, jev_fn=lambda **_: decision(0.71, "autopilot_trigger", 0.90))["route"] == "autopilot_trigger"
    assert mod.evaluate_jev_decision(collected, jev_fn=lambda **_: None)["actionable"] is True


def test_loop6a_fixture_mode_is_closed_and_dual_zone_is_bounded(tmp_path: Path) -> None:
    mod = _load_self_heal_module()
    fixture = {"aidata_home": str(tmp_path / "aidata"), "shared_telemetry_dir": str(tmp_path / "shared"), "vault_dir": str(tmp_path / "vault")}
    result = mod.inspect_and_self_heal(fixture_json=fixture, dry_run=True, core_sources=("raven",))
    assert result["raw"]["fixture_mode"] is True
    assert result["dual_zone_verification"]["ok"]
    assert result["dual_zone_verification"]["human_zone_lines"] <= 15
    assert ("/" + "Users/") not in result["dual_zone_markdown"]
    assert "127.0.0.1" not in result["dual_zone_markdown"]


def test_loop6a_autopilot_reconciles_schedule_with_trigger_update() -> None:
    mod = _load_self_heal_module()
    calls = []
    trigger_reads = 0
    def runner(args, **kwargs):
        nonlocal trigger_reads
        calls.append(list(args))
        if args[:2] == ["autopilot", "list"]:
            return subprocess.CompletedProcess(args, 0, json.dumps({"autopilots": [{"id": "ap-1", "title": mod.AUTOPILOT_TITLE}]}), "")
        if args[:2] == ["autopilot", "trigger-list"]:
            trigger_reads += 1
            trigger = {"id": "tr-1", "kind": "schedule", "cron": mod.AUTOPILOT_CRON if trigger_reads > 1 else "0 0 * * *", "timezone": mod.AUTOPILOT_TIMEZONE if trigger_reads > 1 else "UTC", "enabled": trigger_reads > 1}
            return subprocess.CompletedProcess(args, 0, json.dumps({"triggers": [trigger]}), "")
        return subprocess.CompletedProcess(args, 0, "{}", "")
    result = mod.sync_autopilot(server_url="https://example.invalid", workspace_id="workspace", agent_id="agent", subscriber_id="owner", runner=runner)
    assert result["ok"]
    assert any(call[:3] == ["autopilot", "trigger-update", "ap-1"] and "--enabled=true" in call for call in calls)


def test_loop6a_actual_dict_watermarks_and_raw_grains(tmp_path: Path) -> None:
    mod = _load_self_heal_module()
    root = tmp_path / "aidata"
    state = {
        "raven": 1795020000000,
        "copilot_cli": {"schema_version": 2, "seen": {"event-1": "2026-11-19"}},
        "claude_jsonl": {"~/transcript.jsonl": 12},
        "gtt_ledger": {"machine:goal/ledger.md": "digest"},
        "gtt_receipt": {"machine:goal/receipts/task-r1.md": "digest"},
    }
    (root / "L1_collect/raw/raven").mkdir(parents=True)
    (root / "L1_collect/raw/copilot_cli").mkdir(parents=True)
    (root / "L1_collect/raw/claude_jsonl").mkdir(parents=True)
    (root / "L1_collect/raw/gtt_ledger").mkdir(parents=True)
    (root / "L1_collect/raw/gtt_receipt").mkdir(parents=True)
    (root / "state.json").write_text(json.dumps(state))
    (root / "L1_collect/raw/raven/2026-11-19.jsonl").write_text(json.dumps({"id": "r1", "timestamp": 1795020000000}) + "\n")
    (root / "L1_collect/raw/copilot_cli/2026-11-19.jsonl").write_text(
        json.dumps({"event_id": "event-1", "skill": "team-lead", "timestamp": "2026-11-19T00:00:00Z"}) + "\n"
        + json.dumps({"event_id": "ref-1", "skill": "team-lead", "kind": "reference_hit", "timestamp": "2026-11-19T00:00:00Z"}) + "\n"
    )
    (root / "L1_collect/raw/claude_jsonl/2026-11-19.jsonl").write_text(
        json.dumps({"uuid": "turn-1", "timestamp": "2026-11-19T00:00:00Z"}) + "\n"
        + json.dumps({"uuid": "turn-1", "turn_uuid": "turn-1", "_kind": "reference_hit", "timestamp": "2026-11-19T00:00:00Z"}) + "\n"
    )
    (root / "L1_collect/raw/gtt_ledger/2026-11-19.jsonl").write_text(json.dumps({"machine_id": "machine", "rel_path": "goal/ledger.md", "record_type": "ledger", "content": "- 2026-11-19T00:00:00Z | EVT=READY | ok"}) + "\n")
    (root / "L1_collect/raw/gtt_receipt/2026-11-19.jsonl").write_text(json.dumps({"machine_id": "machine", "rel_path": "goal/receipts/task-r1.md", "record_type": "receipt", "content": "done"}) + "\n")
    audit = mod.watermark_and_shard_audit(root, core_sources=mod.CORE_SOURCES)
    assert not any(item["kind"] == "watermark_regression_or_missing" for item in audit["anomalies"])
    assert audit["sources"]["gtt_ledger"]["relevant_record_count"] == 1
    assert audit["sources"]["gtt_receipt"]["relevant_record_count"] == 1
    assert audit["sources"]["claude_jsonl"]["relevant_record_count"] == 1
    assert audit["sources"]["copilot_cli"]["relevant_record_count"] == 1


def test_loop6a_dismissed_missing_state_and_corrupt_history_preserve_source(tmp_path: Path) -> None:
    mod = _load_self_heal_module()
    root = tmp_path / "aidata"
    vault = tmp_path / "vault"
    vault.mkdir()
    ledger_bytes = json.dumps({"topics": {"topic-dismissed": {"learning_state": "dismissed", "revision": 2, "aliases": ["legacy-topic"]}}}, ensure_ascii=False).encode()
    (vault / "topic-ledger.json").write_bytes(ledger_bytes)
    proposals = root / "L5_apps/digest/state/proposals.jsonl"
    proposals.parent.mkdir(parents=True)
    proposals.write_text("{malformed historical line}\n" + json.dumps({"id": "p1", "ref": "learning-topic://legacy-topic", "learning_state": "proposed", "status": "pending", "revision": 2}) + "\n")
    audit = mod.cross_file_state_audit(root, vault_dir=vault)
    assert audit["drifted_topics"]
    result = mod._default_reconcile_learning_drift(root, vault_dir=vault, drifted_topics=audit["drifted_topics"])
    assert any(item["ok"] for item in result)
    assert (vault / "topic-ledger.json").read_bytes() == ledger_bytes
    state = json.loads((root / "L5_apps/digest/state/learning-topics-state.json").read_text())
    assert state["topics"]["topic-dismissed"]["learning_state"] == "dismissed"
    proposal = json.loads(proposals.read_text().splitlines()[-1])
    assert proposal["status"] == "dismissed"
    assert proposal["learning_state"] == "dismissed"
    assert proposal["exploration_authorized"] is False
    assert "{malformed historical line}" in proposals.read_text()
    second = mod.cross_file_state_audit(root, vault_dir=vault)
    assert not any(item["kind"] == "learning_topic_state_drift" for item in second["anomalies"])


def test_loop6a_normalize_rc0_stderr_error_blocks_merge(tmp_path: Path) -> None:
    mod = _load_self_heal_module()
    root = tmp_path / "aidata"
    root.mkdir()
    (root / "cli.py").write_text(
        "import pathlib, sys\n"
        "pathlib.Path('calls.log').open('a').write(' '.join(sys.argv[1:]) + '\\n')\n"
        "if sys.argv[1] == 'normalize': print('  [normalize] raven ERROR: adapter failed', file=sys.stderr)\n"
    )
    actions = mod._default_normalize_and_merge_healer(root, ["raven"], need_merge=True)
    assert actions[0]["ok"] is False
    assert actions[-1]["error"] == "normalize_failed_no_merge"
    assert not (root / "calls.log").read_text().endswith("merge\n") if (root / "calls.log").exists() else True


def test_loop6a_jev_low_probability_is_always_false() -> None:
    mod = _load_self_heal_module()
    collected = {"delta_count": 1, "severity": "high", "residual_anomalies": [{"kind": "x", "severity": "high"}]}
    result = mod.evaluate_jev_decision(
        collected,
        jev_fn=lambda **_: {"answers": {"actionable_probability": {"noul": 0.12}, "delivery_route": {"choice": "dual_zone_issue"}, "delivery_route_match": {"noul": 0.99}}},
    )
    assert result["actionable"] is False
    assert result["route"] == "ignore"


def test_loop6a_pipeline_unchanged_watermark_skips_jev_and_delivery(tmp_path: Path, monkeypatch) -> None:
    mod = _load_self_heal_module()
    state_file = tmp_path / "watermarks.json"
    state_file.write_text(json.dumps({mod.LOOP_ID: {"watermark": "loop-telemetry-aidata-self-heal:stable"}}))
    collected = {"has_delta": True, "watermark": "loop-telemetry-aidata-self-heal:stable", "healed_items": [], "residual_unhealable_items": [{"kind": "gap", "severity": "high"}]}
    monkeypatch.setattr(mod, "inspect_and_self_heal", lambda **_: collected)
    called = {"jev": 0, "delivery": 0}
    result = mod.run_loop_pipeline(state_path=state_file, jev_fn=lambda **_: called.__setitem__("jev", 1), runner=lambda *args, **kwargs: called.__setitem__("delivery", 1))
    assert result["status"] == "SKIPPED_NO_DELTA"
    assert called == {"jev": 0, "delivery": 0}


def test_loop6a_strict_verifier_rejects_path_cli_and_non_chinese_upper_zone() -> None:
    mod = _load_self_heal_module()
    private_path = "/" + "Users/private/path"
    text = "<!-- multica-cursor:loop-telemetry-aidata-self-heal-2026-11-19 -->\n\n**一句话结论**：检查\n\n- [ ] 1. python3 " + private_path + "\n\n" + mod._DETAILS_OPEN + "\n<pre>{}</pre>\n</details>\n"
    result = mod.verify_dual_zone_markdown(text)
    codes = {item["code"] for item in result["violations"]}
    assert {"human-zone-cli-command", "human-zone-path"} <= codes


def test_loop6a_layer2_routes_snapshot_recursion_fallback_and_dry_run(tmp_path: Path, monkeypatch) -> None:
    mod = _load_self_heal_module()
    monkeypatch.setattr(mod, "_load_optional_helper", lambda *_: None)
    state_file = tmp_path / "watermarks.json"

    def collected(route: str):
        return {
            "has_delta": True,
            "watermark": f"{mod.LOOP_ID}:evidence-{route}",
            "delta_count": 1,
            "severity": "high",
            "title": "巡检告警",
            "cursor": f"{mod.LOOP_ID}-2026-11-19",
            "dual_zone_markdown": mod.render_dual_zone_markdown(tldr="发现需要处理的异常", items=[{"what": "检查遥测链路", "why": "恢复稳定性"}], cursor=f"{mod.LOOP_ID}-2026-11-19", ai_payload={"kind": "bounded"}),
            "residual_unhealable_items": [{"kind": "coverage_gap", "severity": "high"}],
            "healed_items": [],
        }

    def issue_runner(args, **kwargs):
        calls.append(list(args))
        if args[:2] == ["issue", "list"]:
            return subprocess.CompletedProcess(args, 0, json.dumps({"issues": []}), "")
        if args[:2] == ["issue", "create"]:
            return subprocess.CompletedProcess(args, 0, "{}", "")
        return subprocess.CompletedProcess(args, 0, "{}", "")

    calls = []
    monkeypatch.setattr(mod, "inspect_and_self_heal", lambda **_: collected("dual_zone_issue"))
    dual = mod.run_loop_pipeline(state_path=state_file, server_url="https://example.invalid", workspace_id="workspace", owner_id="owner", jev_fn=lambda **_: {"answers": {"actionable_probability": {"noul": 0.9}, "delivery_route": {"choice": "dual_zone_issue"}, "delivery_route_match": {"noul": 0.9}}}, runner=issue_runner)
    assert dual["ok"] and dual["status"] == "ACTION_TAKEN"
    assert json.loads(state_file.read_text())[mod.LOOP_ID]["watermark"] == dual["watermark"]

    calls.clear()
    autopilot_state = tmp_path / "autopilot-watermarks.json"
    def autopilot_runner(args, **kwargs):
        calls.append(list(args))
        if args[:2] == ["autopilot", "list"]:
            return subprocess.CompletedProcess(args, 0, json.dumps({"autopilots": [{"id": "ap-1", "title": mod.AUTOPILOT_TITLE}]}), "")
        if args[:3] == ["autopilot", "trigger", "ap-1"]:
            return subprocess.CompletedProcess(args, 0, "{}", "")
        return subprocess.CompletedProcess(args, 0, "{}", "")

    monkeypatch.setattr(mod, "inspect_and_self_heal", lambda **_: collected("autopilot_trigger"))
    triggered = mod.run_loop_pipeline(state_path=autopilot_state, server_url="https://example.invalid", workspace_id="workspace", jev_fn=lambda **_: {"answers": {"actionable_probability": {"noul": 0.9}, "delivery_route": {"choice": "autopilot_trigger"}, "delivery_route_match": {"noul": 0.9}}}, runner=autopilot_runner)
    assert triggered["ok"]
    assert ["autopilot", "trigger", "ap-1", "--output", "json"] in calls
    snapshot = Path(triggered["delivery"]["snapshot"])
    assert snapshot.is_file() and snapshot.stat().st_mode & 0o777 == 0o600
    assert not any(call[:2] == ["autopilot", "update"] or call[:2] == ["autopilot", "create"] for call in calls)

    calls.clear()
    monkeypatch.setattr(mod, "inspect_and_self_heal", lambda **_: collected("autopilot_trigger"))
    guarded = mod.run_loop_pipeline(state_path=tmp_path / "guarded.json", from_autopilot=True, server_url="https://example.invalid", workspace_id="workspace", owner_id="owner", jev_fn=lambda **_: {"answers": {"actionable_probability": {"noul": 0.9}, "delivery_route": {"choice": "autopilot_trigger"}, "delivery_route_match": {"noul": 0.9}}}, runner=issue_runner)
    assert guarded["ok"] and guarded["route"] == "dual_zone_issue"
    assert not any(call[:2] == ["autopilot", "trigger"] for call in calls)

    calls.clear()
    monkeypatch.setattr(mod, "inspect_and_self_heal", lambda **_: collected("autopilot_trigger"))
    fallback = mod.run_loop_pipeline(state_path=tmp_path / "fallback.json", server_url="https://example.invalid", workspace_id="workspace", owner_id="owner", jev_fn=lambda **_: {"answers": {"actionable_probability": {"noul": 0.9}, "delivery_route": {"choice": "autopilot_trigger"}, "delivery_route_match": {"noul": 0.9}}}, runner=lambda args, **kwargs: subprocess.CompletedProcess(args, 0, json.dumps({"autopilots": []}) if args[:2] == ["autopilot", "list"] else json.dumps({"issues": []}) if args[:2] == ["issue", "list"] else "{}", ""))
    assert fallback["ok"] and fallback["route"] == "dual_zone_issue"

    def failed_runner(args, **kwargs):
        return subprocess.CompletedProcess(args, 1, "", "failed")

    failed = mod.run_loop_pipeline(state_path=tmp_path / "failed.json", server_url="https://example.invalid", workspace_id="workspace", owner_id="owner", jev_fn=lambda **_: {"answers": {"actionable_probability": {"noul": 0.9}, "delivery_route": {"choice": "dual_zone_issue"}, "delivery_route_match": {"noul": 0.9}}}, runner=failed_runner)
    assert failed["ok"] is False and failed["status"] == "DELIVERY_FAILED"
    assert not (tmp_path / "failed.json").exists()

    dry_state = tmp_path / "dry.json"
    snapshot_mtime = snapshot.stat().st_mtime_ns
    dry = mod.run_loop_pipeline(state_path=dry_state, dry_run=True, server_url="https://example.invalid", workspace_id="workspace", owner_id="owner", jev_fn=lambda **_: {"answers": {"actionable_probability": {"noul": 0.9}, "delivery_route": {"choice": "dual_zone_issue"}, "delivery_route_match": {"noul": 0.9}}}, runner=failed_runner)
    assert dry["ok"] and not dry_state.exists()
    assert snapshot.stat().st_mtime_ns == snapshot_mtime
