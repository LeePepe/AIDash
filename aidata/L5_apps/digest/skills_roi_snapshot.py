"""Canonical aidash-personal-skills-roi/v1 artifact for the read-only App.

The configured retro producer owns S1/S2/S3/S4/S6..S12 and their metadata.
Keep its complete report under diagnostics, never rename it to a metrics-only
map or invent S5. skills/daily remains separate day/source/skill populations.
Missing producer/query data is an explicit degraded artifact, not healthy zeros.
"""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from collections.abc import Callable
from pathlib import Path
from typing import Any

import serve

_SECTION_TYPES = {
    "S1_pin_drift": dict, "S2_gate_catch": dict, "S3_skill_health": dict,
    "S4_usage_and_r1": dict, "S6_load_vs_script": list,
    "S7_disclosure_funnel": list, "S8_post_skill_churn": list,
    "S9_escape_attribution": list, "S10_skill_roi_ranking": list,
    "S11_context_composition": dict, "S12_tool_context_burn": list,
}
_META = ("window_cst", "window_start", "window_end", "source_as_of", "sample_size", "coverage_status")
_COVERAGE = {"healthy", "partial", "unknown", "missing", "error"}


def build_snapshot(report: dict[str, Any], daily: list[dict[str, Any]], *, errors: list[str] | None = None) -> dict[str, Any]:
    """Validate producer shape while preserving its values, nulls and estimates."""
    problems = list(errors or [])
    for key, kind in _SECTION_TYPES.items():
        section = report.get(key)
        if not isinstance(section, kind):
            problems.append(f"missing/invalid canonical section: {key}")
            continue
        for population in section if kind is list else [section]:
            if not isinstance(population, dict) or any(field not in population for field in _META):
                problems.append(f"missing population metadata: {key}")
    sample = report.get("sample_size")
    if not isinstance(sample, int) or isinstance(sample, bool) or sample < 0:
        sample = 0
        problems.append("missing/invalid observed sample_size")
    coverage = report.get("coverage_status", "unknown")
    if coverage not in _COVERAGE:
        coverage = "unknown"
        problems.append("invalid coverage_status")
    if report.get("ok") is not True:
        problems.append("producer did not return ok=true")
    if coverage == "healthy" and (sample == 0 or not report.get("source_as_of")):
        problems.append("healthy producer has no observed sample/freshness")
    payload = {
        "schema_version": 1,
        **{key: report.get(key) for key in _META},
        "window_cst": report.get("window_cst") or "unknown",
        "sample_size": sample,
        "coverage_status": "error" if problems else coverage,
        "diagnostics": report,
        "skills_daily": daily,
    }
    if problems:
        payload["errors"] = problems
    return payload


def write_snapshot(
    output: Path, report_path: Path, *,
    query_runner: Callable[..., tuple[list, list[str]]] | None = None,
) -> dict[str, Any]:
    """Capture the real report and query grain, then atomically replace output."""
    errors: list[str] = []
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
        if not isinstance(report, dict):
            raise ValueError("retro report must be an object")
    except (OSError, ValueError) as exc:
        report = {}
        errors.append(f"retro producer report unavailable: {type(exc).__name__}")
    daily: list[dict[str, Any]] = []
    # Only query the producer's explicit observed window. No all-time data
    # labelled 7d, and no generated-at timestamp substituted for source freshness.
    start, end = report.get("window_start"), report.get("window_end")
    if isinstance(start, str) and isinstance(end, str):
        try:
            rows, columns = (query_runner or serve.run_query)("skills/daily", {"day_from": start[:10], "day_to": end[:10]})
            if not {"day", "source", "skill", "n", "sessions"}.issubset(columns):
                raise ValueError("skills/daily grain is missing")
            for values in rows:
                if len(values) != len(columns):
                    raise ValueError("skills/daily row does not match columns")
                row = dict(zip(columns, values))
                n = row["n"]
                if not isinstance(n, int) or isinstance(n, bool) or n < 0:
                    raise ValueError("skills/daily count is not an observed nonnegative integer")
                daily.append({
                    **row, "window_cst": "1d", "window_start": row["day"], "window_end": row["day"],
                    "source_as_of": row["day"], "sample_size": n,
                    "coverage_status": "healthy" if n > 0 else "unknown", "estimated": False,
                })
        except Exception as exc:  # noqa: BLE001 - preserve the producer report on query failure
            daily = []
            errors.append(f"skills/daily unavailable: {type(exc).__name__}")
    payload = build_snapshot(report, daily, errors=errors)
    if not report:
        payload["coverage_status"] = "missing"
    output.parent.mkdir(parents=True, exist_ok=True)
    tmp: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=output.parent, prefix=output.name + ".", delete=False) as handle:
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
    return payload


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    payload = write_snapshot(args.output, args.report)
    return 1 if payload.get("errors") else 0


if __name__ == "__main__":
    raise SystemExit(main())
