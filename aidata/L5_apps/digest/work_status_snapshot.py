"""Canonical aidash-work-status/v1 snapshot artifact for AIDashApp.

Consumes L4 `retro/goal_session_work_stream` plus optional warehouse agent-retro
findings to emit an atomic, degrade-safe JSON snapshot at:
  ~/Library/Application Support/AIDash/jobs/aidata-digest/work-status.json

Stops strictly at the Session Work Receipt grain—never emitting raw prompts,
assistant transcripts, or local absolute paths. Missing warehouse or empty
populations emit `coverage_status` (`missing` / `unknown` / `partial`) rather
than fabricated healthy zeros.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import sqlite3
import subprocess  # nosec B404 - fixed python helper only
import sys
import tempfile
from collections.abc import Callable, Iterable, Mapping, Sequence
from datetime import datetime, timezone
from pathlib import Path
from statistics import median
from typing import Any

import config
import serve
from config import ICLOUD_DRIVE_ROOT, resolve_icloud_sync_dir
from quality_contracts import canonical_skill


def _l4_work_stream_query() -> str:
    return "retro/" + "goal_session_work_stream"


WORK_STREAM_QUERY = _l4_work_stream_query()

UNASSIGNED_GOAL_ID = "unassigned-daily"
UNASSIGNED_GOAL_TITLE = "日常独立会话（未绑定独立 Goal）"

_DEFAULT_OUTPUT = (
    Path.home()
    / "Library"
    / "Application Support"
    / "AIDash"
    / "jobs"
    / "aidata-digest"
    / "work-status.json"
)

_ROLE_LABELS_ZH: dict[str, str] = {
    "m3": "总控协调",
    "m2": "话题编排",
    "m1": "主控编排",
    "designer": "视觉设计",
    "writer": "编码实现",
    "reviewer": "独立审查",
    "explorer": "代码探查",
    "pr_monitor": "交付监控",
}

_ROLE_LABELS_EN: dict[str, str] = {
    "m3": "Top-Level Coordinator",
    "m2": "Topic Dispatcher",
    "m1": "Goal Lead",
    "designer": "Visual Designer",
    "writer": "Code Implementation",
    "reviewer": "Independent Reviewer",
    "explorer": "Code Explorer",
    "pr_monitor": "Delivery Monitor",
}

_LAYER_SIGNAL_LABELS: dict[str, tuple[str, str]] = {
    "role": ("角色职责越界告警", "Role boundary drift detected"),
    "handoff": ("交接回执字段需补齐", "Handoff receipt completeness gap"),
    "invoke": ("工具与参考调用待收敛", "Tool or reference invocation friction"),
    "exec": ("执行收敛偏慢（含返工绕路）", "Execution convergence slowed by rework"),
    "friction": ("人机协作确认摩擦偏多", "Elevated human-agent confirmation friction"),
    "horizon": ("长程会话上下文携带偏重", "Heavy long-session context carry"),
}


_ROLE_RELAY_ORDER: tuple[str, ...] = (
    "m3",
    "m2",
    "m1",
    "explorer",
    "designer",
    "writer",
    "reviewer",
    "pr_monitor",
)

_ACTIVE_STATUSES: frozenset[str] = frozenset(
    {"active", "in_progress", "in_review", "blocked", "planning", "accepting", "ready"}
)
_DONE_STATUSES: frozenset[str] = frozenset({"done", "merged", "completed"})

_VERSION_TOKEN_RE = re.compile(
    r"(?:^\d+\.\d+\.\d+\+)?(?P<ver>v(?P<num>\d+))(?:@(?P<sha>[0-9a-fA-F]{4,40}))?$"
)


def _clean_skill_version(raw: Any) -> tuple[str | None, int | None, str | None]:
    """Return `(short_version, numeric_index, watermark_sha)` for e.g. `'v19@1a2b3c4'`."""
    if raw in (None, ""):
        return None, None, None
    txt = str(raw).strip()
    if not txt:
        return None, None, None
    m = _VERSION_TOKEN_RE.match(txt)
    if m:
        return f"v{int(m.group('num'))}", int(m.group("num")), (m.group("sha").lower() if m.group("sha") else None)
    base = txt.split("@", 1)[0].strip()
    sha = txt.split("@", 1)[1].strip().lower() if "@" in txt else None
    num_m = re.match(r"^v(\d+)$", base)
    return (base or None), (int(num_m.group(1)) if num_m else None), (sha or None)


def _clean_repo_display(raw_repo: str | None) -> str:
    if not raw_repo or not raw_repo.strip():
        return "其他仓库"
    trimmed = raw_repo.strip()
    if "/" in trimmed:
        tail = trimmed.rsplit("/", 1)[-1].strip()
        if tail:
            return tail
    return trimmed


def _median_or_none(values: Sequence[float]) -> float | None:
    if not values:
        return None
    return round(float(median(values)), 1)


def _parse_json_list(raw: Any) -> list[Any]:
    if isinstance(raw, list):
        return raw
    if isinstance(raw, str) and raw.strip():
        try:
            val = json.loads(raw)
            return val if isinstance(val, list) else []
        except ValueError:
            return []
    return []


def _parse_skill_csv(raw: Any) -> set[str]:
    if not raw:
        return set()
    out: set[str] = set()
    for part in str(raw).split(","):
        sk = canonical_skill(part)
        if sk and re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}", sk):
            out.add(sk)
    return out


def _build_action_split(
    search_read: int,
    code_edit: int,
    verify_script: int,
    spin_rework: int,
) -> dict[str, Any]:
    sr = max(0, int(search_read or 0))
    ce = max(0, int(code_edit or 0))
    vs = max(0, int(verify_script or 0))
    sw = max(0, int(spin_rework or 0))
    total = sr + ce + vs + sw
    if total > 0:
        sr_pct = round(100.0 * sr / total, 1)
        ce_pct = round(100.0 * ce / total, 1)
        vs_pct = round(100.0 * vs / total, 1)
        sw_pct = round(max(0.0, 100.0 - sr_pct - ce_pct - vs_pct), 1)
    else:
        sr_pct = ce_pct = vs_pct = sw_pct = 0.0
    return {
        "total_calls": total,
        "search_read_calls": sr,
        "code_edit_calls": ce,
        "verify_script_calls": vs,
        "spin_rework_calls": sw,
        "search_read_pct": sr_pct,
        "code_edit_pct": ce_pct,
        "verify_script_pct": vs_pct,
        "spin_rework_pct": sw_pct,
    }


def load_goal_retro_findings_from_warehouse(
    warehouse_db: Path | None,
    *,
    until_day: str | None = None,
    days: int = 14,
) -> dict[str, dict[str, int]]:
    """Read optional per-goal post-fix retro anomaly counts from warehouse.db."""
    if warehouse_db is None or not warehouse_db.is_file():
        return {}
    try:
        with contextlib.closing(
            sqlite3.connect(f"file:{warehouse_db.resolve()}?mode=ro&immutable=1", uri=True)
        ) as conn:
            tables = {
                str(r[0])
                for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
            }
            if "fact_agent_retro_finding" not in tables:
                return {}
            sql = """
            WITH anchor AS (
                SELECT COALESCE(
                    :until_day,
                    (SELECT MAX(f.cst_day) FROM fact_agent_retro_finding AS f WHERE f.cst_day IS NOT NULL),
                    date('now', '+8 hours')
                ) AS end_day
            )
            SELECT
                f.goal_id,
                f.layer_key,
                SUM(f.occurrence_count) AS cnt
            FROM fact_agent_retro_finding AS f
            CROSS JOIN anchor AS a
            WHERE f.goal_id IS NOT NULL
              AND f.goal_id != ''
              AND f.is_post_fix = 1
              AND f.cst_day >= date(a.end_day, '-' || (:days - 1) || ' days')
              AND f.cst_day <= a.end_day
            GROUP BY f.goal_id, f.layer_key
            """
            rows = conn.execute(sql, {"until_day": until_day, "days": max(1, int(days))}).fetchall()
    except (OSError, sqlite3.Error):
        return {}

    by_goal: dict[str, dict[str, int]] = {}
    for goal_id, layer_key, cnt in rows:
        gid = str(goal_id or "").strip()
        lkey = str(layer_key or "").strip()
        c_val = max(0, int(cnt or 0))
        if gid and lkey and c_val > 0:
            bucket = by_goal.setdefault(gid, {})
            bucket[lkey] = bucket.get(lkey, 0) + c_val
    return by_goal


def load_skill_version_watermarks_from_warehouse(
    warehouse_db: Path | None,
    *,
    until_day: str | None = None,
    days: int = 30,
) -> list[dict[str, Any]]:
    """Read per-goal / per-skill version watermark rows from `fact_agent_retro_finding` (and optional `fact_skill_version_window`)."""
    if warehouse_db is None or not warehouse_db.is_file():
        return []
    out: list[dict[str, Any]] = []
    try:
        with contextlib.closing(
            sqlite3.connect(f"file:{warehouse_db.resolve()}?mode=ro&immutable=1", uri=True)
        ) as conn:
            tables = {
                str(r[0])
                for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
            }
            if "fact_agent_retro_finding" in tables:
                sql = """
                WITH anchor AS (
                    SELECT COALESCE(
                        :until_day,
                        (SELECT MAX(f.cst_day) FROM fact_agent_retro_finding AS f WHERE f.cst_day IS NOT NULL),
                        date('now', '+8 hours')
                    ) AS end_day
                )
                SELECT
                    COALESCE(f.goal_id, '') AS goal_id,
                    f.skill,
                    COALESCE(f.skill_version, '') AS skill_version,
                    f.is_post_fix,
                    SUM(f.occurrence_count) AS cnt,
                    MAX(f.ts) AS latest_ts
                FROM fact_agent_retro_finding AS f
                CROSS JOIN anchor AS a
                WHERE f.skill IS NOT NULL
                  AND f.skill != ''
                  AND f.cst_day >= date(a.end_day, '-' || (:days - 1) || ' days')
                  AND f.cst_day <= a.end_day
                GROUP BY COALESCE(f.goal_id, ''), f.skill, COALESCE(f.skill_version, ''), f.is_post_fix
                """
                for gid, skill, skill_ver, is_post_fix, cnt, latest_ts in conn.execute(
                    sql, {"until_day": until_day, "days": max(1, int(days))}
                ).fetchall():
                    sk = canonical_skill(skill)
                    if not sk:
                        continue
                    out.append({
                        "goal_id": str(gid or "").strip() or None,
                        "skill": sk,
                        "skill_version": str(skill_ver or "").strip() or None,
                        "is_post_fix": int(is_post_fix or 0),
                        "occurrence_count": max(0, int(cnt or 0)),
                        "ts": str(latest_ts or "") or None,
                    })
            if "fact_skill_version_window" in tables:
                cols = {
                    str(r[1])
                    for r in conn.execute("PRAGMA table_info(fact_skill_version_window)").fetchall()
                }
                if {"skill", "skill_version"} <= cols:
                    t_start_col = "t_start" if "t_start" in cols else "NULL"
                    t_end_col = "t_end" if "t_end" in cols else "NULL"
                    w_sql = f"SELECT skill, skill_version, {t_start_col}, {t_end_col} FROM fact_skill_version_window"
                    for skill, skill_ver, t_start, t_end in conn.execute(w_sql).fetchall():
                        sk = canonical_skill(skill)
                        if not sk or not skill_ver:
                            continue
                        out.append({
                            "goal_id": None,
                            "skill": sk,
                            "skill_version": str(skill_ver).strip(),
                            "is_post_fix": None,
                            "occurrence_count": 0,
                            "t_start": str(t_start) if t_start else None,
                            "t_end": str(t_end) if t_end else None,
                        })
    except (OSError, sqlite3.Error):
        return out
    return out


def _parse_goal_retro_watermarks_csv(raw_csv: Any, goal_id: str) -> list[dict[str, Any]]:
    if not raw_csv:
        return []
    entries: list[dict[str, Any]] = []
    for chunk in str(raw_csv).split(","):
        parts = chunk.split("|")
        if len(parts) != 3:
            continue
        sk = canonical_skill(parts[0])
        if not sk:
            continue
        ver = parts[1].strip() or None
        is_post = 1 if parts[2].strip() == "1" else 0
        entries.append({
            "goal_id": goal_id,
            "skill": sk,
            "skill_version": ver,
            "is_post_fix": is_post,
            "occurrence_count": 1,
        })
    return entries


def _build_role_relay(sessions: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    by_role: dict[str, dict[str, Any]] = {}
    total_dur = 0.0
    for sess in sessions:
        rkey = str(sess.get("role_key") or "writer").strip().lower()
        dur = max(0.0, float(sess.get("duration_sec") or 0.0))
        sw = max(0, int((sess.get("action_split") or {}).get("spin_rework_calls") or 0))
        total_dur += dur
        bucket = by_role.get(rkey)
        if bucket is None:
            bucket = {
                "role_key": rkey,
                "role_label_zh": _ROLE_LABELS_ZH.get(rkey, rkey),
                "role_label_en": _ROLE_LABELS_EN.get(rkey, rkey),
                "duration_sec": 0.0,
                "session_count": 0,
                "rework_calls": 0,
            }
            by_role[rkey] = bucket
        bucket["duration_sec"] = round(bucket["duration_sec"] + dur, 1)
        bucket["session_count"] += 1
        bucket["rework_calls"] += sw

    if not by_role:
        return []

    order_map = {rk: idx for idx, rk in enumerate(_ROLE_RELAY_ORDER)}
    sorted_roles = sorted(
        by_role.values(),
        key=lambda item: (order_map.get(item["role_key"], 99), item["role_key"]),
    )
    session_total = max(1, sum(int(r["session_count"]) for r in sorted_roles))
    out: list[dict[str, Any]] = []
    running_pct = 0.0
    for idx, item in enumerate(sorted_roles):
        if idx == len(sorted_roles) - 1:
            pct = round(max(0.0, 100.0 - running_pct), 1) if (total_dur > 0 or sorted_roles) else 0.0
        elif total_dur > 0:
            pct = round(100.0 * float(item["duration_sec"]) / total_dur, 1)
            running_pct += pct
        else:
            pct = round(100.0 * int(item["session_count"]) / session_total, 1)
            running_pct += pct
        out.append({
            "role_key": item["role_key"],
            "role_label_zh": item["role_label_zh"],
            "role_label_en": item["role_label_en"],
            "duration_sec": round(float(item["duration_sec"]), 1),
            "share_pct": pct,
            "session_count": int(item["session_count"]),
            "rework_calls": int(item["rework_calls"]),
        })
    return out


def _classify_goal_focus_bucket(
    *,
    is_unassigned: bool,
    status: str,
    review_round_badge: str | None,
    spin_rework_calls: int,
    ai_signals: Sequence[Mapping[str, Any]],
    has_post_fix_recurrence: bool,
) -> tuple[str, bool]:
    if is_unassigned:
        return "unassigned_daily", False
    norm_status = str(status or "active").strip().lower()
    if norm_status in _ACTIVE_STATUSES or norm_status not in (_DONE_STATUSES | {"cancelled", "canceled", "daily"}):
        return "active_or_blocked", True
    has_warning_signal = any(str(sig.get("severity") or "") == "warning" for sig in ai_signals)
    if (
        has_post_fix_recurrence
        or review_round_badge in {"R2", "R3+"}
        or int(spin_rework_calls or 0) > 0
        or has_warning_signal
    ):
        return "post_fix_collision", True
    return "steady_delivered", False


def _resolve_skill_watermarks_and_cohorts(
    goals_out: list[dict[str, Any]],
    raw_watermarks: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    """Enrich `goals_out[*]['skill_watermarks']` + focus buckets and build `skill_version_cohorts`."""
    wm_rows = [dict(r) for r in raw_watermarks if isinstance(r, Mapping)]

    # Index observed versions and per-(goal, skill) watermark records
    versions_by_skill: dict[str, dict[str, dict[str, Any]]] = {}
    goal_skill_obs: dict[tuple[str, str], list[dict[str, Any]]] = {}

    for rec in wm_rows:
        sk = canonical_skill(rec.get("skill"))
        if not sk:
            continue
        short_ver, ver_num, sha = _clean_skill_version(rec.get("skill_version"))
        if short_ver:
            v_map = versions_by_skill.setdefault(sk, {})
            existing = v_map.get(short_ver)
            if existing is None or (sha and not existing.get("watermark_sha")):
                v_map[short_ver] = {
                    "version_label": short_ver,
                    "version_num": ver_num if ver_num is not None else 0,
                    "watermark_sha": sha,
                    "t_start": rec.get("t_start"),
                    "t_end": rec.get("t_end"),
                }
        gid = str(rec.get("goal_id") or "").strip()
        if gid:
            goal_skill_obs.setdefault((gid, sk), []).append({
                **rec,
                "short_ver": short_ver,
                "ver_num": ver_num,
                "sha": sha,
            })

    # Determine canonical (previous_version, current_version, current_sha) per skill
    skill_pair_meta: dict[str, dict[str, Any]] = {}
    all_touched_skills = {
        str(sk_item["skill"])
        for g in goals_out
        if not g.get("is_unassigned_bucket")
        for sk_item in (g.get("skills_used") or [])
    } | set(versions_by_skill.keys())

    for sk in sorted(all_touched_skills):
        v_entries = sorted(
            (versions_by_skill.get(sk) or {}).values(),
            key=lambda x: (int(x.get("version_num") or 0), str(x.get("version_label") or "")),
        )
        if len(v_entries) >= 2:
            prev_v = str(v_entries[-2]["version_label"])
            curr_v = str(v_entries[-1]["version_label"])
            curr_sha = v_entries[-1].get("watermark_sha")
            t_cut = v_entries[-1].get("t_start")
        elif len(v_entries) == 1:
            curr_v = str(v_entries[0]["version_label"])
            curr_num = int(v_entries[0].get("version_num") or 0)
            prev_v = f"v{curr_num - 1}" if curr_num > 1 else "升级前"
            curr_sha = v_entries[0].get("watermark_sha")
            t_cut = v_entries[0].get("t_start")
        else:
            prev_v = None
            curr_v = None
            curr_sha = None
            t_cut = None
        skill_pair_meta[sk] = {
            "previous_version": prev_v,
            "current_version": curr_v,
            "watermark_sha": curr_sha,
            "t_cut": t_cut,
        }

    # Enrich each goal with skill_watermarks and finalize focus_bucket
    cohort_buckets: dict[str, dict[str, list[dict[str, Any]]]] = {}

    for g in goals_out:
        gid = str(g["goal_id"])
        is_unassigned = bool(g.get("is_unassigned_bucket"))
        if is_unassigned:
            g["skill_watermarks"] = []
            g["focus_bucket"] = "unassigned_daily"
            g["is_focus_anomaly"] = False
            continue

        g_ts = str(g.get("latest_activity_at") or "")
        touched_skills = sorted({
            str(s["skill"]) for s in (g.get("skills_used") or [])
        } | {
            sk for (obs_gid, sk) in goal_skill_obs if obs_gid == gid
        })

        g_watermarks: list[dict[str, Any]] = []
        has_post_fix_recurring = False
        g_rework_collision = (
            g.get("review_round_badge") in {"R2", "R3+"}
            or int((g.get("action_split") or {}).get("spin_rework_calls") or 0) > 0
        )

        for sk in touched_skills:
            meta = skill_pair_meta.get(sk) or {}
            prev_v = meta.get("previous_version")
            curr_v = meta.get("current_version")
            obs_list = goal_skill_obs.get((gid, sk)) or []

            post_obs = [
                o for o in obs_list
                if o.get("is_post_fix") == 1 and int(o.get("occurrence_count") or 0) > 0
            ]
            pre_obs = [
                o for o in obs_list
                if o.get("is_post_fix") == 0 and int(o.get("occurrence_count") or 0) > 0
            ]
            explicit_vers = [o["short_ver"] for o in obs_list if o.get("short_ver")]

            watermark_state: str | None = None
            ver_label: str | None = None
            cohort_side: str | None = None

            if post_obs:
                ver_label = (post_obs[-1].get("short_ver") or curr_v or "当前版")
                watermark_state = "post_fix_recurring"
                cohort_side = "after"
                has_post_fix_recurring = True
            elif pre_obs and (not curr_v or (pre_obs[-1].get("short_ver") and pre_obs[-1].get("short_ver") != curr_v)):
                ver_label = pre_obs[-1].get("short_ver") or prev_v or "升级前"
                watermark_state = "pre_fix_legacy"
                cohort_side = "before"
            elif pre_obs:
                ver_label = prev_v or pre_obs[-1].get("short_ver") or "升级前"
                watermark_state = "pre_fix_legacy"
                cohort_side = "before"
            elif explicit_vers:
                ver_label = explicit_vers[-1]
                if curr_v and ver_label != curr_v:
                    watermark_state = "pre_fix_legacy"
                    cohort_side = "before"
                else:
                    watermark_state = "post_fix_recurring" if g_rework_collision else "post_fix_clean"
                    cohort_side = "after"
                    if watermark_state == "post_fix_recurring":
                        has_post_fix_recurring = True
            elif curr_v:
                t_cut = meta.get("t_cut")
                if t_cut and g_ts and g_ts < str(t_cut):
                    ver_label = prev_v or "升级前"
                    watermark_state = "pre_fix_legacy"
                    cohort_side = "before"
                else:
                    ver_label = curr_v
                    watermark_state = "post_fix_recurring" if g_rework_collision else "post_fix_clean"
                    cohort_side = "after"

            if watermark_state and ver_label:
                if watermark_state == "post_fix_recurring":
                    state_zh = "新版仍复发"
                    state_en = "post-upgrade recurrence"
                elif watermark_state == "pre_fix_legacy":
                    state_zh = "旧版修复前遗留"
                    state_en = "pre-upgrade legacy"
                else:
                    state_zh = "新版已收敛"
                    state_en = "post-upgrade converged"

                g_watermarks.append({
                    "skill": sk,
                    "version_label": ver_label,
                    "watermark_state": watermark_state,
                    "summary_zh": f"{ver_label} {state_zh}",
                    "summary_en": f"{ver_label} {state_en}",
                    "label_zh": f"{sk} {ver_label} · {state_zh}",
                    "label_en": f"{sk} {ver_label} · {state_en}",
                })
                if cohort_side in {"before", "after"}:
                    sk_bkt = cohort_buckets.setdefault(sk, {"before": [], "after": []})
                    sk_bkt[cohort_side].append(g)

        state_priority = {"post_fix_recurring": 0, "pre_fix_legacy": 1, "post_fix_clean": 2}
        g_watermarks.sort(key=lambda w: (state_priority.get(w["watermark_state"], 9), w["skill"]))
        g["skill_watermarks"] = g_watermarks

        fbucket, is_focus = _classify_goal_focus_bucket(
            is_unassigned=False,
            status=str(g.get("status") or "active"),
            review_round_badge=g.get("review_round_badge"),
            spin_rework_calls=int((g.get("action_split") or {}).get("spin_rework_calls") or 0),
            ai_signals=g.get("ai_signals") or [],
            has_post_fix_recurrence=has_post_fix_recurring,
        )
        g["focus_bucket"] = fbucket
        g["is_focus_anomaly"] = is_focus

    # Summarize skill_version_cohorts
    def _cohort_metrics(goal_list: Sequence[Mapping[str, Any]]) -> tuple[int, float | None, float, float | None]:
        cnt = len(goal_list)
        if cnt == 0:
            return 0, None, 0.0, None
        eval_goals = [gg for gg in goal_list if gg.get("review_round_badge")]
        fp_pct = (
            round(100.0 * sum(1 for gg in eval_goals if gg.get("review_round_badge") == "R1") / len(eval_goals), 1)
            if eval_goals
            else None
        )
        tot_calls = sum(int((gg.get("action_split") or {}).get("total_calls") or 0) for gg in goal_list)
        sw_calls = sum(int((gg.get("action_split") or {}).get("spin_rework_calls") or 0) for gg in goal_list)
        rw_pct = round(100.0 * sw_calls / tot_calls, 1) if tot_calls > 0 else 0.0
        durs = [float(gg.get("duration_sec") or 0.0) for gg in goal_list if float(gg.get("duration_sec") or 0.0) > 0]
        return cnt, fp_pct, rw_pct, _median_or_none(durs)

    cohorts_out: list[dict[str, Any]] = []
    for sk, sides in sorted(cohort_buckets.items()):
        meta = skill_pair_meta.get(sk) or {}
        curr_v = meta.get("current_version")
        prev_v = meta.get("previous_version") or "升级前"
        if not curr_v:
            continue
        before_goals = sides["before"]
        after_goals = sides["after"]
        if not before_goals and not after_goals:
            continue

        b_cnt, b_fp, b_rw, b_med = _cohort_metrics(before_goals)
        a_cnt, a_fp, a_rw, a_med = _cohort_metrics(after_goals)
        fp_delta = round(a_fp - b_fp, 1) if (a_fp is not None and b_fp is not None) else None
        rw_delta = round(a_rw - b_rw, 1) if (b_cnt > 0 and a_cnt > 0) else 0.0

        post_recur_cnt = sum(
            1
            for gg in after_goals
            if any(
                wm.get("skill") == sk and wm.get("watermark_state") == "post_fix_recurring"
                for wm in (gg.get("skill_watermarks") or [])
            )
        )

        cohort_entry: dict[str, Any] = {
            "cohort_id": f"{sk}:{prev_v}->{curr_v}",
            "skill": sk,
            "previous_version": prev_v,
            "current_version": curr_v,
            "before_goals_count": b_cnt,
            "after_goals_count": a_cnt,
            "before_first_pass_pct": b_fp,
            "after_first_pass_pct": a_fp,
            "first_pass_delta_pct": fp_delta,
            "before_rework_pct": b_rw,
            "after_rework_pct": a_rw,
            "rework_delta_pct": rw_delta,
            "before_median_duration_sec": b_med,
            "after_median_duration_sec": a_med,
            "post_fix_recurrence_count": post_recur_cnt,
            "before_goal_ids": [str(gg["goal_id"]) for gg in before_goals],
            "after_goal_ids": [str(gg["goal_id"]) for gg in after_goals],
        }
        if meta.get("watermark_sha"):
            cohort_entry["watermark_sha"] = meta["watermark_sha"]
        cohorts_out.append(cohort_entry)

    cohorts_out.sort(
        key=lambda c: (
            -int(c["post_fix_recurrence_count"]),
            -(int(c["before_goals_count"]) + int(c["after_goals_count"])),
            str(c["skill"]),
        )
    )
    return cohorts_out


def _build_time_series_and_trend_summary(
    rows: Sequence[Mapping[str, Any]],
    goals_out: Sequence[Mapping[str, Any]],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Build daily `time_series` and half-window `trend_summary` without fabricating 0% for unevaluated goals."""
    day_sessions: dict[str, dict[str, int]] = {}
    for r in rows:
        day = str(r.get("cst_day") or "").strip()
        if not day:
            continue
        bkt = day_sessions.setdefault(day, {"sessions": 0, "total_calls": 0, "sw_calls": 0})
        bkt["sessions"] += 1
        sr = max(0, int(r.get("search_read_calls") or 0))
        ce = max(0, int(r.get("code_edit_calls") or 0))
        vs = max(0, int(r.get("verify_script_calls") or 0))
        sw = max(0, int(r.get("spin_rework_calls") or 0))
        bkt["total_calls"] += sr + ce + vs + sw
        bkt["sw_calls"] += sw

    day_goals: dict[str, list[Mapping[str, Any]]] = {}
    assigned_goals: list[Mapping[str, Any]] = []
    for g in goals_out:
        if g.get("is_unassigned_bucket"):
            continue
        assigned_goals.append(g)
        g_day = str(g.get("_latest_day") or "").strip()
        if not g_day and g.get("latest_activity_at"):
            g_day = str(g["latest_activity_at"])[:10]
        if g_day:
            day_goals.setdefault(g_day, []).append(g)
            day_sessions.setdefault(g_day, {"sessions": 0, "total_calls": 0, "sw_calls": 0})

    all_days = sorted(day_sessions.keys())
    time_series: list[dict[str, Any]] = []
    for day in all_days:
        sb = day_sessions[day]
        g_list = day_goals.get(day) or []
        eval_g = [gg for gg in g_list if gg.get("review_round_badge")]
        fp_rate = (
            round(100.0 * sum(1 for gg in eval_g if gg.get("review_round_badge") == "R1") / len(eval_g), 1)
            if eval_g
            else None
        )
        durs = [float(gg.get("duration_sec") or 0.0) for gg in g_list if float(gg.get("duration_sec") or 0.0) > 0]
        spin_pct = (
            round(100.0 * sb["sw_calls"] / sb["total_calls"], 1)
            if sb["total_calls"] > 0
            else 0.0
        )
        time_series.append({
            "day": day,
            "goals_completed": len(g_list),
            "first_pass_rate": fp_rate,
            "median_goal_duration_sec": _median_or_none(durs),
            "spin_rework_pct": spin_pct,
            "sessions_count": int(sb["sessions"]),
        })

    # Overall & half-window delta summary
    eval_all = [gg for gg in assigned_goals if gg.get("review_round_badge")]
    overall_fp = (
        round(100.0 * sum(1 for gg in eval_all if gg.get("review_round_badge") == "R1") / len(eval_all), 1)
        if eval_all
        else None
    )
    all_durs = [float(gg.get("duration_sec") or 0.0) for gg in assigned_goals if float(gg.get("duration_sec") or 0.0) > 0]
    overall_med_dur = _median_or_none(all_durs)

    tot_calls_all = sum(b["total_calls"] for b in day_sessions.values())
    sw_calls_all = sum(b["sw_calls"] for b in day_sessions.values())
    overall_spin_pct = round(100.0 * sw_calls_all / tot_calls_all, 1) if tot_calls_all > 0 else 0.0

    fp_delta: float | None = None
    dur_delta: float | None = None
    spin_delta: float | None = None

    if len(all_days) >= 2:
        mid = len(all_days) // 2
        early_days = set(all_days[:mid])
        late_days = set(all_days[mid:])

        early_goals = [gg for d in early_days for gg in (day_goals.get(d) or [])]
        late_goals = [gg for d in late_days for gg in (day_goals.get(d) or [])]

        early_eval = [gg for gg in early_goals if gg.get("review_round_badge")]
        late_eval = [gg for gg in late_goals if gg.get("review_round_badge")]
        if early_eval and late_eval:
            e_fp = 100.0 * sum(1 for gg in early_eval if gg.get("review_round_badge") == "R1") / len(early_eval)
            l_fp = 100.0 * sum(1 for gg in late_eval if gg.get("review_round_badge") == "R1") / len(late_eval)
            fp_delta = round(l_fp - e_fp, 1)

        early_durs = [float(gg.get("duration_sec") or 0.0) for gg in early_goals if float(gg.get("duration_sec") or 0.0) > 0]
        late_durs = [float(gg.get("duration_sec") or 0.0) for gg in late_goals if float(gg.get("duration_sec") or 0.0) > 0]
        e_med = _median_or_none(early_durs)
        l_med = _median_or_none(late_durs)
        if e_med is not None and l_med is not None:
            dur_delta = round(l_med - e_med, 1)

        e_tot = sum(day_sessions[d]["total_calls"] for d in early_days)
        e_sw = sum(day_sessions[d]["sw_calls"] for d in early_days)
        l_tot = sum(day_sessions[d]["total_calls"] for d in late_days)
        l_sw = sum(day_sessions[d]["sw_calls"] for d in late_days)
        if e_tot > 0 and l_tot > 0:
            spin_delta = round((100.0 * l_sw / l_tot) - (100.0 * e_sw / e_tot), 1)

    trend_summary = {
        "first_pass_rate_pct": overall_fp,
        "first_pass_delta_pct": fp_delta,
        "median_goal_duration_sec": overall_med_dur,
        "median_duration_delta_sec": dur_delta,
        "spin_rework_pct": overall_spin_pct,
        "spin_rework_delta_pct": spin_delta,
    }
    return time_series, trend_summary


