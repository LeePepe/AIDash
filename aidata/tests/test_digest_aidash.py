"""Hermetic tests for the non-fatal --aidash wiring in write_digest (ADR-16/23).

The archive is the 必成 sink: write_digest ALWAYS returns the archive path and
the file exists on disk, no matter how the AIDash push fails. The push is
monkeypatched — no real app is ever launched.
"""

import pytest
from L5_apps.digest import aidash, app
from L5_apps.digest.aidash import Briefing, Card, Container, PushResult
from L5_apps.digest.sources import (
    RepoRadar, SourceHealth, TokenDeviceRow, TokenDeviceTrends,
)

from tests.test_digest_golden import (
    _FROZEN_ADO,
    _FROZEN_AUTOMATION,
    _FROZEN_MULTICA,
    _FROZEN_TRENDS,
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
    icloud_dir = tmp_path / "icloud"
    payload = aes.write_snapshot(
        out_path, magpie_path=magpie_file, query_runner=fake_runner,
        icloud_sync_dir=icloud_dir,
    )
    assert out_path.is_file()
    assert (icloud_dir / "jobs" / "aidata-digest" / "agent-efficiency.json").is_file()
    persisted = json.loads(out_path.read_text(encoding="utf-8"))
    assert persisted == payload
    assert payload["contract"] == "aidash-agent-efficiency/v1"
    assert payload["schema_version"] == 1
    assert payload["generated_at"].endswith("Z")
    assert __import__("json").loads(
        (icloud_dir / "jobs" / "aidata-digest" / "agent-efficiency.json").read_text(encoding="utf-8")
    ) == payload
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
def test_snapshots_survive_icloud_mirror_replace_failure_and_timeout(monkeypatch, tmp_path):
    import json
    import subprocess
    from pathlib import Path

    from L5_apps.digest import agent_efficiency_snapshot as aes
    from L5_apps.digest import skills_roi_snapshot as srs

    report_fixture = Path(__file__).parent / "fixtures" / "skills_roi_report.json"
    report_path = tmp_path / "report.json"
    report_path.write_text(report_fixture.read_text(encoding="utf-8"), encoding="utf-8")

    icloud_dir = tmp_path / "icloud"
    local_dir = tmp_path / "local-job"
    skills_out = local_dir / "skills-roi.json"
    eff_out = local_dir / "agent-efficiency.json"

    real_replace = Path.replace

    def fail_icloud_replace(self: Path, target: Path):
        if str(icloud_dir) in str(target):
            raise PermissionError("Operation not permitted on CloudDocs")
        return real_replace(self, target)

    monkeypatch.setattr(Path, "replace", fail_icloud_replace)

    roi_payload = srs.write_snapshot(
        skills_out,
        report_path,
        query_runner=lambda name, params: (
            [("2026-11-11", "copilot_cli_skill", "team-lead", 2, 1)],
            ["day", "source", "skill", "n", "sessions"],
        ),
        icloud_sync_dir=icloud_dir,
    )
    assert roi_payload["coverage_status"] == "healthy"
    assert json.loads(skills_out.read_text(encoding="utf-8")) == roi_payload
    assert json.loads(
        (local_dir / ".icloud-mirror-fallback-skills-roi.json").read_text(encoding="utf-8")
    ) == roi_payload
    assert list((icloud_dir / "jobs" / "aidata-digest").glob(".skills-roi.json.*")) == []

    monkeypatch.setattr(Path, "replace", real_replace)
    monkeypatch.setenv("AIDASH_ICLOUD_FORCE_SUBPROCESS", "1")
    monkeypatch.setattr(
        aes.subprocess,
        "run",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            subprocess.TimeoutExpired(cmd="mirror", timeout=0.2)
        ),
    )
    eff_payload = aes.write_snapshot(
        eff_out,
        magpie_path=tmp_path / "missing-usage.jsonl",
        query_runner=lambda name, params=None: (
            [("writer", "Writer", 4, 2, 4, 3, 1, 0, 0.75, 120.0, 240.0, 5000)],
            [
                "role_key", "role_label", "runs_count", "goals_count", "tasks_count",
                "r1_count", "r2_count", "r3_plus_count", "r1_pass_rate",
                "median_duration_sec", "p90_duration_sec", "estimated_tokens",
            ],
        )
        if name == aes.ROLE_QUERY
        else (
            [("2026-11-18", 1, 2, 2, 0, 0, 1.0, 100.0, 180.0, 0, 1000, 4000, 5000)],
            [
                "cst_day", "goals_completed", "tasks_completed", "r1_count",
                "r2_count", "r3_plus_count", "r1_pass_rate", "median_duration_sec",
                "p90_duration_sec", "blocked_events", "steering_tokens",
                "coding_tokens", "total_tokens",
            ],
        ),
        icloud_sync_dir=icloud_dir,
    )
    assert eff_payload["coverage_status"] == "healthy"
    assert json.loads(eff_out.read_text(encoding="utf-8")) == eff_payload
    assert json.loads(
        (local_dir / ".icloud-mirror-fallback-agent-efficiency.json").read_text(encoding="utf-8")
    ) == eff_payload


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
            "is_ghost": False,
            "doc_preview": "# Team Lead\n\nPreview",
            "scope": "global",
            "repo": "user-skills",
            "skill_dir": "~/Development/user-skills/skills/team-lead",
            "skill_md_path": "SKILL.md",
            "skill_md_lines": 124,
            "frontmatter_tokens_est": 48,
            "body_tokens_est": 1820,
            "bundle_kb": 18.4,
            "refs_kb": 6.4,
            "refs_tokens_est": 1600,
            "loads_7d": 2,
            "loads_30d": 2,
            "unpracticed_rate": 0.0,
            "unhit_refs_count": 0,
            "unhit_refs_ratio": 0.0,
            "roi_score": 0.42,
            "r1_pass_rate": 0.85,
            "avg_context_tokens": 24800,
            "status_label": "active",
            "references": [
                {
                    "rel_path": "references/playbook.md",
                    "doc_preview": "# Playbook\n\nReference preview",
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
        },
        {
            "window_cst": "30d",
            "window_start": "2026-10-13T00:00:00+08:00",
            "window_end": "2026-11-12T00:00:00+08:00",
            "source_as_of": "2026-11-11T14:00:00+08:00",
            "sample_size": 1,
            "coverage_status": "healthy",
            "skill": "legacy-deleted-ghost",
            "is_ghost": True,
            "doc_preview": "",
            "scope": "global",
            "repo": "user-skills",
            "skill_dir": "~/Development/user-skills/skills/legacy-deleted-ghost",
            "skill_md_path": "SKILL.md",
            "skill_md_lines": 0,
            "frontmatter_tokens_est": 1,
            "body_tokens_est": 1,
            "bundle_kb": 0.0,
            "refs_kb": 0.0,
            "refs_tokens_est": 0,
            "loads_7d": 0,
            "loads_30d": 1,
            "unpracticed_rate": 0.0,
            "unhit_refs_count": 0,
            "unhit_refs_ratio": 0.0,
            "roi_score": 0.18,
            "r1_pass_rate": 1.0,
            "avg_context_tokens": 1202,
            "status_label": "ghost",
            "references": [],
            "scripts": [],
            "eval_cases": [],
        },
    ]
    enriched = {**base_report, "skill_details": skill_details}
    report_path = tmp_path / "report.json"
    report_path.write_text(json.dumps(enriched), encoding="utf-8")
    output_path = tmp_path / "skills-roi.json"
    icloud_dir = tmp_path / "icloud"

    snapshot = write_snapshot(
        output_path,
        report_path,
        query_runner=lambda name, params: (
            [("2026-11-11", "copilot_cli_skill", "team-lead", 2, 1)],
            ["day", "source", "skill", "n", "sessions"],
        ),
        icloud_sync_dir=icloud_dir,
    )
    assert snapshot["coverage_status"] == "healthy"
    assert snapshot["generated_at"].endswith("Z")
    assert "errors" not in snapshot
    assert snapshot["skill_details"] == skill_details
    assert snapshot["skill_details"][0]["doc_preview"] == "# Team Lead\n\nPreview"
    assert snapshot["skill_details"][0]["bundle_kb"] == 18.4
    assert snapshot["skill_details"][0]["refs_kb"] == 6.4
    assert snapshot["skill_details"][0]["refs_tokens_est"] == 1600
    assert snapshot["skill_details"][0]["unpracticed_rate"] == 0.0
    assert snapshot["skill_details"][0]["unhit_refs_count"] == 0
    assert snapshot["skill_details"][0]["unhit_refs_ratio"] == 0.0
    assert snapshot["skill_details"][0]["is_ghost"] is False
    assert snapshot["skill_details"][0]["roi_score"] == 0.42
    assert snapshot["skill_details"][0]["r1_pass_rate"] == 0.85
    assert snapshot["skill_details"][0]["avg_context_tokens"] == 24800
    assert snapshot["skill_details"][1]["is_ghost"] is True
    assert snapshot["skill_details"][1]["status_label"] == "ghost"
    assert snapshot["skill_details"][0]["references"][0]["doc_preview"] == "# Playbook\n\nReference preview"
    assert snapshot["diagnostics"]["skill_details"] == skill_details
    persisted = json.loads(output_path.read_text(encoding="utf-8"))
    assert persisted["skill_details"] == skill_details
    mirrored = json.loads(
        (icloud_dir / "jobs" / "aidata-digest" / "skills-roi.json").read_text(encoding="utf-8")
    )
    assert mirrored == persisted

    # Missing required fields on skill_details flags degraded error status without dropping diagnostics
    malformed = {**base_report, "skill_details": [{"skill": "broken-only"}]}
    bad_snapshot = build_snapshot(malformed, [])
    assert bad_snapshot["coverage_status"] == "error"
    assert any("skill_details[0] missing" in err for err in bad_snapshot.get("errors", []))

    # Unfiltered __pycache__ script or bare EV-013 == title is flagged by contract validator
    polluted = {
        **base_report,
        "skill_details": [
            {
                **skill_details[0],
                "scripts": [{"rel_path": "scripts/__pycache__", "calls_30d": 1}],
                "eval_cases": [{"id": "EV-013", "title": "EV-013"}],
            }
        ],
    }
    polluted_snapshot = build_snapshot(polluted, [])
    assert polluted_snapshot["coverage_status"] == "error"
    assert any("invalid script path" in err for err in polluted_snapshot.get("errors", []))
    assert any("human-readable title != id" in err for err in polluted_snapshot.get("errors", []))


