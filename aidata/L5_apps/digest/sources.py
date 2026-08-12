"""Data-fetch layer for the digest.

Calls L4 trend queries and reshapes results into (day, value) series that the
trend math consumes. Each source fetch is wrapped in health tracking so a
failure degrades to an empty series + a SourceHealth state, never a crash
(ADR-23). M1 has one source (raven); M2+ add more here.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field

import serve
from config import MULTICA_WORKSPACES, clean_path


@dataclass(frozen=True)
class SourceHealth:
    name: str
    state: str          # ok | skipped:* | stale | error
    detail: str = ""


@dataclass(frozen=True)
class RavenTrends:
    cost: list[tuple[str, float]]
    tokens: list[tuple[str, float]]
    requests: list[tuple[str, float]]
    waste: list[tuple[str, float]]
    pipeline_completed: list[tuple[str, float]]
    pipeline_cancelled: list[tuple[str, float]]
    sessions: list[tuple[str, float]]
    health: SourceHealth


def _series(name: str, day_col: str, val_col: str) -> list[tuple[str, float]]:
    rows, cols = serve.run_query(name)
    di, vi = cols.index(day_col), cols.index(val_col)
    return [(r[di], float(r[vi]) if r[vi] is not None else 0.0) for r in rows]


def fetch_raven_trends() -> RavenTrends:
    """Fetch all raven-derived trend series; degrade to empty + error health."""
    try:
        cost_rows, cost_cols = serve.run_query("trend/daily-cost")
        di = cost_cols.index("day")
        cost = [(r[di], float(r[cost_cols.index("cost_usd")] or 0)) for r in cost_rows]
        tokens = [(r[di], float(r[cost_cols.index("tokens")] or 0)) for r in cost_rows]
        requests = [(r[di], float(r[cost_cols.index("requests")] or 0)) for r in cost_rows]
        waste = _series("trend/daily-waste", "day", "waste_usd")
        pipe_done = _series("trend/daily-pipeline", "day", "completed")
        pipe_cx = _series("trend/daily-pipeline", "day", "cancelled")
        sessions = _series("trend/daily-behavior", "day", "sessions")
        return RavenTrends(
            cost=cost, tokens=tokens, requests=requests, waste=waste,
            pipeline_completed=pipe_done, pipeline_cancelled=pipe_cx,
            sessions=sessions,
            health=SourceHealth(name="raven", state="ok"),
        )
    except Exception as exc:  # degrade, never crash the digest
        empty: list[tuple[str, float]] = []
        return RavenTrends(
            cost=empty, tokens=empty, requests=empty, waste=empty,
            pipeline_completed=empty, pipeline_cancelled=empty, sessions=empty,
            health=SourceHealth(name="raven", state="error", detail=str(exc)[:200]),
        )


_WS_NAMES = {ws_id: name for ws_id, name in MULTICA_WORKSPACES}


@dataclass(frozen=True)
class MulticaTrends:
    """Completed-issue trends from multica (EXT-3). `completed` is the total
    per CST day; `completed_by_ws` breaks it down by friendly workspace name."""
    completed: list[tuple[str, float]]
    completed_by_ws: dict[str, list[tuple[str, float]]]
    health: SourceHealth


def _accumulate(store: dict[str, float], key: str, val: float) -> None:
    store[key] = store.get(key, 0.0) + val


def fetch_multica_completed() -> MulticaTrends:
    """Fetch per-CST-day completed-issue counts (total + per workspace).

    Degrades to empty series + error health on any failure (ADR-23) — a multica
    CLI/warehouse problem never crashes the digest.
    """
    try:
        rows, cols = serve.run_query("trend/daily-completed")
        di = cols.index("day")
        wi = cols.index("workspace_id")
        ci = cols.index("completed")
        totals: dict[str, float] = {}
        per_ws: dict[str, dict[str, float]] = {}
        for r in rows:
            day = r[di]
            count = float(r[ci] or 0)
            name = _WS_NAMES.get(r[wi], r[wi] or "unknown")
            _accumulate(totals, day, count)
            _accumulate(per_ws.setdefault(name, {}), day, count)
        completed = sorted(totals.items(), key=lambda kv: kv[0], reverse=True)
        by_ws = {
            name: sorted(days.items(), key=lambda kv: kv[0], reverse=True)
            for name, days in per_ws.items()
        }
        return MulticaTrends(
            completed=completed, completed_by_ws=by_ws,
            health=SourceHealth(name="multica", state="ok"),
        )
    except Exception as exc:  # degrade, never crash the digest
        return MulticaTrends(
            completed=[], completed_by_ws={},
            health=SourceHealth(name="multica", state="error",
                                detail=str(exc)[:200]),
        )
# ---------------------------------------------------------------------------
# M3: ADO PR trends (fact_ado_pr) and automation ratio (state.db, L2-only).
# Both degrade to empty series + SourceHealth, never crash (ADR-23). A source
# that was never collected (no clean DB) reports "skipped:未采集" so the digest
# can distinguish "not collected" from "collected but zero" (ADR-23).
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class AdoPrTrends:
    opened: list[tuple[str, float]]
    merged: list[tuple[str, float]]
    health: SourceHealth


@dataclass(frozen=True)
class AutomationTrends:
    ratio: list[tuple[str, float]]
    automated: list[tuple[str, float]]
    manual: list[tuple[str, float]]
    health: SourceHealth


def _series_from(rows: list[tuple], cols: list[str], day_col: str,
                 val_col: str) -> list[tuple[str, float]]:
    di, vi = cols.index(day_col), cols.index(val_col)
    return [(r[di], float(r[vi]) if r[vi] is not None else 0.0) for r in rows]


def fetch_ado_pr_trends() -> AdoPrTrends:
    """Fetch per-CST-day ADO PRs opened/merged; degrade to empty + health.

    Single-host. The digest reads `fetch_combined_pr_trends` (both hosts) —
    this one is kept as a per-source view for ad-hoc use and for
    tests/test_sources_m3.py's degrade-safety cases, which need one host in
    isolation. NOT the seam _fetch_sources calls; freezing only this one in a
    fixture leaves the digest's PR line live (tech-context.md 坑 ①).
    """
    empty: list[tuple[str, float]] = []
    if not clean_path("ado_pr").exists():
        return AdoPrTrends(empty, empty,
                           SourceHealth("ado_pr", "skipped:未采集"))
    try:
        rows, cols = serve.run_query("trend/daily-ado-pr")
        return AdoPrTrends(
            opened=_series_from(rows, cols, "day", "opened"),
            merged=_series_from(rows, cols, "day", "merged"),
            health=SourceHealth("ado_pr", "ok"),
        )
    except Exception as exc:
        return AdoPrTrends(empty, empty,
                           SourceHealth("ado_pr", "error", str(exc)[:200]))


def fetch_github_pr_trends() -> AdoPrTrends:
    """Fetch per-CST-day GitHub PRs opened/merged; degrade to empty + health.

    Single-host twin of fetch_ado_pr_trends (same opened/merged/health shape);
    same caveat — the digest reads the union, not this. Kept for symmetry and
    ad-hoc per-host inspection.
    """
    empty: list[tuple[str, float]] = []
    if not clean_path("github_pr").exists():
        return AdoPrTrends(empty, empty,
                           SourceHealth("github_pr", "skipped:未采集"))
    try:
        rows, cols = serve.run_query("trend/daily-github-pr")
        return AdoPrTrends(
            opened=_series_from(rows, cols, "day", "opened"),
            merged=_series_from(rows, cols, "day", "merged"),
            health=SourceHealth("github_pr", "ok"),
        )
    except Exception as exc:
        return AdoPrTrends(empty, empty,
                           SourceHealth("github_pr", "error", str(exc)[:200]))


def fetch_combined_pr_trends() -> AdoPrTrends:
    """PRs opened/merged per CST day across BOTH hosts, for the 昨日汇总 line.

    The union itself lives in SQL (`trend/daily-pr`) — it is a composite metric
    definition, so it belongs at the metric layer, not here. This function is
    now only the degrade-safe wrapper (ADR-23): decide what to do when one or
    both sources were never collected, which is availability logic, not
    aggregation.

    Health is the healthier of the two: `ok` if either source collected (the
    query then legitimately reports the other as zero), else a combined
    skipped/error state so a total absence still degrades cleanly.
    """
    empty: list[tuple[str, float]] = []
    ado_present = clean_path("ado_pr").exists()
    gh_present = clean_path("github_pr").exists()
    if not ado_present and not gh_present:
        return AdoPrTrends(empty, empty, SourceHealth(
            "pr", "skipped:未采集", "ado=skipped:未采集; github=skipped:未采集"))
    try:
        rows, cols = serve.run_query("trend/daily-pr")
        return AdoPrTrends(
            opened=_series_from(rows, cols, "day", "opened"),
            merged=_series_from(rows, cols, "day", "merged"),
            health=SourceHealth("pr", "ok"),
        )
    except Exception as exc:
        return AdoPrTrends(empty, empty,
                           SourceHealth("pr", "error", str(exc)[:200]))


def fetch_automation_trends() -> AutomationTrends:
    """Fetch per-CST-day automation ratio from state.db; degrade to empty."""
    empty: list[tuple[str, float]] = []
    if not clean_path("state_db").exists():
        return AutomationTrends(empty, empty, empty,
                                SourceHealth("state_db", "skipped:未采集"))
    try:
        rows, cols = serve.run_query("trend/daily-automation")
        return AutomationTrends(
            ratio=_series_from(rows, cols, "day", "automation_ratio"),
            automated=_series_from(rows, cols, "day", "automated"),
            manual=_series_from(rows, cols, "day", "manual"),
            health=SourceHealth("state_db", "ok"),
        )
    except Exception as exc:
        return AutomationTrends(empty, empty, empty,
                                SourceHealth("state_db", "error", str(exc)[:200]))


@dataclass(frozen=True)
class ModelSpend:
    """One model's slice of all-time spend (from cost/pareto)."""
    model: str
    cost_usd: float
    pct_of_spend: float


