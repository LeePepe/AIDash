"""Opt-in, bounded L1/L2 projection for Goal-Aggregated & Session Work Summary.

Reads `~/.copilot/session-store.db` strictly read-only (`mode=ro&immutable=1`),
links sessions to GTT Goals via worktree/handoff paths or explicit `Goal <slug>`
markers, enriches with optional clean skill/script metadata, and materializes
`clean/session_work.db` (`session_work` table) at the Session Work Receipt grain.

Excluded from `config.SOURCES`, `SCHEDULED_SOURCES`, and `MERGE_SOURCES`—invoked
explicitly by `scripts/aidata_digest_run.sh` Stage 3. Persists ONLY metadata,
8-char short session IDs, sanitized repo/goal/branch slugs, scrubbed 1-line
summaries (`<=80` chars), closed role enums, counts, and durations—NEVER raw
prompts, assistant transcripts, or local absolute paths.
"""

from __future__ import annotations

import contextlib
import hashlib
import json
import math
import os
import re
import sqlite3
from collections.abc import Iterable, Mapping, Sequence
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import config
from quality_contracts import canonical_skill, iso_timestamp
from rawio import read_raw, write_raw
from redaction import redact

SOURCE = "session_work"

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

_SKILL_TO_DEFAULT_ROLE: dict[str, str] = {
    "personal-m2-assistant": "m3",
    "m2-dispatcher": "m2",
    "team-lead": "m1",
    "my-designer": "designer",
    "design-studio": "designer",
    "code-review": "reviewer",
    "agent-retro": "explorer",
}

_SKILL_PATTERNS = (
    re.compile(r"(?:^|\n)\s*/skill\s+([A-Za-z0-9][A-Za-z0-9._-]{0,127})(?=\s|$)", re.IGNORECASE),
    re.compile(r'''<skill-context\s+name=["']([A-Za-z0-9][A-Za-z0-9._-]{0,127})["']''', re.IGNORECASE),
    re.compile(r"(?:^|[/\\])skills[/\\]([A-Za-z0-9][A-Za-z0-9._-]{0,127})[/\\]SKILL\.md\b", re.IGNORECASE),
)

_CWD_GOAL_RE = re.compile(
    r"(?:^|[/\\])(?:worktrees|handoffs?)[/\\]([A-Za-z0-9][A-Za-z0-9._-]{1,95})(?:[/\\]|$)"
)
_SUMMARY_GOAL_RE = re.compile(
    r"\bGoal[:\s]+`?([A-Za-z0-9][A-Za-z0-9._-]{1,95})`?",
    re.IGNORECASE,
)
_BRANCH_GOAL_RE = re.compile(
    r"^(?:feat|fix|refactor|docs|chore|test)/([A-Za-z0-9][A-Za-z0-9._-]{1,95})$",
    re.IGNORECASE,
)

_UNIX_ABS_PATH_RE = re.compile(
    r"(?:['\"])?(?:/Users|/home|/Volumes|/private|/var|/tmp|/opt|/etc)(?:/[^\s'\"<>`|;]+)+"
)
_WIN_ABS_PATH_RE = re.compile(r"(?:['\"])?[A-Za-z]:\\(?:[^\s'\"<>`|;]+)")
_EMAIL_FULL_RE = re.compile(r"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b")
_SAFE_SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$")
_SAFE_GOAL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$")
_PR_DIGITS_RE = re.compile(r"(?:#|/pull/|/prs?/)?(\d{1,7})\b")

_SESSION_WORK_DDL = """
CREATE TABLE session_work (
    session_uid TEXT PRIMARY KEY,
    source TEXT NOT NULL,
    session_id_short TEXT NOT NULL,
    goal_id TEXT,
    repo_name TEXT,
    branch_name TEXT,
    role_key TEXT NOT NULL,
    model_id TEXT,
    summary_label TEXT,
    started_at TEXT,
    ended_at TEXT,
    duration_sec REAL NOT NULL,
    turn_count INTEGER NOT NULL,
    total_tokens INTEGER NOT NULL,
    skills_json TEXT NOT NULL,
    search_read_calls INTEGER NOT NULL,
    code_edit_calls INTEGER NOT NULL,
    verify_script_calls INTEGER NOT NULL,
    spin_rework_calls INTEGER NOT NULL,
    files_changed_count INTEGER NOT NULL,
    commits_count INTEGER NOT NULL,
    pr_number INTEGER,
    slow_or_failed_scripts_json TEXT NOT NULL
)
"""

_SESSION_WORK_COLS = (
    "session_uid",
    "source",
    "session_id_short",
    "goal_id",
    "repo_name",
    "branch_name",
    "role_key",
    "model_id",
    "summary_label",
    "started_at",
    "ended_at",
    "duration_sec",
    "turn_count",
    "total_tokens",
    "skills_json",
    "search_read_calls",
    "code_edit_calls",
    "verify_script_calls",
    "spin_rework_calls",
    "files_changed_count",
    "commits_count",
    "pr_number",
    "slow_or_failed_scripts_json",
)

_EDIT_TOOLS = frozenset({"edit", "create", "apply_patch", "write", "write_file", "str_replace_editor"})
_READ_TOOLS = frozenset({"view", "read", "read_file", "grep", "glob"})


