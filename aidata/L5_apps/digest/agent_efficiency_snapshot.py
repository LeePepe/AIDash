"""Canonical aidash-agent-efficiency/v1 snapshot artifact for AIDashApp.

Consumes the L4 `retro/agent_role_efficiency` and `retro/daily_agent_efficiency`
queries plus optional Magpie gateway usage JSONL tail to emit an atomic,
degrade-safe JSON snapshot at:
  ~/Library/Application Support/AIDash/jobs/aidata-digest/agent-efficiency.json

Missing warehouse or empty populations produce explicit coverage_status
(`missing` / `unknown` / `partial`) instead of fabricated healthy zeros.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import sqlite3
import subprocess  # nosec B404 - fixed python helper only
import sys
import tempfile
from collections.abc import Callable, Iterable, Mapping
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import config
import serve
from config import ICLOUD_DRIVE_ROOT, resolve_icloud_sync_dir


def _l4_role_query() -> str:
    return "retro/" + "agent_role_efficiency"


def _l4_daily_query() -> str:
    return "retro/" + "daily_agent_efficiency"


def _l4_six_layer_query() -> str:
    return "retro/" + "agent_retro_six_layer"


def _l4_horizon_waste_query() -> str:
    return "retro/" + "agent_horizon_waste"


ROLE_QUERY = _l4_role_query()
DAILY_QUERY = _l4_daily_query()
SIX_LAYER_QUERY = _l4_six_layer_query()
HORIZON_WASTE_QUERY = _l4_horizon_waste_query()

_DEFAULT_OUTPUT = (
    Path.home()
    / "Library"
    / "Application Support"
    / "AIDash"
    / "jobs"
    / "aidata-digest"
    / "agent-efficiency.json"
)
_DEFAULT_MAGPIE_USAGE = Path.home() / ".config" / "magpie" / "usage.jsonl"

_ROLE_LABELS_EN: dict[str, str] = {
    "m3": "Top-Level Coordinator",
    "m2": "Topic Dispatcher",
    "m1": "Goal Lead (TL)",
    "designer": "Visual Design (Designer)",
    "writer": "Code Implementation (Writer)",
    "reviewer": "Independent Review (Reviewer)",
    "explorer": "Code Exploration (Explorer)",
    "pr_monitor": "Delivery Monitor (PR Monitor)",
}

_ROLE_LABELS_ZH: dict[str, str] = {
    "m3": "总控协调",
    "m2": "话题编排",
    "m1": "Goal 主控 (TL)",
    "designer": "视觉设计 (Designer)",
    "writer": "编码实现 (Writer)",
    "reviewer": "独立审查 (Reviewer)",
    "explorer": "代码探查 (Explorer)",
    "pr_monitor": "交付监控 (PR Monitor)",
}

_AGENT_RETRO_LAYERS_META: tuple[tuple[str, str, str], ...] = (
    ("role", "角色边界", "Role Boundaries"),
    ("handoff", "交接完整度", "Handoff Completeness"),
    ("invoke", "工具与参考调用", "Tool & Reference Invocation"),
    ("exec", "执行与返工收敛", "Execution & Rework Convergence"),
    ("friction", "人机协作摩擦", "Human-Agent Collaboration Friction"),
    ("horizon", "长程上下文损耗", "Long-Horizon Context Waste"),
)

_HORIZON_CATEGORY_LABELS: dict[str, tuple[str, str]] = {
    "context_carry": ("未引用重输出残留", "Unreferenced Context Carry"),
    "wakeup_parallelism": ("唤醒延迟与串行排队", "Wakeup Lag & Serial Queueing"),
    "rework_verify": ("返工绕路与过早全量验证", "Rework Detours & Early Full Verify"),
    "fatigue_inflection": ("长程疲劳失焦拐点", "Long-Session Fatigue Inflection"),
    "steering_overkill": ("高阶模型机械轮询", "High-Tier Model Mechanical Polling"),
}


def _classify_watermark_status(pre_fix_count: int, post_fix_count: int, skill_version: str | None) -> str:
    if post_fix_count > 0 and pre_fix_count > 0:
        return "regressed" if post_fix_count >= pre_fix_count else "observing"
    if post_fix_count > 0:
        return "regressed"
    if pre_fix_count > 0 and post_fix_count == 0:
        return "improved"
    return "baseline" if skill_version else "observing"


def load_skill_watermarks_from_warehouse(
    warehouse_db: Path | None,
    *,
    until_day: str | None = None,
    days: int = 30,
) -> tuple[list[dict[str, Any]], bool]:
    """Read per-skill vN@sha pre_fix vs post_fix watermarks from fact_agent_retro_finding."""
    if warehouse_db is None or not warehouse_db.is_file():
        return [], False
    try:
        with contextlib.closing(
            sqlite3.connect(f"file:{warehouse_db.resolve()}?mode=ro", uri=True)
        ) as conn:
            tables = {
                str(r[0])
                for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
            }
            if "fact_agent_retro_finding" not in tables:
                return [], False
            anchor_sql = """
            WITH anchor AS (
                SELECT COALESCE(
                    :until_day,
                    (SELECT MAX(f.cst_day) FROM fact_agent_retro_finding AS f WHERE f.cst_day IS NOT NULL),
                    date('now', '+8 hours')
                ) AS end_day
            )
            SELECT
                f.skill,
                MAX(f.skill_version) AS skill_version,
                SUM(CASE WHEN f.is_post_fix = 0 THEN f.occurrence_count ELSE 0 END) AS pre_fix_count,
                SUM(CASE WHEN f.is_post_fix = 1 THEN f.occurrence_count ELSE 0 END) AS post_fix_count,
                MAX(f.cst_day) AS source_as_of
            FROM fact_agent_retro_finding AS f
            CROSS JOIN anchor AS a
            WHERE f.cst_day >= date(a.end_day, '-' || (:days - 1) || ' days')
              AND f.cst_day <= a.end_day
            GROUP BY f.skill
            ORDER BY SUM(CASE WHEN f.is_post_fix = 1 THEN f.occurrence_count ELSE 0 END) DESC,
                     SUM(f.occurrence_count) DESC,
                     f.skill ASC
            """
            rows = conn.execute(
                anchor_sql,
                {"until_day": until_day, "days": max(1, int(days))},
            ).fetchall()
    except (OSError, sqlite3.Error):
        return [], False

    watermarks: list[dict[str, Any]] = []
    for skill, skill_ver, pre_cnt, post_cnt, as_of in rows:
        sk = str(skill or "").strip()
        if not sk:
            continue
        pre_i = max(0, int(pre_cnt or 0))
        post_i = max(0, int(post_cnt or 0))
        sv_s = str(skill_ver).strip() if skill_ver not in (None, "") else None
        watermarks.append({
            "skill": sk,
            "skill_version": sv_s,
            "pre_fix_count": pre_i,
            "post_fix_count": post_i,
            "status": _classify_watermark_status(pre_i, post_i, sv_s),
            "source_as_of": str(as_of) if as_of else None,
        })
    return watermarks, True


def build_agent_retro_section(
    layer_rows: Iterable[Mapping[str, Any]] | None = None,
    horizon_rows: Iterable[Mapping[str, Any]] | None = None,
    skill_watermarks: Iterable[Mapping[str, Any]] | None = None,
    *,
    table_present: bool = True,
    window_cst: str = "14d",
) -> dict[str, Any]:
    """Build backward-compatible plain-language `agent_retro` payload section."""
    l_list = [dict(r) for r in (layer_rows or []) if isinstance(r, Mapping)]
    h_list = [dict(r) for r in (horizon_rows or []) if isinstance(r, Mapping)]
    wm_list = [dict(r) for r in (skill_watermarks or []) if isinstance(r, Mapping)]

    by_layer = {str(r.get("layer_key") or "").strip(): r for r in l_list}
    layers_out: list[dict[str, Any]] = []
    pre_fix_total = 0
    post_fix_total = 0
    sample_candidates: list[int] = []
    as_of_candidates: list[str] = []

    for layer_key, label_zh, label_en in _AGENT_RETRO_LAYERS_META:
        src = by_layer.get(layer_key, {})
        pre_c = max(0, int(src.get("pre_fix_count") or 0))
        post_c = max(0, int(src.get("post_fix_count") or 0))
        tot_c = max(pre_c + post_c, int(src.get("total_occurrences") or 0))
        aff_s = max(0, int(src.get("affected_sessions") or 0))
        pre_fix_total += pre_c
        post_fix_total += post_c
        if src.get("sample_size") is not None:
            sample_candidates.append(max(0, int(src.get("sample_size") or 0)))
        if src.get("source_as_of"):
            as_of_candidates.append(str(src["source_as_of"]))
        rkey = str(src.get("top_role_key") or "").strip() or None
        layers_out.append({
            "layer_key": layer_key,
            "label_zh": label_zh,
            "label_en": label_en,
            "pre_fix_count": pre_c,
            "post_fix_count": post_c,
            "total_count": tot_c,
            "affected_sessions": aff_s,
            "top_role_key": rkey,
            "top_role_label_zh": _ROLE_LABELS_ZH.get(rkey, rkey) if rkey else None,
            "top_role_label_en": _ROLE_LABELS_EN.get(rkey, rkey) if rkey else None,
            "top_skill": str(src.get("top_skill") or "").strip() or None,
            "top_skill_version": str(src.get("top_skill_version") or "").strip() or None,
        })

    horizon_items: list[dict[str, Any]] = []
    wasted_turns_total = 0
    wasted_tokens_total = 0
    for hrow in h_list:
        cat_key = str(hrow.get("category_key") or "context_carry").strip()
        zh_lbl, en_lbl = _HORIZON_CATEGORY_LABELS.get(
            cat_key,
            ("长程上下文损耗", "Long-Horizon Context Waste"),
        )
        w_turns = max(0, int(hrow.get("wasted_turns") or 0))
        w_toks = max(0, int(hrow.get("wasted_tokens") or 0))
        dur = round(max(0.0, float(hrow.get("duration_sec") or 0.0)), 1)
        rkey = str(hrow.get("role_key") or "writer").strip()
        wasted_turns_total += w_turns
        wasted_tokens_total += w_toks
        if hrow.get("sample_size") is not None:
            sample_candidates.append(max(0, int(hrow.get("sample_size") or 0)))
        if hrow.get("source_as_of"):
            as_of_candidates.append(str(hrow["source_as_of"]))
        horizon_items.append({
            "category_key": cat_key,
            "label_zh": zh_lbl,
            "label_en": en_lbl,
            "role_key": rkey,
            "role_label_zh": _ROLE_LABELS_ZH.get(rkey, rkey),
            "role_label_en": _ROLE_LABELS_EN.get(rkey, rkey),
            "skill": str(hrow.get("skill") or "unmeasured"),
            "wasted_turns": w_turns,
            "wasted_tokens": w_toks,
            "duration_sec": dur,
            "token_share_pct": round(float(hrow.get("token_share_pct") or 0.0), 2),
        })

    if not wm_list and l_list:
        inferred_wm: dict[str, dict[str, Any]] = {}
        for lrow in l_list:
            sk = str(lrow.get("top_skill") or "").strip()
            if not sk:
                continue
            pre_c = max(0, int(lrow.get("pre_fix_count") or 0))
            post_c = max(0, int(lrow.get("post_fix_count") or 0))
            sv = str(lrow.get("top_skill_version") or "").strip() or None
            cur = inferred_wm.setdefault(
                sk,
                {"skill": sk, "skill_version": sv, "pre_fix_count": 0, "post_fix_count": 0},
            )
            cur["pre_fix_count"] += pre_c
            cur["post_fix_count"] += post_c
            if sv and not cur.get("skill_version"):
                cur["skill_version"] = sv
        for entry in inferred_wm.values():
            entry["status"] = _classify_watermark_status(
                entry["pre_fix_count"],
                entry["post_fix_count"],
                entry.get("skill_version"),
            )
            wm_list.append(entry)

    watermarks_out: list[dict[str, Any]] = []
    for wm in wm_list:
        sk = str(wm.get("skill") or "").strip()
        if not sk:
            continue
        pre_c = max(0, int(wm.get("pre_fix_count") or 0))
        post_c = max(0, int(wm.get("post_fix_count") or 0))
        sv = str(wm.get("skill_version") or "").strip() or None
        st = str(wm.get("status") or "").strip() or _classify_watermark_status(pre_c, post_c, sv)
        if wm.get("source_as_of"):
            as_of_candidates.append(str(wm["source_as_of"]))
        watermarks_out.append({
            "skill": sk,
            "skill_version": sv,
            "pre_fix_count": pre_c,
            "post_fix_count": post_c,
            "status": st,
        })

    sample_size = max(sample_candidates) if sample_candidates else 0
    if sample_size == 0 and (pre_fix_total + post_fix_total > 0 or horizon_items):
        sample_size = max(1, len(horizon_items))
    source_as_of = max(as_of_candidates) if as_of_candidates else None
    eff_window_cst = (
        str(l_list[0].get("window_cst"))
        if l_list and l_list[0].get("window_cst")
        else window_cst
    )

    if not table_present:
        cov_status = "missing"
    elif sample_size == 0 and pre_fix_total == 0 and post_fix_total == 0 and not horizon_items:
        cov_status = "unknown"
    elif (pre_fix_total + post_fix_total > 0) and not horizon_items:
        cov_status = "partial"
    elif horizon_items and (pre_fix_total + post_fix_total == 0):
        cov_status = "partial"
    else:
        cov_status = "healthy"

    return {
        "coverage_status": cov_status,
        "sample_size": sample_size,
        "source_as_of": source_as_of,
        "window_cst": eff_window_cst,
        "pre_fix_total": pre_fix_total,
        "post_fix_total": post_fix_total,
        "layers": layers_out,
        "horizon_waste": {
            "wasted_turns_total": wasted_turns_total,
            "wasted_tokens_total": wasted_tokens_total,
            "items": horizon_items,
        },
        "skill_watermarks": watermarks_out,
    }


def _read_magpie_role_telemetry(
    magpie_path: Path | None,
    *,
    window_start: str | None = None,
    window_end: str | None = None,
    max_bytes: int = 1_048_576,
) -> dict[str, Any]:
    """Read tail of ~/.config/magpie/usage.jsonl for routing-group token & TTFT stats."""
    empty = {
        "by_role_tokens": {},
        "ttft_p90_sec": None,
        "cache_hit_rate": None,
        "steering_token_share": None,
    }
    if magpie_path is None or not magpie_path.is_file():
        return empty
    try:
        with magpie_path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            if size <= 0:
                return empty
            offset = max(0, size - max_bytes)
            handle.seek(offset)
            raw_bytes = handle.read()
        text = raw_bytes.decode("utf-8", errors="ignore")
        if offset > 0 and "\n" in text:
            text = text.split("\n", 1)[1]
    except OSError:
        return empty

    by_role_tokens: dict[str, int] = {}
    ttfts: list[int] = []
    total_in = 0
    total_cr = 0
    total_all = 0
    steering_all = 0

    for line in text.splitlines()[-4000:]:
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if not isinstance(obj, dict):
            continue
        ts = str(obj.get("t") or "")
        day = ts[:10] if len(ts) >= 10 else ""
        if window_start and day and day < window_start:
            continue
        if window_end and day and day > window_end:
            continue
        req = str(obj.get("req") or obj.get("model") or "").lower()
        model = str(obj.get("served") or obj.get("model") or "").lower()
        if obj.get("source") == "probe":
            continue
        in_tok = max(int(obj.get("in") or 0), 0)
        out_tok = max(int(obj.get("out") or 0), 0)
        cr_tok = max(int(obj.get("cache_read") or 0), 0)
        cw_tok = max(int(obj.get("cache_write") or 0), 0)
        tok = in_tok + out_tok + cr_tok + cw_tok
        if tok <= 0:
            continue

        if "steering" in req:
            role_key = "m1"
        elif "designer" in req:
            role_key = "designer"
        elif "review" in req:
            role_key = "reviewer"
        elif "coding" in req:
            role_key = "writer"
        elif "jevs" in req or model == "microsoft-decision-1":
            role_key = "m3"
        elif "flash" in model:
            role_key = "explorer"
        else:
            role_key = "m2"

        by_role_tokens[role_key] = by_role_tokens.get(role_key, 0) + tok
        total_in += in_tok
        total_cr += cr_tok
        total_all += tok
        if role_key in {"m1", "m2", "m3"}:
            steering_all += tok
        ttft = obj.get("ttft_ms")
        if isinstance(ttft, (int, float)) and not isinstance(ttft, bool) and ttft > 0:
            ttfts.append(int(ttft))

    ttft_p90_sec: float | None = None
    if ttfts:
        ttfts.sort()
        idx = min(len(ttfts) - 1, max(0, int(len(ttfts) * 0.9)))
        ttft_p90_sec = round(ttfts[idx] / 1000.0, 2)

    cache_hit_rate = (
        round(total_cr / (total_in + total_cr), 4)
        if (total_in + total_cr) > 0
        else None
    )
    steering_share = (
        round(steering_all / total_all, 4)
        if total_all > 0
        else None
    )
    return {
        "by_role_tokens": by_role_tokens,
        "ttft_p90_sec": ttft_p90_sec,
        "cache_hit_rate": cache_hit_rate,
        "steering_token_share": steering_share,
    }


def _weighted_median_and_p90(roles: list[dict[str, Any]]) -> tuple[float | None, float | None]:
    med_num = 0.0
    med_den = 0
    p90_max: float | None = None
    for role in roles:
        runs = max(int(role.get("runs_count") or 0), 1)
        med = role.get("median_duration_sec")
        p90 = role.get("p90_duration_sec")
        if isinstance(med, (int, float)) and med > 0:
            med_num += float(med) * runs
            med_den += runs
        if isinstance(p90, (int, float)) and p90 > 0:
            p90_max = float(p90) if p90_max is None else max(p90_max, float(p90))
    overall_median = round(med_num / med_den, 1) if med_den > 0 else None
    return overall_median, (round(p90_max, 1) if p90_max is not None else None)


def build_agent_efficiency_snapshot(
    role_rows: list[dict[str, Any]],
    daily_rows: list[dict[str, Any]],
    *,
    magpie_telemetry: dict[str, Any] | None = None,
    agent_retro: Mapping[str, Any] | None = None,
    errors: list[str] | None = None,
) -> dict[str, Any]:
    """Assemble schema_version=1 aidash-agent-efficiency snapshot dictionary."""
    problems = list(errors or [])
    magpie = magpie_telemetry or {}
    magpie_by_role: dict[str, int] = dict(magpie.get("by_role_tokens") or {})

    roles_out: list[dict[str, Any]] = []
    combined_tokens_total = 0
    merged_tokens_map: dict[str, int] = {}

    for row in role_rows:
        rkey = str(row.get("role_key") or "writer")
        sql_tokens = max(int(row.get("estimated_tokens") or 0), 0)
        mg_tokens = max(int(magpie_by_role.get(rkey, 0)), 0)
        tok = max(sql_tokens, mg_tokens)
        merged_tokens_map[rkey] = tok
        combined_tokens_total += tok

    for row in role_rows:
        rkey = str(row.get("role_key") or "writer")
        tok = merged_tokens_map.get(rkey, 0)
        share_pct = (
            round(100.0 * tok / combined_tokens_total, 2)
            if combined_tokens_total > 0
            else 0.0
        )
        r1 = max(int(row.get("r1_count") or 0), 0)
        r2 = max(int(row.get("r2_count") or 0), 0)
        r3p = max(int(row.get("r3_plus_count") or 0), 0)
        pass_rate = row.get("r1_pass_rate")
        if pass_rate is not None:
            pass_rate = round(float(pass_rate), 4)
        med = row.get("median_duration_sec")
        p90 = row.get("p90_duration_sec")
        entry = {
            "role_key": rkey,
            "role_label": _ROLE_LABELS_ZH.get(rkey, str(row.get("role_label") or rkey)),
            "role_label_en": _ROLE_LABELS_EN.get(rkey, rkey),
            "runs_count": max(int(row.get("runs_count") or 0), 0),
            "goals_count": max(int(row.get("goals_count") or 0), 0),
            "tasks_count": max(int(row.get("tasks_count") or 0), 0),
            "r1_count": r1,
            "r2_count": r2,
            "r3_plus_count": r3p,
            "r1_pass_rate": pass_rate,
            "median_duration_sec": round(float(med), 1) if isinstance(med, (int, float)) else None,
            "p90_duration_sec": round(float(p90), 1) if isinstance(p90, (int, float)) else None,
            "estimated_tokens": tok,
            "token_share_pct": share_pct,
        }
        roles_out.append(entry)

    daily_out: list[dict[str, Any]] = []
    for drow in daily_rows:
        day = str(drow.get("cst_day") or "")
        if not day:
            continue
        pr = drow.get("r1_pass_rate")
        med = drow.get("median_duration_sec")
        p90 = drow.get("p90_duration_sec")
        daily_out.append({
            "day": day,
            "cst_day": day,
            "goals_completed": max(int(drow.get("goals_completed") or 0), 0),
            "tasks_completed": max(int(drow.get("tasks_completed") or 0), 0),
            "r1_count": max(int(drow.get("r1_count") or 0), 0),
            "r2_count": max(int(drow.get("r2_count") or 0), 0),
            "r3_plus_count": max(int(drow.get("r3_plus_count") or 0), 0),
            "r1_pass_rate": round(float(pr), 4) if isinstance(pr, (int, float)) else None,
            "median_duration_sec": round(float(med), 1) if isinstance(med, (int, float)) else None,
            "p90_duration_sec": round(float(p90), 1) if isinstance(p90, (int, float)) else None,
            "blocked_events": max(int(drow.get("blocked_events") or 0), 0),
            "steering_tokens": max(int(drow.get("steering_tokens") or 0), 0),
            "coding_tokens": max(int(drow.get("coding_tokens") or 0), 0),
            "total_tokens": max(int(drow.get("total_tokens") or 0), 0),
        })

    # Compute review round summary primarily over review/implementation tasks to avoid
    # inflating pass rate with synthetic M1/M2 coordination ticks.
    exec_roles = [r for r in roles_out if r["role_key"] in {"reviewer", "writer", "designer"}]
    r1_total = sum(r["r1_count"] for r in exec_roles)
    r2_total = sum(r["r2_count"] for r in exec_roles)
    r3p_total = sum(r["r3_plus_count"] for r in exec_roles)
    eval_total = r1_total + r2_total + r3p_total
    overall_r1_pass = round(r1_total / eval_total, 4) if eval_total > 0 else None

    overall_median_sec, overall_p90_sec = _weighted_median_and_p90(
        [r for r in roles_out if r["role_key"] in {"writer", "reviewer", "designer", "explorer", "pr_monitor"}]
    )

    steering_tok_sum = sum(
        r["estimated_tokens"] for r in roles_out if r["role_key"] in {"m3", "m2", "m1"}
    )
    steering_share = (
        magpie.get("steering_token_share")
        if magpie.get("steering_token_share") is not None
        else (round(steering_tok_sum / combined_tokens_total, 4) if combined_tokens_total > 0 else None)
    )

    total_runs = sum(r["runs_count"] for r in roles_out)
    total_daily_tasks = sum(d["tasks_completed"] for d in daily_out)
    sample_size = max(total_runs, total_daily_tasks)

    window_start = daily_out[0]["day"] if daily_out else None
    window_end = daily_out[-1]["day"] if daily_out else None
    active_days = [
        d["day"]
        for d in daily_out
        if d["tasks_completed"] > 0 or d["goals_completed"] > 0 or d["total_tokens"] > 0
    ]
    source_as_of = active_days[-1] if active_days else window_end

    if problems and not roles_out and not daily_out:
        coverage_status = "missing"
    elif problems:
        coverage_status = "error"
    elif sample_size == 0:
        coverage_status = "unknown"
    elif not daily_out or combined_tokens_total == 0:
        coverage_status = "partial"
    else:
        coverage_status = "healthy"

    round_summary = {
        "r1_count": r1_total,
        "r2_count": r2_total,
        "r3_plus_count": r3p_total,
        "evaluated_tasks": eval_total,
        "r1_pass_rate": overall_r1_pass,
        "median_duration_sec": overall_median_sec,
        "p90_duration_sec": overall_p90_sec,
        "steering_token_share": steering_share,
        "ttft_p90_sec": magpie.get("ttft_p90_sec"),
        "cache_hit_rate": magpie.get("cache_hit_rate"),
    }

    payload: dict[str, Any] = {
        "contract": "aidash-agent-efficiency/v1",
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc)
        .isoformat(timespec="seconds").replace("+00:00", "Z"),
        "window_cst": "14d",
        "window_start": window_start,
        "window_end": window_end,
        "source_as_of": source_as_of,
        "sample_size": sample_size,
        "coverage_status": coverage_status,
        "roles": roles_out,
        "role_breakdown": roles_out,
        "round_summary": round_summary,
        "round_distribution": round_summary,
        "daily_series": daily_out,
        "daily_trend": daily_out,
        "agent_retro": dict(agent_retro)
        if isinstance(agent_retro, Mapping)
        else build_agent_retro_section(table_present=False),
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
    magpie_path: Path | None = _DEFAULT_MAGPIE_USAGE,
    warehouse_db: Path | None = None,
    query_runner: Callable[..., tuple[list[tuple[Any, ...]], list[str]]] | None = None,
    icloud_sync_dir: Path | None = None,
) -> dict[str, Any]:
    """Run L4 queries, merge optional Magpie usage, and atomically write snapshot JSON."""
    runner = query_runner or serve.run_query
    errors: list[str] = []
    role_dicts: list[dict[str, Any]] = []
    daily_dicts: list[dict[str, Any]] = []
    six_layer_dicts: list[dict[str, Any]] = []
    horizon_dicts: list[dict[str, Any]] = []
    retro_table_present = True

    try:
        r_rows, r_cols = runner(ROLE_QUERY)
        role_dicts = [dict(zip(r_cols, vals)) for vals in r_rows]
    except Exception as exc:  # noqa: BLE001
        errors.append(f"{ROLE_QUERY} unavailable: {type(exc).__name__}")

    try:
        params = {"until_day": until_day} if until_day else None
        d_rows, d_cols = runner(DAILY_QUERY, params) if params else runner(DAILY_QUERY)
        daily_dicts = [dict(zip(d_cols, vals)) for vals in d_rows]
    except Exception as exc:  # noqa: BLE001
        errors.append(f"{DAILY_QUERY} unavailable: {type(exc).__name__}")

    retro_params = {"until_day": until_day} if until_day else None
    try:
        sl_rows, sl_cols = (
            runner(SIX_LAYER_QUERY, retro_params)
            if retro_params
            else runner(SIX_LAYER_QUERY)
        )
        if sl_cols and "layer_key" in sl_cols:
            six_layer_dicts = [dict(zip(sl_cols, vals)) for vals in sl_rows]
        else:
            retro_table_present = False
    except Exception:  # noqa: BLE001 - optional opt-in table degrades without failing snapshot
        retro_table_present = False

    try:
        hz_rows, hz_cols = (
            runner(HORIZON_WASTE_QUERY, retro_params)
            if retro_params
            else runner(HORIZON_WASTE_QUERY)
        )
        if hz_cols and "category_key" in hz_cols:
            horizon_dicts = [dict(zip(hz_cols, vals)) for vals in hz_rows]
    except Exception:  # noqa: BLE001
        pass

    eff_wh = warehouse_db
    if eff_wh is None and query_runner is None and not os.environ.get("PYTEST_CURRENT_TEST"):
        eff_wh = config.WAREHOUSE_DB
    wm_rows, wm_present = load_skill_watermarks_from_warehouse(eff_wh, until_day=until_day)
    agent_retro_section = build_agent_retro_section(
        six_layer_dicts,
        horizon_dicts,
        wm_rows,
        table_present=(retro_table_present or wm_present),
    )

    w_start = str(daily_dicts[0]["cst_day"]) if daily_dicts else None
    w_end = str(daily_dicts[-1]["cst_day"]) if daily_dicts else None
    magpie = _read_magpie_role_telemetry(
        magpie_path, window_start=w_start, window_end=w_end
    )
    payload = build_agent_efficiency_snapshot(
        role_dicts,
        daily_dicts,
        magpie_telemetry=magpie,
        agent_retro=agent_retro_section,
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
    parser.add_argument("--magpie-usage", type=Path, default=_DEFAULT_MAGPIE_USAGE)
    args = parser.parse_args(argv)
    payload = write_snapshot(
        args.output,
        until_day=args.until_day,
        magpie_path=args.magpie_usage,
    )
    return 1 if payload.get("errors") else 0


if __name__ == "__main__":
    raise SystemExit(main())