@pytest.mark.unit
def test_skill_version_evolution_attribution_deltas_and_status_classification(tmp_path):
    import json
    import os
    import sqlite3
    import subprocess
    from pathlib import Path

    from L5_apps.digest.skills_roi_snapshot import (
        build_snapshot,
        classify_skill_version_evolution,
        compute_skill_version_evolution,
        match_skill_version_for_event,
        resolve_skill_version_history,
        write_snapshot,
    )

    skills_repo = tmp_path / "user-skills"
    skills_dir = skills_repo / "skills"
    skills_dir.mkdir(parents=True)

    clean_env = {
        **{k: v for k, v in os.environ.items() if not k.startswith("GIT_")},
        "GIT_AUTHOR_NAME": "Test Bot",
        "GIT_AUTHOR_EMAIL": "bot@example.com",
        "GIT_COMMITTER_NAME": "Test Bot",
        "GIT_COMMITTER_EMAIL": "bot@example.com",
    }
    subprocess.run(["git", "init"], cwd=skills_repo, env=clean_env, check=True, capture_output=True)

    def _commit_skill(
        name: str,
        semver: str,
        commit_iso: str,
        *,
        broken_drawer: bool = False,
        note: str = "init",
    ) -> None:
        pkg = skills_dir / name
        (pkg / ".claude-plugin").mkdir(parents=True, exist_ok=True)
        (pkg / "references").mkdir(parents=True, exist_ok=True)
        (pkg / "scripts").mkdir(parents=True, exist_ok=True)
        (pkg / ".claude-plugin" / "plugin.json").write_text(
            json.dumps({"name": name, "version": semver, "description": f"{name} plugin"}),
            encoding="utf-8",
        )
        broken_link_md = "\nSee [missing](references/missing-drawer.md)\n" if broken_drawer else "\nSee [guide](references/guide.md)\n"
        (pkg / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: {name} skill\n---\n# {name}\n{note}\n{broken_link_md}",
            encoding="utf-8",
        )
        (pkg / "references" / "guide.md").write_text(f"# Guide for {name}\n{note}\n", encoding="utf-8")
        (pkg / "scripts" / "tool.py").write_text(f"#!/usr/bin/env python3\n# {note}\nprint('ok')\n", encoding="utf-8")
        subprocess.run(["git", "add", f"skills/{name}"], cwd=skills_repo, env=clean_env, check=True, capture_output=True)
        commit_env = {**clean_env, "GIT_AUTHOR_DATE": commit_iso, "GIT_COMMITTER_DATE": commit_iso}
        subprocess.run(
            ["git", "commit", "-m", f"feat({name}): {note}"],
            cwd=skills_repo,
            env=commit_env,
            check=True,
            capture_output=True,
        )

    # 1. alpha-skill: v1 (2026-11-05) -> v2 (2026-11-10) -> improved
    _commit_skill("alpha-skill", "1.0.0", "2026-11-05T10:00:00+08:00", broken_drawer=True, note="v1 initial with roadblock")
    _commit_skill("alpha-skill", "1.1.0", "2026-11-10T10:00:00+08:00", broken_drawer=False, note="v2 soften CLI roadblock and fix drawer")

    # 2. beta-skill: v1 (2026-11-05) -> v2 (2026-11-10) -> regressed (exit=2 rebounded in v2)
    _commit_skill("beta-skill", "1.0.0", "2026-11-05T12:00:00+08:00", note="v1 stable")
    _commit_skill("beta-skill", "1.2.0", "2026-11-10T12:00:00+08:00", note="v2 introduced CLI exit=2 regression")

    # 3. gamma-skill: v1 (2026-11-05) -> v2 (2026-11-11) -> observing (< 5 invocations in v2)
    _commit_skill("gamma-skill", "1.0.0", "2026-11-05T14:00:00+08:00", note="v1 initial")
    _commit_skill("gamma-skill", "2.0.0", "2026-11-11T08:00:00+08:00", note="v2 just released")

    # 4. delta-skill: single commit v1 -> baseline
    _commit_skill("delta-skill", "1.0.0", "2026-11-06T09:00:00+08:00", note="v1 baseline only")

    # 5. epsilon-skill: zero telemetry samples -> sample_size=0, coverage_status="unknown", source_as_of=None
    _commit_skill("epsilon-skill", "1.0.0", "2026-11-06T11:00:00+08:00", note="v1 no telemetry")

    histories = resolve_skill_version_history(skills_repo)
    assert set(histories) == {"alpha-skill", "beta-skill", "gamma-skill", "delta-skill", "epsilon-skill"}
    assert len(histories["alpha-skill"]) == 2
    alpha_v1 = histories["alpha-skill"][0]
    alpha_v2 = histories["alpha-skill"][1]
    assert alpha_v1["semver"] == "1.0.0"
    assert alpha_v1["skill_version"].startswith("v1@")
    assert alpha_v1["combined_version"] == f"1.0.0+{alpha_v1['skill_version']}"
    assert alpha_v2["semver"] == "1.1.0"
    assert alpha_v2["skill_version"].startswith("v2@")
    assert alpha_v2["combined_version"] == f"1.1.0+{alpha_v2['skill_version']}"
    assert alpha_v1["t_end"] == alpha_v2["t_start"]

    # Explicit version match vs timestamp fallback
    matched_explicit = match_skill_version_for_event(
        "alpha-skill",
        histories["alpha-skill"],
        explicit_skill_version=alpha_v1["skill_version"],
        event_ts="2026-11-11T10:00:00+08:00",
    )
    assert matched_explicit is not None
    assert matched_explicit["skill_version"] == alpha_v1["skill_version"]

    matched_ts_v1 = match_skill_version_for_event(
        "alpha-skill",
        histories["alpha-skill"],
        event_ts="2026-11-08T10:00:00+08:00",
    )
    assert matched_ts_v1 is not None
    assert matched_ts_v1["skill_version"] == alpha_v1["skill_version"]

    matched_ts_v2 = match_skill_version_for_event(
        "alpha-skill",
        histories["alpha-skill"],
        event_ts="2026-11-10T15:00:00+08:00",
    )
    assert matched_ts_v2 is not None
    assert matched_ts_v2["skill_version"] == alpha_v2["skill_version"]

    # Build usage.jsonl + warehouse.db telemetry covering Before (v1) and After (v2)
    usage_jsonl = tmp_path / "usage.jsonl"
    usage_events = []

    # alpha-skill v1 (Before): 6 sessions, 4 script calls (2 exit=2, P50=450ms), uptake=0.5
    for idx in range(6):
        usage_events.append({
            "kind": "skill_turn",
            "session_id": f"alpha-v1-s{idx}",
            "turn_id": f"t-{idx}",
            "ts": f"2026-11-07T1{idx}:00:00+08:00",
            "skill": "alpha-skill",
            "skill_version": alpha_v1["skill_version"],
            "uptake_rate": 0.5,
        })
    for idx, (ec, dur) in enumerate([(2, 420), (2, 450), (0, 480), (0, 500)]):
        usage_events.append({
            "kind": "script_call",
            "call_uid": f"alpha-v1-sc{idx}",
            "session_id": f"alpha-v1-s{idx}",
            "ts": f"2026-11-07T1{idx}:05:00+08:00",
            "skill": "alpha-skill",
            "script_path": "skills/alpha-skill/scripts/tool.py",
            "exit_code": ec,
            "duration_ms": dur,
        })

    # alpha-skill v2 (After): 6 sessions, 5 script calls (0 exit=2, P50=120ms), reference hit, uptake=0.95
    for idx in range(6):
        usage_events.append({
            "kind": "skill_turn",
            "session_id": f"alpha-v2-s{idx}",
            "turn_id": f"t2-{idx}",
            "ts": f"2026-11-10T1{idx}:30:00+08:00",
            "skill": "alpha-skill",
            "uptake_rate": 0.95,
        })
    usage_events.append({
        "kind": "reference_hit",
        "hit_uid": "alpha-v2-ref0",
        "session_id": "alpha-v2-s0",
        "ts": "2026-11-10T11:31:00+08:00",
        "skill": "alpha-skill",
        "reference_path": "skills/alpha-skill/references/guide.md",
        "byte_len": 256,
    })
    for idx, dur in enumerate([100, 110, 120, 130, 140]):
        usage_events.append({
            "kind": "script_call",
            "call_uid": f"alpha-v2-sc{idx}",
            "session_id": f"alpha-v2-s{idx}",
            "ts": f"2026-11-10T1{idx}:35:00+08:00",
            "skill": "alpha-skill",
            "script_path": "skills/alpha-skill/scripts/tool.py",
            "exit_code": 0,
            "duration_ms": dur,
        })

    # beta-skill v1 (Before): 5 sessions, 0 exit=2 -> v2 (After): 5 sessions, 2 exit=2 roadblocks (regressed)
    for idx in range(5):
        usage_events.append({
            "kind": "skill_turn",
            "session_id": f"beta-v1-s{idx}",
            "turn_id": f"bt1-{idx}",
            "ts": f"2026-11-08T1{idx}:00:00+08:00",
            "skill": "beta-skill",
        })
        usage_events.append({
            "kind": "script_call",
            "call_uid": f"beta-v1-sc{idx}",
            "session_id": f"beta-v1-s{idx}",
            "ts": f"2026-11-08T1{idx}:05:00+08:00",
            "skill": "beta-skill",
            "script_path": "skills/beta-skill/scripts/tool.py",
            "exit_code": 0,
            "duration_ms": 150,
        })
    for idx in range(5):
        usage_events.append({
            "kind": "skill_turn",
            "session_id": f"beta-v2-s{idx}",
            "turn_id": f"bt2-{idx}",
            "ts": f"2026-11-11T0{idx}:00:00+08:00",
            "skill": "beta-skill",
        })
        usage_events.append({
            "kind": "script_call",
            "call_uid": f"beta-v2-sc{idx}",
            "session_id": f"beta-v2-s{idx}",
            "ts": f"2026-11-11T0{idx}:05:00+08:00",
            "skill": "beta-skill",
            "script_path": "skills/beta-skill/scripts/tool.py",
            "exit_code": 2 if idx < 2 else 0,
            "duration_ms": 200,
        })

    # gamma-skill v1 (Before): 6 sessions -> v2 (After): only 2 sessions (< 5 threshold -> observing)
    for idx in range(6):
        usage_events.append({
            "kind": "skill_turn",
            "session_id": f"gamma-v1-s{idx}",
            "turn_id": f"gm1-{idx}",
            "ts": f"2026-11-07T0{idx}:00:00+08:00",
            "skill": "gamma-skill",
        })
    for idx in range(2):
        usage_events.append({
            "kind": "skill_turn",
            "session_id": f"gamma-v2-s{idx}",
            "turn_id": f"gm2-{idx}",
            "ts": f"2026-11-11T1{idx}:00:00+08:00",
            "skill": "gamma-skill",
        })

    # delta-skill v1 (Baseline): 3 sessions, single version
    for idx in range(3):
        usage_events.append({
            "kind": "skill_turn",
            "session_id": f"delta-v1-s{idx}",
            "turn_id": f"dl1-{idx}",
            "ts": f"2026-11-09T1{idx}:00:00+08:00",
            "skill": "delta-skill",
        })

    usage_jsonl.write_text("\n".join(json.dumps(e) for e in usage_events) + "\n", encoding="utf-8")

    # Build hermetic warehouse.db with R1 review verdicts across Before and After timestamps
    warehouse_db = tmp_path / "warehouse.db"
    with sqlite3.connect(warehouse_db) as conn:
        conn.executescript(
            """
            CREATE TABLE fact_gtt_task_run (
                receipt_uid TEXT PRIMARY KEY,
                goal_id TEXT,
                role_name TEXT,
                round_no INTEGER,
                v5_verdict TEXT,
                status TEXT,
                completed_at TEXT,
                cst_day TEXT,
                skills_used TEXT
            );
            """
        )
        conn.executemany(
            "INSERT INTO fact_gtt_task_run VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                ("r1-alpha-v1-1", "g1", "reviewer", 1, "FAIL", "failed", "2026-11-07T18:00:00+08:00", "2026-11-07", '["alpha-skill"]'),
                ("r1-alpha-v1-2", "g2", "reviewer", 1, "PASS", "completed", "2026-11-08T18:00:00+08:00", "2026-11-08", '["alpha-skill"]'),
                ("r1-alpha-v2-1", "g3", "reviewer", 1, "PASS", "completed", "2026-11-10T20:00:00+08:00", "2026-11-10", '["alpha-skill"]'),
                ("r1-alpha-v2-2", "g4", "reviewer", 1, "PASS", "completed", "2026-11-11T12:00:00+08:00", "2026-11-11", '["alpha-skill"]'),
            ],
        )

    fixture = Path(__file__).parent / "fixtures" / "skills_roi_report.json"
    base_report = json.loads(fixture.read_text(encoding="utf-8"))
    evo_rows = compute_skill_version_evolution(
        base_report,
        skills_repo=skills_repo,
        usage_jsonl=usage_jsonl,
        warehouse_db=warehouse_db,
    )
    by_skill = {row["skill"]: row for row in evo_rows}
    assert set(by_skill) == {"alpha-skill", "beta-skill", "gamma-skill", "delta-skill", "epsilon-skill"}

    alpha_row = by_skill["alpha-skill"]
    assert alpha_row["status"] == "improved"
    assert alpha_row["status_label"] == "✅ 有效演进"
    assert alpha_row["semver"] == "1.1.0"
    assert alpha_row["combined_version"] == f"1.1.0+{alpha_v2['skill_version']}"
    assert alpha_row["before_version"]["skill_version"] == alpha_v1["skill_version"]
    assert alpha_row["before_version"]["exit2_error_rate"] == 0.5
    assert alpha_row["before_version"]["broken_drawer_count"] == 2
    assert alpha_row["before_version"]["script_p50_ms"] == 450.0
    assert alpha_row["before_version"]["r1_pass_rate"] == 0.5
    assert alpha_row["current_version"]["skill_version"] == alpha_v2["skill_version"]
    assert alpha_row["current_version"]["exit2_error_rate"] == 0.0
    assert alpha_row["current_version"]["post_fix_errors"] == 0
    assert alpha_row["current_version"]["broken_drawer_count"] == 0
    assert alpha_row["current_version"]["script_p50_ms"] == 120.0
    assert alpha_row["current_version"]["uptake_rate"] == 0.95
    assert alpha_row["current_version"]["r1_pass_rate"] == 1.0
    assert alpha_row["delta"]["exit2_error_rate_delta"] == -0.5
    assert alpha_row["delta"]["broken_drawer_delta"] == -2
    assert alpha_row["delta"]["script_p50_ms_delta"] == -330.0
    assert alpha_row["delta"]["uptake_rate_delta"] == 0.45
    assert alpha_row["delta"]["r1_pass_rate_delta"] == 0.5
    assert "exit2_error_rate" in alpha_row["delta"]["improved_dimensions"]
    assert "broken_drawer_count" in alpha_row["delta"]["improved_dimensions"]
    assert "script_p50_ms" in alpha_row["delta"]["improved_dimensions"]

    beta_row = by_skill["beta-skill"]
    assert beta_row["status"] == "regressed"
    assert beta_row["status_label"] == "⚠️ 退化告警"
    assert beta_row["current_version"]["exit2_count"] == 2
    assert beta_row["current_version"]["exit2_error_rate"] == 0.4
    assert beta_row["delta"]["exit2_count_delta"] == 2

    gamma_row = by_skill["gamma-skill"]
    assert gamma_row["status"] == "observing"
    assert gamma_row["status_label"] == "⏳ 样本积累中"
    assert gamma_row["current_version"]["sessions"] == 2

    delta_row = by_skill["delta-skill"]
    assert delta_row["status"] == "baseline"
    assert delta_row["status_label"] == "🕰️ 基准版本"
    assert delta_row["before_version"] is None
    assert delta_row["sample_size"] == 3
    assert delta_row["coverage_status"] == "healthy"

    epsilon_row = by_skill["epsilon-skill"]
    assert epsilon_row["status"] == "baseline"
    assert epsilon_row["sample_size"] == 0
    assert epsilon_row["coverage_status"] == "unknown"
    assert epsilon_row["source_as_of"] is None

    # Verify write_snapshot exports skill_version_evolution at root and under diagnostics
    report_path = tmp_path / "report.json"
    report_path.write_text(json.dumps(base_report), encoding="utf-8")
    output_path = tmp_path / "skills-roi.json"
    snapshot = write_snapshot(
        output_path,
        report_path,
        query_runner=lambda name, params: (
            [("2026-11-11", "copilot_cli_skill", "team-lead", 2, 1)],
            ["day", "source", "skill", "n", "sessions"],
        ),
        skills_repo=skills_repo,
        usage_jsonl=usage_jsonl,
        warehouse_db=warehouse_db,
    )
    assert snapshot["coverage_status"] == "healthy"
    assert "errors" not in snapshot
    assert isinstance(snapshot["skill_version_evolution"], list)
    assert len(snapshot["skill_version_evolution"]) == 5
    assert snapshot["diagnostics"]["skill_version_evolution"] == snapshot["skill_version_evolution"]

    # Direct classify_skill_version_evolution edge cases (R1 regression, latency regression, uptake regression)
    st_r1_reg, d_r1_reg = classify_skill_version_evolution(
        {"sessions": 6, "exit2_count": 0, "exit2_error_rate": 0.0, "broken_drawer_count": 0, "script_p50_ms": 100.0, "uptake_rate": 0.9, "r1_pass_rate": 1.0},
        {"sessions": 6, "exit2_count": 0, "exit2_error_rate": 0.0, "broken_drawer_count": 0, "script_p50_ms": 100.0, "uptake_rate": 0.9, "r1_pass_rate": 0.5},
    )
    assert st_r1_reg == "regressed"
    assert "r1_pass_rate" in d_r1_reg["regressed_dimensions"]

    st_lat_reg, d_lat_reg = classify_skill_version_evolution(
        {"sessions": 6, "exit2_count": 0, "exit2_error_rate": 0.0, "broken_drawer_count": 0, "script_p50_ms": 200.0, "uptake_rate": 0.9, "r1_pass_rate": 1.0},
        {"sessions": 6, "exit2_count": 0, "exit2_error_rate": 0.0, "broken_drawer_count": 0, "script_p50_ms": 950.0, "uptake_rate": 0.9, "r1_pass_rate": 1.0},
    )
    assert st_lat_reg == "regressed"
    assert "script_p50_ms" in d_lat_reg["regressed_dimensions"]

    st_up_reg, d_up_reg = classify_skill_version_evolution(
        {"sessions": 6, "exit2_count": 0, "exit2_error_rate": 0.0, "broken_drawer_count": 0, "script_p50_ms": 200.0, "uptake_rate": 0.9, "r1_pass_rate": 1.0},
        {"sessions": 6, "exit2_count": 0, "exit2_error_rate": 0.0, "broken_drawer_count": 0, "script_p50_ms": 180.0, "uptake_rate": 0.6, "r1_pass_rate": 1.0},
    )
    assert st_up_reg == "regressed"
    assert "uptake_rate" in d_up_reg["regressed_dimensions"]

    # Verify validation of invalid skill_version_evolution entries
    invalid_evo_report = {
        **base_report,
        "skill_version_evolution": [{"skill": "broken", "semver": "1.0.0", "skill_version": "v1@abc", "status": "invalid_state", "current_version": {}}],
    }
    bad_snap = build_snapshot(invalid_evo_report, [])
    assert bad_snap["coverage_status"] == "error"
    assert any("skill_version_evolution[0].status invalid" in err for err in bad_snap.get("errors", []))



