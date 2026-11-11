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
import re
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

import serve
from config import clean_path
from sqlite_ro import query_ro

from L5_apps.digest.proposals import Proposal, read_pending
from L5_apps.digest.todo_sync_provider import (
    TodoSyncProvider,
    read_open_local_todos,
    resolve_todo_sync_provider,
)

# Error logs written by the AIDash push path / snapshot cron (类3c signals).
_AIDASH_STATE = Path(os.path.expanduser("~")) / "Development" / "AIDash" / ".aidash-state"
_PUSH_ERR_LOG = _AIDASH_STATE / "aidash-push-errors.log"
_CRON_ERR_LOG = _AIDASH_STATE / "cron-errors.log"

_PRIO_RANK = {"high": 0, "medium": 1, "low": 2}

# Threshold: opus-downgrade waste above this (all-time $) becomes a 类2 finding.
_DOWNGRADE_FINDING_USD = 500.0
# Cap the inbox so the card stays a glance, not a backlog dump.
_MAX_ITEMS = 12
_MAX_PR_AGE_DAYS = 30
_MAX_CRON_ERROR_AGE_DAYS = 7
_ISO_TIMESTAMP = re.compile(
    r"\b20\d{2}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?\b"
)
_TIA_ISSUE_REF = re.compile(r"^(?:linear://)?(TIA-\d+)$", re.IGNORECASE)


@dataclass(frozen=True)
class InboxItem:
    title: str
    priority: str          # high | medium | low
    bucket: str            # 卡顿 | 待决策 | 计划 | 发现
    ref: str = ""          # optional id/identifier for later drill
    category: str = ""
    waiting_on: str = ""
    age_text: str = ""
    command_hint: str = ""
    fresh: bool = True


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
        if days > _MAX_PR_AGE_DAYS:
            continue
        title = str(r[ti])[:60]
        out.append(InboxItem(
            f"PR 卡 {days} 天：{title}", "high", "卡顿", str(r[pi]),
            "stale", "PR owner", f"{days}d"))
    return out


def _pending_issues(
    cap: int = 6,
    *,
    provider: TodoSyncProvider | None = None,
    local_todos_path: Path | None = None,
) -> list[InboxItem]:
    active_provider = provider or resolve_todo_sync_provider(
        local_todos_path=local_todos_path
    )
    out: list[InboxItem] = []

    try:
        rows, cols = serve.run_query("inbox/pending-issues")
    except Exception:  # noqa: BLE001 - inbox sources degrade independently
        rows, cols = [], []

    if rows and cols:
        ii = cols.index("identifier")
        ti = cols.index("title")
        si = cols.index("status")
        for r in rows[:cap]:
            ident = str(r[ii])
            status = str(r[si])
            blocked = status == "blocked"
            ref = active_provider.format_ref(ident)
            tia_match = _TIA_ISSUE_REF.fullmatch(ident.strip())
            if tia_match:
                ref = f"linear://{tia_match.group(1).upper()}"
            out.append(InboxItem(
                f"[{status}] {ident} {str(r[ti])[:44]}",
                "high" if blocked else "medium",
                "卡顿" if blocked else "计划",
                ref,
                "blocked" if blocked else "planned",
                "Owner" if blocked else "",
            ))

    if active_provider.name == "local" or local_todos_path is not None:
        local_items = read_open_local_todos(local_todos_path)
        for item in local_items:
            if len(out) >= cap:
                break
            blocked = item.status == "blocked"
            ref = active_provider.format_ref(item.id)
            if not ref.startswith("local://"):
                ref = f"local://{item.id}"
            out.append(InboxItem(
                f"[{item.status}] {item.id} {item.title[:44]}",
                "high" if blocked else "medium",
                "卡顿" if blocked else "计划",
                ref,
                "blocked" if blocked else "planned",
                "Owner" if blocked else "",
            ))

    return out[:cap]


def _downgrade_finding(downgrade_usd: float) -> list[InboxItem]:
    """类2 数据新发现: opus-on-tiny-outputs waste crossed the threshold."""
    if downgrade_usd is None or downgrade_usd < _DOWNGRADE_FINDING_USD:
        return []
    return [InboxItem(
        f"发现：${downgrade_usd:.0f} 花在 opus 的琐碎输出上，值得核查模型选择",
        "medium", "发现", "", "discovery")]


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
                f"{label}近期报错：{tail[:60]}", "high", "卡顿",
                "", "blocked", "operator"))
    return out


