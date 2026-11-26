"""Opt-in, bounded L1/L2 projection for agent-retro 6-layer trajectory & horizon waste.

This adapter is intentionally excluded from `config.SOURCES` and scheduled cron.
Operators or tests pass bounded records to :func:`normalize_records`, or invoke
:func:`collect` against explicit/local snapshot files, writing only closed enums,
counts, durations, `vN@sha` versions, and SHA-256 hashes—never raw transcripts,
prompt bodies, or secret-bearing local paths.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import re
import sqlite3
from collections.abc import Iterable, Mapping
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from config import CLEAN_DIR, clean_path
from quality_contracts import canonical_skill, iso_timestamp
from rawio import read_raw, write_raw

SOURCE = "agent_retro"

VALID_LAYERS: tuple[str, ...] = (
    "role",
    "handoff",
    "invoke",
    "exec",
    "friction",
    "horizon",
)
VALID_ROLES: frozenset[str] = frozenset({
    "m3",
    "m2",
    "m1",
    "designer",
    "writer",
    "reviewer",
    "explorer",
    "pr_monitor",
})
VALID_SEVERITIES: frozenset[str] = frozenset({"critical", "high", "medium", "low", "info"})
VALID_HORIZON_CATEGORIES: frozenset[str] = frozenset({
    "context_carry",
    "wakeup_parallelism",
    "rework_verify",
    "fatigue_inflection",
    "steering_overkill",
})

_DEFAULT_SNAPSHOT_PATH = Path("/tmp/multica-agent-retro-collect.json")  # nosec B108 - explicit opt-in default
_MAX_SNAPSHOT_BYTES = 4 * 1024 * 1024

_SKILL_VERSION_RE = re.compile(
    r"^(?:[0-9A-Za-z._-]+\+)?(v\d+@[0-9a-fA-F]{4,40})$"
)
_SAFE_CODE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,95}$")

_FINDING_TO_LAYER: dict[str, str] = {
    "R1": "role",
    "R2": "role",
    "R3": "role",
    "R4": "role",
    "R5": "role",
    "H1": "handoff",
    "H2": "handoff",
    "H3": "handoff",
    "H4": "handoff",
    "H5": "handoff",
    "I1": "invoke",
    "I2": "invoke",
    "I3": "invoke",
    "I4": "invoke",
    "I5": "invoke",
    "E1": "exec",
    "E2": "exec",
    "E3": "exec",
    "E4": "exec",
    "F1": "friction",
    "F2": "friction",
    "F3": "friction",
    "HZN1": "horizon",
    "HZN2": "horizon",
    "HZN3": "horizon",
    "HZN4": "horizon",
    "HZN5": "horizon",
}

_HORIZON_CATEGORY_MAP: dict[str, str] = {
    "HZN1": "context_carry",
    "HZN2": "wakeup_parallelism",
    "HZN3": "rework_verify",
    "HZN4": "fatigue_inflection",
    "HZN5": "steering_overkill",
}

_SKILL_TO_DEFAULT_ROLE: dict[str, str] = {
    "personal-m2-assistant": "m3",
    "m2-dispatcher": "m2",
    "team-lead": "m1",
    "my-designer": "designer",
    "design-studio": "designer",
    "code-review": "reviewer",
    "agent-retro": "explorer",
}

_FINDING_DDL = """
CREATE TABLE retro_finding (
    finding_uid TEXT PRIMARY KEY,
    source TEXT NOT NULL,
    session_id TEXT NOT NULL,
    goal_id TEXT,
    role_key TEXT NOT NULL,
    skill TEXT NOT NULL,
    layer_key TEXT NOT NULL,
    finding_code TEXT NOT NULL,
    severity TEXT NOT NULL,
    skill_version TEXT,
    is_post_fix INTEGER NOT NULL,
    occurrence_count INTEGER NOT NULL,
    ts TEXT NOT NULL
)
"""

_FINDING_COLS = (
    "finding_uid",
    "source",
    "session_id",
    "goal_id",
    "role_key",
    "skill",
    "layer_key",
    "finding_code",
    "severity",
    "skill_version",
    "is_post_fix",
    "occurrence_count",
    "ts",
)

_HORIZON_DDL = """
CREATE TABLE horizon_waste (
    waste_uid TEXT PRIMARY KEY,
    source TEXT NOT NULL,
    session_id TEXT NOT NULL,
    role_key TEXT NOT NULL,
    skill TEXT NOT NULL,
    horizon_code TEXT NOT NULL,
    category_key TEXT NOT NULL,
    wasted_turns INTEGER NOT NULL,
    wasted_tokens INTEGER NOT NULL,
    duration_sec REAL NOT NULL,
    ts TEXT NOT NULL
)
"""

_HORIZON_COLS = (
    "waste_uid",
    "source",
    "session_id",
    "role_key",
    "skill",
    "horizon_code",
    "category_key",
    "wasted_turns",
    "wasted_tokens",
    "duration_sec",
    "ts",
)


def _hash_identifier(value: Any, *, prefix: str) -> str:
    raw = str(value or "").strip()
    if not raw:
        return f"{prefix}:anon"
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,63}", raw) and "/" not in raw and "\\" not in raw and "@" not in raw:
        return raw
    digest = hashlib.sha256(raw.encode("utf-8", errors="replace")).hexdigest()[:16]
    return f"{prefix}:{digest}"


def _uid(*parts: Any) -> str:
    payload = "|".join("" if part is None else str(part) for part in parts)
    return hashlib.sha256(payload.encode("utf-8", errors="replace")).hexdigest()[:24]


def _normalize_role(raw_role: Any, *, skill: str) -> str:
    role = str(raw_role or "").strip().lower()
    if role in VALID_ROLES:
        return role
    if "m3" in role or "personal-m2" in role:
        return "m3"
    if "m2" in role or "dispatcher" in role:
        return "m2"
    if "m1" in role or "steering" in role or "team_lead" in role or "team-lead" in role or role == "tl":
        return "m1"
    if "design" in role:
        return "designer"
    if "review" in role:
        return "reviewer"
    if "explor" in role:
        return "explorer"
    if "monitor" in role or "prmon" in role:
        return "pr_monitor"
    if "writ" in role or "cod" in role:
        return "writer"
    return _SKILL_TO_DEFAULT_ROLE.get(skill, "writer")


def _normalize_skill(raw_skill: Any) -> str:
    norm = canonical_skill(raw_skill)
    if not norm or "/" in norm or "\\" in norm or "@" in norm:
        return "unmeasured"
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}", norm):
        return "unmeasured"
    return norm


def _normalize_skill_version(raw_version: Any) -> str | None:
    text = str(raw_version or "").strip()
    if not text:
        return None
    match = _SKILL_VERSION_RE.match(text)
    if match:
        return match.group(1).lower()
    return None


def _normalize_code(raw_code: Any, *, default: str) -> str:
    text = str(raw_code or "").strip()
    if _SAFE_CODE_RE.fullmatch(text):
        return text
    return default


def _infer_layer(raw_layer: Any, finding_code: str) -> str | None:
    layer = str(raw_layer or "").strip().lower()
    if layer.startswith("l-"):  # noqa: FURB188 - Python 3.9 compat
        layer = layer[2:]
    if layer in VALID_LAYERS:
        return layer
    prefix = finding_code.split("_", 1)[0].upper()
    return _FINDING_TO_LAYER.get(prefix)


def _infer_severity(raw_severity: Any, finding_code: str) -> str:
    sev = str(raw_severity or "").strip().lower()
    if sev in VALID_SEVERITIES:
        return sev
    prefix = finding_code.split("_", 1)[0].upper()
    if prefix in {"R2", "E4"}:
        return "critical"
    if prefix in {"I3", "E1", "E2", "H1", "H3"}:
        return "high"
    if prefix.startswith("HZN"):
        return "medium"
    return "medium"


def _infer_horizon_category(raw_category: Any, horizon_code: str) -> str:
    cat = str(raw_category or "").strip().lower()
    if cat in VALID_HORIZON_CATEGORIES:
        return cat
    prefix = horizon_code.split("_", 1)[0].upper()
    return _HORIZON_CATEGORY_MAP.get(prefix, "context_carry")


def _nonneg_int(value: Any, *, default: int = 0) -> int:
    if isinstance(value, bool) or value is None or value == "":
        return default
    try:
        return max(0, int(float(value)))
    except (TypeError, ValueError, OverflowError):
        return default


def _nonneg_float(value: Any, *, default: float = 0.0) -> float:
    if isinstance(value, bool) or value is None or value == "":
        return default
    try:
        parsed = float(value)
        if not math.isfinite(parsed) or parsed < 0.0:
            return default
        return round(parsed, 2)
    except (TypeError, ValueError, OverflowError):
        return default


def _normalize_finding_record(
    record: Mapping[str, Any],
    *,
    fallback_ts: str | None = None,
) -> list[dict[str, Any]]:
    raw_status = str(record.get("status") or "").strip().lower()
    if raw_status == "healthy_progressive_disclosure":
        return []

    code = _normalize_code(
        record.get("finding_code") or record.get("metric") or record.get("code"),
        default="",
    )
    layer = _infer_layer(record.get("layer_key") or record.get("layer"), code)
    if not layer:
        return []
    if not code:
        code = f"{layer}_finding"

    ts = iso_timestamp(record.get("ts") or record.get("timestamp") or record.get("observed_at") or fallback_ts)
    if not ts:
        return []

    source = _hash_identifier(record.get("source") or SOURCE, prefix="src")
    session_id = _hash_identifier(record.get("session_id") or record.get("session") or "aggregate", prefix="sess")
    raw_goal = record.get("goal_id") or record.get("goal")
    goal_id = _hash_identifier(raw_goal, prefix="goal") if raw_goal not in (None, "") else None
    skill = _normalize_skill(record.get("skill") or record.get("upstream_skill"))
    role_key = _normalize_role(record.get("role_key") or record.get("role"), skill=skill)
    severity = _infer_severity(record.get("severity"), code)
    skill_version = _normalize_skill_version(record.get("skill_version") or record.get("version"))

    # Support split pre_fix_count / post_fix_count observations from agent_retro scan
    has_split_counts = (
        record.get("pre_fix_count") is not None or record.get("post_fix_count") is not None
    ) and record.get("is_post_fix") is None

    if has_split_counts:
        pre_cnt = _nonneg_int(record.get("pre_fix_count"), default=0)
        post_cnt = _nonneg_int(record.get("post_fix_count"), default=0)
        out: list[dict[str, Any]] = []
        for is_post, cnt in ((0, pre_cnt), (1, post_cnt)):
            if cnt <= 0:
                continue
            uid = _uid("finding", source, session_id, goal_id, role_key, skill, layer, code, skill_version, is_post, ts)
            out.append({
                "finding_uid": uid,
                "source": source,
                "session_id": session_id,
                "goal_id": goal_id,
                "role_key": role_key,
                "skill": skill,
                "layer_key": layer,
                "finding_code": code,
                "severity": severity,
                "skill_version": skill_version,
                "is_post_fix": is_post,
                "occurrence_count": cnt,
                "ts": ts,
            })
        return out

    raw_post = record.get("is_post_fix")
    if isinstance(raw_post, bool) or raw_post in (0, 1, "0", "1"):
        is_post_fix = int(raw_post)
    else:
        fix_bucket = str(record.get("fix_bucket") or "").strip().lower()
        is_post_fix = 0 if fix_bucket == "pre_fix" else 1

    occurrence_count = _nonneg_int(
        record.get("occurrence_count") if record.get("occurrence_count") is not None else record.get("count"),
        default=1,
    )
    if occurrence_count <= 0:
        return []

    explicit_uid = record.get("finding_uid")
    finding_uid = (
        _hash_identifier(explicit_uid, prefix="fnd")
        if explicit_uid not in (None, "")
        else _uid("finding", source, session_id, goal_id, role_key, skill, layer, code, skill_version, is_post_fix, ts)
    )
    return [{
        "finding_uid": finding_uid,
        "source": source,
        "session_id": session_id,
        "goal_id": goal_id,
        "role_key": role_key,
        "skill": skill,
        "layer_key": layer,
        "finding_code": code,
        "severity": severity,
        "skill_version": skill_version,
        "is_post_fix": is_post_fix,
        "occurrence_count": occurrence_count,
        "ts": ts,
    }]


def _normalize_horizon_record(
    record: Mapping[str, Any],
    *,
    fallback_ts: str | None = None,
) -> dict[str, Any] | None:
    code = _normalize_code(
        record.get("horizon_code") or record.get("metric") or record.get("code"),
        default="",
    )
    if not code:
        return None
    ts = iso_timestamp(record.get("ts") or record.get("timestamp") or record.get("observed_at") or fallback_ts)
    if not ts:
        return None

    source = _hash_identifier(record.get("source") or SOURCE, prefix="src")
    session_id = _hash_identifier(record.get("session_id") or record.get("session") or "aggregate", prefix="sess")
    skill = _normalize_skill(record.get("skill") or record.get("upstream_skill"))
    role_key = _normalize_role(record.get("role_key") or record.get("role"), skill=skill)
    category_key = _infer_horizon_category(record.get("category_key") or record.get("category"), code)
    wasted_turns = _nonneg_int(
        record.get("wasted_turns") if record.get("wasted_turns") is not None else record.get("count"),
        default=0,
    )
    wasted_tokens = _nonneg_int(record.get("wasted_tokens"), default=0)
    duration_sec = _nonneg_float(record.get("duration_sec"), default=0.0)
    if wasted_turns <= 0 and wasted_tokens <= 0 and duration_sec <= 0.0:
        return None

    explicit_uid = record.get("waste_uid")
    waste_uid = (
        _hash_identifier(explicit_uid, prefix="hzn")
        if explicit_uid not in (None, "")
        else _uid("horizon", source, session_id, role_key, skill, code, category_key, ts)
    )
    return {
        "waste_uid": waste_uid,
        "source": source,
        "session_id": session_id,
        "role_key": role_key,
        "skill": skill,
        "horizon_code": code,
        "category_key": category_key,
        "wasted_turns": wasted_turns,
        "wasted_tokens": wasted_tokens,
        "duration_sec": duration_sec,
        "ts": ts,
    }


def _transform_records(
    records: Iterable[Mapping[str, Any]],
    *,
    fallback_ts: str | None = None,
) -> dict[str, Any]:
    findings_by_uid: dict[str, dict[str, Any]] = {}
    waste_by_uid: dict[str, dict[str, Any]] = {}
    stamps: list[str] = []

    for item in records:
        if not isinstance(item, Mapping):
            continue
        kind = str(item.get("kind") or "").strip().lower()
        is_explicit_horizon = (
            kind in {"horizon_waste", "horizon"}
            or item.get("horizon_code") is not None
            or item.get("wasted_tokens") is not None
            or item.get("wasted_turns") is not None
        )
        is_explicit_finding = (
            kind in {"retro_finding", "finding", "observation"}
            or item.get("finding_code") is not None
            or item.get("layer_key") is not None
            or (item.get("layer") is not None and kind not in {"horizon_waste"})
        )

        if is_explicit_finding or not is_explicit_horizon:
            for row in _normalize_finding_record(item, fallback_ts=fallback_ts):
                findings_by_uid[row["finding_uid"]] = row
                stamps.append(row["ts"])

        if is_explicit_horizon:
            w_row = _normalize_horizon_record(item, fallback_ts=fallback_ts)
            if w_row is not None:
                waste_by_uid[w_row["waste_uid"]] = w_row
                stamps.append(w_row["ts"])

    findings = sorted(findings_by_uid.values(), key=lambda r: (r["ts"], r["finding_uid"]))
    waste = sorted(waste_by_uid.values(), key=lambda r: (r["ts"], r["waste_uid"]))
    return {
        "retro_findings": findings,
        "horizon_waste": waste,
        "source_as_of": max(stamps) if stamps else None,
    }


def _write_db(db_path: Path, normalized: Mapping[str, Any]) -> int:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = db_path.with_name(f".{db_path.name}.tmp.{os.getpid()}")
    if tmp_path.exists():
        tmp_path.unlink()
    connection = sqlite3.connect(tmp_path)
    try:
        connection.execute(_FINDING_DDL)
        connection.execute(_HORIZON_DDL)
        finding_rows = [r for r in normalized.get("retro_findings", []) if isinstance(r, Mapping)]
        waste_rows = [r for r in normalized.get("horizon_waste", []) if isinstance(r, Mapping)]
        if finding_rows:
            connection.executemany(
                f"INSERT OR REPLACE INTO retro_finding ({', '.join(_FINDING_COLS)}) "
                f"VALUES ({', '.join('?' for _ in _FINDING_COLS)})",
                [tuple(row.get(col) for col in _FINDING_COLS) for row in finding_rows],
            )
        if waste_rows:
            connection.executemany(
                f"INSERT OR REPLACE INTO horizon_waste ({', '.join(_HORIZON_COLS)}) "
                f"VALUES ({', '.join('?' for _ in _HORIZON_COLS)})",
                [tuple(row.get(col) for col in _HORIZON_COLS) for row in waste_rows],
            )
        connection.commit()
        count = len(finding_rows) + len(waste_rows)
    finally:
        connection.close()
    tmp_path.replace(db_path)
    return count


def normalize_records(
    records: Iterable[Mapping[str, Any]],
    *,
    db_path: Path | None = None,
) -> dict[str, Any]:
    """Normalize bounded agent-retro records and atomically materialize clean/agent_retro.db."""
    normalized = _transform_records(records)
    _write_db(Path(db_path) if db_path is not None else clean_path(SOURCE), normalized)
    return normalized


def _extract_snapshot_records(
    snapshot: Mapping[str, Any],
    *,
    fallback_ts: str,
) -> list[dict[str, Any]]:
    scan = snapshot.get("scan") if isinstance(snapshot.get("scan"), Mapping) else snapshot
    if not isinstance(scan, Mapping):
        return []
    watermark = scan.get("version_watermark") if isinstance(scan.get("version_watermark"), Mapping) else {}
    target_watermarks = (
        watermark.get("target_skill_watermarks")
        if isinstance(watermark.get("target_skill_watermarks"), Mapping)
        else {}
    )
    default_version = _normalize_skill_version(watermark.get("current"))
    extracted: list[dict[str, Any]] = []

    observations = scan.get("observations")
    if isinstance(observations, list):
        for obs in observations:
            if not isinstance(obs, Mapping):
                continue
            skill_raw = obs.get("upstream_skill") or obs.get("skill")
            skill_norm = _normalize_skill(skill_raw)
            target_entry = target_watermarks.get(skill_norm) if isinstance(target_watermarks, Mapping) else None
            target_ver = (
                _normalize_skill_version(
                    target_entry.get("version")
                    or target_entry.get("current")
                    or target_entry.get("skill_version")
                )
                if isinstance(target_entry, Mapping)
                else None
            )
            ev_list = obs.get("evidence") if isinstance(obs.get("evidence"), list) else []
            first_ev = str(ev_list[0]) if ev_list else ""
            raw_sid = first_ev.split(":", 1)[0].strip() if ":" in first_ev else "snapshot"
            sid_hash = _hash_identifier(raw_sid, prefix="sess")
            ts_val = obs.get("ts") or snapshot.get("generated_at") or fallback_ts

            extracted.append({
                "kind": "retro_finding",
                "source": SOURCE,
                "session_id": sid_hash,
                "skill": skill_norm,
                "role_key": obs.get("role_key") or obs.get("role"),
                "layer_key": obs.get("layer"),
                "finding_code": obs.get("metric"),
                "severity": obs.get("severity"),
                "skill_version": obs.get("skill_version") or target_ver or default_version,
                "fix_bucket": obs.get("fix_bucket"),
                "pre_fix_count": obs.get("pre_fix_count"),
                "post_fix_count": obs.get("post_fix_count"),
                "count": obs.get("count"),
                "status": obs.get("status"),
                "ts": ts_val,
            })

            if str(obs.get("layer") or "").strip().lower() == "horizon":
                wasted_tokens = _nonneg_int(obs.get("wasted_tokens"), default=0)
                if wasted_tokens == 0 and first_ev:
                    m_tok = re.search(r"carry_byte_turns=(\d+)", first_ev)
                    if m_tok:
                        wasted_tokens = max(0, int(m_tok.group(1)) // 4)
                dur_sec = _nonneg_float(obs.get("duration_sec"), default=0.0)
                if dur_sec == 0.0 and first_ev:
                    m_lag = re.search(r"wakeup_lag_sec=(\d+)", first_ev)
                    if m_lag:
                        dur_sec = float(m_lag.group(1))
                extracted.append({
                    "kind": "horizon_waste",
                    "source": SOURCE,
                    "session_id": sid_hash,
                    "skill": skill_norm,
                    "role_key": obs.get("role_key") or obs.get("role"),
                    "horizon_code": obs.get("metric"),
                    "wasted_turns": _nonneg_int(obs.get("wasted_turns") or obs.get("count"), default=1),
                    "wasted_tokens": wasted_tokens,
                    "duration_sec": dur_sec,
                    "ts": ts_val,
                })

    horizon_rows = scan.get("horizon")
    if isinstance(horizon_rows, list):
        for h_item in horizon_rows:
            if not isinstance(h_item, Mapping):
                continue
            extracted.append({
                "kind": "horizon_waste",
                "source": SOURCE,
                "session_id": _hash_identifier(h_item.get("session_id") or "snapshot", prefix="sess"),
                "skill": h_item.get("upstream_skill") or h_item.get("skill"),
                "role_key": h_item.get("role_key") or h_item.get("role"),
                "horizon_code": h_item.get("horizon_code") or h_item.get("metric"),
                "category_key": h_item.get("category_key"),
                "wasted_turns": _nonneg_int(h_item.get("wasted_turns") or h_item.get("count"), default=1),
                "wasted_tokens": _nonneg_int(h_item.get("wasted_tokens"), default=0),
                "duration_sec": _nonneg_float(h_item.get("duration_sec"), default=0.0),
                "ts": h_item.get("ts") or snapshot.get("generated_at") or fallback_ts,
            })
    return extracted


def collect(
    *,
    now: datetime | None = None,
    snapshot_path: Path | None = None,
    db_path: Path | None = None,
) -> int:
    """Opt-in bounded collection from an agent-retro JSON snapshot; degrades to 0 when absent."""
    configured = os.environ.get("AIDATA_AGENT_RETRO_SNAPSHOT", "").strip()
    if snapshot_path is not None:
        candidate = Path(snapshot_path).expanduser()
    elif configured:
        candidate = Path(configured).expanduser()
    elif os.environ.get("PYTEST_CURRENT_TEST"):
        return 0
    else:
        candidate = _DEFAULT_SNAPSHOT_PATH

    if not candidate.is_file():
        return 0
    try:
        size = candidate.stat().st_size
        if size <= 0 or size > _MAX_SNAPSHOT_BYTES:
            return 0
        parsed = json.loads(candidate.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return 0
    if not isinstance(parsed, Mapping):
        return 0

    now_iso = iso_timestamp(now or datetime.now(timezone.utc)) or "1970-01-01T00:00:00Z"  # noqa: UP017
    if isinstance(parsed.get("records"), list):
        candidates = [r for r in parsed["records"] if isinstance(r, Mapping)]
    else:
        candidates = _extract_snapshot_records(parsed, fallback_ts=now_iso)

    normalized = _transform_records(candidates, fallback_ts=now_iso)
    existing = read_raw(SOURCE)
    seen = {
        str(row.get("finding_uid") or row.get("waste_uid"))
        for row in existing
        if row.get("kind") in {"retro_finding", "horizon_waste"}
    }
    new_rows: list[dict[str, Any]] = [
        {"kind": "retro_finding", **row}
        for row in normalized["retro_findings"]
        if str(row["finding_uid"]) not in seen
    ]
    new_rows.extend(
        {"kind": "horizon_waste", **row}
        for row in normalized["horizon_waste"]
        if str(row["waste_uid"]) not in seen
    )
    written = write_raw(SOURCE, new_rows) if new_rows else 0
    all_raw = existing + new_rows
    if all_raw or db_path is not None:
        rebuilt = _transform_records(all_raw, fallback_ts=now_iso)
        _write_db(Path(db_path) if db_path is not None else clean_path(SOURCE), rebuilt)
    return written


def normalize(*, db_path: Path | None = None) -> int:
    """Materialize clean/agent_retro.db from redacted L1 raw shards."""
    raw = read_raw(SOURCE)
    normalized = _transform_records(raw)
    return _write_db(Path(db_path) if db_path is not None else clean_path(SOURCE), normalized)


def clean_db_path() -> Path:
    """Return the derived L2 path without creating or touching it."""
    return CLEAN_DIR / f"{SOURCE}.db"
