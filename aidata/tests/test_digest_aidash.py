"""Hermetic tests for the non-fatal --aidash wiring in write_digest (ADR-16/23).

The archive is the 必成 sink: write_digest ALWAYS returns the archive path and
the file exists on disk, no matter how the AIDash push fails. The push is
monkeypatched — no real app is ever launched.
"""

import pytest

import L5_apps.digest.app as app
from L5_apps.digest.aidash import Briefing, Card, Container, PushResult
from L5_apps.digest import aidash
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
    # Freeze the seam _fetch_sources ACTUALLY calls. Freezing only
    # fetch_ado_pr_trends leaves the PR line reading this machine's live
    # warehouse — the exact trap recorded in tech-context.md 坑 ①.
    monkeypatch.setattr(app, "fetch_combined_pr_trends", lambda: _FROZEN_ADO)
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


@pytest.mark.unit
def test_widget_snapshot_exports_compact_metrics(tmp_path):
    briefing = Briefing("2026-11-05", "test", (
        Container("c", "行动", 1, (
            Card("todo", "todoList", "wide", {"items": [{"title": "Fix CI"}]}),
        )),
    ))
    path = aidash.export_widget_briefing_snapshot(briefing, path=tmp_path / "snapshot.json")
    assert path is not None
    payload = __import__("json").loads(path.read_text(encoding="utf-8"))
    assert payload["date"] == "2026-11-05"
    assert payload["needsPersonCount"] == 1
    assert payload["topActions"] == ["Fix CI"]


@pytest.mark.unit
def test_retro_ops_keeps_repo_rank_and_time_stats():
    from L5_apps.digest.sources import RetroOpsTrends

    retro = RetroOpsTrends(
        (("通过", 1.0, "success"),), (("repo", 1.0, "1次", None),),
        (("已完成", 1.0, "success"),), (("run", 1.0, "1次", None),), 1.0, 1.0, None, None,
        SourceHealth("retro_ops", "ok"), avg_queue_wait_sec=2.5,
        avg_duration_sec=8.0,
    )
    container = aidash._retro_ops_container("1105", retro)
    ids = [card.id for card in container.cards]
    assert aidash._kuid("1105", 43) in ids
    stats = next(card.payload["stats"] for card in container.cards
                 if card.type == "agentSummary")
    assert {item["label"] for item in stats} >= {"CI 平均排队（秒）", "release_tf 平均耗时（秒）"}


@pytest.mark.unit
def test_relationship_falls_back_to_ci_scatter():
    from types import SimpleNamespace

    rework = SimpleNamespace(
        health=SourceHealth("rework", "ok"),
        cells=[SimpleNamespace(row="one", column="cause", value=1.0)],
        sample_size=1,
    )
    retro = SimpleNamespace(
        ci_points=(("repo-a", 3.0, 0.8), ("repo-b", 2.0, 0.5)),
    )
    container = aidash._relationship_container("1105", rework, retro)
    assert container is not None
    assert container.cards[0].id == aidash._kuid("1105", 52)