@dataclass(frozen=True)
class CostImprovement:
    """All-time cost-improvement signals for the '可改良' card (§M1).

    Sourced from the already-built cost/* queries (all-time, not yesterday):
      - `top_models`: spend concentration (cost/pareto) — where the money goes.
      - `downgrade_usd` / `downgrade_requests`: opus used for <20-token outputs
        (cost/model-downgrade) — the concrete "switch to a cheaper model" prize.
    Degrades to empty + health on any query failure; the card falls back to the
    old markdown 可改良 body when this is unavailable.
    """
    top_models: list[ModelSpend]
    downgrade_usd: float
    downgrade_requests: int
    health: SourceHealth


def fetch_cost_improvement() -> CostImprovement:
    """Fetch all-time spend concentration + model-downgrade waste; degrade safe."""
    try:
        prows, pcols = serve.run_query("cost/pareto")
        mi = pcols.index("model")
        ci = pcols.index("cost_usd")
        pi = pcols.index("pct_of_spend")
        top = [
            ModelSpend(str(r[mi]), float(r[ci] or 0), float(r[pi] or 0))
            for r in prows[:3]
        ]
        drows, dcols = serve.run_query("cost/model-downgrade")
        wi = dcols.index("wasted_usd")
        ri = dcols.index("tiny_output_requests")
        waste = round(sum(float(r[wi] or 0) for r in drows), 2)
        reqs = sum(int(r[ri] or 0) for r in drows)
        return CostImprovement(
            top_models=top, downgrade_usd=waste, downgrade_requests=reqs,
            health=SourceHealth("cost", "ok"),
        )
    except Exception as exc:
        return CostImprovement([], 0.0, 0,
                               SourceHealth("cost", "error", str(exc)[:200]))


