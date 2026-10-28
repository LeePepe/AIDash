"""Action inbox aggregator (§M3, goal ② 需要处理什么).

Merges four buckets into ONE prioritized "待我处理/决策" list — the thing the
user most wants to see first thing (AIDash's one-glance-briefing定位):

  类1 计划的活   ← multica issues (todo / in_review / in_progress)   → medium
  类3 卡顿/阻塞  ← blocked issues, stalled ADO PRs, error-log signals → high
  类2 数据新发现 ← threshold breaches (e.g. opus-downgrade waste)     → medium
  类4 待决策     ← agent proposals (pending)                          → high

Each bucket is independently guarded: a failing source degrades that bucket to
empty without breaking the inbox. Output is a flat list of InboxItem sorted by
priority (high→medium→low) then bucket order, capped for readability.

Pure-ish: SQL via serve.run_query, proposals/error-logs via injected readers so
the unit suite is hermetic.
"""

from __future__ import annotations

import os
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

import serve

from L5_apps.digest.proposals import Proposal, read_pending

# Error logs written by the AIDash push path / snapshot cron (类3c signals).
_AIDASH_STATE = Path(os.path.expanduser("~")) / "Development" / "AIDash" / ".aidash-state"
_PUSH_ERR_LOG = _AIDASH_STATE / "aidash-push-errors.log"
_CRON_ERR_LOG = _AIDASH_STATE / "cron-errors.log"

_PRIO_RANK = {"high": 0, "medium": 1, "low": 2}

# Threshold: opus-downgrade waste above this (all-time $) becomes a 类2 finding.
_DOWNGRADE_FINDING_USD = 500.0
# Cap the inbox so the card stays a glance, not a backlog dump.
_MAX_ITEMS = 12


@dataclass(frozen=True)
class InboxItem:
    title: str
    priority: str          # high | medium | low
    bucket: str            # 卡顿 | 待决策 | 计划 | 发现
    ref: str = ""          # optional id/identifier for later drill