# ---------------------------------------------------------------------------
# Loop 6B (`loop-apple-crash-metrickit`): Apple Crash & MetricKit Quality Loop
# ---------------------------------------------------------------------------

@pytest.mark.unit
def test_metrickit_and_ips_extract_top_app_responsible_frame(tmp_path, crash_loop):
    import json

    from L5_apps.digest import apple_crash_metrickit_loop as acm

    metrickit_payload = {
        "app_name": "AIDash",
        "platform": "macOS",
        "crashDiagnostics": [
            {
                "exceptionType": "EXC_BREAKPOINT",
                "exceptionCode": "0x0000000000000001",
                "signal": "SIGTRAP",
                "terminationReason": "Swift runtime failure: unexpectedly found nil",
                "callStackTree": {
                    "callStacks": [
                        {
                            "threadAttributed": True,
                            "callStackRootFrames": [
                                {
                                    "binaryName": "libsystem_kernel.dylib",
                                    "symbol": "__pthread_kill",
                                    "subFrames": [
                                        {
                                            "binaryName": "SwiftUI",
                                            "symbol": "$s7SwiftUI19ViewGraphHostUpdateV",
                                            "subFrames": [
                                                {
                                                    "binaryName": "AIDashApp",
                                                    "symbol": "MenuBarController.refreshBriefing() (MenuBarController.swift:142)",
                                                    "file": "Apps/AIDashApp/MenuBarController.swift",
                                                    "line": 142,
                                                }
                                            ],
                                        }
                                    ],
                                }
                            ],
                        }
                    ]
                },
            }
        ],
        "hangDiagnostics": [
            {
                "hangDuration": "780ms",
                "callStackTree": {
                    "callStacks": [
                        {
                            "threadAttributed": True,
                            "callStackRootFrames": [
                                {
                                    "binaryName": "AppKit",
                                    "symbol": "-[NSApplication run]",
                                    "subFrames": [
                                        {
                                            "binaryName": "AIDashUI",
                                            "symbol": "BriefingGridView.layoutCards()",
                                            "file": "BriefingGridView.swift",
                                            "line": 88,
                                        }
                                    ],
                                }
                            ],
                        }
                    ]
                },
            }
        ],
    }

    parsed_mk = acm.parse_metrickit_payload(metrickit_payload)
    assert len(parsed_mk) == 2
    crash_finding = next(f for f in parsed_mk if f.event_kind == "crash")
    assert crash_finding.app_name == "AIDash"
    assert crash_finding.responsible_file_line == "MenuBarController.swift:142"
    assert crash_finding.is_new_crash_signature is False

    hang_finding = next(f for f in parsed_mk if f.event_kind == "hang")
    assert hang_finding.responsible_file_line == "BriefingGridView.swift:88"
    assert hang_finding.hang_duration_ms == 780.0
    assert hang_finding.is_perf_regressed is False
    assert hang_finding.p95_metric_ms_7d is None

    ips_header = json.dumps({"app_name": "VoxPocket", "bug_type": "309"})
    ips_body = json.dumps({
        "procName": "VoxPocket",
        "faultingThread": 0,
        "usedImages": [
            {"name": "UIKitCore"},
            {"name": "VoxPocket"},
        ],
        "exception": {"type": "EXC_BAD_ACCESS", "signal": "SIGSEGV"},
        "threads": [
            {
                "triggered": True,
                "frames": [
                    {"imageIndex": 0, "symbol": "-[UIApplication sendAction:]"},
                    {
                        "imageIndex": 1,
                        "symbol": "AudioRecorderEngine.stopCapture()",
                        "sourceFile": "AudioRecorderEngine.swift",
                        "sourceLine": 215,
                    },
                ],
            }
        ],
    })
    ips_file = tmp_path / "VoxPocket-2026-11-19.ips"
    ips_file.write_text(f"{ips_header}\n{ips_body}\n", encoding="utf-8")

    parsed_ips = acm.parse_ips_text(ips_file.read_text(encoding="utf-8"))
    assert len(parsed_ips) == 1
    assert parsed_ips[0].app_name == "VoxPocket"
    assert parsed_ips[0].responsible_file_line == "AudioRecorderEngine.swift:215"


