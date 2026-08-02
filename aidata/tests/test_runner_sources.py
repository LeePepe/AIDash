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
