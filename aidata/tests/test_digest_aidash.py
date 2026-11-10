"""Hermetic tests for the non-fatal --aidash wiring in write_digest (ADR-16/23).

The archive is the 必成 sink: write_digest ALWAYS returns the archive path and
the file exists on disk, no matter how the AIDash push fails. The push is
monkeypatched — no real app is ever launched.
"""

import pytest

import L5_apps.digest.app as app
from L5_apps.digest.aidash import Briefing, Card, Container, PushResult
from L5_apps.digest import aidash
from L5_apps.digest.sources import (
    RepoRadar, SourceHealth, TokenDeviceRow, TokenDeviceTrends,
)

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
def test_token_device_card_shows_merged_totals_and_share():
    raven = type("Raven", (), {})()
    raven.token_devices = TokenDeviceTrends(
        rows=(
            TokenDeviceRow("2026-11-08", "__all__", "All devices", 100, 40, 20, 10, 170, 3, 100),
            TokenDeviceRow("2026-11-08", "phone", "Phone", 60, 20, 10, 5, 95, 2, 55.88),
        ),
        health=SourceHealth("token_devices", "ok"),
    )
    card = aidash._token_device_card("1108", "2026-11-08", raven)
    assert card is not None
    assert card.type == "barList"
    assert card.payload["items"][0]["valueText"].startswith("input 100")
    assert card.payload["items"][1]["valueText"] == "55.88% · 95 tokens"


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
def test_build_briefing_follows_main_page_reading_bands(frozen):
    briefing = aidash.build_briefing(
        REPORT_DATE,
        app._fetch_sources(REPORT_DATE),
        "## 今日 TODO\n- P0: Fix CI\n",
        "> 💡 点评: Fix CI",
    )
    assert briefing.containers[0].title == "总览"
    assert briefing.containers[0].order == 10
    assert all(
        container.order < 50
        for container in briefing.containers
        if container.title in {"今日工作", "今日规划", "昨日汇总"}
    )


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
@pytest.mark.parametrize("has_ci_rank", [False, True])
@pytest.mark.parametrize("has_gtt", [False, True])
@pytest.mark.parametrize("has_operational", [False, True])
def test_retro_ops_card_ids_keep_distinct_signals(has_ci_rank, has_gtt, has_operational):
    from L5_apps.digest.sources import RetroOpsTrends

    retro = RetroOpsTrends(
        ci_segments=(("通过", 1.0, "success"),),
        ci_repo_bars=(("repo", 1.0, "1次", None),) if has_ci_rank else (),
        gtt_segments=(("已完成", 1.0, "success"),) if has_gtt else (),
        bot_tl_bars=(("CHECK", 1.0, "1次", None),),
        ci_pass_ratio=1.0, gtt_done_ratio=None,
        prmon_checked=None, prmon_stuck=None,
        health=SourceHealth("retro_ops", "ok"),
        release_tf_bars=(("release", 2.0, "2次", None),) if has_operational else (),
        workspace_hygiene_bars=(("worktree", 3.0, "3个", "warning"),)
        if has_operational else (),
    )
    container = aidash._retro_ops_container("1105", retro)
    expected = [(41, "stackedBar")]
    if has_gtt:
        expected.append((42, "stackedBar"))
    if has_ci_rank:
        expected.append((43, "barList"))
    expected.append((46, "sectionHeader"))
    if has_operational:
        expected.append((47, "barList"))
    expected.append((49, "agentSummary"))
    assert [(card.id, card.type) for card in container.cards] == [
        (aidash._kuid("1105", number), kind) for number, kind in expected
    ]
    assert len({card.id for card in container.cards}) == len(container.cards)
    by_id = {card.id: card for card in container.cards}
    if has_ci_rank:
        rank = by_id[aidash._kuid("1105", 43)]
        assert rank.payload["title"] == "各仓 CI 运行与配置异常排行"
        assert [item["label"] for item in rank.payload["items"]] == ["repo"]
    if has_operational:
        operations = by_id[aidash._kuid("1105", 47)]
        assert [item["label"] for item in operations.payload["items"]] == [
            "worktree", "release",
        ]


@pytest.mark.unit
@pytest.mark.parametrize("queue_values, expected", [
    ((2.0, None, 6.0), 4.0),
    ((0.0, None, 0.0), 0.0),
    ((None, None, None), None),
    ((), None),
])
def test_retro_ops_fetches_queue_wait_into_summary(monkeypatch, queue_values, expected):
    from L5_apps.digest import sources

    columns = [
        "repo_key", "run_count", "success_count", "failure_count",
        "cancelled_or_timeout_count", "pass_rate", "config_noise_job_count",
    ]
    rows = [("repo", 1, 1, 0, 0, 1.0, 0)] * 3
    if queue_values:
        columns.append("avg_queue_wait_sec")
        rows = [row + (value,) for row, value in zip(rows, queue_values)]
    queries = {
        "retro/ci_health_and_noise": (rows, columns),
        "retro/bot_tl_operations": (
            [("CHECK", 1, 1, 0)],
            ["action_kind", "action_count", "latest_checked_pr_count",
             "latest_stuck_pr_count"],
        ),
    }
    monkeypatch.setattr(sources.serve, "run_query", lambda name: queries.get(name, ([], [])))
    monkeypatch.setattr(sources, "_claude_job_counts", lambda: ())
    retro = sources.fetch_retro_ops_trends()
    assert retro.health.state == "ok"
    assert retro.avg_queue_wait_sec == expected
    container = aidash._retro_ops_container("1105", retro)
    stats = next(card.payload["stats"] for card in container.cards
                 if card.type == "agentSummary")
    queue_stats = [item["value"] for item in stats if item["label"] == "CI 平均排队（秒）"]
    assert queue_stats == ([] if expected is None else [expected])


@pytest.mark.unit
@pytest.mark.parametrize("field", ["repo", "project", "related_project", "category"])
@pytest.mark.parametrize("candidate, starred", [
    (" https://GitHub.com/Owner/Repo/ ", "owner/repo"),
    ("http://github.com/OWNER/REPO/", "https://github.com/owner/repo/"),
    (" OWNER/REPO/ ", "http://github.com/owner/repo/"),
])
def test_star_direct_matches_normalize_both_sides(field, candidate, starred):
    from L5_apps.digest.sources import apply_star_preferences

    unrelated = {"repo": "other/repo", "category": "other"}
    peer = {"repo": "peer/repo", "topics": ["shared"]}
    direct = {field: candidate, "topics": ["shared"]}
    assert apply_star_preferences([unrelated, peer, direct], [starred]) == [
        direct, peer, unrelated,
    ]


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