@pytest.mark.unit
def test_loop_6b_warehouse_join_jev_truth_table_and_dual_zone_verification(tmp_path, crash_loop):
    from L5_apps.digest import apple_crash_metrickit_loop as acm

    cols = [
        "app_name",
        "platform",
        "total_events_7d",
        "crash_count_7d",
        "new_crash_signature_count",
        "crash_free_rate_7d",
        "signature",
        "stack_top_symbol",
        "p95_metric_ms_7d",
        "p95_metric_ms_prev_7d",
        "p95_regression_pct",
        "is_perf_regressed",
    ]
    rows = [
        (
            "AIDash",
            "macOS",
            120,
            2,
            1,
            0.9833,
            "SIGTRAP_MenuBar",
            "MenuBarController.swift:142",
            280.0,
            200.0,
            40.0,
            1,
        ),
        (
            "VitalStride",
            "iOS",
            90,
            0,
            0,
            1.0,
            "cold_start_ms",
            "WorkoutViewModel.swift:56",
            180.0,
            175.0,
            2.86,
            0,
        ),
    ]

    asc_fixture = {
        "app_name": "Financial",
        "occurred_at": "2026-11-19T10:00:00+08:00",
        "diagnosticSignatures": [
            {
                "id": "asc-sig-01",
                "attributes": {
                    "diagnosticType": "CRASHES",
                    "signature": "LedgerSyncService.swift:91",
                    "weight": 3,
                },
                "diagnosticLogs": [
                    {
                        "frames": [
                            {"binaryName": "Foundation", "symbol": "NSJSONSerialization"},
                            {
                                "binaryName": "Financial",
                                "symbol": "LedgerSyncService.parseRow()",
                                "file": "LedgerSyncService.swift",
                                "line": 91,
                            },
                        ]
                    }
                ],
            }
        ],
    }

    collected = acm.collect_crash_and_metrickit_diagnostics(
        target_date="2026-11-19",
        fixture_json=asc_fixture,
        query_runner=lambda _name: (rows, cols),
    )
    assert collected["ok"] is True
    assert collected["loop_id"] == "loop-apple-crash-metrickit"
    assert collected["has_delta"] is True
    assert collected["new_crash_signature_count"] == 2
    assert collected["perf_regressed_count"] == 1
    assert collected["max_p95_regression_pct"] == 40.0

    # Verify Dual-Zone Markdown compliance (<= 15 Upper Zone lines, valid cursor, zero forbidden tokens)
    ver = acm.verify_dual_zone_markdown(collected["dual_zone_markdown"])
    assert ver["ok"] is True, ver["violations"]
    assert ver["human_zone_lines"] <= 15
    assert ver["cursor"] == "loop-apple-crash-metrickit-2026-11-19"

    # Layer 1 Jev truth table:
    # 1) High confidence (>0.70) -> actionable = True
    v_high = acm.evaluate_jev_decision(
        collected,
        mock_jev_json={
            "answers": {
                "actionable_probability": {"noul": 0.88},
                "delivery_route": {"choice": "dual_zone_issue"},
                "delivery_route_match": {"noul": 0.91},
                "urgency_score": {"score": 0.82},
            }
        },
    )
    assert v_high["actionable"] is True
    assert v_high["decision_source"] == "jev_high_confidence"

    # 2) Low confidence (<0.30) -> actionable = False
    v_low = acm.evaluate_jev_decision(
        collected,
        mock_jev_json={
            "answers": {
                "actionable_probability": {"noul": 0.15},
                "delivery_route": {"choice": "ignore"},
                "delivery_route_match": {"noul": 0.85},
                "urgency_score": {"score": 0.10},
            }
        },
    )
    assert v_low["actionable"] is False
    assert v_low["decision_source"] == "jev_choice_ignore"

    # 3) Grey zone (0.30..0.70) -> deterministic fallback (True because new_crash > 0 & p95 > 20%)
    v_grey = acm.evaluate_jev_decision(
        collected,
        mock_jev_json={
            "answers": {
                "actionable_probability": {"noul": 0.50},
                "delivery_route": {"choice": "dual_zone_issue"},
                "delivery_route_match": {"noul": 0.60},
                "urgency_score": {"score": 0.55},
            }
        },
    )
    assert v_grey["actionable"] is True
    assert v_grey["decision_source"] == "jev_grey_zone_fallback"

    # 4) Offline fallback -> deterministic fallback
    v_offline = acm.evaluate_jev_decision(collected, jev_fn=lambda **_kw: None)
    assert v_offline["actionable"] is True
    assert v_offline["decision_source"] == "deterministic_fallback_unavailable"

    # Layer 2 pipeline dry-run + watermark dedup
    state_file = tmp_path / "watermarks.json"
    run_res = acm.run_loop_pipeline(
        target_date="2026-11-19",
        fixture_json=asc_fixture,
        state_path=state_file,
        dry_run=True,
        query_runner=lambda _name: (rows, cols),
        mock_jev_json={"answers": {"actionable_probability": {"noul": 0.90}}},
    )
    assert run_res["status"] == "ACTIONABLE_DRY_RUN"
    assert run_res["layer_reached"] == 2
    assert run_res["delivery"]["dual_zone_verification"]["ok"] is True