def _build_repo_delivered_groups(goals_out: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    by_repo: dict[str, list[Mapping[str, Any]]] = {}
    for g in goals_out:
        if g.get("focus_bucket") != "steady_delivered":
            continue
        repo_label = _clean_repo_display(g.get("repo"))
        by_repo.setdefault(repo_label, []).append(g)

    groups: list[dict[str, Any]] = []
    for repo_name, g_list in by_repo.items():
        prs_seen = {
            int((gg.get("outputs") or {}).get("pr_number"))
            for gg in g_list
            if (gg.get("outputs") or {}).get("pr_number") is not None
        }
        eval_g = [gg for gg in g_list if gg.get("review_round_badge")]
        fp_cnt = sum(1 for gg in eval_g if gg.get("review_round_badge") == "R1")
        fp_pct = round(100.0 * fp_cnt / len(eval_g), 1) if eval_g else None
        durs = [float(gg.get("duration_sec") or 0.0) for gg in g_list if float(gg.get("duration_sec") or 0.0) > 0]
        groups.append({
            "repo": repo_name,
            "goals_count": len(g_list),
            "prs_count": len(prs_seen),
            "first_pass_count": fp_cnt,
            "first_pass_rate_pct": fp_pct,
            "total_duration_sec": round(sum(float(gg.get("duration_sec") or 0.0) for gg in g_list), 1),
            "median_duration_sec": _median_or_none(durs),
            "files_changed_count": sum(int((gg.get("outputs") or {}).get("files_changed_count") or 0) for gg in g_list),
            "commits_count": sum(int((gg.get("outputs") or {}).get("commits_count") or 0) for gg in g_list),
            "goal_ids": [str(gg["goal_id"]) for gg in g_list],
        })

    groups.sort(key=lambda grp: (-int(grp["goals_count"]), -float(grp["total_duration_sec"]), str(grp["repo"])))
    return groups


def _build_ai_signals(
    *,
    is_unassigned: bool,
    review_round_badge: str | None,
    action_split: Mapping[str, Any],
    skills_used: list[dict[str, Any]],
    slow_or_failed_scripts: list[dict[str, Any]],
    files_changed_count: int,
    pr_number: int | None,
    retro_layers: Mapping[str, int] | None = None,
) -> list[dict[str, Any]]:
    signals: list[dict[str, Any]] = []

    empty_skills = [s["skill"] for s in skills_used if s.get("empty_load")]
    if empty_skills:
        joined = "、".join(empty_skills[:3])
        signals.append({
            "kind": "empty_skill_load",
            "severity": "warning",
            "target": "skill_owner",
            "label_zh": f"技能空载提醒：{joined} 已加载但未命中参考文档或脚本",
            "label_en": f"Unused skill context: {', '.join(empty_skills[:3])} loaded without script or reference use",
        })

    sr = int(action_split.get("search_read_calls") or 0)
    ce = int(action_split.get("code_edit_calls") or 0)
    sw = int(action_split.get("spin_rework_calls") or 0)

    if ce > 0 and sr / max(1, ce) >= 4.0 and sr >= 8:
        ratio = round(sr / max(1, ce), 1)
        signals.append({
            "kind": "high_search_to_edit",
            "severity": "info",
            "target": "context_routing",
            "label_zh": f"探查阅读占比偏高（探查与编辑比 {ratio}x），可补充上下文目录索引",
            "label_en": f"High read-to-edit ratio ({ratio}x); consider tightening context routing",
        })

    if sw > 0 or slow_or_failed_scripts:
        retry_count = max(sw, len(slow_or_failed_scripts))
        signals.append({
            "kind": "script_or_rework_friction",
            "severity": "warning",
            "target": "tooling",
            "label_zh": f"验证或脚本重试 {retry_count} 次，建议收紧前置参数校验与单步验证",
            "label_en": f"Observed {retry_count} verification retries or slow tool calls; tighten preflight validation",
        })

    if review_round_badge == "R3+":
        signals.append({
            "kind": "multi_round_review",
            "severity": "warning",
            "target": "spec_alignment",
            "label_zh": "多轮审查返工才收敛，建议前置对齐验收边界",
            "label_en": "Converged after three or more review rounds; tighten upfront acceptance criteria",
        })
    elif review_round_badge == "R1" and (pr_number is not None or files_changed_count > 0) and sw == 0:
        signals.append({
            "kind": "first_pass_clean",
            "severity": "positive",
            "target": "workflow",
            "label_zh": "首轮审查一次通过，探查与编码节奏均衡",
            "label_en": "Clean first-pass delivery with balanced read-edit-verify flow",
        })

    if retro_layers:
        for lkey, cnt in sorted(retro_layers.items(), key=lambda kv: (-kv[1], kv[0]))[:2]:
            zh_base, en_base = _LAYER_SIGNAL_LABELS.get(
                lkey,
                ("协作轨迹存在待收敛信号", "Workflow trajectory optimization opportunity"),
            )
            signals.append({
                "kind": f"retro_{lkey}",
                "severity": "warning",
                "target": "agent_retro",
                "label_zh": f"{zh_base}（近期累计 {cnt} 次）",
                "label_en": f"{en_base} ({cnt} occurrences)",
            })

    if not signals and not is_unassigned and files_changed_count > 0:
        signals.append({
            "kind": "steady_delivery",
            "severity": "positive",
            "target": "workflow",
            "label_zh": "交付链路平稳，无空载技能或脚本阻塞",
            "label_en": "Steady delivery with no empty skill loads or script blockers",
        })

    return signals[:5]


def build_work_status_snapshot(
    stream_rows: Iterable[Mapping[str, Any]] | None = None,
    *,
    goal_retro_findings: Mapping[str, Mapping[str, int]] | None = None,
    skill_version_watermarks: Iterable[Mapping[str, Any]] | None = None,
    table_present: bool = True,
    window_cst: str = "14d",
    errors: list[str] | None = None,
) -> dict[str, Any]:
    """Build schema_version=1 `aidash-work-status/v1` snapshot dictionary."""
    rows = [dict(r) for r in (stream_rows or []) if isinstance(r, Mapping)]
    problems = list(errors or [])
    retro_by_goal = goal_retro_findings or {}
    collected_watermarks: list[dict[str, Any]] = [
        dict(w) for w in (skill_version_watermarks or []) if isinstance(w, Mapping)
    ]

    goals_map: dict[str, dict[str, Any]] = {}
    sample_candidates: list[int] = []
    as_of_candidates: list[str] = []
    w_start_candidates: list[str] = []
    w_end_candidates: list[str] = []

    for row in rows:
        if row.get("sample_size") is not None:
            sample_candidates.append(max(0, int(row.get("sample_size") or 0)))
        if row.get("source_as_of"):
            as_of_candidates.append(str(row["source_as_of"]))
        elif row.get("cst_day"):
            as_of_candidates.append(str(row["cst_day"]))
        if row.get("window_start"):
            w_start_candidates.append(str(row["window_start"]))
        if row.get("window_end"):
            w_end_candidates.append(str(row["window_end"]))

        raw_gid = str(row.get("goal_id") or "").strip()
        is_unassigned = bool(row.get("is_unassigned_bucket")) or not raw_gid or raw_gid == UNASSIGNED_GOAL_ID
        gid = UNASSIGNED_GOAL_ID if is_unassigned else raw_gid
        title = (
            UNASSIGNED_GOAL_TITLE
            if is_unassigned
            else str(row.get("goal_title") or gid)
        )

        g_entry = goals_map.get(gid)
        if g_entry is None:
            g_entry = {
                "goal_id": gid,
                "title": title,
                "is_unassigned_bucket": is_unassigned,
                "repo": str(row["repo_name"]) if row.get("repo_name") not in (None, "") else None,
                "status": "daily" if is_unassigned else str(row.get("goal_status") or "active"),
                "review_round_badge": (
                    None
                    if is_unassigned
                    else (str(row["review_round_badge"]) if row.get("review_round_badge") else None)
                ),
                "duration_sec": 0.0,
                "total_tokens": 0,
                "turn_count": 0,
                "sr": 0,
                "ce": 0,
                "vs": 0,
                "sw": 0,
                "files_changed_count": 0,
                "commits_count": 0,
                "pr_number": None,
                "latest_ts": "",
                "latest_day": "",
                "skills_touch": {},
                "slow_failed": [],
                "sessions": [],
            }
            goals_map[gid] = g_entry

        if not g_entry["repo"] and row.get("repo_name"):
            g_entry["repo"] = str(row["repo_name"])
        if row.get("goal_retro_watermarks_csv") and not is_unassigned:
            g_entry.setdefault("_seen_csv_wm", set()).update(
                (
                    w["goal_id"],
                    w["skill"],
                    w.get("skill_version"),
                    w.get("is_post_fix"),
                )
                for w in _parse_goal_retro_watermarks_csv(row["goal_retro_watermarks_csv"], gid)
            )

        dur = round(max(0.0, float(row.get("duration_sec") or 0.0)), 1)
        toks = max(0, int(row.get("total_tokens") or 0))
        turns = max(0, int(row.get("turn_count") or 0))
        sr = max(0, int(row.get("search_read_calls") or 0))
        ce = max(0, int(row.get("code_edit_calls") or 0))
        vs = max(0, int(row.get("verify_script_calls") or 0))
        sw = max(0, int(row.get("spin_rework_calls") or 0))
        f_cnt = max(0, int(row.get("files_changed_count") or 0))
        c_cnt = max(0, int(row.get("commits_count") or 0))
        pr_raw = row.get("pr_number")
        pr_num = int(pr_raw) if isinstance(pr_raw, (int, float)) and not isinstance(pr_raw, bool) and int(pr_raw) > 0 else None

        g_entry["duration_sec"] = round(g_entry["duration_sec"] + dur, 1)
        g_entry["total_tokens"] += toks
        g_entry["turn_count"] += turns
        g_entry["sr"] += sr
        g_entry["ce"] += ce
        g_entry["vs"] += vs
        g_entry["sw"] += sw
        g_entry["files_changed_count"] += f_cnt
        g_entry["commits_count"] += c_cnt
        if pr_num is not None and (g_entry["pr_number"] is None or pr_num > g_entry["pr_number"]):
            g_entry["pr_number"] = pr_num

        end_ts = str(row.get("ended_at") or row.get("started_at") or "")
        g_entry["latest_ts"] = max(g_entry["latest_ts"], end_ts)
        row_day = str(row.get("goal_latest_day") or row.get("cst_day") or "")
        g_entry["latest_day"] = max(g_entry["latest_day"], row_day)

        sess_skills = [
            sk
            for item in _parse_json_list(row.get("skills_json"))
            for sk in [canonical_skill(item)]
            if sk and re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}", sk)
        ]
        ref_skills = _parse_skill_csv(row.get("ref_skills_csv"))
        script_skills = _parse_skill_csv(row.get("script_skills_csv"))
        all_sess_skills = sorted(set(sess_skills) | ref_skills | script_skills)

        sess_skill_items: list[dict[str, Any]] = []
        for sk in all_sess_skills:
            used_ref = sk in ref_skills
            used_script = sk in script_skills
            empty_load = not used_ref and not used_script
            sess_skill_items.append({
                "skill": sk,
                "used_reference": used_ref,
                "used_script": used_script,
                "empty_load": empty_load,
            })
            st = g_entry["skills_touch"].setdefault(
                sk,
                {"skill": sk, "session_loads": 0, "reference_sessions": 0, "script_sessions": 0},
            )
            st["session_loads"] += 1
            if used_ref:
                st["reference_sessions"] += 1
            if used_script:
                st["script_sessions"] += 1

        slow_list = [
            it for it in _parse_json_list(row.get("slow_or_failed_scripts_json"))
            if isinstance(it, Mapping)
        ]
        g_entry["slow_failed"].extend(slow_list)

        rkey = str(row.get("role_key") or "writer").strip().lower()
        sess_split = _build_action_split(sr, ce, vs, sw)
        sess_receipt = {
            "session_uid": str(row.get("session_uid") or ""),
            "session_id_short": str(row.get("session_id_short") or "00000000")[:8],
            "source": str(row.get("source") or "copilot_cli"),
            "role_key": rkey,
            "role_label_zh": _ROLE_LABELS_ZH.get(rkey, rkey),
            "role_label_en": _ROLE_LABELS_EN.get(rkey, rkey),
            "model_id": str(row["model_id"]) if row.get("model_id") not in (None, "") else None,
            "branch": str(row["branch_name"]) if row.get("branch_name") not in (None, "") else None,
            "summary_label": str(row["summary_label"]) if row.get("summary_label") not in (None, "") else None,
            "started_at": str(row["started_at"]) if row.get("started_at") else None,
            "ended_at": str(row["ended_at"]) if row.get("ended_at") else None,
            "cst_day": str(row["cst_day"]) if row.get("cst_day") else None,
            "duration_sec": dur,
            "turn_count": turns,
            "total_tokens": toks,
            "skills_used": sess_skill_items,
            "action_split": sess_split,
            "outputs": {
                "files_changed_count": f_cnt,
                "commits_count": c_cnt,
                "pr_number": pr_num,
            },
        }
        g_entry["sessions"].append(sess_receipt)

    # Sort goals newest first (by latest_ts DESC, keeping assigned goals ahead on exact timestamp ties)
    ordered_goals_raw = sorted(
        goals_map.values(),
        key=lambda g: (g["latest_ts"], 0 if g["is_unassigned_bucket"] else 1),
        reverse=True,
    )

    goals_out: list[dict[str, Any]] = []
    grand_duration = 0.0
    grand_tokens = 0
    grand_files = 0
    grand_commits = 0
    prs_seen: set[tuple[str, int]] = set()
    grand_sr = grand_ce = grand_vs = grand_sw = 0
    active_goals_count = 0

    for g in ordered_goals_raw:
        sessions_sorted = sorted(
            g["sessions"],
            key=lambda s: str(s.get("ended_at") or s.get("started_at") or ""),
            reverse=True,
        )
        skills_out: list[dict[str, Any]] = []
        for sk_name in sorted(g["skills_touch"]):
            st = g["skills_touch"][sk_name]
            ref_s = int(st["reference_sessions"])
            scr_s = int(st["script_sessions"])
            skills_out.append({
                "skill": sk_name,
                "session_loads": int(st["session_loads"]),
                "reference_sessions": ref_s,
                "script_sessions": scr_s,
                "used_reference": ref_s > 0,
                "used_script": scr_s > 0,
                "empty_load": (ref_s == 0 and scr_s == 0),
            })

        g_split = _build_action_split(g["sr"], g["ce"], g["vs"], g["sw"])
        ai_signals = _build_ai_signals(
            is_unassigned=g["is_unassigned_bucket"],
            review_round_badge=g["review_round_badge"],
            action_split=g_split,
            skills_used=skills_out,
            slow_or_failed_scripts=g["slow_failed"],
            files_changed_count=g["files_changed_count"],
            pr_number=g["pr_number"],
            retro_layers=retro_by_goal.get(g["goal_id"]),
        )

        outputs_obj = {
            "files_changed_count": g["files_changed_count"],
            "commits_count": g["commits_count"],
            "pr_number": g["pr_number"],
            "session_count": len(sessions_sorted),
        }

        if not g["is_unassigned_bucket"]:
            active_goals_count += 1
        grand_duration += g["duration_sec"]
        grand_tokens += g["total_tokens"]
        grand_files += g["files_changed_count"]
        grand_commits += g["commits_count"]
        if g["pr_number"] is not None:
            prs_seen.add((g["repo"] or g["goal_id"], g["pr_number"]))
        grand_sr += g["sr"]
        grand_ce += g["ce"]
        grand_vs += g["vs"]
        grand_sw += g["sw"]

        role_relay = _build_role_relay(sessions_sorted)
        goals_out.append({
            "goal_id": g["goal_id"],
            "title": g["title"],
            "is_unassigned_bucket": g["is_unassigned_bucket"],
            "repo": g["repo"],
            "status": g["status"],
            "review_round_badge": g["review_round_badge"],
            "latest_activity_at": g["latest_ts"] or None,
            "_latest_day": g["latest_day"] or None,
            "duration_sec": round(g["duration_sec"], 1),
            "turn_count": g["turn_count"],
            "total_tokens": g["total_tokens"],
            "skills_used": skills_out,
            "skill_watermarks": [],
            "role_relay": role_relay,
            "focus_bucket": "unassigned_daily" if g["is_unassigned_bucket"] else "steady_delivered",
            "is_focus_anomaly": False,
            "action_split": g_split,
            "outputs": outputs_obj,
            "ai_signals": ai_signals,
            "sessions": sessions_sorted,
        })

    for g_raw in ordered_goals_raw:
        for gid_w, sk_w, ver_w, post_w in sorted(g_raw.get("_seen_csv_wm") or set()):
            collected_watermarks.append({
                "goal_id": gid_w,
                "skill": sk_w,
                "skill_version": ver_w,
                "is_post_fix": post_w,
                "occurrence_count": 1,
            })

    skill_version_cohorts = _resolve_skill_watermarks_and_cohorts(goals_out, collected_watermarks)
    time_series, trend_summary = _build_time_series_and_trend_summary(rows, goals_out)
    repo_delivered_groups = _build_repo_delivered_groups(goals_out)
    for g_item in goals_out:
        g_item.pop("_latest_day", None)

    sample_size = max(sample_candidates) if sample_candidates else len(rows)
    source_as_of = max(as_of_candidates) if as_of_candidates else None
    eff_window_cst = (
        str(rows[0].get("window_cst"))
        if rows and rows[0].get("window_cst")
        else window_cst
    )

    if not table_present or (problems and not rows):
        coverage_status = "missing"
    elif problems:
        coverage_status = "partial"
    elif sample_size == 0 or not goals_out:
        coverage_status = "unknown"
    elif grand_tokens == 0 and (grand_sr + grand_ce + grand_vs + grand_sw) == 0:
        coverage_status = "partial"
    else:
        coverage_status = "healthy"

    pulse = {
        "goals_count": active_goals_count,
        "buckets_count": len(goals_out),
        "sessions_count": sample_size,
        "duration_sec": round(grand_duration, 1),
        "total_tokens": grand_tokens,
        "files_changed_count": grand_files,
        "commits_count": grand_commits,
        "prs_touched_count": len(prs_seen),
        "action_split": _build_action_split(grand_sr, grand_ce, grand_vs, grand_sw),
    }

    payload: dict[str, Any] = {
        "contract": "aidash-work-status/v1",
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc)  # noqa: UP017
        .isoformat(timespec="seconds").replace("+00:00", "Z"),
        "window_cst": eff_window_cst,
        "window_start": min(w_start_candidates) if w_start_candidates else None,
        "window_end": max(w_end_candidates) if w_end_candidates else None,
        "source_as_of": source_as_of,
        "sample_size": sample_size,
        "coverage_status": coverage_status,
        "pulse": pulse,
        "trend_summary": trend_summary,
        "time_series": time_series,
        "skill_version_cohorts": skill_version_cohorts,
        "repo_delivered_groups": repo_delivered_groups,
        "goals": goals_out,
    }
    if problems:
        payload["errors"] = problems
    return payload