def _embedded_timestamp(line: str) -> float | None:
    match = _ISO_TIMESTAMP.search(line)
    if not match:
        return None
    value = match.group(0).replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)  # noqa: UP017
    return parsed.timestamp()


def _default_log_reader(path: Path) -> str:
    """Return a recent error line, using mtime or an embedded timestamp."""
    try:
        if not path.exists():
            return ""
        lines = [ln for ln in path.read_text(encoding="utf-8").splitlines() if ln.strip()]
        if not lines:
            return ""
        cutoff = time.time() - timedelta(days=_MAX_CRON_ERROR_AGE_DAYS).total_seconds()
        if path.stat().st_mtime >= cutoff:
            return lines[-1].strip()
        timestamp = _embedded_timestamp(lines[-1])
        return lines[-1].strip() if timestamp is not None and timestamp >= cutoff else ""
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
        explicit_ref = getattr(p, "ref", "") or ""
        if explicit_ref:
            ref = explicit_ref
        elif str(p.id).startswith(("proposal://", "knowledge://")):
            ref = str(p.id)
        else:
            ref = f"proposal://{p.id}"
        out.append(InboxItem(
            f"待决策（{p.agent}）：{p.title[:56]}", prio, "待决策",
            ref, "decision", "Owner GO"))
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
            if str(row[status_i]).lower() in {"done", "completed", "complete"}:
                continue
            if (row[status_i] != "blocked"
                    and (row[blocked_i] or 0) <= 0) or goal_id in seen_goals:
                continue
            seen_goals.add(goal_id)
            blocked_count = row[blocked_i] or 0
            out.append(InboxItem(
                f"GTT 阻塞：{goal_id}（{blocked_count} 项阻塞）",
                "high", "卡顿", goal_id, "blocked", "Writer / Reviewer"))
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
                "medium", "发现", str(top_repo), "drift", "Owner"))
    except Exception:  # noqa: BLE001, S110 - one retro source must not block others
        pass

    try:
        rows, cols = serve.run_query("retro/workspace_hygiene_reclaim")
        reclaim_i = cols.index("reclaimable_count")
        total_reclaimable = sum((row[reclaim_i] or 0) for row in rows)
        if total_reclaimable > 0:
            out.append(InboxItem(
                f"发现：{total_reclaimable} 个已合并洁净 Worktree 可安全回收",
                "medium", "发现", "workspace_hygiene", "stale", "Owner"))
    except Exception:  # noqa: BLE001, S110 - one retro source must not block others
        pass

    return out


def _mail_and_work_watch_signals(
    *,
    mail_db_path: Path | None = None,
    teams_db_path: Path | None = None,
    cap: int = 3,
) -> list[InboxItem]:
    """Work Watch / 待我处理: actionable unread/unreplied mail todos and Work-PC Teams @mentions."""
    out: list[InboxItem] = []

    teams_db = teams_db_path or clean_path("work_teams_bridge")
    if teams_db.exists():
        try:
            rows = query_ro(
                teams_db,
                "SELECT dedup_key, channel_kind, sender_alias, title_preview, summary_preview, "
                "has_mention, priority FROM work_teams_item "
                "WHERE COALESCE(replied, 0) = 0 AND (COALESCE(has_mention, 0) = 1 OR COALESCE(needs_reply, 0) = 1) "
                "ORDER BY cursor DESC LIMIT ?",
                (cap,),
            )
            for row in rows:
                dedup_key = row.get("dedup_key")
                channel_kind = row.get("channel_kind")
                sender_alias = row.get("sender_alias")
                title_prev = row.get("title_preview")
                summary_prev = row.get("summary_preview")
                has_mention = row.get("has_mention")
                prio = row.get("priority")
                headline = str(title_prev or summary_prev or "Teams 待处理消息").strip()[:48]
                sender_label = str(sender_alias or "colleague").strip()[:24]
                tag = "ADO 提醒" if str(channel_kind) == "ado_reminder" else ("Teams @我" if has_mention else "Teams 待回")
                eff_prio = str(prio) if str(prio) in _PRIO_RANK else ("high" if has_mention else "medium")
                out.append(
                    InboxItem(
                        f"[{tag}] {sender_label}: {headline}",
                        eff_prio,
                        "待决策" if has_mention else "计划",
                        str(dedup_key or ""),
                        "work_watch",
                        "Owner",
                    )
                )
        except Exception:  # noqa: BLE001, S110
            pass

    mail_db = mail_db_path or clean_path("mail_inbox")
    if mail_db.exists() and len(out) < cap:
        try:
            rem = max(1, cap - len(out))
            rows = query_ro(
                mail_db,
                "SELECT dedup_key, sender_domain, subject_preview, snippet_preview, "
                "has_mention, priority FROM mail_inbox_item "
                "WHERE COALESCE(replied, 0) = 0 AND (COALESCE(is_todo, 0) = 1 OR COALESCE(has_mention, 0) = 1) "
                "ORDER BY cursor DESC LIMIT ?",
                (rem,),
            )
            for row in rows:
                dedup_key = row.get("dedup_key")
                sender_dom = row.get("sender_domain")
                subject_prev = row.get("subject_preview")
                snippet_prev = row.get("snippet_preview")
                has_mention = row.get("has_mention")
                prio = row.get("priority")
                headline = str(subject_prev or snippet_prev or "邮件待办").strip()[:48]
                dom = str(sender_dom or "mail").strip()[:24]
                tag = "邮件 @我" if has_mention else "邮件待办"
                eff_prio = str(prio) if str(prio) in _PRIO_RANK else ("high" if has_mention else "medium")
                out.append(
                    InboxItem(
                        f"[{tag}] {dom}: {headline}",
                        eff_prio,
                        "待决策" if has_mention else "计划",
                        str(dedup_key or ""),
                        "work_watch",
                        "Owner",
                    )
                )
        except Exception:  # noqa: BLE001, S110
            pass

    return out[:cap]