@pytest.fixture
def crash_loop(tmp_path, monkeypatch):
    from L5_apps.digest import apple_crash_metrickit_loop as loop

    monkeypatch.setattr(loop, "HOME", tmp_path)
    monkeypatch.setattr(loop, "DEFAULT_DIAGNOSTICS_DIRS", (tmp_path / "absent",))
    monkeypatch.setattr(loop, "DEFAULT_WATERMARK_PATH", tmp_path / "state.json")
    return loop


def _crash_fixture(when="2026-11-19T10:00:00+08:00", signature="known-crash"):
    return {
        "timeStampEnd": when,
        "crashDiagnostics": [{
            "signature": signature,
            "diagnosticMetaData": {"exceptionType": "EXC_BAD_ACCESS"},
            "callStackTree": {"callStacks": [{
                "threadAttributed": True,
                "callStackRootFrames": [{
                    "binaryName": "Foundation", "symbolName": "system",
                    "subFrames": [{"binaryName": "AIDashApp", "symbolName": "refresh()",
                                   "fileName": "Refresh.swift", "lineNumber": "42"}],
                }],
            }]},
        }],
    }


@pytest.mark.unit
@pytest.mark.parametrize("prob,route,match,expected", [
    (0.71, "ignore", 1, True), (0.29, "dual_zone_issue", 1, False),
    (0.30, "dual_zone_issue", 1, True), (0.70, "dual_zone_issue", 1, True),
    (0.55, "ignore", None, True), (0.55, "ignore", 0.49, True),
    (0.55, "ignore", 0.50, False), (0.70, "ignore", 0.50, False),
])
def test_crash_jev_boundaries(crash_loop, prob, route, match, expected):
    verdict = crash_loop.evaluate_jev_decision(
        {"new_crash_signature_count": 1},
        mock_jev_json={"actionable_probability": prob, "delivery_route": route, "delivery_route_match": match},
    )
    assert verdict["actionable"] is expected