_MIRROR_SUBPROCESS_SCRIPT = """
import os
import sys
import tempfile
from pathlib import Path

dst = Path(sys.argv[1])
dst.parent.mkdir(parents=True, exist_ok=True)
data = sys.stdin.buffer.read()
tmp = None
try:
    with tempfile.NamedTemporaryFile(mode="wb", dir=dst.parent, prefix=f".{dst.name}.", delete=False) as fh:
        tmp = Path(fh.name)
        fh.write(data)
        fh.flush()
        os.fsync(fh.fileno())
    tmp.replace(dst)
except OSError:
    if tmp is not None:
        tmp.unlink(missing_ok=True)
    dst.write_bytes(data)
finally:
    if tmp is not None:
        tmp.unlink(missing_ok=True)
"""


def _is_cloud_docs_dir(path: Path) -> bool:
    expanded = path.expanduser()
    try:
        return expanded.is_relative_to(ICLOUD_DRIVE_ROOT)
    except (OSError, ValueError):
        return str(ICLOUD_DRIVE_ROOT) in str(expanded)


def _write_local_mirror_fallback(raw_bytes: bytes, filename: str, fallback_dir: Path | None) -> None:
    if fallback_dir is None:
        return
    with contextlib.suppress(OSError):
        fallback_dir.mkdir(parents=True, exist_ok=True)
        (fallback_dir / f".icloud-mirror-fallback-{filename}").write_bytes(raw_bytes)