@dataclass(frozen=True)
class ValueEfficiency:
    """Research-backed '值不值' efficiency signals over a rolling window (§M1).

    Deliberately NOT a naive cost-per-issue ratio (research 2026-07-18: output
    is nearly free, LOC tracks token spend not value). Two computable metrics:
      - cost_per_completed_task: Σcost (incl. failed-task spend) / completed.
      - output_share_pct: output/total tokens — low ⇒ input/context-dominated.
    (cache-read ratio, the 3rd recommended metric, is omitted: raven doesn't
    capture cache tokens — a known data gap.)
    window_days records the rolling window for honest labeling.
    """
    total_cost: float
    completed_tasks: int
    cost_per_completed_task: float | None
    output_share_pct: float | None
    window_days: int
    health: SourceHealth


def fetch_value_efficiency(since: str | None, window_days: int = 7) -> ValueEfficiency:
    """Fetch cost-per-completed-task + output-share over [since, now]; degrade safe."""
    try:
        rows, cols = serve.run_query("roi/value-efficiency", {"since": since})
        if not rows:
            return ValueEfficiency(0.0, 0, None, None, window_days,
                                   SourceHealth("efficiency", "skipped:无数据"))
        r = rows[0]

        def _g(name):
            return r[cols.index(name)]

        return ValueEfficiency(
            total_cost=float(_g("total_cost") or 0),
            completed_tasks=int(_g("completed_tasks") or 0),
            cost_per_completed_task=(
                float(_g("cost_per_completed_task"))
                if _g("cost_per_completed_task") is not None else None),
            output_share_pct=(
                float(_g("output_share_pct"))
                if _g("output_share_pct") is not None else None),
            window_days=window_days,
            health=SourceHealth("efficiency", "ok"),
        )
    except Exception as exc:
        return ValueEfficiency(0.0, 0, None, None, window_days,
                               SourceHealth("efficiency", "error", str(exc)[:200]))


@dataclass(frozen=True)
class ProjectWork:
    """One project's effort for the '做了什么' card (§M2)."""
    project: str
    turns: int
    out_ktok: float
    sessions: int


@dataclass(frozen=True)
class WorkByProject:
    """Yesterday's effort split by project (fact_turn.project).

    Answers goal ① "做了什么": which projects got worked on and how much.
    `projects` is ordered by turns desc; degrades to empty + health on failure.
    """
    projects: list[ProjectWork]
    health: SourceHealth


def fetch_work_by_project(since: str | None, until: str | None) -> WorkByProject:
    """Fetch per-project effort over [since, until); degrade safe."""
    try:
        rows, cols = serve.run_query(
            "work/by-project", {"since": since, "until": until})
        pi = cols.index("project")
        ti = cols.index("turns")
        ki = cols.index("out_ktok")
        si = cols.index("sessions")
        projects = [
            ProjectWork(str(r[pi]), int(r[ti] or 0),
                        float(r[ki] or 0), int(r[si] or 0))
            for r in rows
        ]
        return WorkByProject(projects, SourceHealth("work", "ok"))
    except Exception as exc:
        return WorkByProject([], SourceHealth("work", "error", str(exc)[:200]))


# ---------------------------------------------------------------------------
# Fetched-source bundle. Lets the orchestrator fetch every trend series ONCE
# and hand the same immutable snapshot to both the Markdown renderer and the
# AIDash payload builder (avoids a double fetch; ADR-16). Pure data — no I/O.
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class DigestSources:
    raven: RavenTrends
    multica: MulticaTrends
    ado: AdoPrTrends
    automation: AutomationTrends
    # Optional so existing constructors (tests, older callers) keep working;
    # defaults to an empty/degraded improvement bundle. Populated by
    # _fetch_sources() in the real pipeline.
    cost_improvement: "CostImprovement" = field(
        default_factory=lambda: CostImprovement(
            [], 0.0, 0, SourceHealth("cost", "skipped:未取")
        )
    )
    value_efficiency: "ValueEfficiency" = field(
        default_factory=lambda: ValueEfficiency(
            0.0, 0, None, None, 7, SourceHealth("efficiency", "skipped:未取")
        )
    )
    work_by_project: "WorkByProject" = field(
        default_factory=lambda: WorkByProject(
            [], SourceHealth("work", "skipped:未取")
        )
    )
    # Action inbox (§M3): prioritized "需要处理什么" list. list[InboxItem];
    # kept as a plain list to avoid a hard import cycle. Empty by default.
    action_inbox: list = field(default_factory=list)
    # GitHub tool-radar (§radar): curated watchlist stars/delta + enrichment.
    # Defaults to a skipped/empty bundle so older constructors keep working;
    # populated by _fetch_sources() in the real pipeline. RepoRadar is defined
    # later in this module — the factory resolves it lazily at instantiation.
    repo_radar: "RepoRadar" = field(
        default_factory=lambda: RepoRadar([], SourceHealth("github_repo",
                                                           "skipped:未取"))
    )
    # ── batch-2 (L5 数据接入批2): AI 效能 + 时间与产出 + 新闻雷达 ──
    # Each defaults to a skipped/empty bundle so older constructors (tests, the
    # golden fixture) keep working unchanged; _fetch_sources() populates them in
    # the real pipeline. All degrade-safe (ADR-23): a failed/empty fetch yields a
    # non-"ok" health so the producer omits that card/container.
    ai_efficiency: "AiEfficiency" = field(
        default_factory=lambda: AiEfficiency.empty()
    )
    app_focus: "RankBundle" = field(
        default_factory=lambda: RankBundle([], SourceHealth("gecko", "skipped:未取"))
    )
    # ── attribution (§07-17 目标⑤「为什么」): the cross-source layer ──
    # Every other bundle above is single-dimension. These two answer "why did
    # the number move", which no trend arrow can.
    cost_by_project: "RankBundle" = field(
        default_factory=lambda: RankBundle([], SourceHealth("attribution", "skipped:未取"))
    )
    model_by_project: "RankBundle" = field(
        default_factory=lambda: RankBundle([], SourceHealth("attribution", "skipped:未取"))
    )
    leverage: "Leverage" = field(default_factory=lambda: Leverage.empty())
    rework_by_workspace: "RankBundle" = field(
        default_factory=lambda: RankBundle([], SourceHealth("multica_run", "skipped:未取"))
    )
    tool_cross: "RankBundle" = field(
        default_factory=lambda: RankBundle([], SourceHealth("hermes_messages", "skipped:未取"))
    )
    commit_by_repo: "RankBundle" = field(
        default_factory=lambda: RankBundle([], SourceHealth("local_git", "skipped:未取"))
    )
    news_radar: "NewsRadar" = field(
        default_factory=lambda: NewsRadar([], SourceHealth("news", "skipped:未取"))
    )
    model_tier: "ModelTier" = field(
        default_factory=lambda: ModelTier([], SourceHealth("state_db", "skipped:未取"))
    )
    # 你最常收藏的卡型 Top-N (spec 005 T007/US5): whole-card star interest, most-
    # starred first. Defaults to a skipped/empty bundle so older constructors
    # (tests, golden fixture) keep working; _fetch_sources() populates it in the
    # real pipeline. CardInterest is defined later in this module (same
    # forward-ref pattern as RepoRadar/AiEfficiency above).
    card_interest: "CardInterest" = field(
        default_factory=lambda: CardInterest(
            [], SourceHealth("aidash_events", "skipped:未取")
        )
    )
    # 交叉信号 (§design 4.2): rework tokens crossed by workspace × root cause.
    # The first genuinely two-dimensional bundle here — everything above is a
    # series or a ranking, which is why none of them can carry a relationship
    # card. Defaults to a skipped/empty bundle so older constructors keep
    # working; _fetch_sources() populates it in the real pipeline.
    rework_relationship: "ReworkRelationship" = field(
        default_factory=lambda: ReworkRelationship.empty()
    )


