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


@pytest.mark.unit
def test_agent_efficiency_snapshot_writes_atomic_contract_and_merges_magpie(tmp_path):
    import json

    from L5_apps.digest import agent_efficiency_snapshot as aes

    magpie_file = tmp_path / "usage.jsonl"
    magpie_file.write_text(
        "\n".join([
            json.dumps({
                "t": "2026-11-18T10:00:00+08:00",
                "req": "group/steering",
                "served": "gemini-4-argon",
                "in": 2000,
                "out": 500,
                "cache_read": 8000,
                "cache_write": 0,
                "ttft_ms": 1800,
            }),
            json.dumps({
                "t": "2026-11-18T11:00:00+08:00",
                "req": "group/coding",
                "served": "gpt-5.6-luna",
                "in": 3000,
                "out": 1500,
                "cache_read": 15000,
                "cache_write": 0,
                "ttft_ms": 4200,
            }),
        ]) + "\n",
        encoding="utf-8",
    )

    role_cols = [
        "role_key", "role_label", "runs_count", "goals_count", "tasks_count",
        "r1_count", "r2_count", "r3_plus_count", "r1_pass_rate",
        "median_duration_sec", "p90_duration_sec", "estimated_tokens", "token_share_pct",
    ]
    role_rows = [
        ("m3", "总控协调", 2, 1, 2, 2, 0, 0, 1.0, 0.8, 1.5, 500, 1.0),
        ("m2", "话题编排", 4, 2, 3, 3, 0, 0, 1.0, 6.2, 14.0, 2000, 4.0),
        ("m1", "Goal 主控 (TL)", 8, 3, 6, 6, 0, 0, 1.0, 1200.0, 2800.0, 0, 0.0),
        ("designer", "视觉设计 (Designer)", 2, 1, 2, 2, 0, 0, 1.0, 420.0, 600.0, 4000, 8.0),
        ("writer", "编码实现 (Writer)", 12, 3, 8, 6, 1, 1, 0.75, 1600.0, 3200.0, 18000, 36.0),
        ("reviewer", "独立审查 (Reviewer)", 10, 3, 8, 5, 2, 1, 0.625, 900.0, 1800.0, 22000, 44.0),
        ("explorer", "代码探查 (Explorer)", 3, 2, 3, 3, 0, 0, 1.0, 240.0, 480.0, 1500, 3.0),
        ("pr_monitor", "交付监控 (PR Monitor)", 5, 3, 4, 3, 1, 0, 0.75, 600.0, 1500.0, 2000, 4.0),
    ]
    daily_cols = [
        "cst_day", "goals_completed", "tasks_completed",
        "r1_count", "r2_count", "r3_plus_count", "r1_pass_rate",
        "median_duration_sec", "p90_duration_sec", "blocked_events",
        "steering_tokens", "coding_tokens", "total_tokens",
    ]
    daily_rows = [
        ("2026-11-17", 2, 5, 4, 1, 0, 0.8, 1100.0, 2400.0, 0, 4000, 18000, 22000),
        ("2026-11-18", 3, 7, 5, 1, 1, 0.7143, 1400.0, 3100.0, 2, 10500, 19500, 30000),
    ]

    def fake_runner(name, params=None):
        if name == aes.ROLE_QUERY:
            return role_rows, role_cols
        if name == aes.DAILY_QUERY:
            return daily_rows, daily_cols
        raise AssertionError(f"unexpected query {name}")

    out_path = tmp_path / "jobs" / "aidata-digest" / "agent-efficiency.json"
    payload = aes.write_snapshot(out_path, magpie_path=magpie_file, query_runner=fake_runner)
    assert out_path.is_file()
    persisted = json.loads(out_path.read_text(encoding="utf-8"))
    assert persisted == payload
    assert payload["contract"] == "aidash-agent-efficiency/v1"
    assert payload["schema_version"] == 1
    assert payload["coverage_status"] == "healthy"
    assert payload["window_start"] == "2026-11-17"
    assert payload["window_end"] == "2026-11-18"
    assert payload["source_as_of"] == "2026-11-18"
    assert len(payload["roles"]) == 8
    m1_row = next(r for r in payload["roles"] if r["role_key"] == "m1")
    assert m1_row["estimated_tokens"] == 10500  # merged from magpie group/steering
    assert payload["round_summary"]["r1_count"] == 13
    assert payload["round_summary"]["r2_count"] == 3
    assert payload["round_summary"]["r3_plus_count"] == 2
    assert payload["round_summary"]["ttft_p90_sec"] == 4.2
    assert len(payload["daily_series"]) == 2


