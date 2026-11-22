"""Hermetic tests for the digest source-freshness gate (integrity alarm).

The gate never blocks digest generation (ADR-16 必成 sink) — it only surfaces a
loud, actionable line when a source degraded, so a silently-incomplete digest
(the 07-21 "0 issue / 0 PR" and stale-radar failures) is noticed the same day.
"""

import pytest

from L5_apps.digest.sources import SourceHealth
from L5_apps.digest.freshness import alarm_if_degraded, degraded_sources, format_alarm


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


@pytest.mark.unit
def test_alarm_if_degraded_writes_cron_error_log_without_osascript(monkeypatch, tmp_path):
    import subprocess
    called = []
    monkeypatch.setattr(subprocess, "run", lambda *a, **kw: called.append(a))
    log_path = tmp_path / "cron-errors.log"
    msg = alarm_if_degraded(
        _FakeSources(multica="error", radar="stale"),
        "2026-07-21",
        log_path=log_path,
    )
    assert "2026-07-21" in msg
    logged = log_path.read_text(encoding="utf-8")
    assert "multica=error" in logged and "github_repo=stale" in logged
    assert called == []


@pytest.mark.unit
def test_alarm_if_degraded_invokes_injected_notifier_when_provided(tmp_path):
    notes: list[tuple[str, str]] = []
    log_path = tmp_path / "cron-errors.log"
    msg = alarm_if_degraded(
        _FakeSources(multica="error"),
        "2026-07-21",
        log_path=log_path,
        notifier=lambda title, body: notes.append((title, body)),
    )
    assert msg
    assert len(notes) == 1
    assert "multica=error" in notes[0][1]