# ---------------------------------------------------------------------------
# GitHub tool-radar (§radar): the curated watchlist's daily stars + delta,
# enriched with LLM category / related-project / tier. Degrades to empty +
# health on any failure (query, warehouse, or LLM) — never crashes the digest.
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class RepoRadar:
    cards: list          # list[repo_radar.RepoCard], ordered by stars desc
    health: SourceHealth


def fetch_known_projects(limit: int = 12) -> list[str]:
    """Distinct project names the user actually works on (for repo↔project match).

    Reads work/by-project all-time (bare, no window) and returns the top project
    names by effort. Degrades to [] on any failure — enrichment then just never
    proposes a related project.
    """
    try:
        rows, cols = serve.run_query("work/by-project")
        pi = cols.index("project")
        return [str(r[pi]) for r in rows[:limit] if r[pi]]
    except Exception:  # noqa: BLE001 - optional signal; never fatal
        return []


def fetch_repo_radar(client=None) -> RepoRadar:
    """Fetch the radar query, enrich each repo, return an immutable bundle.

    A repo that was never collected (no clean DB) reports "skipped:未采集" so the
    digest distinguishes "not collected" from "collected but empty" (ADR-23). Any
    query/enrichment failure degrades to empty + error health.
    """
    if not clean_path("github_repo").exists():
        return RepoRadar([], SourceHealth("github_repo", "skipped:未采集"))
    try:
        from L5_apps.digest.repo_radar import RepoCard, enrich_repos
        rows, cols = serve.run_query("radar/latest")
        idx = {name: cols.index(name) for name in
               ("repo", "stars", "star_delta", "description", "language",
                "topics", "provenance")}
        cards: list = []
        for r in rows:
            repo = str(r[idx["repo"]])
            topics_raw = r[idx["topics"]]
            try:
                topics = tuple(json.loads(topics_raw)) if topics_raw else ()
            except (ValueError, TypeError):
                topics = ()
            cards.append(RepoCard(
                repo=repo,
                stars=int(r[idx["stars"]] or 0),
                star_delta=(int(r[idx["star_delta"]])
                            if r[idx["star_delta"]] is not None else None),
                description=str(r[idx["description"]] or ""),
                language=str(r[idx["language"]] or ""),
                topics=tuple(str(t) for t in topics),
                url=f"https://github.com/{repo}",
                provenance=str(r[idx["provenance"]] or "curated"),
            ))
        enriched = enrich_repos(cards, client=client,
                                projects=fetch_known_projects())
        return RepoRadar(enriched, SourceHealth("github_repo", "ok"))
    except Exception as exc:  # noqa: BLE001 - degrade, never crash the digest
        return RepoRadar([], SourceHealth("github_repo", "error",
                                          str(exc)[:200]))



# ---------------------------------------------------------------------------
# batch-2 fetchers (L5 数据接入批2). Every fetch is health-wrapped so a query
# failure / missing clean DB / empty result degrades that one card without
# crashing the digest (ADR-23). The producer (aidash.build_briefing) guards on
# the SourceHealth.state == "ok" AND non-empty data before emitting a container.
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class RankItem:
    """One row of a descending rank (barList): label + magnitude + a
    pre-formatted display string. `semantic` optionally flags a status row
    (e.g. an infrastructure failure) that the UI colors — None = neutral."""
    label: str
    value: float
    value_text: str
    semantic: str | None = None


@dataclass(frozen=True)
class RankBundle:
    """A descending list[RankItem] for one barList card + its source health.
    Ordered by value desc; degrades to empty + non-ok health on failure."""
    items: list[RankItem]
    health: SourceHealth


@dataclass(frozen=True)
class Segment:
    """One stackedBar segment: category label + magnitude + optional semantic
    ("good"/"warning") for a quality-graded segment (None = plain category)."""
    label: str
    value: float
    semantic: str | None = None


@dataclass(frozen=True)
class SegmentBundle:
    """Segments for one stackedBar card + its source health."""
    segments: list[Segment]
    health: SourceHealth


