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
from collections.abc import Callable, Iterable, Mapping
from datetime import datetime, timezone
from pathlib import Path
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
    table_present: bool = True,
    window_cst: str = "14d",
    errors: list[str] | None = None,
) -> dict[str, Any]:
    """Build schema_version=1 `aidash-work-status/v1` snapshot dictionary."""
    rows = [dict(r) for r in (stream_rows or []) if isinstance(r, Mapping)]
    problems = list(errors or [])
    retro_by_goal = goal_retro_findings or {}

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
                "skills_touch": {},
                "slow_failed": [],
                "sessions": [],
            }
            goals_map[gid] = g_entry

        if not g_entry["repo"] and row.get("repo_name"):
            g_entry["repo"] = str(row["repo_name"])

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
        if end_ts > g_entry["latest_ts"]:
            g_entry["latest_ts"] = end_ts

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

        goals_out.append({
            "goal_id": g["goal_id"],
            "title": g["title"],
            "is_unassigned_bucket": g["is_unassigned_bucket"],
            "repo": g["repo"],
            "status": g["status"],
            "review_round_badge": g["review_round_badge"],
            "latest_activity_at": g["latest_ts"] or None,
            "duration_sec": round(g["duration_sec"], 1),
            "turn_count": g["turn_count"],
            "total_tokens": g["total_tokens"],
            "skills_used": skills_out,
            "action_split": g_split,
            "outputs": outputs_obj,
            "ai_signals": ai_signals,
            "sessions": sessions_sorted,
        })

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

    payload = build_work_status_snapshot(
        stream_dicts,
        goal_retro_findings=retro_by_goal,
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