def _parse_dt(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        dt = value
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        try:
            sec = float(value) / 1000.0 if float(value) > 1e11 else float(value)
            dt = datetime.fromtimestamp(sec, timezone.utc)  # noqa: UP017
        except (OverflowError, OSError, ValueError):
            return None
    elif isinstance(value, str) and value.strip():
        raw = value.strip()
        try:
            dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))  # noqa: FURB162
        except ValueError:
            return None
    else:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)  # noqa: UP017
    return dt.astimezone(timezone.utc)  # noqa: UP017


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


def _short_session_id(raw_id: Any) -> str:
    text = str(raw_id or "").strip()
    if not text:
        return "00000000"
    if re.fullmatch(r"[0-9a-fA-F]{8}", text):
        return text.lower()
    if re.fullmatch(r"[0-9a-fA-F]{8}-[0-9a-fA-F-]{4,}", text):
        return text[:8].lower()
    if re.fullmatch(r"[A-Za-z0-9_-]{8}", text):
        return text.lower()
    return hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()[:8]


def _session_uid(source: str, raw_session_id: Any, explicit_uid: Any = None) -> str:
    if explicit_uid not in (None, ""):
        uid_s = str(explicit_uid).strip()
        if re.fullmatch(r"[A-Za-z0-9:._-]{8,64}", uid_s) and "/" not in uid_s and "\\" not in uid_s and "@" not in uid_s:
            return uid_s
    raw_s = str(raw_session_id or "").strip() or "anon"
    digest = hashlib.sha256(f"{source}|{raw_s}".encode("utf-8", errors="replace")).hexdigest()[:20]
    return f"sw:{digest}"


def _sanitize_goal_slug(raw_goal: Any) -> str | None:
    text = str(raw_goal or "").strip().strip("`'\"/\\")
    if not text or text.startswith("_"):
        return None
    if _SAFE_GOAL_RE.fullmatch(text):
        return text
    return None


def _sanitize_repo_name(raw_repo: Any, *, cwd: Any = None) -> str | None:
    text = str(raw_repo or "").strip()
    if text:
        text = re.sub(r"^https?://[^/]+/", "", text)
        text = re.sub(r"\.git$", "", text).strip("/")
        parts = [p for p in text.split("/") if p and p not in {"Users", "home", "Volumes", "private", "tmp", "Development", "worktrees"}]
        if len(parts) >= 2:
            cand = f"{parts[-2]}/{parts[-1]}"
            if _SAFE_SLUG_RE.fullmatch(cand):
                return cand
        elif len(parts) == 1 and _SAFE_GOAL_RE.fullmatch(parts[0]):
            return parts[0]
    cwd_text = str(cwd or "").strip()
    if cwd_text and not _CWD_GOAL_RE.search(cwd_text):
        norm = cwd_text.replace("\\", "/").rstrip("/")
        leaf = norm.rsplit("/", 1)[-1] if "/" in norm else norm
        if leaf and leaf not in {"Users", "home", "Development", "tmp", "private", "worktrees"} and _SAFE_GOAL_RE.fullmatch(leaf):
            return leaf
    return None


def _sanitize_branch_name(raw_branch: Any) -> str | None:
    text = str(raw_branch or "").strip()
    if not text or "/" in text and text.startswith(("/Users/", "/home/", "/Volumes/", "/private/")):
        return None
    text = text.removeprefix("refs/heads/")
    if _SAFE_SLUG_RE.fullmatch(text) and "@" not in text:
        return text[:96]
    return None


def _sanitize_model_id(raw_model: Any) -> str | None:
    text = str(raw_model or "").strip()
    if not text:
        return None
    if "/" in text:
        text = text.rsplit("/", 1)[-1]
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:@-]{0,63}", text):
        return text.lower()
    return None


def _sanitize_summary(raw_summary: Any, *, fallback: str = "") -> str | None:
    text = str(raw_summary if raw_summary is not None else fallback).strip()
    if not text:
        return None
    first_line = next((ln.strip() for ln in text.splitlines() if ln.strip()), "")
    if not first_line:
        return None
    cleaned = _UNIX_ABS_PATH_RE.sub("", first_line)
    cleaned = _WIN_ABS_PATH_RE.sub("", cleaned)
    cleaned = _EMAIL_FULL_RE.sub("", cleaned)
    cleaned = redact(cleaned)
    cleaned = cleaned.replace("<REDACTED>", "").replace("~/", "")
    cleaned = re.sub(r"\b(?:python3?|SKILL\.md|session_id)\b", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" -–—:;|,`'\"")
    if not cleaned:
        return None
    if len(cleaned) > 80:
        cleaned = cleaned[:79].rstrip() + "…"
    return cleaned