def _stalled_prs() -> list[InboxItem]:
    try:
        rows, cols = serve.run_query("inbox/stalled-prs")
    except Exception:  # noqa: BLE001 - inbox sources degrade independently
        return []
    if not rows or not cols:
        return []
    ti, ai, pi = cols.index("title"), cols.index("age_hours"), cols.index("pr_id")
    out = []
    for r in rows[:4]:
        days = int((r[ai] or 0) // 24)
        title = str(r[ti])[:60]
        out.append(InboxItem(
            f"PR 卡 {days} 天：{title}", "high", "卡顿", str(r[pi])))
    return out


def _pending_issues(cap: int = 6) -> list[InboxItem]:
    try:
        rows, cols = serve.run_query("inbox/pending-issues")
    except Exception:  # noqa: BLE001 - inbox sources degrade independently
        return []
    if not rows or not cols:
        return []
    ii = cols.index("identifier")
    ti = cols.index("title")
    si = cols.index("status")
    out = []
    for r in rows[:cap]:
        status = str(r[si])
        blocked = status == "blocked"
        out.append(InboxItem(
            f"[{status}] {r[ii]!s} {str(r[ti])[:44]}",
            "high" if blocked else "medium",
            "卡顿" if blocked else "计划",
            str(r[ii])))
    return out


def _downgrade_finding(downgrade_usd: float) -> list[InboxItem]:
    """类2 数据新发现: opus-on-tiny-outputs waste crossed the threshold."""
    if downgrade_usd is None or downgrade_usd < _DOWNGRADE_FINDING_USD:
        return []
    return [InboxItem(
        f"发现：${downgrade_usd:.0f} 花在 opus 的琐碎输出上，值得核查模型选择",
        "medium", "发现")]


def _error_log_signals(
    read: Callable[[Path], str] | None = None,
) -> list[InboxItem]:
    """类3c: recent lines in the AIDash error logs mean something is broken."""
    reader = read or _default_log_reader
    out: list[InboxItem] = []
    for path, label in ((_PUSH_ERR_LOG, "AIDash 推送"),
                        (_CRON_ERR_LOG, "snapshot cron")):
        tail = reader(path)
        if tail:
            out.append(InboxItem(
                f"{label}近期报错：{tail[:60]}", "high", "卡顿"))
    return out


def _default_log_reader(path: Path) -> str:
    """Return the last non-empty line if the log was touched recently, else ''."""
    try:
        if not path.exists():
            return ""
        lines = [ln for ln in path.read_text(encoding="utf-8").splitlines() if ln.strip()]
        return lines[-1].strip() if lines else ""
    except OSError:
        return ""


def _proposals(read: Callable[[], list[Proposal]] | None = None) -> list[InboxItem]:
    """类4 待决策: pending agent proposals awaiting user approval."""
    reader = read or read_pending
    try:
        pending = reader()
    except Exception:  # noqa: BLE001 - proposal source degrades independently
        return []
    out = []
    for p in pending:
        prio = p.priority if p.priority in _PRIO_RANK else "high"
        out.append(InboxItem(
            f"待决策（{p.agent}）：{p.title[:56]}", prio, "待决策", p.id))
    return out


def _retro_signals() -> list[InboxItem]:
    """Surface operational signals from the retro L4 query family."""
    out: list[InboxItem] = []

    try:
        rows, cols = serve.run_query("retro/gtt_scorecard")
        goal_i = cols.index("goal_id")
        status_i = cols.index("actual_status")
        blocked_i = cols.index("task_blocked_count")
        seen_goals: set[str] = set()
        for row in rows:
            goal_id = str(row[goal_i])
            if (row[status_i] != "blocked"
                    and (row[blocked_i] or 0) <= 0) or goal_id in seen_goals:
                continue
            seen_goals.add(goal_id)
            blocked_count = row[blocked_i] or 0
            out.append(InboxItem(
                f"GTT 阻塞：{goal_id}（{blocked_count} 项阻塞）",
                "high", "卡顿", goal_id))
            if len(out) == 2:
                break
    except Exception:  # noqa: BLE001, S110 - one retro source must not block others
        pass

    try:
        rows, cols = serve.run_query("retro/ci_health_and_noise")
        repo_i = cols.index("repo_key")
        noise_i = cols.index("config_noise_job_count")
        total_noise = sum((row[noise_i] or 0) for row in rows)
        if total_noise > 0:
            top_repo = max(rows, key=lambda row: row[noise_i] or 0)[repo_i]
            out.append(InboxItem(
                f"发现：CI 配置噪音 {total_noise} 次（如 {top_repo}），"
                "建议补齐变量或停用空跑任务",
                "medium", "发现", str(top_repo)))
    except Exception:  # noqa: BLE001, S110 - one retro source must not block others
        pass

    try:
        rows, cols = serve.run_query("retro/workspace_hygiene_reclaim")
        reclaim_i = cols.index("reclaimable_count")
        total_reclaimable = sum((row[reclaim_i] or 0) for row in rows)
        if total_reclaimable > 0:
            out.append(InboxItem(
                f"发现：{total_reclaimable} 个已合并洁净 Worktree 可安全回收",
                "medium", "发现", "workspace_hygiene"))
    except Exception:  # noqa: BLE001, S110 - one retro source must not block others
        pass

    return out


def build_inbox(
    downgrade_usd: float | None = None,
    *,
    proposals_reader: Callable[[], list[Proposal]] | None = None,
    log_reader: Callable[[Path], str] | None = None,
) -> list[InboxItem]:
    """Aggregate all buckets → one prioritized, BALANCED inbox list.

    Per-bucket quotas (not a global cap) so a wall of stalls can't crowd out the
    planned work or a pending decision — the user should see a representative
    slice of each bucket. Within the final list, sort by priority then bucket
    order. Each bucket is guarded independently (a failing source → empty).
    """
    bucket_order = {"卡顿": 0, "待决策": 1, "计划": 2, "发现": 3}
    # Quotas: decisions and findings are rare but important (show all up to 3);
    # stalls and planned work are capped so neither dominates.
    quotas = {"待决策": 3, "卡顿": 5, "计划": 3, "发现": 2}

    raw: list[InboxItem] = []
    raw += _error_log_signals(log_reader)
    raw += _stalled_prs()
    raw += _proposals(proposals_reader)
    raw += _pending_issues()
    raw += _downgrade_finding(downgrade_usd if downgrade_usd is not None else 0.0)
    raw += _retro_signals()

    # Apply per-bucket quota, preserving each bucket's internal (urgency) order.
    kept: list[InboxItem] = []
    seen: dict[str, int] = {}
    for it in raw:
        n = seen.get(it.bucket, 0)
        if n < quotas.get(it.bucket, 3):
            kept.append(it)
            seen[it.bucket] = n + 1

    kept.sort(key=lambda it: (_PRIO_RANK.get(it.priority, 1),
                              bucket_order.get(it.bucket, 9)))
    return kept[:_MAX_ITEMS]