@pytest.mark.unit
@pytest.mark.parametrize("when,expected", [
    ("2026-11-12T23:59:59+08:00", False), ("2026-11-13T00:00:00+08:00", True),
    ("2026-11-19T23:59:59+08:00", True), ("2026-11-20T00:00:00+08:00", False),
    ("", False),
])
def test_crash_raw_window_and_unknown_timestamp(crash_loop, when, expected):
    result = crash_loop.collect_crash_and_metrickit_diagnostics(
        target_date="2026-11-19", fixture_json=_crash_fixture(when),
    )
    assert result["has_delta"] is expected
    if when == "2026-11-20T00:00:00+08:00":
        assert not result["all_findings"]
    else:
        assert result["all_findings"][0]["responsible_file_line"] == "Refresh.swift:42"


@pytest.mark.unit
def test_crash_prior_raw_history_and_warehouse_override(crash_loop):
    old, recent = _crash_fixture("2026-10-01T10:00:00Z"), _crash_fixture()
    result = crash_loop.collect_crash_and_metrickit_diagnostics(
        target_date="2026-11-19", fixture_json=[old, recent],
    )
    assert not result["has_delta"]
    result = crash_loop.collect_crash_and_metrickit_diagnostics(
        target_date="2026-11-19", fixture_json=recent,
        query_runner=lambda _: ([("AIDash", "known-crash", 0, 5)],
                                ["app_name", "signature", "new_crash_signature_count", "crash_count_7d"]),
    )
    assert not result["has_delta"]


@pytest.mark.unit
def test_crash_sql_exact_twenty_percent_and_historical_signatures(crash_loop, tmp_path):
    import sqlite3

    database = tmp_path / "warehouse.db"
    with sqlite3.connect(database) as db:
        db.execute("""CREATE TABLE fact_product_telemetry (
            event_id TEXT PRIMARY KEY, app_name TEXT, platform TEXT, event_kind TEXT,
            signature TEXT, stack_top_symbol TEXT, metric_ms REAL, occurred_at TEXT,
            cst_day TEXT GENERATED ALWAYS AS (date(occurred_at, '+8 hours')) STORED)""")
        db.executemany("INSERT INTO fact_product_telemetry VALUES (?,?,?,?,?,?,?,?)", [
            ("old-crash", "AIDash", "macOS", "crash", "old", "Refresh.swift:42", None, "2026-11-08T10:00:00Z"),
            ("repeat", "AIDash", "macOS", "crash", "old", "Refresh.swift:42", None, "2026-11-19T10:00:00Z"),
            ("base", "AIDash", "macOS", "perf", "load", "Refresh.swift:42", 100, "2026-11-08T10:00:00Z"),
            ("current", "AIDash", "macOS", "perf", "load", "Refresh.swift:42", 120, "2026-11-19T10:00:00Z"),
        ])
    def collect():
        return crash_loop.collect_crash_and_metrickit_diagnostics(
            target_date="2026-11-19", diagnostics_dir=tmp_path / "none", warehouse_db=database)
    assert not collect()["has_delta"]
    with sqlite3.connect(database) as db:
        db.execute("UPDATE fact_product_telemetry SET metric_ms=120.01 WHERE event_id='current'")
    assert collect()["perf_regressed_count"] == 1
    assert collect()["new_crash_signature_count"] == 0
    with sqlite3.connect(database) as db:
        db.execute("UPDATE fact_product_telemetry SET signature='new' WHERE event_id='repeat'")
    assert collect()["new_crash_signature_count"] == 1


@pytest.mark.unit
def test_crash_xcresult_bundle_asc_nested_and_hang_are_not_fabricated_p95(crash_loop, tmp_path):
    import json

    bundle = tmp_path / "report.xcresult"
    bundle.mkdir()
    (bundle / "summary.json").write_text(json.dumps({
        "finishTime": 1795075200,
        "testFailures": [{"targetName": "VoxPocketTests", "failureText": "Crash: EXC_BAD_ACCESS"}],
    }))
    findings = crash_loop._scan_diagnostics_dir(tmp_path)
    assert findings[0].source_kind == "xcresult"
    assert findings[0].event_kind == "crash"
    asc = {
        "productData": [{"signatureId": "downloaded", "diagnosticLogs": [{
            "diagnosticMetaData": {"event": "hang"},
            "hangDuration": "2 s",
            "callStackTree": [{"callStacks": [{"callStackRootFrames": [{
                "binaryName": "Financial", "symbolName": "sync()", "fileName": "Sync.swift", "lineNumber": "12",
            }]}]}],
        }]}],
    }
    parsed = crash_loop.parse_asc_diagnostics_payload(asc)
    assert parsed[0].responsible_file_line == "Sync.swift:12"
    assert parsed[0].hang_duration_ms == 2000
    assert parsed[0].p95_metric_ms_7d is None
    assert not parsed[0].is_perf_regressed
    ips = {"procName": "AIDash", "bug_type": "298", "threads": []}
    assert crash_loop.parse_ips_text(json.dumps(ips))[0].event_kind == "hang"


@pytest.mark.unit
def test_crash_missing_sources_degrade_without_falcon_or_mutation(crash_loop, tmp_path):
    def forbidden(**_):
        pytest.fail("must stop at L0 without evidence")
    result = crash_loop.run_loop_pipeline(
        target_date="2026-11-19", warehouse_db=tmp_path / "missing.db", dry_run=True, jev_fn=forbidden,
    )
    assert result["status"] == "SKIPPED_NO_DELTA"
    assert result["token_cost"] == 0
    assert result["collected"]["coverage_status"] == "missing"
    assert "数据覆盖不足" in result["collected"]["summary"]
    assert not (tmp_path / "missing.db").exists()
    assert not (tmp_path / "state.json").exists()