def _normalize_skill_list(raw_skills: Any) -> list[str]:
    items: Sequence[Any]
    if isinstance(raw_skills, str):
        raw_str = raw_skills.strip()
        if raw_str.startswith("["):
            try:
                parsed = json.loads(raw_str)
                items = parsed if isinstance(parsed, list) else [raw_str]
            except ValueError:
                items = [s.strip() for s in raw_str.split(",")]
        else:
            items = [s.strip() for s in raw_str.split(",") if s.strip()]
    elif isinstance(raw_skills, Iterable) and not isinstance(raw_skills, (bytes, Mapping)):
        items = list(raw_skills)
    else:
        items = []

    out: set[str] = set()
    for item in items:
        norm = canonical_skill(item)
        if not norm or "/" in norm or "\\" in norm or "@" in norm:
            continue
        if re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}", norm):
            out.add(norm)
    return sorted(out)


def _normalize_slow_failed_scripts(raw_scripts: Any) -> list[dict[str, Any]]:
    items: Sequence[Any]
    if isinstance(raw_scripts, str):
        raw_str = raw_scripts.strip()
        if not raw_str:
            return []
        try:
            parsed = json.loads(raw_str)
            items = parsed if isinstance(parsed, list) else []
        except ValueError:
            return []
    elif isinstance(raw_scripts, Iterable) and not isinstance(raw_scripts, (bytes, Mapping)):
        items = list(raw_scripts)
    else:
        return []

    sanitized: list[dict[str, Any]] = []
    seen: set[tuple[str, str, int | None]] = set()
    for entry in items:
        if isinstance(entry, str):
            name = Path(entry.replace("\\", "/")).name
            if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", name):
                key = ("", name, None)
                if key not in seen:
                    seen.add(key)
                    sanitized.append({"script": name, "skill": None, "exit_code": None, "duration_ms": None})
            continue
        if not isinstance(entry, Mapping):
            continue
        raw_path = str(entry.get("script") or entry.get("script_path") or "").replace("\\", "/")
        name = Path(raw_path).name if raw_path else ""
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", name):
            continue
        sk = canonical_skill(entry.get("skill"))
        if sk and not re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}", sk):
            sk = None
        exit_raw = entry.get("exit_code")
        exit_code = int(exit_raw) if isinstance(exit_raw, (int, float)) and not isinstance(exit_raw, bool) else None
        dur_raw = entry.get("duration_ms")
        dur_ms = max(0, int(dur_raw)) if isinstance(dur_raw, (int, float)) and not isinstance(dur_raw, bool) else None
        key = (sk or "", name, exit_code)
        if key in seen:
            continue
        seen.add(key)
        sanitized.append({
            "script": name,
            "skill": sk,
            "exit_code": exit_code,
            "duration_ms": dur_ms,
        })
    return sanitized[:12]


def _normalize_role(
    raw_role: Any,
    *,
    skills: Sequence[str] = (),
    model_id: str | None = None,
    summary: str | None = None,
) -> str:
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

    for sk in skills:
        if sk in _SKILL_TO_DEFAULT_ROLE:
            return _SKILL_TO_DEFAULT_ROLE[sk]

    mod = (model_id or "").lower()
    if "decision" in mod:
        return "m3"
    if "steering" in mod:
        return "m1"
    if "review" in mod:
        return "reviewer"
    if "designer" in mod:
        return "designer"
    if "flash" in mod:
        return "explorer"

    sum_low = (summary or "").lower()
    if "review" in sum_low and "pr" in sum_low:
        return "reviewer"
    return "writer"


def _extract_pr_number(raw_pr: Any) -> int | None:
    if isinstance(raw_pr, bool) or raw_pr is None or raw_pr == "":
        return None
    if isinstance(raw_pr, (int, float)):
        val = int(raw_pr)
        return val if 0 < val <= 9_999_999 else None
    match = _PR_DIGITS_RE.search(str(raw_pr).strip())
    if match:
        val = int(match.group(1))
        return val if 0 < val <= 9_999_999 else None
    return None


def _discover_known_goals(handoff_roots: Sequence[Path]) -> set[str]:
    known: set[str] = set()
    for root in handoff_roots:
        if not root or not root.is_dir():
            continue
        try:
            for child in root.iterdir():
                if child.is_dir() and not child.name.startswith("_"):
                    slug = _sanitize_goal_slug(child.name)
                    if slug:
                        known.add(slug)
        except OSError:
            continue
    return known


def _infer_goal_id(
    *,
    explicit_goal: Any = None,
    cwd: Any = None,
    summary: Any = None,
    branch: Any = None,
    known_goals: set[str] | None = None,
) -> str | None:
    direct = _sanitize_goal_slug(explicit_goal)
    if direct:
        return direct
    cwd_text = str(cwd or "")
    if cwd_text:
        m = _CWD_GOAL_RE.search(cwd_text)
        if m:
            slug = _sanitize_goal_slug(m.group(1))
            if slug:
                return slug
    sum_text = str(summary or "")
    if sum_text:
        m = _SUMMARY_GOAL_RE.search(sum_text)
        if m:
            slug = _sanitize_goal_slug(m.group(1))
            if slug:
                return slug
    if known_goals:
        br_text = str(branch or "").strip().removeprefix("refs/heads/")
        if br_text in known_goals:
            return br_text
        m = _BRANCH_GOAL_RE.match(br_text)
        if m and m.group(1) in known_goals:
            return m.group(1)
    return None