def build_inbox(
    downgrade_usd: float | None = None,
    *,
    proposals_reader: Callable[[], list[Proposal]] | None = None,
    log_reader: Callable[[Path], str] | None = None,
    mail_db_path: Path | None = None,
    teams_db_path: Path | None = None,
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
    raw += _mail_and_work_watch_signals(mail_db_path=mail_db_path, teams_db_path=teams_db_path)
    raw += _pending_issues()
    raw += _downgrade_finding(downgrade_usd if downgrade_usd is not None else 0.0)
    raw += _retro_signals()

    raw = [item for item in raw if item.fresh]

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


_ACTION_ID_INVALID_RE = re.compile(r"[\x00-\x1f\x7f|]+")
_JOBS_SUBPATH = Path("Library") / "Application Support" / "AIDash" / "jobs"
_DEFAULT_REGISTERED_JOB_IDS = ("my-pr-supervisor", "pr-auto-review", "aidata-digest")


def _safe_action_id(raw: str, index: int) -> str:
    cleaned = _ACTION_ID_INVALID_RE.sub("-", str(raw or "").strip())
    cleaned = re.sub(r"\s+", "-", cleaned)[:120]
    return cleaned or f"inbox-item-{index}"


def _controls_for_inbox_item(item: InboxItem) -> list[dict[str, object]]:
    ref = (item.ref or "").strip()
    if ref.lower().startswith(("linear://", "local://")) or _TIA_ISSUE_REF.fullmatch(ref):
        return [
            {
                "id": "decision",
                "kind": "singleSelect",
                "title": "状态操作",
                "options": ["Done", "Unblock & Comment", "Hold"],
            },
            {
                "id": "note",
                "kind": "textInput",
                "title": "备注说明",
                "options": [],
                "maxLength": 80,
            },
        ]
    if ref.startswith(("proposal://", "knowledge://")) or item.category in {"decision", "work_watch"}:
        return [
            {
                "id": "decision",
                "kind": "singleSelect",
                "title": "决策操作",
                "options": ["Promote to Linear TIA", "Done", "Hold"],
            },
            {
                "id": "note",
                "kind": "textInput",
                "title": "备注说明",
                "options": [],
                "maxLength": 80,
            },
        ]
    return [
        {
            "id": "decision",
            "kind": "singleSelect",
            "title": "处理操作",
            "options": ["Done", "Promote to Linear TIA", "Hold"],
        },
        {
            "id": "note",
            "kind": "textInput",
            "title": "备注说明",
            "options": [],
            "maxLength": 80,
        },
    ]


def build_job_actions(
    items: list[InboxItem] | None = None,
    *,
    job_id: str = "aidata-digest",
    created_at: str | None = None,
    proposals_path: Path | None = None,
) -> list[dict[str, object]]:
    """Map unified InboxItems (Linear TIA + proposals + mail/teams + stalls) to JobActionsAction v1."""
    source_items = items if items is not None else build_inbox()
    stamp = created_at or (
        datetime.now(timezone.utc)  # noqa: UP017
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z")
    )
    pending_by_id: dict[str, Proposal] = {}
    try:
        for prop in read_pending(proposals_path):
            pending_by_id[prop.id] = prop
            if prop.ref:
                pending_by_id[prop.ref] = prop
    except Exception:  # noqa: BLE001, S110
        pass

    actions: list[dict[str, object]] = []
    seen_ids: set[str] = set()
    for index, item in enumerate(source_items, start=1):
        ref = (item.ref or "").strip()
        if ref.lower().startswith("linear://"):
            issue_ident = ref.split("://", 1)[1].upper()
            raw_id = f"linear-{issue_ident}"
        elif _TIA_ISSUE_REF.fullmatch(ref):
            issue_ident = ref.upper()
            raw_id = f"linear-{issue_ident}"
            ref = f"linear://{issue_ident}"
        elif ref.lower().startswith("local://"):
            local_ident = ref.split("://", 1)[1].upper()
            raw_id = f"local-{local_ident}"
        elif ref.startswith("proposal://"):
            prop_id = ref.removeprefix("proposal://")
            raw_id = f"proposal-{prop_id}"
        elif ref.startswith("knowledge://"):
            slug = ref.removeprefix("knowledge://").strip("/")
            raw_id = f"knowledge-{slug}"
        elif item.category == "work_watch" and ref:
            raw_id = f"work-watch-{ref}"
        elif ref:
            raw_id = f"item-{ref}"
        else:
            raw_id = f"signal-{index}"

        action_id = _safe_action_id(raw_id, index)
        if action_id in seen_ids:
            action_id = _safe_action_id(f"{action_id}-{index}", index)
        seen_ids.add(action_id)

        title = str(item.title or action_id).strip()[:512] or action_id
        desc_lines = [
            f"- **来源分类**: `{item.bucket}` (`{item.category or 'inbox'}`)",
            f"- **优先级**: `{item.priority}`",
        ]
        if ref:
            desc_lines.append(f"- **关联引用 (ref)**: `{ref}`")
        if item.waiting_on:
            desc_lines.append(f"- **等待方**: {item.waiting_on}")
        if item.age_text:
            desc_lines.append(f"- **持续时长**: {item.age_text}")

        prop_key = ref.removeprefix("proposal://") if ref.startswith("proposal://") else ref
        matched_prop = pending_by_id.get(prop_key)
        if matched_prop and matched_prop.detail:
            desc_lines.append(f"\n{matched_prop.detail.strip()}")

        description_md = "\n".join(desc_lines)[:16384]
        actions.append(
            {
                "id": action_id,
                "jobID": job_id,
                "createdAt": stamp,
                "title": title,
                "descriptionMd": description_md,
                "controls": _controls_for_inbox_item(item),
            }
        )
        if len(actions) >= 64:
            break
    return actions


def export_job_actions(
    items: list[InboxItem] | None = None,
    *,
    jobs_root: Path | None = None,
    job_id: str = "aidata-digest",
    created_at: str | None = None,
    proposals_path: Path | None = None,
) -> Path | None:
    """Atomically write unified actions.jsonl for AIDash job-actions snapshot."""
    import json

    root = jobs_root or (Path.home() / _JOBS_SUBPATH)
    try:
        for registered in _DEFAULT_REGISTERED_JOB_IDS:
            job_dir = root / registered
            job_dir.mkdir(parents=True, exist_ok=True)
            actions_file = job_dir / "actions.jsonl"
            if registered != job_id and not actions_file.exists():
                actions_file.write_text("", encoding="utf-8")

        actions = build_job_actions(
            items,
            job_id=job_id,
            created_at=created_at,
            proposals_path=proposals_path,
        )
        target_dir = root / job_id
        target_dir.mkdir(parents=True, exist_ok=True)
        target_path = target_dir / "actions.jsonl"
        payload = "".join(
            json.dumps(action, ensure_ascii=False, separators=(",", ":")) + "\n"
            for action in actions
        )
        tmp_path = target_dir / ".actions.jsonl.tmp"
        tmp_path.write_text(payload, encoding="utf-8")
        tmp_path.replace(target_path)
        return target_path
    except OSError:
        return None