@dataclass(frozen=True)
class AiEfficiency:
    """🧠 AI 效能 section bundle (§design 2): the differentiation core.

    Each field is independently health-tracked so a partial outage still shows
    the cards that DO have data. Cache/rework are per-day/week series (metric
    cards with sparklines); failure/quality are single-snapshot distributions
    (barList/stackedBar); planner_gap_count is a scalar for the insight line.
    """
    cache: list[tuple[str, float]]          # (day, cache_hit_pct) newest-first
    cache_savings: list[tuple[str, float]]  # (day, cache_savings_pct)
    cache_health: SourceHealth
    rework: list[tuple[str, float]]         # (week, rework_rate_pct) newest-first
    rework_health: SourceHealth
    failure: "RankBundle"                   # barList: failure root causes
    quality: "SegmentBundle"                # stackedBar: finish-reason mix
    planner_gap_count: int
    planner_gap_health: SourceHealth

    @classmethod
    def empty(cls) -> "AiEfficiency":
        def skip(n: str) -> SourceHealth:
            return SourceHealth(n, "skipped:未取")
        return cls(
            cache=[], cache_savings=[], cache_health=skip("state_db"),
            rework=[], rework_health=skip("multica_run"),
            failure=RankBundle([], skip("multica_run")),
            quality=SegmentBundle([], skip("claude_jsonl")),
            planner_gap_count=0, planner_gap_health=skip("multica_comment"),
        )


@dataclass(frozen=True)
class NewsItem:
    topic: str
    title: str
    url: str
    source_name: str


@dataclass(frozen=True)
class NewsRadar:
    """📰 新闻雷达: newest headlines grouped by topic (trending cards)."""
    items: list[NewsItem]
    health: SourceHealth


@dataclass(frozen=True)
class ModelTier:
    """🔍 可改良: model-tier token mix as stackedBar segments (pure category)."""
    segments: list[Segment]
    health: SourceHealth


def _rows(name: str, params: dict | None = None):
    """Run a query, returning (rows, {col: index}). Raises on query failure —
    each caller wraps this in its own degrade-safe try/except (ADR-23)."""
    rows, cols = serve.run_query(name, params)
    return rows, {c: i for i, c in enumerate(cols)}


def _fold_top_n(ranked: list[tuple[str, float, float]], top_n: int, *,
                value_text, semantic) -> list["RankItem"]:
    """Keep the top_n rows; fold the rest into a trailing 'Other' (§≥9 折 Other).

    `ranked` is (label, value, pct) value-desc. `value_text(pct)` formats the
    trailing display; `semantic(label)` flags a status row. Other's pct is the
    summed remainder so the bar stays truthful. Never emits an empty Other."""
    if not ranked:
        return []
    head = ranked[:top_n]
    tail = ranked[top_n:]
    items = [RankItem(label, value, value_text(pct), semantic(label))
             for label, value, pct in head]
    if tail:
        other_val = sum(v for _, v, _ in tail)
        other_pct = sum(p for _, _, p in tail)
        items.append(RankItem("Other", other_val, value_text(other_pct), None))
    return items


# ---- 🧠 AI 效能 ----------------------------------------------------------
def fetch_cache_hit_rate() -> tuple[list, list, SourceHealth]:
    """Per-CST-day cache hit % + savings %; degrade to empty + health."""
    if not clean_path("state_db").exists():
        return [], [], SourceHealth("state_db", "skipped:未采集")
    try:
        rows, idx = _rows("cost/cache-hit-rate")
        di = idx["day"]
        hi, si = idx["cache_hit_pct"], idx["cache_savings_pct"]
        hit = [(r[di], float(r[hi] or 0)) for r in rows]
        save = [(r[di], float(r[si] or 0)) for r in rows]
        return hit, save, SourceHealth("state_db", "ok")
    except Exception as exc:  # degrade, never crash
        return [], [], SourceHealth("state_db", "error", str(exc)[:200])


def fetch_rework_rate() -> tuple[list, SourceHealth]:
    """Per-CST-week rework rate %; degrade to empty + health."""
    try:
        rows, idx = _rows("health/rework-rate")
        wi, ri = idx["week"], idx["rework_rate_pct"]
        return ([(r[wi], float(r[ri] or 0)) for r in rows],
                SourceHealth("multica_run", "ok"))
    except Exception as exc:
        return [], SourceHealth("multica_run", "error", str(exc)[:200])


# Infrastructure (not agent-logic) failure causes — flagged semantic="warning"
# so the barList colors + icons them (§design 卡C: "失败绝大多是基础设施抖动不是
# agent 逻辑错"). Kept deliberately narrow: the design law is ONE hot infra row
# popping out of an otherwise-neutral ranking, so a broad set would dilute it.
# The SQL's own lowercase 'other' catch-all bucket is explicitly NOT flagged.
_INFRA_ROOT_CAUSES = {"runtime-offline", "daemon-restart"}


def fetch_failure_rootcause(top_n: int = 6) -> "RankBundle":
    """Failure root causes as a descending barList (top_n + Other fold).

    valueText is the pct share; infra causes get semantic="warning". Degrades to
    empty + non-ok health so the producer omits the card (ADR-23)."""
    try:
        rows, idx = _rows("health/failure-rootcause")
        ci, ri, pi = idx["root_cause"], idx["runs"], idx["pct"]
        ranked = [(str(r[ci]), float(r[ri] or 0), float(r[pi] or 0)) for r in rows]
        items = _fold_top_n(
            ranked, top_n,
            value_text=lambda pct: f"{pct:.0f}%",
            semantic=lambda cause: ("warning" if cause in _INFRA_ROOT_CAUSES
                                    else None),
        )
        return RankBundle(items, SourceHealth("multica_run", "ok"))
    except Exception as exc:
        return RankBundle([], SourceHealth("multica_run", "error", str(exc)[:200]))


# finish_reason → (display label, semantic). end_turn = a clean completion
# (good); max_tokens = a truncated/incomplete answer (warning); tool_use / other
# are neutral mid-flight categories (§design 卡D).
_QUALITY_SEMANTIC = {"end_turn": "good", "max_tokens": "warning"}
_QUALITY_ORDER = ("end_turn", "tool_use", "max_tokens", "other")