def _mirror_to_icloud(
    payload: dict[str, Any],
    filename: str,
    sync_dir: Path | None,
    *,
    timeout_sec: float | None = None,
    fallback_dir: Path | None = None,
) -> bool:
    resolved = resolve_icloud_sync_dir(sync_dir)
    if resolved is None:
        return False
    raw_bytes = (json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")
    destination_dir = resolved / "jobs" / "aidata-digest"
    destination = destination_dir / filename
    use_subprocess = (
        os.environ.get("AIDASH_ICLOUD_FORCE_SUBPROCESS") == "1"
        or _is_cloud_docs_dir(resolved)
    )
    if use_subprocess:
        eff_timeout = (
            timeout_sec
            if timeout_sec is not None
            else float(os.environ.get("AIDASH_ICLOUD_MIRROR_TIMEOUT_SEC", "5.0"))
        )
        try:
            result = subprocess.run(  # nosec B603
                [sys.executable, "-c", _MIRROR_SUBPROCESS_SCRIPT, str(destination)],
                input=raw_bytes,
                capture_output=True,
                check=False,
                shell=False,
                timeout=eff_timeout,
            )
            if result.returncode == 0:
                return True
        except (OSError, TimeoutError, subprocess.SubprocessError):
            pass
        _write_local_mirror_fallback(raw_bytes, filename, fallback_dir)
        return False

    tmp: Path | None = None
    try:
        destination_dir.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="wb",
            dir=destination_dir,
            prefix=f".{filename}.",
            delete=False,
        ) as handle:
            tmp = Path(handle.name)
            handle.write(raw_bytes)
            handle.flush()
            with contextlib.suppress(OSError):
                os.fsync(handle.fileno())
        tmp.replace(destination)
        return True
    except (OSError, TimeoutError):
        if tmp is not None:
            with contextlib.suppress(OSError):
                tmp.unlink(missing_ok=True)
            tmp = None
        _write_local_mirror_fallback(raw_bytes, filename, fallback_dir)
        with contextlib.suppress(OSError):
            destination_dir.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(raw_bytes)
        return False
    finally:
        if tmp is not None:
            with contextlib.suppress(OSError):
                tmp.unlink(missing_ok=True)


