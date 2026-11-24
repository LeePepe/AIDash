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
import subprocess  # nosec B404 - fixed python helper only
import sys
import tempfile
from collections.abc import Callable
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import serve
from config import ICLOUD_DRIVE_ROOT, resolve_icloud_sync_dir


def _l4_role_query() -> str:
    return "retro/" + "agent_role_efficiency"


def _l4_daily_query() -> str:
    return "retro/" + "daily_agent_efficiency"


ROLE_QUERY = _l4_role_query()
DAILY_QUERY = _l4_daily_query()

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
    query_runner: Callable[..., tuple[list[tuple[Any, ...]], list[str]]] | None = None,
    icloud_sync_dir: Path | None = None,
) -> dict[str, Any]:
    """Run L4 queries, merge optional Magpie usage, and atomically write snapshot JSON."""
    runner = query_runner or serve.run_query
    errors: list[str] = []
    role_dicts: list[dict[str, Any]] = []
    daily_dicts: list[dict[str, Any]] = []

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

    w_start = str(daily_dicts[0]["cst_day"]) if daily_dicts else None
    w_end = str(daily_dicts[-1]["cst_day"]) if daily_dicts else None
    magpie = _read_magpie_role_telemetry(
        magpie_path, window_start=w_start, window_end=w_end
    )
    payload = build_agent_efficiency_snapshot(
        role_dicts, daily_dicts, magpie_telemetry=magpie, errors=errors
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