def _normalize_single_record(record: Mapping[str, Any]) -> dict[str, Any] | None:
    raw_source = str(record.get("source") or "copilot_cli").strip()
    source = raw_source if re.fullmatch(r"[A-Za-z0-9._:-]{1,32}", raw_source) else "copilot_cli"

    raw_sess_id = record.get("session_id") or record.get("id") or record.get("session_id_short")
    if not raw_sess_id and not record.get("session_uid"):
        return None

    started_at = iso_timestamp(record.get("started_at") or record.get("created_at") or record.get("ts"))
    ended_at = iso_timestamp(record.get("ended_at") or record.get("updated_at") or started_at)
    if started_at is None and ended_at is None:
        return None
    if started_at is None:
        started_at = ended_at
    if ended_at is None:
        ended_at = started_at

    explicit_dur = record.get("duration_sec")
    if explicit_dur is not None and explicit_dur != "":
        duration_sec = _nonneg_float(explicit_dur, default=0.0)
    else:
        s_dt = _parse_dt(started_at)
        e_dt = _parse_dt(ended_at)
        duration_sec = round(max(0.0, (e_dt - s_dt).total_seconds()), 2) if (s_dt and e_dt) else 0.0

    session_uid = _session_uid(source, raw_sess_id or ended_at, record.get("session_uid"))
    short_raw = record.get("session_id_short")
    session_id_short = (
        str(short_raw).lower()
        if isinstance(short_raw, str) and re.fullmatch(r"[0-9a-z]{8}", short_raw.lower())
        else _short_session_id(raw_sess_id or session_uid)
    )

    goal_id = _infer_goal_id(
        explicit_goal=record.get("goal_id"),
        cwd=record.get("cwd"),
        summary=record.get("summary") or record.get("summary_label"),
        branch=record.get("branch_name") or record.get("branch"),
    )
    repo_name = _sanitize_repo_name(record.get("repo_name") or record.get("repository"), cwd=record.get("cwd"))
    branch_name = _sanitize_branch_name(record.get("branch_name") or record.get("branch"))
    skills = _normalize_skill_list(record.get("skills_json") if record.get("skills_json") is not None else record.get("skills"))
    model_id = _sanitize_model_id(record.get("model_id") or record.get("model"))
    summary_label = _sanitize_summary(
        record.get("summary_label") if record.get("summary_label") is not None else record.get("summary"),
        fallback=goal_id or branch_name or repo_name or "",
    )
    role_key = _normalize_role(
        record.get("role_key") or record.get("role"),
        skills=skills,
        model_id=model_id,
        summary=summary_label,
    )

    turn_count = _nonneg_int(record.get("turn_count"), default=0)
    total_tokens = _nonneg_int(record.get("total_tokens"), default=0)
    code_edit_calls = _nonneg_int(record.get("code_edit_calls"), default=0)
    verify_script_calls = _nonneg_int(record.get("verify_script_calls"), default=0)
    spin_rework_calls = _nonneg_int(record.get("spin_rework_calls"), default=0)
    search_read_calls = _nonneg_int(record.get("search_read_calls"), default=0)
    if search_read_calls == 0 and turn_count > code_edit_calls:
        search_read_calls = max(
            0,
            turn_count - code_edit_calls - verify_script_calls - spin_rework_calls,
        )

    files_changed_count = _nonneg_int(record.get("files_changed_count"), default=0)
    commits_count = _nonneg_int(record.get("commits_count"), default=0)
    pr_number = _extract_pr_number(record.get("pr_number"))
    slow_failed = _normalize_slow_failed_scripts(
        record.get("slow_or_failed_scripts_json")
        if record.get("slow_or_failed_scripts_json") is not None
        else record.get("slow_or_failed_scripts")
    )

    return {
        "session_uid": session_uid,
        "source": source,
        "session_id_short": session_id_short,
        "goal_id": goal_id,
        "repo_name": repo_name,
        "branch_name": branch_name,
        "role_key": role_key,
        "model_id": model_id,
        "summary_label": summary_label,
        "started_at": started_at,
        "ended_at": ended_at,
        "duration_sec": duration_sec,
        "turn_count": turn_count,
        "total_tokens": total_tokens,
        "skills_json": json.dumps(skills, ensure_ascii=False),
        "search_read_calls": search_read_calls,
        "code_edit_calls": code_edit_calls,
        "verify_script_calls": verify_script_calls,
        "spin_rework_calls": spin_rework_calls,
        "files_changed_count": files_changed_count,
        "commits_count": commits_count,
        "pr_number": pr_number,
        "slow_or_failed_scripts_json": json.dumps(slow_failed, ensure_ascii=False),
    }


