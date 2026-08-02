"""Hermetic tests for the non-fatal --aidash wiring in write_digest (ADR-16/23).

The archive is the 必成 sink: write_digest ALWAYS returns the archive path and
the file exists on disk, no matter how the AIDash push fails. The push is
monkeypatched — no real app is ever launched.
"""

import pytest

import L5_apps.digest.app as app
from L5_apps.digest.aidash import PushResult
from L5_apps.digest.sources import RepoRadar, SourceHealth

from tests.test_digest_golden import (
    _FROZEN_TRENDS, _FROZEN_MULTICA, _FROZEN_ADO, _FROZEN_AUTOMATION,
)

REPORT_DATE = "2026-07-10"


@pytest.fixture
def frozen(monkeypatch, tmp_path):
    monkeypatch.setattr(app, "fetch_raven_trends", lambda: _FROZEN_TRENDS)
    monkeypatch.setattr(app, "fetch_multica_completed", lambda: _FROZEN_MULTICA)
    monkeypatch.setattr(app, "fetch_ado_pr_trends", lambda: _FROZEN_ADO)
    monkeypatch.setattr(app, "fetch_automation_trends", lambda: _FROZEN_AUTOMATION)
    # Keep radar hermetic: empty/degraded so no warehouse/LLM access (ADR-23).
    monkeypatch.setattr(app, "fetch_repo_radar",
                        lambda: RepoRadar([], SourceHealth("github_repo", "skipped:未取")))
    monkeypatch.setattr(app, "DIGEST_DIR", tmp_path)
    return tmp_path


@pytest.mark.unit
def test_push_disabled_never_calls_push(frozen, monkeypatch):
    called = {"n": 0}

    def spy(*a, **k):
        called["n"] += 1
        return PushResult(True)

    monkeypatch.setattr(app, "_push_to_aidash", spy)
    path = app.write_digest(REPORT_DATE, push_aidash=False)
    assert path.exists()
    assert called["n"] == 0


@pytest.mark.unit
def test_archive_written_before_push_even_if_push_raises(frozen, monkeypatch):
    seen = {}

    def boom(md, report_date, sources):
        seen["existed"] = (frozen / "daily" / "2026-07-09.md").exists()
        raise RuntimeError("XPC exploded mid-push")

    monkeypatch.setattr(app, "_push_to_aidash", boom)
    # write_digest must NOT propagate the push exception
    path = app.write_digest(REPORT_DATE, push_aidash=True)
    assert path.exists()
    assert seen["existed"] is True  # archive written before push attempt


@pytest.mark.unit
def test_push_failure_result_is_non_fatal(frozen, monkeypatch):
    monkeypatch.setattr(app, "_push_to_aidash",
                        lambda md, d, s: PushResult(False, "AIDash app not running"))
    path = app.write_digest(REPORT_DATE, push_aidash=True)
    assert path.exists()


@pytest.mark.unit
def test_push_happy_path_still_returns_archive(frozen, monkeypatch):
    monkeypatch.setattr(app, "_push_to_aidash",
                        lambda md, d, s: PushResult(True, published=True))
    path = app.write_digest(REPORT_DATE, push_aidash=True)
    assert path.exists()
    assert path.name == "2026-07-09.md"