@pytest.mark.unit
def test_crash_delivery_route_state_retry_and_cross_day_dedup(crash_loop, tmp_path):
    import json
    import subprocess

    calls = []
    def runner(args, **_):
        calls.append(args)
        if args[:2] == ["autopilot", "list"]:
            return subprocess.CompletedProcess(args, 0, json.dumps([{"id": "fixture-autopilot", "title": crash_loop.AUTOPILOT_TITLE}]))
        return subprocess.CompletedProcess(args, 0, "{}")
    kwargs = {"target_date": "2026-11-19", "fixture_json": _crash_fixture(),
              "server_url": "http://fixture.invalid", "workspace_id": "fixture-workspace", "owner_id": "fixture-owner", "runner": runner,
              "mock_jev_json": {"actionable_probability": .9, "delivery_route": "autopilot_trigger", "delivery_route_match": .9}}
    dry = crash_loop.run_loop_pipeline(**kwargs, dry_run=True)
    assert dry["delivery"]["action"] == "dry_run_autopilot_trigger"
    assert not calls and not (tmp_path / "state.json").exists()
    delivered = crash_loop.run_loop_pipeline(**kwargs)
    assert delivered["delivery"]["action"] == "triggered_autopilot"
    assert ["autopilot", "trigger", "fixture-autopilot", "--output", "json"] in calls
    assert (tmp_path / ".cache" / "multica-loop-runner" / f"{crash_loop.LOOP_ID}-collect.json").is_file()
    kwargs["target_date"] = "2026-11-20"
    calls.clear()
    assert crash_loop.run_loop_pipeline(**kwargs)["status"] == "SKIPPED_NO_DELTA"
    assert calls == []


@pytest.mark.unit
def test_crash_failed_delivery_does_not_consume_watermark(crash_loop, tmp_path):
    import subprocess

    with pytest.raises(RuntimeError):
        crash_loop.run_loop_pipeline(
            target_date="2026-11-19", fixture_json=_crash_fixture(),
            server_url="http://fixture.invalid", workspace_id="workspace", owner_id="owner",
            mock_jev_json={"actionable_probability": .9},
            runner=lambda args, **_: subprocess.CompletedProcess(args, 1, "", "offline"),
        )
    assert not (tmp_path / "state.json").exists()


@pytest.mark.unit
@pytest.mark.parametrize("failure", [False, True])
def test_crash_autopilot_schedule_reconciliation_and_failure(crash_loop, failure):
    import json
    import subprocess

    calls = []
    def runner(args, **_):
        calls.append(args)
        value = {}
        if args[:2] == ["autopilot", "list"]:
            value = [{"id": "fixture", "title": crash_loop.AUTOPILOT_TITLE}]
        if args[:2] == ["autopilot", "trigger-list"]:
            value = [{"id": "schedule", "kind": "schedule", "cron": "0 1 * * *", "timezone": "UTC"}]
        return subprocess.CompletedProcess(args, int(failure and args[1] == "trigger-update"), json.dumps(value), "failed")
    kwargs = {"server_url": "http://fixture.invalid", "workspace_id": "workspace", "agent_id": "agent", "subscriber_id": "owner", "runner": runner}
    if failure:
        with pytest.raises(RuntimeError):
            crash_loop.sync_autopilot(**kwargs)
    else:
        result = crash_loop.sync_autopilot(**kwargs)
        assert result["trigger_action"] == "updated"
        assert any("50 4 * * *" in call and "Asia/Shanghai" in call for call in calls)


@pytest.mark.unit
@pytest.mark.parametrize("existing", [False, True])
def test_crash_direct_issue_upsert_fallback_is_cursor_idempotent(crash_loop, existing):
    import json
    import subprocess

    calls = []
    def runner(args, **kwargs):
        calls.append((args, kwargs))
        result = {}
        if args[:2] == ["issue", "list"]:
            result = [{"id": "fixture-issue", "description": "<!-- multica-cursor:loop-apple-crash-metrickit-2026-11-19 -->"}] if existing else []
        return subprocess.CompletedProcess(args, 0, json.dumps(result))
    result = crash_loop.run_loop_pipeline(
        target_date="2026-11-19", fixture_json=_crash_fixture(),
        server_url="http://fixture.invalid", workspace_id="workspace", owner_id="owner",
        mock_jev_json={"actionable_probability": .9}, runner=runner,
    )
    assert result["delivery"]["action"] == ("updated" if existing else "created")
    assert calls[-1][0][1] == ("update" if existing else "create")
    assert crash_loop.verify_dual_zone_markdown(calls[-1][1]["stdin_text"])["ok"]


@pytest.mark.unit
def test_crash_shared_runner_is_used_when_installed(crash_loop, monkeypatch):
    from types import SimpleNamespace

    calls = []
    hub = SimpleNamespace(upsert_multica_dual_zone_issue=lambda **kwargs: calls.append(kwargs) or {"ok": True})
    monkeypatch.setattr(crash_loop, "_load_local_module", lambda *_: hub)
    crash_loop.run_loop_pipeline(
        target_date="2026-11-19", fixture_json=_crash_fixture(),
        server_url="http://fixture.invalid", workspace_id="workspace", owner_id="owner",
        mock_jev_json={"actionable_probability": .9},
    )
    assert len(calls) == 1
    assert calls[0]["cursor"] == "loop-apple-crash-metrickit-2026-11-19"
    assert calls[0]["assignee_id"] == "owner"


@pytest.mark.unit
@pytest.mark.parametrize("failed", [False, True])
def test_crash_autopilot_creation_checks_schedule_result(crash_loop, failed):
    import json
    import subprocess

    calls = []
    def runner(args, **_):
        calls.append(args)
        result = {"id": "new-autopilot"} if args[1] == "create" else [] if args[1] in ("list", "trigger-list") else {}
        return subprocess.CompletedProcess(args, int(failed and args[1] == "trigger-add"), json.dumps(result), "failed")
    kwargs = {"server_url": "http://fixture.invalid", "workspace_id": "workspace", "agent_id": "agent", "subscriber_id": "owner", "runner": runner}
    if failed:
        with pytest.raises(RuntimeError):
            crash_loop.sync_autopilot(**kwargs)
    else:
        assert crash_loop.sync_autopilot(**kwargs)["trigger_action"] == "created"
        assert sum(call[1] == "create" for call in calls) == 1


@pytest.mark.unit
def test_crash_export_redacts_secrets_and_keeps_source_paths_basename_only(crash_loop):
    import json

    fixture = _crash_fixture()
    diagnostic = fixture["crashDiagnostics"][0]
    diagnostic["terminationReason"] = "api_key=" + "sensitivevalue" * 3
    frame = diagnostic["callStackTree"]["callStacks"][0]["callStackRootFrames"][0]["subFrames"][0]
    frame["symbolName"] = f"refresh() at {crash_loop.HOME}/project/Refresh.swift:42"
    result = crash_loop.collect_crash_and_metrickit_diagnostics(target_date="2026-11-19", fixture_json=fixture)
    serialized = json.dumps(result)
    assert str(crash_loop.HOME) not in serialized
    assert "sensitivevalue" not in serialized
    assert "Refresh.swift:42" in serialized