def _transform_records(records: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    by_uid: dict[str, dict[str, Any]] = {}
    stamps: list[str] = []
    for item in records:
        if not isinstance(item, Mapping):
            continue
        row = _normalize_single_record(item)
        if row is None:
            continue
        by_uid[row["session_uid"]] = row
        end_ts = row.get("ended_at") or row.get("started_at")
        if end_ts:
            stamps.append(str(end_ts))

    ordered = sorted(
        by_uid.values(),
        key=lambda r: (str(r.get("ended_at") or r.get("started_at") or ""), r["session_uid"]),
    )
    return {
        "sessions": ordered,
        "source_as_of": max(stamps) if stamps else None,
    }


def _write_db(db_path: Path, normalized: Mapping[str, Any]) -> int:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = db_path.with_name(f".{db_path.name}.tmp.{os.getpid()}")
    if tmp_path.exists():
        tmp_path.unlink()
    conn = sqlite3.connect(tmp_path)
    try:
        conn.execute(_SESSION_WORK_DDL)
        rows = [r for r in normalized.get("sessions", []) if isinstance(r, Mapping)]
        if rows:
            conn.executemany(
                f"INSERT OR REPLACE INTO session_work ({', '.join(_SESSION_WORK_COLS)}) "
                f"VALUES ({', '.join('?' for _ in _SESSION_WORK_COLS)})",
                [tuple(row.get(col) for col in _SESSION_WORK_COLS) for row in rows],
            )
        conn.commit()
        count = len(rows)
    finally:
        conn.close()
    tmp_path.replace(db_path)
    return count


def normalize_records(
    records: Iterable[Mapping[str, Any]],
    *,
    db_path: Path | None = None,
) -> dict[str, Any]:
    """Normalize bounded session-work records and atomically materialize clean/session_work.db."""
    normalized = _transform_records(records)
    _write_db(Path(db_path) if db_path is not None else config.clean_path(SOURCE), normalized)
    return normalized


def normalize(*, db_path: Path | None = None) -> int:
    """Rebuild clean/session_work.db from persisted L1 raw shards."""
    normalized = normalize_records(read_raw(SOURCE), db_path=db_path)
    return len(normalized["sessions"])


def _metadata_skills(text: str | None) -> set[str]:
    if not isinstance(text, str) or not text:
        return set()
    found: set[str] = set()
    for pat in _SKILL_PATTERNS:
        for m in pat.finditer(text):
            sk = canonical_skill(m.group(1))
            if sk and re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}", sk):
                found.add(sk)
    return found


def _load_clean_enrichment(
    *,
    copilot_clean_db: Path | None,
    warehouse_db: Path | None,
) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    """Read optional per-session reference_hit & script_call aggregates read-only."""
    refs_by_sess: dict[str, dict[str, Any]] = {}
    scripts_by_sess: dict[str, dict[str, Any]] = {}

    candidate_dbs: list[tuple[Path, str, str]] = []
    if warehouse_db is not None and warehouse_db.is_file():
        candidate_dbs.append((warehouse_db, "reference_hits", "script_call"))
    if copilot_clean_db is not None and copilot_clean_db.is_file():
        candidate_dbs.append((copilot_clean_db, "reference_hit", "script_call"))

    for db_file, ref_table, script_table in candidate_dbs:
        try:
            with contextlib.closing(
                sqlite3.connect(f"file:{db_file.resolve()}?mode=ro&immutable=1", uri=True)
            ) as conn:
                tables = {
                    str(r[0])
                    for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
                }
                if ref_table in tables and not refs_by_sess:
                    cols = {r[1] for r in conn.execute(f"PRAGMA table_info({ref_table})")}
                    if {"session_id", "hit_uid"}.issubset(cols):
                        sk_col = "skill" if "skill" in cols else "NULL"
                        for sid, cnt, sk_csv in conn.execute(
                            f"SELECT session_id, COUNT(DISTINCT hit_uid), GROUP_CONCAT(DISTINCT {sk_col}) "
                            f"FROM {ref_table} WHERE session_id IS NOT NULL GROUP BY session_id"
                        ):
                            sid_s = str(sid)
                            refs_by_sess[sid_s] = {
                                "ref_hits": int(cnt or 0),
                                "skills": _normalize_skill_list(sk_csv or ""),
                            }
                if script_table in tables and not scripts_by_sess:
                    cols = {r[1] for r in conn.execute(f"PRAGMA table_info({script_table})")}
                    if {"session_id", "script_path"}.issubset(cols):
                        sk_col = "skill" if "skill" in cols else "NULL"
                        ex_col = "exit_code" if "exit_code" in cols else "NULL"
                        du_col = "duration_ms" if "duration_ms" in cols else "NULL"
                        for sid, sk, spath, ex_code, dur_ms in conn.execute(
                            f"SELECT session_id, {sk_col}, script_path, {ex_col}, {du_col} "
                            f"FROM {script_table} WHERE session_id IS NOT NULL"
                        ):
                            sid_s = str(sid)
                            bucket = scripts_by_sess.setdefault(
                                sid_s,
                                {"verify_calls": 0, "failed_calls": 0, "skills": set(), "slow_failed": []},
                            )
                            bucket["verify_calls"] += 1
                            norm_sk = canonical_skill(sk)
                            if norm_sk and re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}", norm_sk):
                                bucket["skills"].add(norm_sk)
                            ex_i = int(ex_code) if ex_code is not None else None
                            du_i = int(dur_ms) if dur_ms is not None else None
                            if (ex_i is not None and ex_i != 0) or (du_i is not None and du_i >= 5000):
                                if ex_i is not None and ex_i != 0:
                                    bucket["failed_calls"] += 1
                                bucket["slow_failed"].append({
                                    "script": Path(str(spath).replace("\\", "/")).name,
                                    "skill": norm_sk,
                                    "exit_code": ex_i,
                                    "duration_ms": du_i,
                                })
        except (OSError, sqlite3.Error):
            continue
    return refs_by_sess, scripts_by_sess