def write_snapshot(
    output: Path = _DEFAULT_OUTPUT,
    *,
    until_day: str | None = None,
    days: int = 14,
    warehouse_db: Path | None = None,
    query_runner: Callable[..., tuple[list[tuple[Any, ...]], list[str]]] | None = None,
    icloud_sync_dir: Path | None = None,
) -> dict[str, Any]:
    """Run L4 work-stream query, enrich with retro signals, and atomically write work-status.json."""
    runner = query_runner or serve.run_query
    errors: list[str] = []
    stream_dicts: list[dict[str, Any]] = []
    table_present = True

    params: dict[str, Any] = {"days": max(1, int(days))}
    if until_day:
        params["until_day"] = until_day

    try:
        s_rows, s_cols = runner(WORK_STREAM_QUERY, params)
        if s_cols and "session_uid" in s_cols:
            stream_dicts = [dict(zip(s_cols, vals)) for vals in s_rows]
        elif not s_cols and not s_rows:
            table_present = False
    except Exception as exc:  # noqa: BLE001
        table_present = False
        errors.append(f"{WORK_STREAM_QUERY} unavailable: {type(exc).__name__}")

    eff_wh = warehouse_db
    if eff_wh is None and query_runner is None and not os.environ.get("PYTEST_CURRENT_TEST"):
        eff_wh = config.WAREHOUSE_DB
    retro_by_goal = load_goal_retro_findings_from_warehouse(
        eff_wh,
        until_day=until_day,
        days=days,
    )
    wm_rows = load_skill_version_watermarks_from_warehouse(
        eff_wh,
        until_day=until_day,
        days=max(30, int(days) * 2),
    )

    payload = build_work_status_snapshot(
        stream_dicts,
        goal_retro_findings=retro_by_goal,
        skill_version_watermarks=wm_rows,
        table_present=table_present,
        window_cst=f"{max(1, int(days))}d",
        errors=errors,
    )

    output.parent.mkdir(parents=True, exist_ok=True)
    tmp: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=output.parent,
            prefix=output.name + ".",
            delete=False,
        ) as handle:
            tmp = Path(handle.name)
            json.dump(payload, handle, ensure_ascii=False, indent=2, allow_nan=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        tmp.replace(output)
        directory = os.open(output.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if tmp is not None:
            tmp.unlink(missing_ok=True)
    _mirror_to_icloud(payload, output.name, icloud_sync_dir, fallback_dir=output.parent)
    return payload


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=_DEFAULT_OUTPUT)
    parser.add_argument("--until-day", type=str, default=None)
    parser.add_argument("--days", type=int, default=14)
    args = parser.parse_args(argv)
    payload = write_snapshot(
        args.output,
        until_day=args.until_day,
        days=args.days,
    )
    return 1 if payload.get("errors") else 0


if __name__ == "__main__":
    raise SystemExit(main())