@pytest.mark.unit
def test_agent_efficiency_snapshot_degrades_cleanly_when_queries_fail(tmp_path):
    from L5_apps.digest import agent_efficiency_snapshot as aes

    def failing_runner(_name, _params=None):
        raise FileNotFoundError("warehouse missing")

    out_path = tmp_path / "agent-efficiency.json"
    payload = aes.write_snapshot(
        out_path,
        magpie_path=tmp_path / "missing-usage.jsonl",
        query_runner=failing_runner,
    )
    assert out_path.is_file()
    assert payload["coverage_status"] == "missing"
    assert payload["sample_size"] == 0
    assert payload["errors"]


@pytest.mark.unit
def test_skills_roi_snapshot_preserves_and_validates_skill_details(tmp_path):
    import json
    from pathlib import Path

    from L5_apps.digest.skills_roi_snapshot import build_snapshot, write_snapshot

    fixture = Path(__file__).parent / "fixtures" / "skills_roi_report.json"
    base_report = json.loads(fixture.read_text(encoding="utf-8"))
    skill_details = [
        {
            "window_cst": "30d",
            "window_start": "2026-10-13T00:00:00+08:00",
            "window_end": "2026-11-12T00:00:00+08:00",
            "source_as_of": "2026-11-11T14:00:00+08:00",
            "sample_size": 2,
            "coverage_status": "healthy",
            "skill": "team-lead",
            "scope": "global",
            "repo": "user-skills",
            "skill_dir": "~/Development/user-skills/skills/team-lead",
            "skill_md_path": "SKILL.md",
            "skill_md_lines": 124,
            "frontmatter_tokens_est": 48,
            "body_tokens_est": 1820,
            "loads_7d": 2,
            "loads_30d": 2,
            "status_label": "active",
            "references": [
                {
                    "rel_path": "references/playbook.md",
                    "line_count": 140,
                    "tokens_est": 1600,
                    "hits_30d": 2,
                    "sessions_30d": 1,
                    "is_unhit": False,
                }
            ],
            "scripts": [
                {
                    "rel_path": "scripts/goal-queue.py",
                    "calls_30d": 4,
                    "success_rate": 1.0,
                    "p95_ms": 110.0,
                    "is_unpracticed": False,
                }
            ],
            "eval_cases": [
                {
                    "id": "EV-001",
                    "title": "pre-review-check CLI help",
                    "kind": "cli",
                    "assertion_summary": "python3 skills/team-lead/scripts/feedback_guard.py --help",
                    "status": "active",
                    "interceptions_30d": 1,
                    "escapes_30d": 0,
                }
            ],
        }
    ]
    enriched = {**base_report, "skill_details": skill_details}
    report_path = tmp_path / "report.json"
    report_path.write_text(json.dumps(enriched), encoding="utf-8")
    output_path = tmp_path / "skills-roi.json"

    snapshot = write_snapshot(
        output_path,
        report_path,
        query_runner=lambda name, params: (
            [("2026-11-11", "copilot_cli_skill", "team-lead", 2, 1)],
            ["day", "source", "skill", "n", "sessions"],
        ),
    )
    assert snapshot["coverage_status"] == "healthy"
    assert "errors" not in snapshot
    assert snapshot["skill_details"] == skill_details
    assert snapshot["diagnostics"]["skill_details"] == skill_details
    assert json.loads(output_path.read_text(encoding="utf-8"))["skill_details"] == skill_details

    # Missing required fields on skill_details flags degraded error status without dropping diagnostics
    malformed = {**base_report, "skill_details": [{"skill": "broken-only"}]}
    bad_snapshot = build_snapshot(malformed, [])
    assert bad_snapshot["coverage_status"] == "error"
    assert any("skill_details[0] missing" in err for err in bad_snapshot.get("errors", []))