@pytest.mark.unit
def test_pseudo_skills_filtered_and_skill_retro_4layer_fallback(tmp_path, monkeypatch):
    import json
    import sqlite3
    from pathlib import Path

    from adapters import bot_tl, release_tf
    from L5_apps.digest.skills_roi_snapshot import write_snapshot

    # 1. Verify SQL filters out pseudo-skill tokens ('tests', 'leepepe', 'pull', 'main')
    sql_path = Path(__file__).resolve().parent.parent / "L4_serve" / "queries" / "retro" / "skill_roi_diagnostics.sql"
    sql_text = sql_path.read_text(encoding="utf-8")
    wh = tmp_path / "wh_filter.db"
    with sqlite3.connect(wh) as conn:
        conn.execute(
            "CREATE TABLE fact_turn (turn_uuid TEXT, session_id TEXT, cst_day TEXT, attribution_skill TEXT, "
            "skill_names TEXT, tool_calls TEXT, input_tokens INTEGER, output_tokens INTEGER, cache_read INTEGER)"
        )
        conn.execute(
            "CREATE TABLE fact_gtt_task_run (goal_id TEXT, task_id TEXT, role_name TEXT, "
            "round_no INTEGER, v5_verdict TEXT, status TEXT, cst_day TEXT, skills_used TEXT)"
        )
        conn.execute(
            "CREATE TABLE fact_gtt_event (goal_id TEXT, evt_type TEXT, note_preview TEXT, cst_day TEXT, "
            "eval_case TEXT, interception INTEGER, \"escape\" INTEGER)"
        )
        conn.execute(
            "CREATE TABLE reference_hits (hit_uid TEXT, source TEXT, session_id TEXT, turn_uuid TEXT, "
            "skill TEXT, reference_path TEXT, byte_len INTEGER, ts TEXT)"
        )
        conn.execute(
            "CREATE TABLE script_call (call_uid TEXT, source TEXT, session_id TEXT, turn_uuid TEXT, "
            "skill TEXT, script_path TEXT, exit_code INTEGER, duration_ms INTEGER, ts TEXT)"
        )
        conn.executemany(
            "INSERT INTO fact_turn VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                ("u1", "s1", "2026-11-22", "team-lead", '["team-lead", "tests", "leepepe", "pull", "main"]', '["Bash"]', 1000, 200, 100),
                ("u2", "s2", "2026-11-22", "tests", '["tests"]', '["Read"]', 500, 100, 0),
                ("u3", "s3", "2026-11-22", "leepepe", '["pull"]', '["Read"]', 500, 100, 0),
            ],
        )
        rows = conn.execute(sql_text).fetchall()
    returned_skills = {r[0] for r in rows}
    assert "team-lead" in returned_skills
    assert returned_skills.isdisjoint({"tests", "leepepe", "pull", "main"})

    # 2. Verify skills_roi_snapshot filters pseudo-skills, emits skill_retro 4-layer health, and falls back when report is empty
    fixture = Path(__file__).parent / "fixtures" / "skills_roi_report.json"
    base_report = json.loads(fixture.read_text(encoding="utf-8"))
    polluted_report = {
        **base_report,
        "S10_skill_roi_ranking": [
            *base_report["S10_skill_roi_ranking"],
            {
                **base_report["S10_skill_roi_ranking"][0],
                "skill": "tests",
            },
            {
                **base_report["S10_skill_roi_ranking"][0],
                "skill": "leepepe",
            },
            {
                **base_report["S10_skill_roi_ranking"][0],
                "skill": "pull",
            },
        ],
    }
    report_file = tmp_path / "polluted-report.json"
    report_file.write_text(json.dumps(polluted_report), encoding="utf-8")
    out_file = tmp_path / "skills-roi.json"

    snap = write_snapshot(
        out_file,
        report_file,
        query_runner=lambda name, params: (
            [
                ("2026-11-11", "copilot_cli_skill", "team-lead", 2, 1),
                ("2026-11-11", "copilot_cli_skill", "tests", 9, 1),
            ],
            ["day", "source", "skill", "n", "sessions"],
        ),
    )
    s10_skills = {r["skill"] for r in snap["diagnostics"]["S10_skill_roi_ranking"]}
    daily_skills = {r["skill"] for r in snap["skills_daily"]}
    assert s10_skills == {"team-lead"}
    assert daily_skills == {"team-lead"}
    assert isinstance(snap.get("skill_retro"), dict)
    for k in (
        "summary",
        "layer0_direction_and_triggers",
        "layer1_drawer_metabolism",
        "layer2_script_efficacy_and_speed",
        "layer3_wild_patterns_and_eval",
        "proposals",
    ):
        assert k in snap["skill_retro"]

    # Simulate Stage 3 timeout leaving an empty report file: fallback preserves prior diagnostics & 4-layer skill_retro
    empty_report = tmp_path / "empty-report.json"
    empty_report.write_text("", encoding="utf-8")
    fallback_snap = write_snapshot(
        out_file,
        empty_report,
        producer_exit_code=124,
        query_runner=lambda name, params: (
            [("2026-11-11", "copilot_cli_skill", "team-lead", 2, 1)],
            ["day", "source", "skill", "n", "sessions"],
        ),
    )
    assert fallback_snap["coverage_status"] == "error"
    assert any("124" in err for err in fallback_snap["errors"])
    assert fallback_snap["diagnostics"]["S10_skill_roi_ranking"][0]["skill"] == "team-lead"
    assert isinstance(fallback_snap["skill_retro"], dict)
    assert "layer0_direction_and_triggers" in fallback_snap["skill_retro"]

    # Subsequent healthy refresh recomputes skill_retro from new report rather than keeping stale prior skill_retro
    refreshed_report = {
        **base_report,
        "source_as_of": "2026-11-22T20:00:00+08:00",
        "S10_skill_roi_ranking": [
            {
                **base_report["S10_skill_roi_ranking"][0],
                "empty_load_sessions": 12,
            }
        ],
    }
    refreshed_file = tmp_path / "refreshed-report.json"
    refreshed_file.write_text(json.dumps(refreshed_report), encoding="utf-8")
    refreshed_snap = write_snapshot(
        out_file,
        refreshed_file,
        query_runner=lambda name, params: (
            [("2026-11-11", "copilot_cli_skill", "team-lead", 2, 1)],
            ["day", "source", "skill", "n", "sessions"],
        ),
    )
    assert refreshed_snap["skill_retro"]["source_as_of"] == "2026-11-22T20:00:00+08:00"
    assert refreshed_snap["skill_retro"]["summary"]["zero_action_load_skills"] == 1

    # 3. Verify bot_tl file_stats cache skips unchanged files and release_tf watermark skips completed runs
    goal_dir = tmp_path / "handoff" / "goal-a"
    goal_dir.mkdir(parents=True)
    ledger = goal_dir / "ledger.md"
    ledger.write_text("- 2026-11-22T10:00:00+08:00 | EVT=SPAWN_TL | id=B1 | note=init\n", encoding="utf-8")
    monkeypatch.setattr(bot_tl, "GTT_HANDOFF_ROOTS", (tmp_path / "handoff",))
    monkeypatch.setattr(bot_tl, "CLAUDE_QUOTA_CACHE", tmp_path / "no-quota.json")
    fstats: dict[str, str] = {}
    first_local = bot_tl._local_records(file_stats={}, new_file_stats=fstats)
    assert len(first_local) == 1
    second_local = bot_tl._local_records(file_stats=fstats, new_file_stats={})
    assert second_local == []

    wm_store: dict[str, object] = {
        "release_tf": {
            "LeePepe/AIDash": 500,
            "completed_runs": {"LeePepe/AIDash:500": "completed:1:success"},
        }
    }
    api_calls: list[str] = []
    monkeypatch.setattr(release_tf, "_REPOS", ("LeePepe/AIDash",))
    monkeypatch.setattr(
        release_tf,
        "read_raw",
        lambda _s: [
            {
                "delivery_uid": "LeePepe/AIDash:500",
                "repo_key": "LeePepe/AIDash",
                "run_id": 500,
                "status": "completed",
                "run_attempt": 1,
            },
            {
                "delivery_uid": "LeePepe/AIDash:490",
                "repo_key": "LeePepe/AIDash",
                "run_id": 490,
                "status": "in_progress",
                "run_attempt": 1,
                "delivery_outcome": "failed_signing_or_upload",
            },
        ],
    )
    monkeypatch.setattr(release_tf, "get_watermark", lambda k: wm_store.get(k))
    monkeypatch.setattr(release_tf, "set_watermark", lambda k, v: wm_store.__setitem__(k, v))
    monkeypatch.setattr(release_tf, "write_raw_snapshot", lambda _s, recs: len(recs))
    monkeypatch.setattr(
        release_tf,
        "_gh_api",
        lambda path: (
            api_calls.append(path)
            or (
                {
                    "workflow_runs": [
                        {"id": 500, "name": "TestFlight", "path": "release.yml", "status": "completed", "conclusion": "success", "run_attempt": 1},
                        {"id": 490, "name": "TestFlight", "path": "release.yml", "status": "completed", "conclusion": "success", "run_attempt": 1},
                    ]
                }
                if "jobs" not in path
                else {"jobs": [{"steps": [{"name": "Archive", "conclusion": "success"}, {"name": "Upload to TestFlight", "conclusion": "success"}, {"name": "Move last-released tag", "conclusion": "success"}]}]}
            )
        ),
    )
    assert release_tf.collect() == 2
    assert api_calls == [
        "repos/LeePepe/AIDash/actions/runs?per_page=25",
        "repos/LeePepe/AIDash/actions/runs/490/jobs?per_page=100",
    ]