def fetch_finish_reason_dist() -> "SegmentBundle":
    """Latest-day finish-reason mix as stackedBar segments (quality gradient).

    Uses the most-recent day's row (finish-reason-dist is per-day newest-first).
    Segments are ordered good→neutral→warning; zero-count reasons are dropped so
    an all-clean day doesn't render an empty warning segment. Degrades to empty +
    non-ok health (ADR-23)."""
    try:
        rows, idx = _rows("health/finish-reason-dist")
        if not rows:
            return SegmentBundle([], SourceHealth("claude_jsonl", "skipped:无数据"))
        r = rows[0]                       # newest CST day
        segs: list[Segment] = []
        for reason in _QUALITY_ORDER:
            val = float(r[idx[reason]] or 0)
            if val > 0:
                segs.append(Segment(reason, val, _QUALITY_SEMANTIC.get(reason)))
        return SegmentBundle(segs, SourceHealth("claude_jsonl", "ok"))
    except Exception as exc:
        return SegmentBundle([], SourceHealth("claude_jsonl", "error", str(exc)[:200]))


def fetch_planner_gap_count() -> tuple[int, SourceHealth]:
    """Count of issues with Engineer work but no Planner (§design insight).

    Returns (count, health). Degrades to (0, non-ok) so the insight is omitted."""
    if not clean_path("multica_comment").exists():
        return 0, SourceHealth("multica_comment", "skipped:未采集")
    try:
        rows, _ = _rows("health/planner-gap")
        return len(rows), SourceHealth("multica_comment", "ok")
    except Exception as exc:
        return 0, SourceHealth("multica_comment", "error", str(exc)[:200])


def fetch_ai_efficiency() -> "AiEfficiency":
    """Bundle every 🧠 AI 效能 signal into one immutable snapshot (degrade-safe)."""
    cache, save, cache_h = fetch_cache_hit_rate()
    rework, rework_h = fetch_rework_rate()
    gap_count, gap_h = fetch_planner_gap_count()
    return AiEfficiency(
        cache=cache, cache_savings=save, cache_health=cache_h,
        rework=rework, rework_health=rework_h,
        failure=fetch_failure_rootcause(),
        quality=fetch_finish_reason_dist(),
        planner_gap_count=gap_count, planner_gap_health=gap_h,
    )


# ---- ⏱ 时间与产出 -------------------------------------------------------
def fetch_cost_by_project(day: str | None, top_n: int = 6) -> "RankBundle":
    """Where the day's spend actually went, as a descending barList.

    This is the attribution layer: every other trend card reports one
    dimension, so "cost up 968%" carries no cause. Attributing it to project
    turns the same number into somewhere to look.

    Cost is allocated across a session's projects in proportion to turns — a
    session touches 1.68 projects on average, so summing per project would
    double-count (see the query header). Degrades to empty + non-ok health
    when the warehouse or query fails (ADR-23).
    """
    try:
        rows, idx = _rows("attribution/cost-by-project", {"day": day})
        pi, ci, pci = idx["project"], idx["cost_usd"], idx["cost_pct"]
        ranked = [(str(r[pi]), float(r[ci] or 0), float(r[pci] or 0))
                  for r in rows]
        items = _fold_top_n(
            ranked, top_n,
            value_text=lambda pct: f"{pct:.0f}%",
            semantic=lambda _label: None,
        )
        return RankBundle(items, SourceHealth("attribution", "ok"))
    except Exception as exc:
        return RankBundle([], SourceHealth("attribution", "error", str(exc)[:200]))


def fetch_model_by_project(day: str | None, top_n: int = 5) -> "RankBundle":
    """Top project x model spend pairs — what the money was spent ON.

    Pairs with `fetch_cost_by_project`: that one says where, this says on what,
    so "opus dominates spend" becomes "AIDash runs opus-5 for $1293". Labels
    read "project · model". Degrades to empty + non-ok health (ADR-23).
    """
    try:
        rows, idx = _rows("attribution/model-by-project", {"day": day})
        pi, mi, ci = idx["project"], idx["model"], idx["cost_usd"]
        ranked = [(f"{r[pi]} · {r[mi]}", float(r[ci] or 0), float(r[ci] or 0))
                  for r in rows]
        items = _fold_top_n(
            ranked, top_n,
            value_text=lambda c: f"${c:.0f}",
            semantic=lambda _label: None,
        )
        return RankBundle(items, SourceHealth("attribution", "ok"))
    except Exception as exc:
        return RankBundle([], SourceHealth("attribution", "error", str(exc)[:200]))


@dataclass(frozen=True)
class Leverage:
    """One typed prompt, priced — the human/machine ratio.

    Every other bundle measures the machine alone. This divides that by the one
    input that is entirely mine, so it is the only figure here that says what a
    sentence of mine sets in motion. `ok` is False when nothing was typed that
    day (division would be meaningless) or the query failed.
    """
    prompts: int
    usd_per_prompt: float
    requests_per_prompt: float
    avg_prompt_chars: int
    health: SourceHealth

    @staticmethod
    def empty(state: str = "skipped:未取") -> "Leverage":
        return Leverage(0, 0.0, 0.0, 0, SourceHealth("leverage", state))


def fetch_leverage(day: str | None) -> "Leverage":
    """What one thing I typed cost the machine. Degrades to empty (ADR-23).

    Reads only `source_kind='typed'`: 93% of "user" lines are tool results and
    harness injections, so counting those would make the denominator lie.
    """
    if not clean_path("claude_prompts").exists():
        return Leverage.empty("skipped:未采集")
    try:
        rows, idx = _rows("attribution/leverage-per-prompt", {"day": day})
        if not rows or not rows[0][idx["prompts"]]:
            return Leverage.empty("skipped:当日无输入")
        r = rows[0]
        return Leverage(
            prompts=int(r[idx["prompts"]] or 0),
            usd_per_prompt=float(r[idx["usd_per_prompt"]] or 0),
            requests_per_prompt=float(r[idx["requests_per_prompt"]] or 0),
            avg_prompt_chars=int(r[idx["avg_prompt_chars"]] or 0),
            health=SourceHealth("leverage", "ok"),
        )
    except Exception as exc:
        return Leverage(0, 0.0, 0.0, 0,
                        SourceHealth("leverage", "error", str(exc)[:200]))