def collect(
    *,
    copilot_db: Path | None = None,
    handoff_root: Path | Sequence[Path] | None = None,
    warehouse_db: Path | None = None,
    copilot_clean_db: Path | None = None,
    db_path: Path | None = None,
    now: datetime | None = None,
    window_days: int = 30,
) -> int:
    """Collect privacy-safe session work summaries from Copilot session-store.db."""
    eff_copilot_db = Path(copilot_db) if copilot_db is not None else config.COPILOT_SESSION_DB
    if not eff_copilot_db.is_file():
        return 0

    if handoff_root is None:
        handoff_roots: tuple[Path, ...] = tuple(config.GTT_HANDOFF_ROOTS)
    elif isinstance(handoff_root, Path):
        handoff_roots = (handoff_root,)
    else:
        handoff_roots = tuple(Path(p) for p in handoff_root)

    known_goals = _discover_known_goals(handoff_roots)

    eff_now = _parse_dt(now) or datetime.now(timezone.utc)  # noqa: UP017
    cutoff_day = (eff_now.date() - timedelta(days=max(1, int(window_days)))).isoformat()

    is_pytest = bool(os.environ.get("PYTEST_CURRENT_TEST"))
    eff_wh = warehouse_db if warehouse_db is not None else (None if is_pytest else config.WAREHOUSE_DB)
    eff_cp_clean = (
        copilot_clean_db
        if copilot_clean_db is not None
        else (None if is_pytest else config.clean_path("copilot_cli"))
    )
    refs_by_sess, scripts_by_sess = _load_clean_enrichment(
        copilot_clean_db=eff_cp_clean,
        warehouse_db=eff_wh,
    )

    sessions_raw: dict[str, dict[str, Any]] = {}
    try:
        uri = f"file:{eff_copilot_db.resolve()}?mode=ro&immutable=1"
        with contextlib.closing(sqlite3.connect(uri, uri=True)) as conn:
            tables = {
                str(r[0])
                for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
            }
            if "sessions" not in tables:
                return 0
            sess_cols = {r[1] for r in conn.execute("PRAGMA table_info(sessions)")}
            if "id" not in sess_cols:
                return 0

            sel_cols = [
                "id",
                "cwd" if "cwd" in sess_cols else "NULL AS cwd",
                "repository" if "repository" in sess_cols else "NULL AS repository",
                "branch" if "branch" in sess_cols else "NULL AS branch",
                "summary" if "summary" in sess_cols else "NULL AS summary",
                "created_at" if "created_at" in sess_cols else "NULL AS created_at",
                "updated_at" if "updated_at" in sess_cols else "NULL AS updated_at",
            ]
            stamp_expr = (
                "COALESCE(updated_at, created_at)"
                if {"updated_at", "created_at"}.issubset(sess_cols)
                else "updated_at"
                if "updated_at" in sess_cols
                else "created_at"
                if "created_at" in sess_cols
                else None
            )
            where_sql = f"WHERE substr({stamp_expr}, 1, 10) >= ?" if stamp_expr else ""
            params: tuple[Any, ...] = (cutoff_day,) if stamp_expr else ()
            for sid, cwd, repo, branch, summary, created_at, updated_at in conn.execute(
                f"SELECT {', '.join(sel_cols)} FROM sessions {where_sql} LIMIT 20000",
                params,
            ):
                if not sid:
                    continue
                sid_s = str(sid)
                goal_id = _infer_goal_id(
                    cwd=cwd,
                    summary=summary,
                    branch=branch,
                    known_goals=known_goals,
                )
                sessions_raw[sid_s] = {
                    "session_id": sid_s,
                    "cwd": cwd,
                    "repo_name": _sanitize_repo_name(repo, cwd=cwd),
                    "branch_name": _sanitize_branch_name(branch),
                    "goal_id": goal_id,
                    "summary": summary,
                    "started_at": created_at,
                    "ended_at": updated_at or created_at,
                    "turn_count": 0,
                    "total_tokens": 0,
                    "model_id": None,
                    "skills": set(_metadata_skills(str(summary or ""))),
                    "search_read_calls": 0,
                    "code_edit_calls": 0,
                    "verify_script_calls": 0,
                    "spin_rework_calls": 0,
                    "files_changed_count": 0,
                    "commits_count": 0,
                    "pr_number": None,
                    "slow_or_failed_scripts": [],
                }

            if not sessions_raw:
                return 0

            # 1. turns: turn_count + skill metadata + timestamp bounds (never persist user/assistant text!)
            if "turns" in tables:
                t_cols = {r[1] for r in conn.execute("PRAGMA table_info(turns)")}
                if "session_id" in t_cols:
                    ts_col = "timestamp" if "timestamp" in t_cols else "NULL"
                    um_col = "user_message" if "user_message" in t_cols else "NULL"
                    ar_col = "assistant_response" if "assistant_response" in t_cols else "NULL"
                    t_where = "WHERE substr(timestamp, 1, 10) >= ?" if "timestamp" in t_cols else ""
                    t_params = (cutoff_day,) if "timestamp" in t_cols else ()
                    try:
                        for sid, ts_val, um_val, ar_val in conn.execute(
                            f"SELECT session_id, {ts_col}, {um_col}, {ar_col} FROM turns {t_where} LIMIT 200000",
                            t_params,
                        ):
                            rec = sessions_raw.get(str(sid))
                            if rec is None:
                                continue
                            rec["turn_count"] += 1
                            if isinstance(um_val, str):
                                rec["skills"].update(_metadata_skills(um_val))
                            if isinstance(ar_val, str):
                                rec["skills"].update(_metadata_skills(ar_val))
                            if ts_val:
                                if not rec["started_at"] or str(ts_val) < str(rec["started_at"]):
                                    rec["started_at"] = ts_val
                                if not rec["ended_at"] or str(ts_val) > str(rec["ended_at"]):
                                    rec["ended_at"] = ts_val
                    except sqlite3.Error:
                        pass

            # 2. session_files: code_edit_calls, files_changed_count, read calls, skill paths
            if "session_files" in tables:
                sf_cols = {r[1] for r in conn.execute("PRAGMA table_info(session_files)")}
                if {"session_id", "file_path"}.issubset(sf_cols):
                    tool_col = "tool_name" if "tool_name" in sf_cols else "NULL"
                    sf_where = "WHERE substr(first_seen_at, 1, 10) >= ?" if "first_seen_at" in sf_cols else ""
                    sf_params = (cutoff_day,) if "first_seen_at" in sf_cols else ()
                    edited_paths: dict[str, set[str]] = {}
                    try:
                        for sid, fpath, tname in conn.execute(
                            f"SELECT session_id, file_path, {tool_col} FROM session_files {sf_where} LIMIT 200000",
                            sf_params,
                        ):
                            rec = sessions_raw.get(str(sid))
                            if rec is None or not fpath:
                                continue
                            fpath_s = str(fpath)
                            rec["skills"].update(_metadata_skills(fpath_s))
                            tool_low = str(tname or "edit").strip().lower()
                            if tool_low in _READ_TOOLS:
                                rec["search_read_calls"] += 1
                            elif tool_low in _EDIT_TOOLS or not tool_low:
                                rec["code_edit_calls"] += 1
                                edited_paths.setdefault(str(sid), set()).add(fpath_s)
                        for sid_s, pset in edited_paths.items():
                            sessions_raw[sid_s]["files_changed_count"] = len(pset)
                    except sqlite3.Error:
                        pass

            # 3. session_refs: pr_number & commits_count
            if "session_refs" in tables:
                sr_cols = {r[1] for r in conn.execute("PRAGMA table_info(session_refs)")}
                if {"session_id", "ref_type", "ref_value"}.issubset(sr_cols):
                    commits_by_sess: dict[str, set[str]] = {}
                    try:
                        for sid, rtype, rval in conn.execute(
                            "SELECT session_id, ref_type, ref_value FROM session_refs LIMIT 100000"
                        ):
                            rec = sessions_raw.get(str(sid))
                            if rec is None or not rval:
                                continue
                            rt = str(rtype or "").strip().lower()
                            if rt == "commit":
                                commits_by_sess.setdefault(str(sid), set()).add(str(rval))
                            elif rt == "pr":
                                pr_num = _extract_pr_number(rval)
                                if pr_num is not None:
                                    rec["pr_number"] = pr_num
                        for sid_s, cset in commits_by_sess.items():
                            sessions_raw[sid_s]["commits_count"] = len(cset)
                    except sqlite3.Error:
                        pass

            # 4. assistant_usage_events: total_tokens & dominant model_id
            if "assistant_usage_events" in tables:
                au_cols = {r[1] for r in conn.execute("PRAGMA table_info(assistant_usage_events)")}
                if "session_id" in au_cols:
                    in_c = "COALESCE(input_tokens, 0)" if "input_tokens" in au_cols else "0"
                    out_c = "COALESCE(output_tokens, 0)" if "output_tokens" in au_cols else "0"
                    cr_c = "COALESCE(cache_read_tokens, 0)" if "cache_read_tokens" in au_cols else "0"
                    cw_c = "COALESCE(cache_write_tokens, 0)" if "cache_write_tokens" in au_cols else "0"
                    mod_c = (
                        "COALESCE(NULLIF(model, ''), copilot_usage_model)"
                        if {"model", "copilot_usage_model"}.issubset(au_cols)
                        else "model"
                        if "model" in au_cols
                        else "NULL"
                    )
                    au_where = "WHERE substr(created_at, 1, 10) >= ?" if "created_at" in au_cols else ""
                    au_params = (cutoff_day,) if "created_at" in au_cols else ()
                    model_tokens: dict[str, dict[str, int]] = {}
                    try:
                        for sid, mod_val, tok_sum in conn.execute(
                            f"SELECT session_id, {mod_c}, SUM({in_c} + {out_c} + {cr_c} + {cw_c}) "
                            f"FROM assistant_usage_events {au_where} GROUP BY session_id, {mod_c}",
                            au_params,
                        ):
                            rec = sessions_raw.get(str(sid))
                            if rec is None:
                                continue
                            tok_i = max(0, int(tok_sum or 0))
                            rec["total_tokens"] += tok_i
                            clean_mod = _sanitize_model_id(mod_val)
                            if clean_mod:
                                bucket = model_tokens.setdefault(str(sid), {})
                                bucket[clean_mod] = bucket.get(clean_mod, 0) + max(1, tok_i)
                        for sid_s, mbucket in model_tokens.items():
                            best_mod = max(mbucket.items(), key=lambda kv: (kv[1], kv[0]))[0]
                            sessions_raw[sid_s]["model_id"] = best_mod
                    except sqlite3.Error:
                        pass

            # 5. forge_trajectory_events (optional local command exit_code metadata — never persist output/cmd!)
            if "forge_trajectory_events" in tables:
                ft_cols = {r[1] for r in conn.execute("PRAGMA table_info(forge_trajectory_events)")}
                if {"session_id", "exit_code"}.issubset(ft_cols):
                    try:
                        for sid, total_exec, failed_exec in conn.execute(
                            "SELECT session_id, COUNT(*), "
                            "SUM(CASE WHEN exit_code IS NOT NULL AND exit_code != 0 THEN 1 ELSE 0 END) "
                            "FROM forge_trajectory_events WHERE exit_code IS NOT NULL GROUP BY session_id"
                        ):
                            rec = sessions_raw.get(str(sid))
                            if rec is None:
                                continue
                            rec["verify_script_calls"] = max(rec["verify_script_calls"], int(total_exec or 0))
                            rec["spin_rework_calls"] = max(rec["spin_rework_calls"], int(failed_exec or 0))
                    except sqlite3.Error:
                        pass
    except (OSError, sqlite3.Error):
        return 0

    # Merge clean enrichment (reference_hits & script_call) and scrub transient paths before L1/L2 persistence
    sanitized_batch: list[dict[str, Any]] = []
    for sid_s, raw_rec in sessions_raw.items():
        ref_info = refs_by_sess.get(sid_s)
        if ref_info:
            raw_rec["search_read_calls"] += int(ref_info.get("ref_hits") or 0)
            raw_rec["skills"].update(ref_info.get("skills") or [])
        sc_info = scripts_by_sess.get(sid_s)
        if sc_info:
            raw_rec["verify_script_calls"] = max(raw_rec["verify_script_calls"], int(sc_info.get("verify_calls") or 0))
            raw_rec["spin_rework_calls"] = max(raw_rec["spin_rework_calls"], int(sc_info.get("failed_calls") or 0))
            raw_rec["skills"].update(sc_info.get("skills") or set())
            raw_rec["slow_or_failed_scripts"].extend(sc_info.get("slow_failed") or [])

        # Drop raw cwd / raw session_id / raw summary before any raw JSONL persistence!
        pre_norm = _normalize_single_record({
            "source": "copilot_cli",
            "session_id": sid_s,
            "goal_id": raw_rec["goal_id"],
            "repo_name": raw_rec["repo_name"],
            "branch_name": raw_rec["branch_name"],
            "model_id": raw_rec["model_id"],
            "summary": raw_rec["summary"],
            "started_at": raw_rec["started_at"],
            "ended_at": raw_rec["ended_at"],
            "turn_count": raw_rec["turn_count"],
            "total_tokens": raw_rec["total_tokens"],
            "skills": sorted(raw_rec["skills"]),
            "search_read_calls": raw_rec["search_read_calls"],
            "code_edit_calls": raw_rec["code_edit_calls"],
            "verify_script_calls": raw_rec["verify_script_calls"],
            "spin_rework_calls": raw_rec["spin_rework_calls"],
            "files_changed_count": raw_rec["files_changed_count"],
            "commits_count": raw_rec["commits_count"],
            "pr_number": raw_rec["pr_number"],
            "slow_or_failed_scripts": raw_rec["slow_or_failed_scripts"],
        })
        if pre_norm is not None:
            sanitized_batch.append(pre_norm)

    if not sanitized_batch:
        return 0

    # Deduplicate against existing raw records (append only changed or new session digests)
    existing_rows = list(read_raw(SOURCE))
    existing_digests: dict[str, str] = {}
    merged_by_uid: dict[str, dict[str, Any]] = {}
    for old_row in existing_rows:
        if not isinstance(old_row, Mapping):
            continue
        norm_old = _normalize_single_record(old_row)
        if norm_old is not None:
            uid = norm_old["session_uid"]
            merged_by_uid[uid] = norm_old
            existing_digests[uid] = json.dumps(norm_old, sort_keys=True, ensure_ascii=False)

    fresh: list[dict[str, Any]] = []
    for row in sanitized_batch:
        uid = row["session_uid"]
        digest_str = json.dumps(row, sort_keys=True, ensure_ascii=False)
        merged_by_uid[uid] = row
        if existing_digests.get(uid) != digest_str:
            fresh.append(row)

    if fresh:
        write_raw(SOURCE, fresh)

    normalize_records(merged_by_uid.values(), db_path=db_path)
    return len(fresh)
