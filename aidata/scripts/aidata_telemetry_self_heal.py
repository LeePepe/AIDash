#!/usr/bin/env python3
"""Loop 6A deterministic telemetry/aidata audit and bounded delivery loop.

This module deliberately keeps collection read-only.  Local healing is limited to
running the repository's existing normalize/merge commands and reconciling the
consumer-side learning state; source vault data is never written.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import html
import importlib.util
import json
import math
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.request
from collections.abc import Callable, Iterator, Mapping, Sequence
from contextlib import contextmanager
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

LOOP_ID = "loop-telemetry-aidata-self-heal"
AUTOPILOT_TITLE = "Telemetry & Aidata Self-Heal Patrol Autopilot (Loop 6A -> Owner)"
AUTOPILOT_CRON = "45 3 * * *"
AUTOPILOT_TIMEZONE = "Asia/Shanghai"
AUTOPILOT_TRIGGER_LABEL = "Daily CST 03:45 Telemetry & Aidata Self-Heal Patrol"
ISSUE_TITLE_TEMPLATE = "[P3 / Priority 3][Telemetry & Aidata] {date} 埋点覆盖与数仓自愈巡检清单"
CST = timezone(timedelta(hours=8))

# Runtime identity is intentionally empty in tracked code.  Operators must inject
# it through CLI flags or environment variables.
CORE_SOURCES: tuple[str, ...] = ("raven", "copilot_cli", "claude_jsonl", "gtt_ledger", "gtt_receipt")
SOURCE_PRIMARY_KEYS: dict[str, tuple[str, ...]] = {
    "raven": ("id", "request_id"),
    "copilot_cli": ("event_id",),
    "claude_jsonl": ("uuid",),
    "gtt_ledger": ("machine_id", "rel_path"),
    "gtt_receipt": ("machine_id", "rel_path"),
}
CLEAN_TABLE_SPECS: dict[str, tuple[str, str | None]] = {
    "raven": ("req", "fact_request"),
    "copilot_cli": ("skill_day", None),
    "claude_jsonl": ("turn", "fact_turn"),
    "gtt_ledger": ("gtt_event", "fact_gtt_event"),
    "gtt_receipt": ("task_run", "fact_gtt_task_run"),
}
# Raw records at these grains are allowed to have no corresponding fact table.
_SOURCE_GRAIN_FIELDS: dict[str, tuple[str, ...]] = {
    "copilot_cli": ("event_id", "skill"),
    "claude_jsonl": ("uuid",),
    "gtt_ledger": ("machine_id", "rel_path"),
    "gtt_receipt": ("machine_id", "rel_path"),
}
_GTT_EVENT_RE = re.compile(r"^\s*-\s*\S+\s*\|\s*EVT=\S+\s*\|")
_GTT_RECEIPT_FILE_RE = re.compile(r"^.+?-r\d+\.md$")
_CJK_RE = re.compile(r"[\u3400-\u9fff]")
_PATH_RE = re.compile(r"(?:/Users/|/home/|[A-Za-z]:[\\/])")
_CLI_RE = re.compile(r"(?:\b(?:python3?|pytest|bash|sh|curl|gh|multica|git)\s+|(?:^|\s)\./scripts/)")
_SOURCE_LABELS = {
    "raven": "网关请求",
    "copilot_cli": "技能使用",
    "claude_jsonl": "会话轮次",
    "gtt_ledger": "任务事件",
    "gtt_receipt": "任务回执",
}

CANONICAL_AI_SUMMARY = "🤖 AI 执行上下文与确定性证据（人无需展开）"
_DETAILS_OPEN = f"<details><summary>{CANONICAL_AI_SUMMARY}</summary>"
_CURSOR_RE = re.compile(r"<!--\s*multica-cursor\s*:\s*([^>]+?)\s*-->")
_UUID_RE = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")
_SHA_RE = re.compile(r"(?<![A-Za-z0-9_-])[0-9a-f]{7,40}(?![A-Za-z0-9_-])")
_INTERNAL_RE = re.compile(r"(?<![A-Za-z0-9_-])(?:S(?:1[0-2]|[1-9])|M[1-5]|EV-\d+|DC-\d+|H[1-5]|R10|V[1-5])(?![A-Za-z0-9_-])")


def _default_aidata_home() -> Path:
    return Path(os.environ.get("AIDATA_HOME", Path(__file__).resolve().parent.parent)).expanduser()


def _default_shared_telemetry_dir() -> Path:
    return Path(os.environ.get("SHARED_TELEMETRY_DIR", Path.home() / "Development" / "shared-telemetry")).expanduser()


def _default_vault_dir() -> Path:
    return Path(os.environ.get("KNOWLEDGE_VAULT_DIR", Path.home() / "Development" / "Personal" / "knowledge-vault")).expanduser()


def _default_state_path() -> Path:
    return Path(os.environ.get("MULTICA_LOOP_STATE_FILE", Path.home() / ".cache" / "multica-loop-runner" / "watermarks.json")).expanduser()


def _load_optional_helper(relative_path: str) -> Any | None:
    for candidate in (
        Path.home() / "Development" / "user-skills" / "skills" / relative_path,
        Path.home() / ".copilot" / "skills" / relative_path,
        Path.home() / ".agents" / "skills" / relative_path,
    ):
        if not candidate.is_file():
            continue
        spec = importlib.util.spec_from_file_location("aidata_self_heal_helper", candidate)
        if spec is None or spec.loader is None:
            continue
        module = importlib.util.module_from_spec(spec)
        try:
            spec.loader.exec_module(module)
            return module
        except Exception:  # noqa: BLE001, S112 - optional helper is best-effort and must never break the loop
            continue
    return None


def _compute_signature(payload: Any) -> str:
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def _sanitize_human_text(value: Any) -> str:
    text = str(value or "")
    text = _UUID_RE.sub("实例", text)
    text = _SHA_RE.sub("快照", text)
    text = _INTERNAL_RE.sub("指标", text)
    return text.replace("\n", " ").replace("\r", " ").strip()


def _atomic_json_replace(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.chmod(tmp, 0o600)
        with tmp.open("rb") as fh:
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    finally:
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass


@contextmanager
def _sidecar_lock(path: Path, *, timeout: float = 5.0) -> Iterator[None]:
    """Use the persistent advisory lock shared by digest producers/consumers."""
    lock = path.with_suffix(path.suffix + ".lock")
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open("a+", encoding="utf-8") as handle:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"lock timeout for {path.name}")
                time.sleep(0.02)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def _fixture_paths(
    fixture_json: Path | Mapping[str, Any] | None,
    aidata_home: Path | None,
    shared_telemetry_dir: Path | None,
    vault_dir: Path | None,
) -> tuple[Path, Path, Path, dict[str, Any], bool]:
    if fixture_json is None:
        return (
            (aidata_home or _default_aidata_home()).expanduser(),
            (shared_telemetry_dir or _default_shared_telemetry_dir()).expanduser(),
            (vault_dir or _default_vault_dir()).expanduser(),
            {},
            False,
        )
    if isinstance(fixture_json, Mapping):
        data = dict(fixture_json)
    else:
        data = json.loads(Path(fixture_json).expanduser().read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise TypeError("fixture JSON must be an object")
    # Fixture mode is fail-closed: it never fills omitted paths from HOME.
    def path_value(explicit: Path | None, key: str) -> Path:
        value = explicit or data.get(key)
        return Path(value).expanduser() if value else Path("/__missing_fixture_root__")
    return path_value(aidata_home, "aidata_home"), path_value(shared_telemetry_dir, "shared_telemetry_dir"), path_value(vault_dir, "vault_dir"), data, True


def render_dual_zone_markdown(*, tldr: str, items: Sequence[str | Mapping[str, Any]], cursor: str, ai_payload: Mapping[str, Any] | None = None) -> str:
    clean_cursor = _sanitize_human_text(cursor).replace(" ", "-")
    lines = [f"<!-- multica-cursor:{clean_cursor} -->", "", f"**一句话结论**：{_sanitize_human_text(tldr)}", ""]
    for index, item in enumerate(items[:6], start=1):
        if isinstance(item, Mapping):
            what = _sanitize_human_text(item.get("what") or "待办项")
            why = _sanitize_human_text(item.get("why") or "")
            text = f"{what} — {why}" if why else what
        else:
            text = _sanitize_human_text(item)
        lines.append(f"- [ ] {index}. {text}")
    if not items:
        lines.append("- [ ] 1. 审阅本次巡检结果 — 保持遥测与数仓链路健康")
    # The lower zone is bounded metadata, escaped so input cannot terminate details.
    lower = html.escape(json.dumps(ai_payload or {}, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    lines.extend(["", _DETAILS_OPEN, "", f"<pre>{lower}</pre>", "", "</details>"])
    return "\n".join(lines) + "\n"


def verify_dual_zone_markdown(markdown_text: str, *, max_human_lines: int = 15) -> dict[str, Any]:
    text = str(markdown_text or "")
    violations: list[dict[str, Any]] = []
    cursor_match = _CURSOR_RE.search(text)
    if cursor_match is None:
        violations.append({"code": "missing-cursor"})
    open_match = re.search(re.escape(_DETAILS_OPEN), text)
    close_index = text.find("</details>", open_match.end() if open_match else 0)
    if open_match is None:
        violations.append({"code": "missing-ai-details"})
        upper = text
    else:
        upper = text[: open_match.start()]
        if close_index < 0:
            violations.append({"code": "unbalanced-details"})
        elif not text[open_match.end() : close_index].strip():
            violations.append({"code": "empty-ai-context"})
    visible = []
    for number, line in enumerate(re.sub(r"<!--.*?-->", "", upper, flags=re.DOTALL).splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped in {"---", "***", "___"}:
            continue
        visible.append((number, stripped))
        if stripped.startswith(("```", "~~~")):
            violations.append({"code": "human-zone-fenced-code", "line": number})
        if _INTERNAL_RE.search(stripped) or _UUID_RE.search(stripped) or _SHA_RE.search(stripped):
            violations.append({"code": "human-zone-private-token", "line": number})
        if _PATH_RE.search(stripped):
            violations.append({"code": "human-zone-path", "line": number})
        if _CLI_RE.search(stripped):
            violations.append({"code": "human-zone-cli-command", "line": number})
        if not _CJK_RE.search(stripped):
            violations.append({"code": "human-zone-not-chinese", "line": number})
        if stripped.startswith("|") and stripped.endswith("|"):
            violations.append({"code": "human-zone-table", "line": number})
    if len(visible) > max_human_lines:
        violations.append({"code": "human-zone-line-budget", "count": len(visible)})
    if not any("**一句话结论**" in line for _, line in visible):
        violations.append({"code": "missing-tldr"})
    if not any(re.match(r"[-*+]\s*\[[ xX]\]\s+", line) for _, line in visible):
        violations.append({"code": "missing-checkable-items"})
    return {"ok": not violations, "human_zone_lines": len(visible), "max_human_lines": max_human_lines, "cursor": cursor_match.group(1).strip() if cursor_match else None, "violations": violations}


def _sqlite_table_count(db_path: Path, table_name: str) -> int | None:
    if not db_path.is_file():
        return None
    try:
        with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as conn:
            exists = conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table_name,)).fetchone()
            if not exists:
                return None
            return int(conn.execute(f'SELECT COUNT(*) FROM "{table_name}"').fetchone()[0])
    except (OSError, sqlite3.Error):
        return None


def _sqlite_daily_cost_days(warehouse_db: Path) -> int | None:
    if not warehouse_db.is_file():
        return None
    try:
        with sqlite3.connect(f"file:{warehouse_db}?mode=ro", uri=True) as conn:
            cols = {row[1] for row in conn.execute("PRAGMA table_info(fact_request)")}
            if "cst_day" not in cols:
                return None
            # Match trend/daily-cost.sql: every non-null CST day counts, even
            # when pricing is unknown or the stored cost is zero.
            return int(conn.execute("SELECT COUNT(DISTINCT cst_day) FROM fact_request WHERE cst_day IS NOT NULL").fetchone()[0])
    except (OSError, sqlite3.Error):
        return None


def _record_pk(record: Mapping[str, Any], fields: Sequence[str]) -> tuple[str, str] | None:
    if len(fields) == 2 and all(str(record.get(field) or "").strip() for field in fields):
        return "composite", ":".join(str(record[field]).strip() for field in fields)
    for field in fields:
        value = record.get(field)
        if value is not None and str(value).strip():
            return field, str(value).strip()
    return None


def _record_relevant(source: str, record: Mapping[str, Any], pk: tuple[str, str] | None) -> bool:
    if pk is None:
        return False
    if source == "copilot_cli":
        if record.get("kind") in {"reference_hit", "script_call"}:
            return False
        return bool(record.get("event_id") and record.get("skill") and _valid_event_timestamp(record.get("timestamp")))
    if source == "claude_jsonl":
        return record.get("_kind") not in {"reference_hit", "script_call"} and bool(record.get("uuid"))
    if source == "gtt_ledger":
        return record.get("record_type") == "ledger" and bool(_GTT_EVENT_RE.search(str(record.get("content") or "")))
    if source == "gtt_receipt":
        return record.get("record_type") == "receipt" and bool(_GTT_RECEIPT_FILE_RE.match(Path(str(record.get("rel_path") or "")).name))
    return True


def _valid_event_timestamp(value: Any) -> bool:
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return math.isfinite(float(value))
    if isinstance(value, str):
        try:
            datetime.fromisoformat(value.replace("Z", "+00:00"))  # noqa: FURB162 - Python 3.9 accepts neither trailing Z nor all source forms
            return True
        except ValueError:
            return False
    return False


def _scan_raw_shards(raw_source_dir: Path, *, pk_fields: Sequence[str]) -> dict[str, Any]:
    result: dict[str, Any] = {"shard_count": 0, "record_count": 0, "relevant_record_count": 0, "unique_pk_count": 0, "duplicate_pk_count": 0, "latest_shard_date": None, "latest_event_date": None, "latest_mtime": None, "max_numeric_ts": None, "coverage_complete": True, "malformed_lines": 0}
    if not raw_source_dir.is_dir():
        return result
    shards = sorted(p for p in raw_source_dir.glob("*.jsonl") if p.is_file())
    result["shard_count"] = len(shards)
    seen: set[tuple[str, str]] = set()
    duplicate_keys: set[tuple[str, str]] = set()
    first_shard: dict[tuple[str, str], str] = {}
    for shard in shards:
        try:
            result["latest_mtime"] = max(float(result["latest_mtime"] or 0), shard.stat().st_mtime)
            if re.fullmatch(r"\d{4}-\d{2}-\d{2}", shard.stem):
                latest = result["latest_shard_date"]
                result["latest_shard_date"] = max(str(latest or "0000-00-00"), shard.stem)
            with shard.open("r", encoding="utf-8", errors="replace") as stream:
                for line in stream:
                    line = line.strip()
                    if not line:
                        continue
                    result["record_count"] += 1
                    try:
                        obj = json.loads(line)
                    except (TypeError, ValueError):
                        result["malformed_lines"] += 1
                        continue
                    if not isinstance(obj, dict):
                        result["malformed_lines"] += 1
                        continue
                    ts = obj.get("timestamp", obj.get("ts"))
                    if isinstance(ts, (int, float)) and not isinstance(ts, bool) and math.isfinite(float(ts)):
                        result["max_numeric_ts"] = max(int(ts), int(result["max_numeric_ts"] or ts))
                        try:
                            seconds = float(ts) / 1000 if abs(float(ts)) > 10_000_000_000 else float(ts)
                            event_day = datetime.fromtimestamp(seconds, tz=CST).date().isoformat()
                            result["latest_event_date"] = max(str(result["latest_event_date"] or "0000-00-00"), event_day)
                        except (OverflowError, OSError, ValueError):
                            pass
                    elif isinstance(ts, str):
                        result["latest_event_date"] = max(str(result["latest_event_date"] or "0000-00-00"), ts[:10])
                    pk = _record_pk(obj, pk_fields)
                    if not _record_relevant(raw_source_dir.name, obj, pk):
                        continue
                    result["relevant_record_count"] += 1
                    if pk is None:
                        continue
                    if pk in seen and first_shard.get(pk) != shard.name:
                        duplicate_keys.add(pk)
                    seen.add(pk)
                    first_shard.setdefault(pk, shard.name)
        except (OSError, UnicodeError):
            result["coverage_complete"] = False
    result["duplicate_pk_count"] = len(duplicate_keys)
    result["unique_pk_count"] = len(seen)
    if result["latest_mtime"] == 0:
        result["latest_mtime"] = None
    return result


def _watermark_value(value: Any) -> int | float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, Mapping):
        for key in ("watermark", "ts", "timestamp", "updated_at"):
            found = _watermark_value(value.get(key))
            if found is not None:
                return found
    return None


def _freshness_stale(report: Mapping[str, Any], now: datetime, hours: float = 48.0) -> bool:
    if report.get("latest_shard_date"):
        try:
            # A date-only filename is freshest at the end of that local day;
            # this avoids declaring a shard stale before 48h is certain.
            end_of_day = datetime.combine(date.fromisoformat(str(report["latest_shard_date"])), datetime.max.time(), tzinfo=CST)
            return now.astimezone(CST) - end_of_day > timedelta(hours=hours)
        except (TypeError, ValueError):
            return False
    mtime = report.get("latest_mtime")
    return bool(mtime and now.timestamp() - float(mtime) > hours * 3600)


def _source_watermark_status(source: str, value: Any, report: Mapping[str, Any]) -> tuple[bool, bool, str | None]:
    """Return (present, regressed, reason) without treating hashes/offsets as epochs."""
    if source == "raven":
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return False, False, "numeric_epoch_ms_required"
        regressed = report.get("max_numeric_ts") is not None and float(value) < float(report["max_numeric_ts"])
        return True, regressed, "numeric_epoch_ms"
    if source == "copilot_cli":
        if not isinstance(value, Mapping) or not isinstance(value.get("seen"), Mapping) or not value.get("seen"):
            return False, False, "schema_version_seen_required"
        dates = [str(day) for day in value["seen"].values() if isinstance(day, str)]
        latest_raw = str(report.get("latest_event_date") or "")
        regressed = bool(latest_raw and dates and max(dates) < latest_raw)
        return True, regressed, "seen_dates"
    if source == "claude_jsonl":
        if not isinstance(value, Mapping) or not value or not all(isinstance(offset, int) and not isinstance(offset, bool) and offset >= 0 for offset in value.values()):
            return False, False, "nonnegative_file_offsets_required"
        return True, False, "file_offsets_regression_unsupported"
    if source in {"gtt_ledger", "gtt_receipt"}:
        if not isinstance(value, Mapping) or not value or not all(isinstance(digest, str) and bool(digest) for digest in value.values()):
            return False, False, "digest_map_required"
        return True, False, "content_digest_regression_unsupported"
    return value is not None, False, None


def watermark_and_shard_audit(aidata_home: Path, *, now: datetime | None = None, core_sources: Sequence[str] = CORE_SOURCES, staleness_hours: float = 48.0) -> dict[str, Any]:
    now = now or datetime.now(CST)
    state_path = aidata_home / "state.json"
    state_error: str | None = None
    if not state_path.is_file():
        state: dict[str, Any] = {}
    else:
        try:
            loaded = json.loads(state_path.read_text(encoding="utf-8"))
            state = loaded if isinstance(loaded, dict) else {}
            if not isinstance(loaded, dict):
                state_error = "state_not_object"
        except (OSError, ValueError, UnicodeError):
            state = {}
            state_error = "state_corrupt_or_unreadable"
    reports: dict[str, Any] = {}
    anomalies: list[dict[str, Any]] = []
    if state_error:
        anomalies.append({"dimension": "watermark_and_shard_audit", "kind": "corrupt_state_json", "severity": "medium", "healable": False, "detail": "水位线状态文件损坏或不可读"})
    for source in core_sources:
        report = _scan_raw_shards(aidata_home / "L1_collect" / "raw" / source, pk_fields=SOURCE_PRIMARY_KEYS.get(source, ("id",)))
        raw_count = int(report["relevant_record_count"])
        present, regressed, watermark_kind = _source_watermark_status(source, state.get(source), report)
        stale = raw_count > 0 and _freshness_stale(report, now, staleness_hours)
        reports[source] = {**report, "watermark_present": present, "watermark_kind": watermark_kind, "regressed_watermark": regressed, "stale_48h": stale}
        if report["shard_count"] == 0:
            anomalies.append({"dimension": "watermark_and_shard_audit", "kind": "source_missing_or_empty", "source": source, "severity": "medium", "healable": False, "detail": f"{_SOURCE_LABELS.get(source, source)}没有可核验的原始分片"})
        elif report["record_count"] == 0:
            anomalies.append({"dimension": "watermark_and_shard_audit", "kind": "source_missing_or_empty", "source": source, "severity": "medium", "healable": False, "detail": f"{_SOURCE_LABELS.get(source, source)}最新分片为空，覆盖状态未知"})
        if not report["coverage_complete"] or report["malformed_lines"]:
            anomalies.append({"dimension": "watermark_and_shard_audit", "kind": "raw_coverage_incomplete", "source": source, "severity": "medium", "healable": False, "detail": f"{_SOURCE_LABELS.get(source, source)}原始分片存在不可读记录"})
        if raw_count > 0 and not present:
            anomalies.append({"dimension": "watermark_and_shard_audit", "kind": "watermark_regression_or_missing", "source": source, "severity": "medium", "healable": False, "detail": f"{_SOURCE_LABELS.get(source, source)}水位线结构缺失或不符合来源契约"})
        if regressed:
            anomalies.append({"dimension": "watermark_and_shard_audit", "kind": "watermark_regression_or_missing", "source": source, "severity": "medium", "healable": False, "detail": f"{_SOURCE_LABELS.get(source, source)}水位线落后于可比较的原始证据"})
        if report["duplicate_pk_count"]:
            anomalies.append({"dimension": "watermark_and_shard_audit", "kind": "cross_shard_duplicate_pk", "source": source, "severity": "low", "healable": False, "detail": f"{_SOURCE_LABELS.get(source, source)}跨分片存在重复主键，原始层保持追加只读"})
        if stale:
            anomalies.append({"dimension": "watermark_and_shard_audit", "kind": "source_stale_48h", "source": source, "severity": "medium", "healable": False, "detail": f"{_SOURCE_LABELS.get(source, source)}超过四十八小时无新分片"})
    return {"ok": not anomalies, "sources": reports, "anomalies": anomalies}


def zero_table_and_warehouse_audit(aidata_home: Path, *, raw_audit: Mapping[str, Any] | None = None, core_sources: Sequence[str] = CORE_SOURCES) -> dict[str, Any]:
    raw_sources = (raw_audit or {}).get("sources") or {}
    warehouse = aidata_home / "L3_merge" / "warehouse.db"
    tables: dict[str, Any] = {}
    anomalies: list[dict[str, Any]] = []
    direct_l2_grain = {"raven", "claude_jsonl", "gtt_receipt"}
    direct_l3_grain = {"raven", "claude_jsonl", "gtt_receipt"}
    for source in core_sources:
        clean_table, fact_table = CLEAN_TABLE_SPECS[source]
        source_report = raw_sources.get(source, {})
        relevant = int(source_report.get("relevant_record_count") or 0)
        unique_count = int(source_report.get("unique_pk_count") or relevant)
        clean_rows = _sqlite_table_count(aidata_home / "L2_normalize" / "clean" / f"{source}.db", clean_table)
        fact_rows = _sqlite_table_count(warehouse, fact_table) if fact_table else None
        clean_zero = relevant > 0 and (clean_rows is None or clean_rows == 0)
        clean_lag = source in direct_l2_grain and clean_rows is not None and clean_rows < unique_count
        fact_zero = relevant > 0 and fact_table is not None and (fact_rows is None or fact_rows == 0)
        fact_lag = source in direct_l3_grain and clean_rows is not None and fact_rows is not None and fact_rows < clean_rows
        tables[source] = {"raw_relevant_records": relevant, "raw_unique_identities": unique_count, "clean_rows": clean_rows, "fact_rows": fact_rows, "clean_zero_or_missing": clean_zero, "clean_lagging": clean_lag, "fact_zero_or_missing": fact_zero, "fact_lagging": fact_lag}
        if clean_zero or clean_lag:
            anomalies.append({"dimension": "zero_table_and_warehouse_audit", "kind": "l2_clean_zero_table" if clean_zero else "l2_clean_lagging_table", "source": source, "severity": "high", "healable": True, "detail": f"{_SOURCE_LABELS.get(source, source)}原始身份数量超过清洗层可核验数量"})
        if fact_zero or fact_lag:
            anomalies.append({"dimension": "zero_table_and_warehouse_audit", "kind": "l3_warehouse_zero_or_lagging_table", "source": source, "severity": "high", "healable": True, "detail": f"{_SOURCE_LABELS.get(source, source)}对应事实表为空或落后于同粒度清洗表"})
    raven_relevant = int((tables.get("raven") or {}).get("raw_relevant_records") or 0)
    daily_cost_days = _sqlite_daily_cost_days(warehouse)
    if raven_relevant > 0 and daily_cost_days is None:
        anomalies.append({"dimension": "zero_table_and_warehouse_audit", "kind": "daily_cost_schema_unreadable", "source": "raven", "severity": "high", "healable": True, "detail": "网关请求原始记录非空但每日成本事实表不可核验"})
    elif raven_relevant > 0 and daily_cost_days == 0:
        anomalies.append({"dimension": "zero_table_and_warehouse_audit", "kind": "daily_cost_zero_days", "source": "raven", "severity": "high", "healable": True, "detail": "网关请求原始记录非空但每日成本查询没有有效日期"})
    return {"ok": not anomalies, "tables": tables, "daily_cost_days": daily_cost_days, "anomalies": anomalies}


def _load_json_object(path: Path) -> tuple[dict[str, Any] | None, str | None]:
    if not path.is_file():
        return None, None
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return (value, None) if isinstance(value, dict) else (None, "not_object")
    except (OSError, ValueError, UnicodeError):
        return None, "corrupt"


def _topic_identifiers(topic_key: str, entry: Mapping[str, Any]) -> set[str]:
    values = {topic_key, f"learning-topic://{topic_key}", f"knowledge://{topic_key}"}
    aliases = entry.get("aliases", [])
    if isinstance(aliases, str):
        aliases = [aliases]
    if isinstance(aliases, Sequence):
        for alias in aliases:
            alias_text = str(alias).strip()
            if alias_text:
                values.update({alias_text, f"learning-topic://{alias_text}", f"knowledge://{alias_text}"})
    return {value for value in values if value}


def _proposal_matches(proposal_id: str, proposal: Mapping[str, Any], identifiers: set[str], topic_key: str) -> bool:
    candidates = {proposal_id}
    for field in ("topic_key", "ref", "origin_ref"):
        value = proposal.get(field)
        if value:
            candidates.add(str(value))
    normalized = {item.replace("://", "-").replace("/", "-") for item in candidates}
    expected = identifiers | {item.replace("://", "-").replace("/", "-") for item in identifiers}
    return bool(candidates & expected or normalized & expected or proposal_id.endswith(topic_key))


def cross_file_state_audit(aidata_home: Path, *, vault_dir: Path | None = None) -> dict[str, Any]:
    vault = vault_dir or _default_vault_dir()
    ledger_path = vault / "topic-ledger.json"
    state_path = aidata_home / "L5_apps" / "digest" / "state" / "learning-topics-state.json"
    proposals_path = aidata_home / "L5_apps" / "digest" / "state" / "proposals.jsonl"
    if not ledger_path.is_file():
        return {"ok": True, "ledger_present": False, "drifted_topics": [], "anomalies": []}
    ledger, ledger_error = _load_json_object(ledger_path)
    if ledger_error or ledger is None:
        return {"ok": False, "ledger_present": True, "drifted_topics": [], "anomalies": [{"dimension": "cross_file_state_audit", "kind": "corrupt_topic_ledger", "severity": "medium", "healable": False, "detail": "知识库主题台账损坏或无法解析"}]}
    raw_topics = ledger.get("topics", [])
    ledger_topics: dict[str, dict[str, Any]] = {}
    if isinstance(raw_topics, list):
        for item in raw_topics:
            if isinstance(item, dict) and str(item.get("topic_key") or "").strip():
                ledger_topics[str(item["topic_key"]).strip()] = item
    elif isinstance(raw_topics, dict):
        for key, item in raw_topics.items():
            if isinstance(item, dict):
                ledger_topics[str(key).strip()] = item
    state, state_error = _load_json_object(state_path)
    anomalies: list[dict[str, Any]] = []
    if state_error:
        anomalies.append({"dimension": "cross_file_state_audit", "kind": "corrupt_learning_state", "severity": "medium", "healable": False, "detail": "学习状态消费者文件损坏，保留原文件不覆盖"})
    state_topics = state.get("topics") if isinstance(state, dict) and isinstance(state.get("topics"), dict) else {}
    proposals: dict[str, dict[str, Any]] = {}
    malformed_proposals = False
    if proposals_path.is_file():
        try:
            for line in proposals_path.read_text(encoding="utf-8", errors="replace").splitlines():
                if not line.strip():
                    continue
                try:
                    item = json.loads(line)
                except ValueError:
                    malformed_proposals = True
                    continue
                if isinstance(item, dict) and item.get("id"):
                    proposals[str(item["id"])] = item
        except OSError:
            malformed_proposals = True
    if malformed_proposals:
        anomalies.append({"dimension": "cross_file_state_audit", "kind": "corrupt_proposals_history", "severity": "medium", "healable": False, "detail": "提案历史含损坏行，保留原始历史不重写"})
    drifted: list[dict[str, Any]] = []
    for topic_key, entry in sorted(ledger_topics.items()):
        ledger_state = str(entry.get("learning_state") or "").lower()
        if ledger_state not in {"learned", "dismissed"}:
            continue
        ledger_revision = int(entry.get("revision") or 1)
        state_entry = state_topics.get(topic_key) if isinstance(state_topics, dict) else None
        state_drift = state_error is None and (not state_path.is_file() or not isinstance(state_entry, dict) or str(state_entry.get("learning_state") or "").lower() != ledger_state or int(state_entry.get("revision") or 0) < ledger_revision or state_entry.get("exploration_authorized") is not False)
        identifiers = _topic_identifiers(topic_key, entry)
        matched: list[tuple[str, dict[str, Any]]] = [(proposal_id, proposal) for proposal_id, proposal in proposals.items() if _proposal_matches(proposal_id, proposal, identifiers, topic_key)]
        proposal_drift = any(str(proposal.get("learning_state") or "").lower() != ledger_state or str(proposal.get("status") or "").lower() != "dismissed" or proposal.get("exploration_authorized") is not False or (ledger_state == "learned" and proposal.get("outcome") != "reconciled_from_ledger") or int(proposal.get("revision") or 0) < ledger_revision for _, proposal in matched)
        if state_drift or proposal_drift:
            drifted.append({"topic_key": topic_key, "ledger_learning_state": ledger_state, "ledger_revision": ledger_revision, "aliases": sorted(identifiers), "state_revision": int(state_entry.get("revision") or 0) if isinstance(state_entry, dict) else 0, "proposal_revisions": [int(item.get("revision") or 0) for _, item in matched], "proposal_ids": [proposal_id for proposal_id, _ in matched], "state_file_drift": state_drift, "proposal_drift": proposal_drift})
            anomalies.append({"dimension": "cross_file_state_audit", "kind": "learning_topic_state_drift", "severity": "medium", "healable": True, "detail": "知识库主题状态与消费端状态或提案终态不一致"})
    return {"ok": not anomalies, "ledger_present": True, "drifted_topics": drifted, "anomalies": anomalies}


def _read_nonempty_contract_files(root: Path, suffixes: set[str]) -> tuple[bool, bool, str]:
    """Return (has_file, readable, text) for concrete source evidence."""
    if not root.is_dir():
        return False, False, ""
    texts: list[str] = []
    try:
        files = [item for item in root.rglob("*") if item.is_file() and item.suffix.lower() in suffixes]
    except OSError:
        return False, False, ""
    readable = True
    for item in files:
        try:
            text = item.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            readable = False
            continue
        if text.strip():
            texts.append(text)
    return bool(texts), readable, "\n".join(texts)


def shared_telemetry_coverage_audit(aidata_home: Path, *, shared_telemetry_dir: Path | None = None) -> dict[str, Any]:
    shared = shared_telemetry_dir or _default_shared_telemetry_dir()
    repo_root = aidata_home.parent
    coordinator = repo_root / "Apps" / "AIDashApp" / "Sources" / "Telemetry" / "AIDashTelemetryCoordinator.swift"
    preferences = repo_root / "Apps" / "AIDashApp" / "Sources" / "Telemetry" / "AIDashTelemetryPreferences.swift"
    factory = repo_root / "Apps" / "AIDashApp" / "Sources" / "Telemetry" / "AIDashTelemetryFactory.swift"
    product_blob = aidata_home / "adapters" / "product_blob.py"
    anomalies: list[dict[str, Any]] = []
    def read(path: Path) -> str:
        try:
            return path.read_text(encoding="utf-8") if path.is_file() else ""
        except (OSError, UnicodeError):
            return ""
    coordinator_text, preference_text, factory_text = read(coordinator), read(preferences), read(factory)
    coordinator_ok = all(token in coordinator_text for token in ("enum AIDashTelemetryAction", "briefing_viewed", "establishedEnabled")) and "consent" in preference_text and "establishedEnabled" in preference_text and "AzureBlobPrivacyPolicy" in factory_text
    if not coordinator_ok:
        anomalies.append({"dimension": "shared_telemetry_coverage_audit", "kind": "aidash_telemetry_contract_gap", "severity": "high", "healable": False, "detail": "AIDash遥测协调器缺少类型白名单、同意状态或隐私策略证据"})
    blob_text = read(product_blob)
    blob_ok = "AZURE_CORE_COLLECT_TELEMETRY" in blob_text and "_preflight" in blob_text and "privacy" in blob_text.lower()
    if not blob_ok:
        anomalies.append({"dimension": "shared_telemetry_coverage_audit", "kind": "product_blob_guard_missing", "severity": "high", "healable": False, "detail": "采集适配器缺少离线预检或安全环境守卫"})
    sdk_checks: dict[str, bool] = {}
    for key, relative, suffixes in (("swift_sdk", "sdks/swift", {".swift", ".md"}), ("web_sdk", "sdks/web", {".ts", ".tsx", ".js", ".md"}), ("python_sdk", "sdks/python", {".py", ".md"})):
        has_file, readable, text = _read_nonempty_contract_files(shared / relative, suffixes)
        ok = has_file and readable and bool(re.search(r"telemetr|event|consent|privacy", text, re.IGNORECASE))
        sdk_checks[key] = ok
        if not ok:
            anomalies.append({"dimension": "shared_telemetry_coverage_audit", "kind": f"shared_telemetry_missing_{key}", "severity": "medium", "healable": False, "detail": "共享遥测SDK缺少可读的非空契约证据"})
    context_path = shared / "docs" / "architecture" / "tech-context.md"
    context_text = read(context_path)
    context_ok = bool(context_text.strip()) and bool(re.search(r"telemetr|privacy|consent|contract", context_text, re.IGNORECASE))
    sdk_checks["tech_context"] = context_ok
    if not context_ok:
        anomalies.append({"dimension": "shared_telemetry_coverage_audit", "kind": "shared_telemetry_missing_tech_context", "severity": "medium", "healable": False, "detail": "共享遥测架构契约缺少可读内容"})
    return {"ok": not anomalies, "checks": {"aidash_telemetry_coordinator": coordinator_ok, "product_blob_adapter": blob_ok, "shared_telemetry_repo": shared.is_dir(), "sdks": sdk_checks}, "anomalies": anomalies}


def _default_reconcile_learning_drift(aidata_home: Path, *, vault_dir: Path, drifted_topics: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    if not drifted_topics:
        return []
    state_path = aidata_home / "L5_apps" / "digest" / "state" / "learning-topics-state.json"
    proposals_path = aidata_home / "L5_apps" / "digest" / "state" / "proposals.jsonl"
    now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")  # noqa: UP017 - Python 3.9 gate
    actions: list[dict[str, Any]] = []
    try:
        # This is deliberately the proposals lock, matching proposals.py and
        # digest_vault.py, held across both downstream files.
        with _sidecar_lock(proposals_path):
            state, error = _load_json_object(state_path)
            if error:
                return [{"action": "reconcile_learning_topic_drift", "ok": False, "error": "corrupt_learning_state"}]
            if state is None:
                state = {"schema_version": 1, "updated_at": now, "topics": {}, "consumed_events": {}}
            topics = state.get("topics")
            if not isinstance(topics, dict):
                return [{"action": "reconcile_learning_topic_drift", "ok": False, "error": "invalid_learning_state_topics"}]
            latest: dict[str, dict[str, Any]] = {}
            if proposals_path.is_file():
                for line in proposals_path.read_text(encoding="utf-8", errors="replace").splitlines():
                    try:
                        item = json.loads(line) if line.strip() else None
                    except ValueError:
                        continue
                    if isinstance(item, dict) and item.get("id"):
                        latest[str(item["id"])] = item
            changed_state = False
            additions: list[str] = []
            for drift in drifted_topics:
                key = str(drift.get("topic_key") or "")
                old_state = topics.get(key) if isinstance(topics.get(key), dict) else {}
                state_revision = int(old_state.get("revision") or 0)
                matched = [item for proposal_id, item in latest.items() if proposal_id in {str(value) for value in drift.get("proposal_ids") or []}]
                proposal_revision = max((int(item.get("revision") or 0) for item in matched), default=0)
                new_revision = max(int(drift.get("ledger_revision") or 1), state_revision, proposal_revision) + 1
                target = str(drift.get("ledger_learning_state") or "learned")
                desired_state = dict(old_state)
                desired_state.update({"topic_key": key, "learning_state": target, "revision": new_revision, "exploration_authorized": False, "updated_at": now})
                if target == "learned":
                    desired_state["outcome"] = "reconciled_from_ledger"
                if desired_state != old_state or not state_path.is_file():
                    topics[key] = desired_state
                    changed_state = True
                for proposal_id, old in latest.items():
                    if proposal_id not in {str(value) for value in drift.get("proposal_ids") or []}:
                        continue
                    new = dict(old)
                    new.update({"learning_state": target, "status": "dismissed", "exploration_authorized": False, "revision": new_revision, "ts": now})
                    if target == "learned":
                        new["outcome"] = "reconciled_from_ledger"
                    if new != old:
                        additions.append(json.dumps(new, ensure_ascii=False, separators=(",", ":")))
            if changed_state:
                state["updated_at"] = now
                _atomic_json_replace(state_path, state)
                actions.append({"action": "reconcile_learning_state", "count": len(drifted_topics), "ok": True})
            if additions:
                with proposals_path.open("a", encoding="utf-8") as stream:
                    stream.write("\n".join(additions) + "\n")
                    stream.flush()
                    os.fsync(stream.fileno())
                actions.append({"action": "reconcile_learning_proposals", "count": len(additions), "ok": True})
    except (OSError, TimeoutError):
        return [{"action": "reconcile_learning_topic_drift", "ok": False, "error": "proposals_lock_failed"}]
    return actions


def _default_normalize_and_merge_healer(aidata_home: Path, sources_to_normalize: Sequence[str], *, need_merge: bool, timeout_sec: float = 30.0) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []
    cli = aidata_home / "cli.py"
    if not cli.is_file():
        return [{"action": "normalize_source", "ok": False, "error": "cli_missing"}]
    for source in dict.fromkeys(sources_to_normalize):
        env = dict(os.environ)
        env["AIDATA_HOME"] = str(aidata_home)
        env["PYTHONPATH"] = str(aidata_home)
        try:
            proc = subprocess.run([sys.executable, str(cli), "normalize", "--source", source], cwd=str(aidata_home), env=env, capture_output=True, text=True, timeout=timeout_sec, check=False)
        except (OSError, subprocess.TimeoutExpired) as exc:
            actions.append({"action": "normalize_source", "source": source, "ok": False, "error": type(exc).__name__})
            continue
        failed_output = bool(re.search(r"\bERROR\s*:", proc.stderr or ""))
        if proc.returncode != 0 or failed_output:
            actions.append({"action": "normalize_source", "source": source, "ok": False, "error": "command_failed"})
        else:
            actions.append({"action": "normalize_source", "source": source, "ok": True})
    normalizers_ok = all(a.get("ok") for a in actions if a.get("action") == "normalize_source")
    if need_merge and normalizers_ok:
        try:
            proc = subprocess.run([sys.executable, str(cli), "merge"], cwd=str(aidata_home), capture_output=True, text=True, timeout=timeout_sec, check=False)
            actions.append({"action": "merge_warehouse", "ok": proc.returncode == 0, "error": None if proc.returncode == 0 else "command_failed"})
        except (OSError, subprocess.TimeoutExpired) as exc:
            actions.append({"action": "merge_warehouse", "ok": False, "error": type(exc).__name__})
    elif need_merge:
        actions.append({"action": "merge_warehouse", "ok": False, "error": "normalize_failed_no_merge"})
    return actions


def _audit_payload(audits: Mapping[str, Any]) -> dict[str, Any]:
    # Keep issue evidence bounded and free of paths, IDs, raw records, and titles.
    result: dict[str, Any] = {}
    for name, audit in audits.items():
        result[name] = {"ok": bool(audit.get("ok")), "anomaly_kinds": sorted({str(item.get("kind")) for item in audit.get("anomalies", []) if item.get("kind")})}
    return result


def _build_human_action_items(residuals: Sequence[Mapping[str, Any]]) -> list[dict[str, str]]:
    items: list[dict[str, str]] = []
    for item in residuals[:6]:
        source = _SOURCE_LABELS.get(str(item.get("source") or ""), "遥测链路")
        kind = str(item.get("kind") or "")
        if "stale" in kind or "watermark" in kind:
            why = "恢复上游采集连续性"
        elif "coverage" in kind or "contract" in kind or "guard" in kind:
            why = "补齐跨端契约与隐私守卫"
        else:
            why = "核对数仓或消费端状态"
        items.append({"what": f"检查{source}异常", "why": why})
    return items


def inspect_and_self_heal(*, aidata_home: Path | None = None, shared_telemetry_dir: Path | None = None, vault_dir: Path | None = None, fixture_json: Path | Mapping[str, Any] | None = None, target_date: date | None = None, now: datetime | None = None, auto_heal: bool = True, dry_run: bool = False, core_sources: Sequence[str] = CORE_SOURCES, normalize_merge_healer: Callable[..., list[dict[str, Any]]] | None = None) -> dict[str, Any]:
    resolved_aidata, resolved_shared, resolved_vault, fixture, fixture_mode = _fixture_paths(fixture_json, aidata_home, shared_telemetry_dir, vault_dir)
    now = now or datetime.now(CST)
    target_date = target_date or now.astimezone(CST).date()
    audits = {}
    audits["watermark_and_shard_audit"] = watermark_and_shard_audit(resolved_aidata, now=now, core_sources=core_sources)
    audits["zero_table_and_warehouse_audit"] = zero_table_and_warehouse_audit(resolved_aidata, raw_audit=audits["watermark_and_shard_audit"], core_sources=core_sources)
    audits["cross_file_state_audit"] = cross_file_state_audit(resolved_aidata, vault_dir=resolved_vault)
    audits["shared_telemetry_coverage_audit"] = shared_telemetry_coverage_audit(resolved_aidata, shared_telemetry_dir=resolved_shared)
    healed: list[dict[str, Any]] = []
    attempted: list[dict[str, Any]] = []
    if auto_heal and not dry_run:
        sources: list[str] = []
        need_merge = False
        for anomaly in audits["zero_table_and_warehouse_audit"]["anomalies"]:
            if anomaly.get("healable"):
                source = str(anomaly.get("source") or "")
                if source and source not in sources:
                    sources.append(source)
                need_merge = True
        if sources or need_merge:
            fn = normalize_merge_healer or _default_normalize_and_merge_healer
            attempted.extend(fn(resolved_aidata, sources, need_merge=need_merge))
            healed.extend(item for item in attempted if item.get("ok") is True)
        if audits["cross_file_state_audit"].get("drifted_topics"):
            reconcile_actions = _default_reconcile_learning_drift(resolved_aidata, vault_dir=resolved_vault, drifted_topics=audits["cross_file_state_audit"]["drifted_topics"])
            attempted.extend(reconcile_actions)
            healed.extend(item for item in reconcile_actions if item.get("ok") is True)
        # Always re-audit after an attempted action.  A failed command cannot claim healing.
        if attempted or audits["cross_file_state_audit"].get("drifted_topics"):
            audits["watermark_and_shard_audit"] = watermark_and_shard_audit(resolved_aidata, now=now, core_sources=core_sources)
            audits["zero_table_and_warehouse_audit"] = zero_table_and_warehouse_audit(resolved_aidata, raw_audit=audits["watermark_and_shard_audit"], core_sources=core_sources)
            audits["cross_file_state_audit"] = cross_file_state_audit(resolved_aidata, vault_dir=resolved_vault)
    residuals = [dict(anomaly) for audit in audits.values() for anomaly in audit.get("anomalies", [])]
    for injected in fixture.get("injected_anomalies", []) if isinstance(fixture.get("injected_anomalies"), list) else []:
        if isinstance(injected, Mapping):
            residuals.append({"dimension": "fixture", "kind": str(injected.get("kind") or "fixture_residual"), "severity": str(injected.get("severity") or "medium"), "healable": False, "detail": "离线夹具注入的残余证据"})
    # Failed actions are explicit residuals even if a fixture runner altered nothing observable.
    residuals.extend({"dimension": "self_heal_apply", "kind": "self_heal_failed", "severity": "high", "healable": False, "detail": "本地自愈命令失败，未声明已修复"} for action in attempted if action.get("ok") is False)
    signature_items = sorted((str(item.get("dimension")), str(item.get("kind")), str(item.get("source") or ""), str(item.get("table") or ""), str(item.get("severity") or "")) for item in residuals)
    signature = _compute_signature(signature_items)
    has_delta = bool(residuals)
    severity = "high" if any(item.get("severity") == "high" for item in residuals) else ("medium" if any(item.get("severity") == "medium" for item in residuals) else "low")
    watermark = f"{LOOP_ID}:{signature}"
    summary = f"完成四维遥测与数仓巡检，{len(healed)}项本地动作已核验；剩余{len(residuals)}项需要处理。"
    items = _build_human_action_items(residuals)
    if not items and healed:
        items = [{"what": "复核本次数仓与遥测自愈结果", "why": "本地可修复漂移已恢复一致"}]
    payload = {"loop_id": LOOP_ID, "watermark": watermark, "delta_count": len(residuals), "severity": severity, "healed_count": len(healed), "audits": _audit_payload(audits)}
    cursor = f"{LOOP_ID}-{target_date.isoformat()}"
    markdown = render_dual_zone_markdown(tldr=summary, items=items, cursor=cursor, ai_payload=payload)
    verification = verify_dual_zone_markdown(markdown)
    status = "RESIDUAL_ANOMALIES_FOUND" if has_delta else ("HEALED_LOCALLY_NO_ALERT" if healed else "SKIPPED_NO_DELTA")
    return {"ok": True, "loop_id": LOOP_ID, "date": target_date.isoformat(), "status": status, "token_cost": 0, "has_delta": has_delta, "delta_count": len(residuals), "severity": severity, "watermark": watermark, "cursor": cursor, "title": ISSUE_TITLE_TEMPLATE.format(date=target_date.isoformat()), "summary": summary, "items": items, "dual_zone_markdown": markdown, "dual_zone_verification": verification, "healed_items": healed, "healed_actions": healed, "residual_unhealable_items": residuals, "residual_anomalies": residuals, "audits": audits, "raw": {"daily_cost_days": audits["zero_table_and_warehouse_audit"].get("daily_cost_days"), "fixture_mode": fixture_mode}}


def _extract_prob(value: Any, field: str) -> float | None:
    if isinstance(value, Mapping):
        value = value.get(field, value.get("value"))
    if isinstance(value, bool) or value is None:
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) and 0 <= number <= 1 else None


def _parse_mock_jev(value: Any) -> Mapping[str, Any] | None:
    if value is None:
        value = os.environ.get("GTT_JEV_MOCK_JSON")
    if isinstance(value, Mapping):
        return value
    if not isinstance(value, str):
        return None
    try:
        path = Path(value).expanduser()
        raw = path.read_text(encoding="utf-8") if path.is_file() else value
        parsed = json.loads(raw)
        return parsed if isinstance(parsed, Mapping) else None
    except (OSError, ValueError, TypeError):
        return None


def _default_jev_decide(*, state: Mapping[str, Any], questions: Mapping[str, Any], agent_role: str = "team-lead", goal_id: str = LOOP_ID, timeout_sec: float = 1.5, falcon_only: bool = True, mock_response: Any = None) -> Mapping[str, Any] | None:
    mock = _parse_mock_jev(mock_response)
    if mock is not None:
        return mock
    token = os.environ.get("FALCON_API_KEY") or os.environ.get("JEV_API_KEY")
    if not token:
        return None
    request = urllib.request.Request("http://127.0.0.1:19823/v1/systemone", data=json.dumps({"model": "microsoft-decision-1", "state": dict(state), "questions": dict(questions), "falcon_only": falcon_only}).encode(), headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", "X-Falcon-Agent": agent_role, "X-Falcon-Run-ID": goal_id}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=timeout_sec) as response:
            result = json.loads(response.read().decode())
            return result if isinstance(result, Mapping) else None
    except (OSError, ValueError, TypeError):
        return None


def evaluate_jev_decision(collected: Mapping[str, Any], *, mock_jev_json: Any = None, jev_fn: Callable[..., Mapping[str, Any] | None] | None = None) -> dict[str, Any]:
    residuals = list(collected.get("residual_unhealable_items") or collected.get("residual_anomalies") or [])
    if not residuals and not int(collected.get("delta_count") or 0):
        return {"actionable": False, "route": "ignore", "probability": 0.0, "delivery_route_match": 1.0, "urgency_score": 0.0, "decision_source": "layer0_zero_residual"}
    high_medium = any(str(item.get("severity") or "").lower() in {"high", "medium"} for item in residuals) or str(collected.get("severity") or "").lower() in {"high", "medium"}
    fallback_actionable = bool(residuals) and high_medium
    state = {"loop_id": LOOP_ID, "delta_count": len(residuals), "severity": str(collected.get("severity") or "low"), "anomaly_kinds": sorted({str(item.get("kind")) for item in residuals})}
    questions = {"actionable_probability": {"type": "noul"}, "delivery_route": {"type": "choice"}, "delivery_route_match": {"type": "noul"}, "urgency_score": {"type": "score"}}
    try:
        response = (jev_fn or _default_jev_decide)(state=state, questions=questions, agent_role="team-lead", goal_id=LOOP_ID, timeout_sec=1.5, falcon_only=True, mock_response=_parse_mock_jev(mock_jev_json))
    except Exception:  # noqa: BLE001 - Jev is an optional bounded decision service
        response = None
    if not isinstance(response, Mapping):
        return {"actionable": fallback_actionable, "route": "dual_zone_issue" if fallback_actionable else "ignore", "probability": None, "delivery_route_match": None, "urgency_score": None, "decision_source": "deterministic_fallback_unavailable"}
    answers = response.get("answers", response)
    if not isinstance(answers, Mapping):
        return {"actionable": fallback_actionable, "route": "dual_zone_issue" if fallback_actionable else "ignore", "probability": None, "delivery_route_match": None, "urgency_score": None, "decision_source": "deterministic_fallback_malformed"}
    probability = _extract_prob(answers.get("actionable_probability"), "noul")
    match = _extract_prob(answers.get("delivery_route_match"), "noul")
    urgency = _extract_prob(answers.get("urgency_score"), "score")
    route_value = answers.get("delivery_route")
    route = route_value.get("choice") if isinstance(route_value, Mapping) else route_value
    route = route if route in {"dual_zone_issue", "autopilot_trigger", "ignore"} else "dual_zone_issue"
    if probability is None:
        return {"actionable": fallback_actionable, "route": "dual_zone_issue" if fallback_actionable else "ignore", "probability": None, "delivery_route_match": match, "urgency_score": urgency, "decision_source": "deterministic_fallback_missing_prob"}
    # Ignore is permitted only with a matched route and probability <= .70.
    if route == "ignore" and match is not None and match >= 0.50 and probability <= 0.70:
        return {"actionable": False, "route": "ignore", "probability": probability, "delivery_route_match": match, "urgency_score": urgency, "decision_source": "jev_choice_ignore"}
    if probability > 0.70:
        return {"actionable": True, "route": "dual_zone_issue" if route == "ignore" else route, "probability": probability, "delivery_route_match": match, "urgency_score": urgency, "decision_source": "jev_high_confidence"}
    if probability < 0.30:
        return {"actionable": False, "route": "ignore", "probability": probability, "delivery_route_match": match, "urgency_score": urgency, "decision_source": "jev_low_confidence_reject"}
    safe_route = route if route != "autopilot_trigger" or (match is not None and match >= 0.50) else "dual_zone_issue"
    return {"actionable": fallback_actionable, "route": ("dual_zone_issue" if safe_route == "ignore" else safe_route) if fallback_actionable else "ignore", "probability": probability, "delivery_route_match": match, "urgency_score": urgency, "decision_source": "jev_grey_zone_fallback"}


def _resolve_multica_bin(explicit: str | None = None) -> str:
    return explicit or os.environ.get("MULTICA_BIN") or shutil.which("multica") or "multica"


def _default_multica_runner(args: Sequence[str], *, stdin_text: str | None = None, multica_bin: str | None = None, server_url: str | None = None, workspace_id: str | None = None) -> subprocess.CompletedProcess[str]:
    command = [_resolve_multica_bin(multica_bin)]
    if server_url:
        command += ["--server-url", server_url]
    if workspace_id:
        command += ["--workspace-id", workspace_id]
    try:
        return subprocess.run(command + list(args), input=stdin_text, capture_output=True, text=True, timeout=30, check=False)
    except OSError as exc:
        return subprocess.CompletedProcess(command + list(args), 127, "", str(exc))


def _parse_json_stdout(proc: subprocess.CompletedProcess[str], context: str) -> Any:
    if proc.returncode != 0:
        raise RuntimeError(f"multica {context} failed")
    try:
        return json.loads((proc.stdout or "{}").strip() or "{}")
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"multica {context} returned invalid JSON") from exc


def build_autopilot_description(snapshot_ref: str = "~/.cache/multica-loop-runner/loop-telemetry-aidata-self-heal/snapshot.json") -> str:
    return (f"# {AUTOPILOT_TITLE}\n\n" "This scheduled tick executes the repository Loop 6A script.\n\n" "```bash\npython3 \"$AIDASH_ROOT/aidata/scripts/aidata_telemetry_self_heal.py\" run --from-autopilot --json\n```\n\n" f"The bounded redacted snapshot is read from `{snapshot_ref}`; an autopilot tick never triggers this autopilot again.\n")


def _runtime_value(value: str | None, env_name: str) -> str | None:
    return value or os.environ.get(env_name) or None


def sync_autopilot(*, server_url: str | None = None, workspace_id: str | None = None, agent_id: str | None = None, subscriber_id: str | None = None, tz_name: str = AUTOPILOT_TIMEZONE, dry_run: bool = False, runner: Callable[..., subprocess.CompletedProcess[str]] = _default_multica_runner, multica_bin: str | None = None) -> dict[str, Any]:
    if dry_run:
        return {"ok": True, "action": "dry_run", "loop_id": LOOP_ID, "title": AUTOPILOT_TITLE, "cron": AUTOPILOT_CRON, "timezone": tz_name}
    server_url = _runtime_value(server_url, "MULTICA_SERVER_URL")
    workspace_id = _runtime_value(workspace_id, "MULTICA_WORKSPACE_ID")
    agent_id = _runtime_value(agent_id, "MULTICA_AGENT_ID")
    subscriber_id = _runtime_value(subscriber_id, "MULTICA_SUBSCRIBER_ID")
    if not all((server_url, workspace_id, agent_id, subscriber_id)):
        return {"ok": False, "error": "missing_runtime_configuration"}
    kwargs = {"multica_bin": multica_bin, "server_url": server_url, "workspace_id": workspace_id}
    listed = _parse_json_stdout(runner(["autopilot", "list", "--output", "json"], **kwargs), "autopilot list")
    autopilots = listed.get("autopilots", []) if isinstance(listed, Mapping) else listed if isinstance(listed, list) else []
    existing = next((item for item in autopilots if isinstance(item, Mapping) and (item.get("title") == AUTOPILOT_TITLE or LOOP_ID in str(item.get("description") or ""))), None)
    description = build_autopilot_description()
    if existing:
        autopilot_id = str(existing.get("id") or existing.get("autopilot_id") or "")
        if not autopilot_id:
            return {"ok": False, "error": "autopilot_id_missing"}
        action = "updated"
        result = runner(["autopilot", "update", autopilot_id, "--title", AUTOPILOT_TITLE, "--agent", agent_id, "--mode", "run_only", "--status", "active", "--description", description, "--subscriber", subscriber_id, "--output", "json"], **kwargs)
        _parse_json_stdout(result, "autopilot update")
    else:
        created = _parse_json_stdout(runner(["autopilot", "create", "--title", AUTOPILOT_TITLE, "--agent", agent_id, "--mode", "run_only", "--description", description, "--subscriber", subscriber_id, "--output", "json"], **kwargs), "autopilot create")
        autopilot_id = str(created.get("id") or (created.get("autopilot") or {}).get("id") or "") if isinstance(created, Mapping) else ""
        if not autopilot_id:
            return {"ok": False, "error": "autopilot_id_missing"}
        action = "created"
    trig_data = _parse_json_stdout(runner(["autopilot", "trigger-list", autopilot_id, "--output", "json"], **kwargs), "autopilot trigger-list")
    triggers = trig_data.get("triggers", []) if isinstance(trig_data, Mapping) else trig_data if isinstance(trig_data, list) else []
    schedule = next((item for item in triggers if isinstance(item, Mapping) and str(item.get("kind") or item.get("type") or "schedule") == "schedule"), None)
    if schedule is None:
        added = _parse_json_stdout(runner(["autopilot", "trigger-add", autopilot_id, "--kind", "schedule", "--cron", AUTOPILOT_CRON, "--timezone", tz_name, "--label", AUTOPILOT_TRIGGER_LABEL, "--output", "json"], **kwargs), "autopilot trigger-add")
        trigger_id = str(added.get("id") or (added.get("trigger") or {}).get("id") or "") if isinstance(added, Mapping) else ""
        if not trigger_id:
            return {"ok": False, "error": "schedule_trigger_id_missing", "autopilot_id": autopilot_id}
        trigger_action = "created"
    else:
        trigger_id = str(schedule.get("id") or schedule.get("trigger_id") or "")
        if not trigger_id:
            return {"ok": False, "error": "schedule_trigger_id_missing", "autopilot_id": autopilot_id}
        current_cron = str(schedule.get("cron") or "")
        current_tz = str(schedule.get("timezone") or schedule.get("tz") or "")
        enabled = schedule.get("enabled", True)
        if current_cron != AUTOPILOT_CRON or current_tz != tz_name or enabled is False:
            _parse_json_stdout(runner(["autopilot", "trigger-update", autopilot_id, trigger_id, "--cron", AUTOPILOT_CRON, "--timezone", tz_name, "--enabled=true", "--output", "json"], **kwargs), "autopilot trigger-update")
            trigger_action = "updated"
        else:
            trigger_action = "kept"
    readback = _parse_json_stdout(runner(["autopilot", "trigger-list", autopilot_id, "--output", "json"], **kwargs), "autopilot trigger-list readback")
    readback_triggers = readback.get("triggers", []) if isinstance(readback, Mapping) else readback if isinstance(readback, list) else []
    persisted = next((item for item in readback_triggers if isinstance(item, Mapping) and str(item.get("id") or item.get("trigger_id") or "") == trigger_id), None)
    if not isinstance(persisted, Mapping) or str(persisted.get("cron") or "") != AUTOPILOT_CRON or str(persisted.get("timezone") or persisted.get("tz") or "") != tz_name or persisted.get("enabled", True) is False:
        return {"ok": False, "error": "schedule_readback_mismatch", "autopilot_id": autopilot_id, "trigger_id": trigger_id}
    return {"ok": True, "loop_id": LOOP_ID, "autopilot_id": autopilot_id, "trigger_id": trigger_id, "action": action, "trigger_action": trigger_action, "cron": AUTOPILOT_CRON, "timezone": tz_name}


def _load_watermarks(path: Path | None = None) -> dict[str, Any]:
    target = path or _default_state_path()
    try:
        value = json.loads(target.read_text(encoding="utf-8")) if target.is_file() else {}
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def _save_watermarks(state: Mapping[str, Any], path: Path | None = None) -> None:
    target = path or _default_state_path()
    with _sidecar_lock(target):
        current = _load_watermarks(target)
        current.update(state)
        _atomic_json_replace(target, current)


def _upsert_dual_zone_issue(*, title: str, description: str, cursor: str, assignee_id: str | None = None, priority: str = "medium", status: str = "todo", server_url: str | None = None, workspace_id: str | None = None, dry_run: bool = False, runner: Callable[..., subprocess.CompletedProcess[str]] = _default_multica_runner, multica_bin: str | None = None, allow_external_helpers: bool = True) -> dict[str, Any]:
    verification = verify_dual_zone_markdown(description)
    if not verification["ok"]:
        return {"ok": False, "error": "invalid_dual_zone", "verification": verification}
    if dry_run:
        return {"ok": True, "action": "dry_run", "cursor": cursor, "dual_zone_verification": verification}
    if not server_url or not workspace_id or not assignee_id:
        return {"ok": False, "error": "missing_runtime_configuration"}
    if allow_external_helpers:
        helper = _load_optional_helper("team-lead/scripts/multica_loop_runner.py")
        if helper is not None and hasattr(helper, "upsert_multica_dual_zone_issue"):
            return dict(helper.upsert_multica_dual_zone_issue(title=title, description=description, cursor=cursor, assignee_id=assignee_id, priority=priority, status=status, server_url=server_url, workspace_id=workspace_id, dry_run=False, runner=runner, multica_bin=multica_bin))
    kwargs = {"multica_bin": multica_bin, "server_url": server_url, "workspace_id": workspace_id}
    listed = _parse_json_stdout(runner(["issue", "list", "--limit", "100", "--output", "json"], **kwargs), "issue list")
    issues = listed.get("issues", []) if isinstance(listed, Mapping) else listed if isinstance(listed, list) else []
    token = f"multica-cursor:{cursor}"
    existing = next((item for item in issues if isinstance(item, Mapping) and token in str(item.get("description") or "")), None)
    if existing:
        issue_id = str(existing.get("id") or existing.get("identifier") or "")
        proc = runner(["issue", "update", issue_id, "--title", title, "--description-stdin", "--priority", priority, "--assignee-id", assignee_id, "--status", status, "--output", "json"], stdin_text=description, **kwargs)
        return {"ok": True, "action": "updated", "issue": _parse_json_stdout(proc, "issue update")}
    proc = runner(["issue", "create", "--title", title, "--description-stdin", "--priority", priority, "--assignee-id", assignee_id, "--status", status, "--output", "json"], stdin_text=description, **kwargs)
    return {"ok": True, "action": "created", "issue": _parse_json_stdout(proc, "issue create")}


def _trigger_autopilot(*, autopilot_id: str, runner: Callable[..., subprocess.CompletedProcess[str]], server_url: str, workspace_id: str, multica_bin: str | None) -> dict[str, Any]:
    if not autopilot_id:
        return {"ok": False, "error": "autopilot_id_missing"}
    proc = runner(["autopilot", "trigger", autopilot_id, "--output", "json"], multica_bin=multica_bin, server_url=server_url, workspace_id=workspace_id)
    return {"ok": proc.returncode == 0, "response": _parse_json_stdout(proc, "autopilot trigger") if proc.returncode == 0 else None}


def _existing_autopilot_id(*, runner: Callable[..., subprocess.CompletedProcess[str]], server_url: str, workspace_id: str, multica_bin: str | None) -> str | None:
    listed = _parse_json_stdout(runner(["autopilot", "list", "--output", "json"], multica_bin=multica_bin, server_url=server_url, workspace_id=workspace_id), "autopilot list")
    autopilots = listed.get("autopilots", []) if isinstance(listed, Mapping) else listed if isinstance(listed, list) else []
    for item in autopilots:
        if isinstance(item, Mapping) and (item.get("title") == AUTOPILOT_TITLE or LOOP_ID in str(item.get("description") or "")):
            identifier = str(item.get("id") or item.get("autopilot_id") or "")
            if identifier:
                return identifier
    return None


def _write_autopilot_snapshot(collected: Mapping[str, Any], state_path: Path | None) -> Path:
    target = (state_path.parent / f".{LOOP_ID}.snapshot.json") if state_path else Path.home() / ".cache" / "multica-loop-runner" / f"{LOOP_ID}.snapshot.json"
    payload = {"loop_id": LOOP_ID, "watermark": collected.get("watermark"), "delta_count": int(collected.get("delta_count") or 0), "severity": collected.get("severity"), "anomaly_kinds": sorted({str(item.get("kind")) for item in collected.get("residual_unhealable_items", []) if item.get("kind")})}
    _atomic_json_replace(target, payload)
    os.chmod(target, 0o600)
    return target


def run_loop_pipeline(*, aidata_home: Path | None = None, shared_telemetry_dir: Path | None = None, vault_dir: Path | None = None, fixture_json: Path | Mapping[str, Any] | None = None, target_date: date | None = None, now: datetime | None = None, state_path: Path | None = None, auto_heal: bool = True, dry_run: bool = False, force: bool = False, mock_jev_json: Any = None, server_url: str | None = None, workspace_id: str | None = None, owner_id: str | None = None, jev_fn: Callable[..., Mapping[str, Any] | None] | None = None, runner: Callable[..., subprocess.CompletedProcess[str]] = _default_multica_runner, multica_bin: str | None = None, normalize_merge_healer: Callable[..., list[dict[str, Any]]] | None = None, from_autopilot: bool = False) -> dict[str, Any]:
    collected = inspect_and_self_heal(aidata_home=aidata_home, shared_telemetry_dir=shared_telemetry_dir, vault_dir=vault_dir, fixture_json=fixture_json, target_date=target_date, now=now, auto_heal=auto_heal, dry_run=dry_run, normalize_merge_healer=normalize_merge_healer)
    previous = _load_watermarks(state_path).get(LOOP_ID, {})
    previous_watermark = str(previous.get("watermark") or "") if isinstance(previous, Mapping) else ""
    watermark = str(collected.get("watermark") or "")
    if not force and (not collected["has_delta"] or watermark == previous_watermark):
        return {"ok": True, "loop_id": LOOP_ID, "status": "SKIPPED_NO_DELTA" if not collected.get("healed_items") else "HEALED_LOCALLY_NO_ALERT", "layer_reached": 0, "token_cost": 0, "watermark": watermark, "previous_watermark": previous_watermark, "healed_items": collected.get("healed_items", []), "residual_unhealable_items": collected.get("residual_unhealable_items", [])}
    fixture_mode = fixture_json is not None
    effective_jev_fn = jev_fn or ((lambda **_: None) if fixture_mode and mock_jev_json is None else None)
    verdict = evaluate_jev_decision(collected, mock_jev_json=mock_jev_json, jev_fn=effective_jev_fn)
    if not verdict["actionable"]:
        if not dry_run and watermark:
            _save_watermarks({LOOP_ID: {"watermark": watermark, "last_status": "SKIPPED_NOT_ACTIONABLE"}}, state_path)
        return {"ok": True, "loop_id": LOOP_ID, "status": "SKIPPED_NOT_ACTIONABLE", "layer_reached": 1, "watermark": watermark, "jev": verdict}
    route = str(verdict.get("route") or "dual_zone_issue")
    if route == "autopilot_trigger" and (from_autopilot or os.environ.get("MULTICA_FROM_AUTOPILOT") == "1"):
        route = "dual_zone_issue"
    delivery: dict[str, Any]
    if route == "autopilot_trigger":
        if dry_run:
            delivery = {"ok": True, "action": "dry_run_trigger", "route": route}
        else:
            server = _runtime_value(server_url, "MULTICA_SERVER_URL")
            workspace = _runtime_value(workspace_id, "MULTICA_WORKSPACE_ID")
            if not server or not workspace:
                delivery = {"ok": False, "error": "missing_runtime_configuration"}
            else:
                snapshot = _write_autopilot_snapshot(collected, state_path)
                autopilot_id = _existing_autopilot_id(runner=runner, server_url=server, workspace_id=workspace, multica_bin=multica_bin)
                if not autopilot_id:
                    delivery = {"ok": False, "error": "autopilot_not_registered", "retryable": True}
                else:
                    delivery = {"ok": True, "action": "triggered", "autopilot_id": autopilot_id, "snapshot": str(snapshot), "trigger": _trigger_autopilot(autopilot_id=autopilot_id, runner=runner, server_url=server, workspace_id=workspace, multica_bin=multica_bin)}
                    delivery["ok"] = bool(delivery["trigger"].get("ok"))
    else:
        delivery = _upsert_dual_zone_issue(title=str(collected["title"]), description=str(collected["dual_zone_markdown"]), cursor=str(collected["cursor"]), assignee_id=_runtime_value(owner_id, "MULTICA_SUBSCRIBER_ID"), server_url=_runtime_value(server_url, "MULTICA_SERVER_URL"), workspace_id=_runtime_value(workspace_id, "MULTICA_WORKSPACE_ID"), dry_run=dry_run, runner=runner, multica_bin=multica_bin, allow_external_helpers=not fixture_mode)
    delivered = bool(delivery.get("ok"))
    if not dry_run and delivered and watermark:
        _save_watermarks({LOOP_ID: {"watermark": watermark, "last_status": "ACTION_TAKEN", "route": route}}, state_path)
    return {"ok": delivered, "loop_id": LOOP_ID, "status": "ACTION_TAKEN" if delivered else "DELIVERY_FAILED", "layer_reached": 2, "route": route, "watermark": watermark, "jev": verdict, "delivery": delivery, "dual_zone_verification": collected.get("dual_zone_verification")}


def _common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--aidata-home", type=Path)
    parser.add_argument("--shared-telemetry-dir", type=Path)
    parser.add_argument("--vault-dir", type=Path)
    parser.add_argument("--fixture-json", type=Path)
    parser.add_argument("--date", default="today")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--no-heal", action="store_true")
    parser.add_argument("--json", action="store_true")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="aidata_telemetry_self_heal.py")
    sub = parser.add_subparsers(dest="subcommand", required=True)
    for name, help_text in (("collect", "Run deterministic collection audit"), ("self-heal", "Run local deterministic self-heal"), ("run", "Run the full bounded loop")):
        child = sub.add_parser(name, help=help_text)
        _common_args(child)
    sync = sub.add_parser("sync-autopilot", help="Reconcile the Loop 6A autopilot schedule")
    sync.add_argument("--server-url")
    sync.add_argument("--workspace-id")
    sync.add_argument("--agent-id")
    sync.add_argument("--subscriber-id")
    sync.add_argument("--timezone", default=AUTOPILOT_TIMEZONE)
    sync.add_argument("--dry-run", action="store_true")
    sync.add_argument("--json", action="store_true")
    run = sub.choices["run"]
    run.add_argument("--state-file", type=Path)
    run.add_argument("--force", action="store_true")
    run.add_argument("--mock-jev-json")
    run.add_argument("--server-url")
    run.add_argument("--workspace-id")
    run.add_argument("--owner-id")
    run.add_argument("--from-autopilot", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    ns = _build_parser().parse_args(argv)
    try:
        if ns.subcommand == "sync-autopilot":
            result = sync_autopilot(server_url=ns.server_url, workspace_id=ns.workspace_id, agent_id=ns.agent_id, subscriber_id=ns.subscriber_id, tz_name=ns.timezone, dry_run=ns.dry_run)
        else:
            target = datetime.now(CST).date() if ns.date == "today" else date.fromisoformat(ns.date)
            if ns.subcommand == "run":
                result = run_loop_pipeline(aidata_home=ns.aidata_home, shared_telemetry_dir=ns.shared_telemetry_dir, vault_dir=ns.vault_dir, fixture_json=ns.fixture_json, target_date=target, auto_heal=not ns.no_heal, dry_run=ns.dry_run, force=ns.force, mock_jev_json=ns.mock_jev_json, state_path=ns.state_file, server_url=ns.server_url, workspace_id=ns.workspace_id, owner_id=ns.owner_id, from_autopilot=ns.from_autopilot)
            else:
                result = inspect_and_self_heal(aidata_home=ns.aidata_home, shared_telemetry_dir=ns.shared_telemetry_dir, vault_dir=ns.vault_dir, fixture_json=ns.fixture_json, target_date=target, auto_heal=not ns.no_heal and ns.subcommand == "self-heal", dry_run=ns.dry_run)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0 if result.get("ok") else 1
    except (OSError, ValueError, RuntimeError, TimeoutError) as exc:
        print(json.dumps({"ok": False, "error": type(exc).__name__}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