def fetch_rework_by_workspace(since: str | None, top_n: int = 5,
                              min_issues: int = 30) -> "RankBundle":
    """Rework rate per workspace as a descending barList.

    `health/rework-rate` gives one global number; this says which workspace it
    is concentrated in, which is the difference between knowing a cost exists
    and knowing where to look. Workspace UUIDs are mapped to friendly names
    here (config.MULTICA_WORKSPACES is gitignored, so the SQL cannot do it).

    Workspaces below `min_issues` are dropped rather than shown: a rate over a
    handful of issues is noise wearing a percentage sign. Measured on the
    7-day window, one workspace had 0 rework across 22 issues — rendering
    "0%" there reads as "healthy" when it actually means "too few to tell".
    """
    if not clean_path("multica_run").exists():
        return RankBundle([], SourceHealth("multica_run", "skipped:未采集"))
    try:
        rows, idx = _rows("attribution/rework-by-workspace", {"since": since})
        wi, pi, ii = idx["workspace_id"], idx["rework_pct"], idx["issues"]
        ranked = [
            (_WS_NAMES.get(str(r[wi]), str(r[wi])[:8]),
             float(r[pi] or 0), float(r[pi] or 0))
            for r in rows
            if int(r[ii] or 0) >= min_issues
        ]
        if not ranked:
            return RankBundle([], SourceHealth("multica_run", "skipped:样本不足"))
        items = _fold_top_n(
            ranked, top_n,
            value_text=lambda pct: f"{pct:.0f}%",
            semantic=lambda _label: None,
        )
        return RankBundle(items, SourceHealth("multica_run", "ok"))
    except Exception as exc:
        return RankBundle([], SourceHealth("multica_run", "error", str(exc)[:200]))


def fetch_tool_cross(since: str | None, top_n: int = 6) -> "RankBundle":
    """Tool usage crossed with token weight — the cost of a tool CALL.

    Ranked by tokens-per-call rather than raw call count on purpose: a call
    count is what `hermes_tools` already showed and it answered nothing
    ("terminal 2577 times" — so what). Tokens-per-call surfaces the tools that
    are individually expensive, which is the actionable end (measured:
    execute_code 11.9 Ktok/call vs write_file 4.8).

    The label carries the automated share, because the two together say
    something neither says alone: an expensive tool that is 0% automated is
    work still on me, an expensive one at 86% is work already handed off.

    Degrades to empty + non-ok health when Hermes was not collected (ADR-23).
    """
    if not clean_path("hermes_messages").exists():
        return RankBundle([], SourceHealth("hermes_messages", "skipped:未采集"))
    try:
        rows, idx = _rows("attribution/tool-cross", {"since": since})
        ti, ki = idx["tool"], idx["ktok_per_call"]
        ai, ci = idx["automated_pct"], idx["calls"]
        ranked = [
            (f"{r[ti]} · 自动 {int(r[ai] or 0)}%",
             float(r[ki] or 0), float(r[ki] or 0))
            for r in rows
            # A tool seen a handful of times has a meaningless per-call average.
            if int(r[ci] or 0) >= 100
        ]
        ranked.sort(key=lambda item: item[1], reverse=True)
        if not ranked:
            return RankBundle([], SourceHealth("hermes_messages", "skipped:样本不足"))
        items = _fold_top_n(
            ranked, top_n,
            value_text=lambda k: f"{k:.1f} Ktok",
            semantic=lambda _label: None,
        )
        return RankBundle(items, SourceHealth("hermes_messages", "ok"))
    except Exception as exc:
        return RankBundle([], SourceHealth("hermes_messages", "error",
                                           str(exc)[:200]))


def fetch_app_focus(since: str | None, until: str | None,
                    top_n: int = 6) -> "RankBundle":
    """Per-app focus minutes over [since, until) as a descending barList.

    valueText is "N.N min". Folds >top_n into Other (§≥9 折 Other). Degrades to
    empty + non-ok health when gecko is not collected / the query fails (ADR-23)."""
    if not clean_path("gecko").exists():
        return RankBundle([], SourceHealth("gecko", "skipped:未采集"))
    try:
        rows, idx = _rows("time/app-focus", {"since": since, "until": until})
        ai, mi = idx["app"], idx["minutes"]
        ranked = [(str(r[ai]), float(r[mi] or 0), float(r[mi] or 0)) for r in rows]
        items = _fold_top_n(
            ranked, top_n,
            value_text=lambda m: f"{m:.1f} min",
            semantic=lambda _label: None,
        )
        return RankBundle(items, SourceHealth("gecko", "ok"))
    except Exception as exc:
        return RankBundle([], SourceHealth("gecko", "error", str(exc)[:200]))


def fetch_commit_by_repo(since: str | None, until: str | None,
                         top_n: int = 6) -> "RankBundle":
    """Per-repo commit count over [since, until) as a descending barList.

    valueText is the integer count. Folds >top_n into Other. Degrades to empty +
    non-ok health when local_git is not collected / the query fails (ADR-23)."""
    if not clean_path("local_git").exists():
        return RankBundle([], SourceHealth("local_git", "skipped:未采集"))
    try:
        rows, idx = _rows("work/commit-by-repo", {"since": since, "until": until})
        ri, ci = idx["repo"], idx["commits"]
        ranked = [(str(r[ri]), float(r[ci] or 0), float(r[ci] or 0)) for r in rows]
        items = _fold_top_n(
            ranked, top_n,
            value_text=lambda c: f"{c:.0f}",
            semantic=lambda _label: None,
        )
        return RankBundle(items, SourceHealth("local_git", "ok"))
    except Exception as exc:
        return RankBundle([], SourceHealth("local_git", "error", str(exc)[:200]))


