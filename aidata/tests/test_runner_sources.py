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

import re
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

