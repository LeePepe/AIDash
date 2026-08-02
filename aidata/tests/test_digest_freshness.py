"""Hermetic tests for the digest source-freshness gate (integrity alarm).

The gate never blocks digest generation (ADR-16 必成 sink) — it only surfaces a
loud, actionable line when a source degraded, so a silently-incomplete digest
(the 07-21 "0 issue / 0 PR" and stale-radar failures) is noticed the same day.
"""

import pytest

from L5_apps.digest.sources import SourceHealth
from L5_apps.digest.freshness import degraded_sources, format_alarm


class _FakeSource:
    def __init__(self, state, name="src", detail=None):
        self.health = SourceHealth(name, state, detail)


class _FakeSources:
    """Minimal DigestSources stand-in: only the health-bearing fields matter."""
    def __init__(self, **states):
        self.multica = _FakeSource(states.get("multica", "ok"), "multica")
        self.ado = _FakeSource(states.get("ado", "ok"), "pr")
        self.repo_radar = _FakeSource(states.get("radar", "ok"), "github_repo")
        self.automation = _FakeSource(states.get("automation", "ok"), "automation")


@pytest.mark.unit
def test_all_ok_no_degraded():
    assert degraded_sources(_FakeSources()) == []


@pytest.mark.unit
def test_error_state_is_degraded():
    d = degraded_sources(_FakeSources(multica="error"))
    assert any(s.name == "multica" for s in d)


@pytest.mark.unit
def test_stale_and_skipped_are_degraded():
    d = degraded_sources(_FakeSources(radar="stale", ado="skipped:未采集"))
    names = {s.name for s in d}
    assert "github_repo" in names and "pr" in names


@pytest.mark.unit
def test_ok_sources_excluded():
    d = degraded_sources(_FakeSources(multica="ok", radar="error"))
    assert [s.name for s in d] == ["github_repo"]


@pytest.mark.unit
def test_format_alarm_mentions_each_degraded_source_and_date():
    d = degraded_sources(_FakeSources(multica="error", radar="stale"))
    msg = format_alarm(d, "2026-07-21")
    assert "2026-07-21" in msg
    assert "multica" in msg and "github_repo" in msg


@pytest.mark.unit
def test_format_alarm_empty_when_none():
    assert format_alarm([], "2026-07-21") == ""