# ---- 📰 新闻雷达 --------------------------------------------------------
def fetch_news_radar() -> "NewsRadar":
    """Newest headlines grouped by topic (trending cards). Degrade-safe."""
    if not clean_path("news").exists():
        return NewsRadar([], SourceHealth("news", "skipped:未采集"))
    try:
        rows, idx = _rows("news/latest-by-topic")
        ti, hi = idx["topic"], idx["title"]
        ui, si = idx["url"], idx["source_name"]
        items = [NewsItem(str(r[ti]), str(r[hi]), str(r[ui] or ""),
                          str(r[si] or "")) for r in rows]
        return NewsRadar(items, SourceHealth("news", "ok"))
    except Exception as exc:
        return NewsRadar([], SourceHealth("news", "error", str(exc)[:200]))


# ---- 🔍 可改良 · 模型分层 ----------------------------------------------
def fetch_model_tier(top_n: int = 5) -> "ModelTier":
    """Per-model token-share as stackedBar segments (pure category, no semantic).

    Keeps the top_n models by share; folds the rest into 'Other'. Degrades to
    empty + non-ok health so the producer omits the card (ADR-23)."""
    if not clean_path("state_db").exists():
        return ModelTier([], SourceHealth("state_db", "skipped:未采集"))
    try:
        rows, idx = _rows("cost/model-tier-usage")
        mi, si = idx["model"], idx["token_share_pct"]
        ranked = [(str(r[mi]), float(r[si] or 0)) for r in rows]
        head = ranked[:top_n]
        tail = ranked[top_n:]
        segs = [Segment(model, share) for model, share in head if share > 0]
        if tail:
            other = sum(s for _, s in tail)
            if other > 0:
                segs.append(Segment("Other", other))
        return ModelTier(segs, SourceHealth("state_db", "ok"))
    except Exception as exc:
        return ModelTier([], SourceHealth("state_db", "error", str(exc)[:200]))


# ---- 交叉信号 · 返工关系矩阵 (§design 4.2) --------------------------------
@dataclass(frozen=True)
class RelationshipCell:
    """One cell of a two-dimensional relationship: row × column → magnitude."""
    row: str
    column: str
    value: float


@dataclass(frozen=True)
class ReworkRelationship:
    """Rework tokens crossed by workspace × root cause (attribution/rework-
    relationship), plus the evidence a relationship card must carry.

    `sample_size` is the number of rework issues behind the WHOLE matrix (not
    per cell) and `time_window` the observed CST span — both are required by the
    constitution's relationship recipe, because an association without its
    sample and window is a claim without evidence.

    Degrades to an empty bundle + non-ok health on a missing source or a failed
    query (ADR-23), so the producer omits the card rather than drawing a chart
    from nothing.
    """
    cells: list[RelationshipCell]
    sample_size: int
    time_window: str
    health: SourceHealth

    @staticmethod
    def empty(state: str = "skipped:未取") -> "ReworkRelationship":
        return ReworkRelationship([], 0, "", SourceHealth("multica_run", state))


def fetch_rework_relationship(since: str | None) -> "ReworkRelationship":
    """Fetch the workspace × root-cause rework matrix; degrade-safe (ADR-23).

    Workspace UUIDs are mapped to friendly names HERE rather than in SQL, for
    the same reason as `fetch_rework_by_workspace`: the name table lives in the
    gitignored `config_local.py`, so a public query cannot do the lookup. An
    unmapped workspace falls back to its first UUID segment, which is still a
    stable, distinguishable row label.

    Rows already arrive tokens-desc from L4; that order is preserved so the
    heaviest cell leads.
    """
    if not clean_path("multica_run").exists():
        return ReworkRelationship.empty("skipped:未采集")
    try:
        rows, idx = _rows("attribution/rework-relationship", {"since": since})
        if not rows:
            return ReworkRelationship.empty("skipped:无返工数据")
        cells = [
            RelationshipCell(
                row=_WS_NAMES.get(str(r[idx["workspace_id"]]),
                                  str(r[idx["workspace_id"]])[:8]),
                column=str(r[idx["root_cause"]]),
                value=float(r[idx["rework_tokens"]] or 0),
            )
            for r in rows
        ]
        start = str(rows[0][idx["window_start"]] or "")
        end = str(rows[0][idx["window_end"]] or "")
        window = f"{start} → {end}" if start and end else ""
        return ReworkRelationship(
            cells=cells,
            sample_size=int(rows[0][idx["sample_size"]] or 0),
            time_window=window,
            health=SourceHealth("multica_run", "ok"),
        )
    except Exception as exc:  # noqa: BLE001 - degrade, never crash the digest
        return ReworkRelationship([], 0, "",
                                  SourceHealth("multica_run", "error",
                                               str(exc)[:200]))


# ---- 你最常收藏的卡型 (spec 005 T007/US5) ---------------------------------
@dataclass(frozen=True)
class CardTypeStar:
    """One card type's whole-card star count, over the caller's window."""
    card_type: str
    star_count: int


@dataclass(frozen=True)
class CardInterest:
    """Whole-card star counts by card_type, descending (behavior/card-interest).
    Degrades to empty + non-ok health so the producer omits the insight card
    (ADR-23) — a source that was never collected reports "skipped:未采集"."""
    types: list[CardTypeStar]
    health: SourceHealth


def fetch_card_interest(since: str | None) -> "CardInterest":
    """Fetch whole-card star counts by card_type over [since, now].

    `since` is a CST date 'YYYY-MM-DD' (the caller computes the rolling 7-day
    window, ADR-22); None means all-time (serve.py auto-binds a missing param
    to NULL). aidash_events is L2-only (never merged into warehouse), so a
    fresh worktree with no collected events is the normal case, not an error —
    reported as "skipped:未采集" same as gecko/local_git/state_db above."""
    if not clean_path("aidash_events").exists():
        return CardInterest([], SourceHealth("aidash_events", "skipped:未采集"))
    try:
        rows, idx = _rows("behavior/card-interest", {"since": since})
        ti, si = idx["card_type"], idx["star_count"]
        types = [CardTypeStar(str(r[ti]), int(r[si] or 0)) for r in rows]
        return CardInterest(types, SourceHealth("aidash_events", "ok"))
    except Exception as exc:
        return CardInterest([], SourceHealth("aidash_events", "error", str(exc)[:200]))
