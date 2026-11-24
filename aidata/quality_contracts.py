"""Contracts and pure transforms for skill-quality telemetry.

This module is deliberately storage- and provider-free. It owns the fixed
registry, closed vocabularies, privacy boundary, and deterministic transforms
shared by L1/L2, L3, the offline judge, and L5 snapshots.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from collections import Counter
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from statistics import median
from typing import Any

REGISTRY_VERSION = "skill-registry-v1"
CLASSIFIER_VERSION = "correction-classifier-v1"
INVOCATIONIZER_VERSION = "skill-invocationizer-v1"
RUBRIC_VERSION = "skill-quality-rubric-v1"
RUNNER_VERSION = "offline-judge-runner-v1"
REDACTION_VERSION = "quality-redaction-v1"
QUALITY_METRIC_MANIFEST = {
    "skill_quality_behavior": {"layer": "L1-L5", "window": "rolling_30d", "estimated": False},
    "skill_quality_judge": {"layer": "L1-L5", "window": "rolling_30d", "estimated": False},
}
ROLLING_WINDOW_DAYS = 30
CORRECTION_WINDOW_SEC = 30 * 60
INVOCATION_GAP_SEC = 30 * 60
ACTIVE_GAP_CAP_SEC = 900
JUDGE_PASS_THRESHOLD = 4.0
JUDGE_SCORE_MIN = 1.0
JUDGE_SCORE_MAX = 5.0
JUDGE_COMPONENT_MIN = 0.0
JUDGE_COMPONENT_MAX = 3.0
MAX_PREVIEW_CHARS = 500
MAX_JUDGE_OUTPUT_BYTES = 64 * 1024

# Twenty-four user skill packages plus the repository-local aidash-content
# package. Keep this explicit: filesystem discovery is evidence, not the
# denominator used by the product contract.
ACTIVE_SKILLS: tuple[str, ...] = (
    "aidash-content",
    "aidash-metrics",
    "asset-screener",
    "code-review",
    "codebase-design",
    "deep-research",
    "design-studio",
    "howto",
    "ios-architecture-testing",
    "ios-concurrency-swiftui",
    "ios-debugging-performance",
    "issue-brief",
    "knowledge-digest",
    "linear-board",
    "m2-dispatcher",
    "my-designer",
    "nas-smart-home",
    "personal-m2-assistant",
    "portfolio-advisor",
    "retro-loop",
    "skill-contract",
    "story-craft",
    "team-lead",
    "workflow-hub",
    "xcode-cli",
)
ALIASES: dict[str, str] = {
    "goal-task": "team-lead",
    "goal-target-task": "team-lead",
}
CORRECTION_CLASSES = frozenset({
    "none",
    "negative_feedback",
    "repair_request",
    "repeat_request",
    "reopen_edit",
})
COVERAGE_STATES = frozenset({"covered", "partial", "unknown", "missing"})
JUDGE_STATUSES = frozenset({"valid", "abstained", "timeout", "malformed", "duplicate"})
JUDGE_REASON_CODES = frozenset({
    "accepted",
    "missing_input",
    "redaction_uncertain",
    "injected_turn",
    "tool_only",
    "timeout",
    "malformed_json",
    "low_confidence_abstention",
    "duplicate_sample",
    "provider_error",
    "output_too_large",
    "judge_busy",
})
_HUMAN_KINDS = frozenset({"typed", "human", "user", "prompt"})
_NON_HUMAN_KINDS = frozenset({
    "agent_authored", "injected", "task_notification", "slash_command",
    "bash_io", "tool_result", "system", "unknown",
})
_NEGATIVE_RE = re.compile(
    r"\b(?:wrong|incorrect|not\s+(?:right|what|working)|doesn['’]?t\s+work|failed|failure|reject|rejected|"
    r"that['’]?s\s+wrong|you\s+missed|bug(?:gy)?)\b|(?:不对|错误|错了|不正确|失败|拒绝|没生效|有问题)",
    re.IGNORECASE,
)
_REPAIR_RE = re.compile(
    r"\b(?:fix|repair|redo|retry|revert|rollback|undo|correct|continue|finish|complete|try\s+again|"
    r"change\s+it|update\s+it)\b|(?:修复|重做|重试|回滚|撤销|继续|补完|改一下|再来一次)",
    re.IGNORECASE,
)
_REOPEN_RE = re.compile(
    r"\b(?:edit|modify|patch|write|apply|reopen|open\s+again)\b|(?:编辑|修改|补丁|重新打开)",
    re.IGNORECASE,
)


def _timestamp(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        stamp = value
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        try:
            stamp = datetime.fromtimestamp(float(value), timezone.utc)
        except (OverflowError, OSError, ValueError):
            return None
    elif isinstance(value, str) and value.strip():
        try:
            stamp = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    return stamp.astimezone(timezone.utc)


def iso_timestamp(value: Any) -> str | None:
    stamp = _timestamp(value)
    return stamp.isoformat(timespec="seconds").replace("+00:00", "Z") if stamp else None


def canonical_skill(name: Any) -> str | None:
    raw = str(name or "").strip().lstrip("/").lower()
    if not raw:
        return None
    return ALIASES.get(raw, raw)


def registry_rows(observed_at: Any | None = None) -> list[dict[str, Any]]:
    stamp = iso_timestamp(observed_at) if observed_at is not None else None
    return [
        {
            "skill": skill,
            "registry_source": "active-skill-registry",
            "active": True,
            "registry_version": REGISTRY_VERSION,
            "observed_at": stamp,
        }
        for skill in ACTIVE_SKILLS
    ]


def _sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()


def _bounded_text(value: Any) -> str | None:
    if not isinstance(value, str) or not value:
        return None
    return value[:MAX_PREVIEW_CHARS]


def classify_correction(
    text: Any,
    *,
    source_kind: str = "typed",
    repeated_prompt: bool = False,
    edit_burst: bool = False,
) -> dict[str, Any]:
    """Classify one bounded in-memory human follow-up.

    The returned envelope contains no prompt text. A caller may pass a longer
    string, but only the bounded preview is inspected by lexical rules and the
    full value is represented by length and hash metadata.
    """
    raw = text if isinstance(text, str) else ""
    preview = _bounded_text(raw) or ""
    kind = str(source_kind or "unknown").strip().lower()
    correction_class = "none"
    confidence = 0.0
    if kind in _NON_HUMAN_KINDS or kind not in _HUMAN_KINDS:
        confidence = 1.0 if kind in _NON_HUMAN_KINDS else 0.0
    elif _NEGATIVE_RE.search(preview):
        correction_class, confidence = "negative_feedback", 0.98
    elif _REPAIR_RE.search(preview):
        correction_class, confidence = "repair_request", 0.94
    elif repeated_prompt:
        correction_class, confidence = "repeat_request", 0.86
    elif edit_burst and _REOPEN_RE.search(preview):
        correction_class, confidence = "reopen_edit", 0.82
    else:
        confidence = 0.72
    return {
        "correction_class": correction_class,
        "confidence": confidence,
        "classifier_version": CLASSIFIER_VERSION,
        "text_len": len(raw),
        "text_sha256": _sha256_text(raw),
    }


def _tool_names(value: Any) -> list[str]:
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError:
            return []
    if not isinstance(value, list):
        return []
    names: list[str] = []
    for item in value:
        if isinstance(item, str):
            names.append(item.strip().lower())
        elif isinstance(item, Mapping):
            name = item.get("name") or item.get("tool_name")
            if name:
                names.append(str(name).strip().lower())
    return [name for name in names if name]


def count_edit_tools(value: Any, explicit: Any = None) -> int:
    if explicit is not None:
        try:
            return max(0, int(explicit))
        except (TypeError, ValueError):
            pass
    edit_names = {"edit", "write", "multiedit", "apply_patch", "create", "edit_file", "write_file"}
    return sum(name in edit_names or "edit" in name or "patch" in name for name in _tool_names(value))


def _uid(*parts: Any) -> str:
    return hashlib.sha256("\0".join(str(part or "") for part in parts).encode()).hexdigest()


def prompt_signal(
    record: Mapping[str, Any],
    *,
    repeated_prompt: bool = False,
    edit_burst: bool = False,
) -> dict[str, Any] | None:
    """Convert a source prompt to a privacy-safe L2 signal."""
    source = str(record.get("source") or "unknown")
    session_id = str(record.get("session_id") or record.get("sessionId") or "")
    event_id = str(record.get("event_id") or record.get("turn_id") or record.get("prompt_id") or "")
    skill = canonical_skill(record.get("skill") or record.get("attribution_skill"))
    ts = iso_timestamp(record.get("timestamp") or record.get("ts"))
    text = record.get("text", record.get("prompt", record.get("user_message")))
    source_kind = str(record.get("source_kind") or record.get("kind") or "typed")
    if not session_id or not event_id or not skill or not ts or not isinstance(text, str):
        return None
    signal = classify_correction(
        text, source_kind=source_kind, repeated_prompt=repeated_prompt, edit_burst=edit_burst
    )
    return {
        "signal_uid": _uid(source, session_id, event_id, ts),
        "source": source,
        "session_id": session_id,
        "event_id": event_id,
        "skill": skill,
        "ts": ts,
        "source_kind": source_kind,
        "source_covered": bool(record.get("source_covered", True)),
        **signal,
    }


def activity_event(record: Mapping[str, Any]) -> dict[str, Any] | None:
    """Convert one source activity row to a privacy-safe L2 event."""
    source = str(record.get("source") or "unknown")
    session_id = str(record.get("session_id") or record.get("sessionId") or "")
    event_id = str(record.get("event_id") or record.get("turn_id") or record.get("turn_uuid") or "")
    skill = canonical_skill(record.get("skill") or record.get("attribution_skill"))
    ts = iso_timestamp(record.get("timestamp") or record.get("ts"))
    if not session_id or not event_id or not skill or not ts:
        return None
    event_type = str(record.get("event_type") or "assistant_activity")
    assistant = bool(record.get("assistant_activity", event_type in {"assistant", "assistant_activity", "activity"}))
    return {
        "event_uid": _uid(source, session_id, event_id, ts, event_type),
        "source": source,
        "session_id": session_id,
        "event_id": event_id,
        "skill": skill,
        "ts": ts,
        "event_type": event_type,
        "assistant_activity": assistant,
        "edit_tool_calls": count_edit_tools(record.get("tool_calls"), record.get("edit_tool_calls")),
        "assistant_turn": int(bool(record.get("assistant_turn", assistant))),
        "finish_reason": record.get("finish_reason"),
        "source_covered": bool(record.get("source_covered", True)),
    }


def normalize_behavior_records(records: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    """Normalize bounded source projections without retaining raw text."""
    prompt_rows: dict[str, dict[str, Any]] = {}
    activity_rows: dict[str, dict[str, Any]] = {}
    seen_prompt_hashes: set[tuple[str, str, str, str]] = set()
    for record in records:
        if not isinstance(record, Mapping):
            continue
        text = record.get("prompt", record.get("user_message", record.get("text")))
        if text is not None:
            session = str(record.get("session_id") or record.get("sessionId") or "")
            skill = canonical_skill(record.get("skill") or record.get("attribution_skill")) or ""
            source = str(record.get("source") or "unknown")
            repeated = isinstance(text, str) and (source, session, skill, _sha256_text(text)) in seen_prompt_hashes
            if isinstance(text, str):
                seen_prompt_hashes.add((source, session, skill, _sha256_text(text)))
            signal = prompt_signal(
                record,
                repeated_prompt=repeated,
                edit_burst=bool(record.get("edit_burst")),
            )
            if signal:
                prompt_rows[signal["signal_uid"]] = signal
        activity_markers = {
            "event_type", "assistant_activity", "assistant_turn", "tool_calls",
            "edit_tool_calls", "finish_reason",
        }
        if any(marker in record for marker in activity_markers):
            event = activity_event(record)
            if event:
                activity_rows[event["event_uid"]] = event
    timestamps = [r["ts"] for r in (*prompt_rows.values(), *activity_rows.values()) if r.get("ts")]
    return {
        "registry": registry_rows(max(timestamps) if timestamps else None),
        "prompt_signals": sorted(prompt_rows.values(), key=lambda row: (row["ts"], row["signal_uid"])),
        "activity_events": sorted(activity_rows.values(), key=lambda row: (row["ts"], row["event_uid"])),
        "source_as_of": max(timestamps) if timestamps else None,
    }


@dataclass(frozen=True)
class Invocation:
    invocation_id: str
    source: str
    session_id: str
    skill: str
    start_ts: str
    end_ts: str
    observation_end_ts: str
    assistant_turn_count: int
    edit_tool_calls: int
    active_duration_sec: int
    max_tokens: bool
    source_covered: bool
    prompt_linked: bool
    closed: bool
    eligible: bool
    correction_class: str | None
    correction_confidence: float | None
    correction_signal_uid: str | None
    invocationizer_version: str = INVOCATIONIZER_VERSION

    def as_dict(self) -> dict[str, Any]:
        return {
            "invocation_id": self.invocation_id,
            "source": self.source,
            "session_id": self.session_id,
            "skill": self.skill,
            "start_ts": self.start_ts,
            "end_ts": self.end_ts,
            "observation_end_ts": self.observation_end_ts,
            "assistant_turn_count": self.assistant_turn_count,
            "edit_tool_calls": self.edit_tool_calls,
            "normalized_edit_churn": self.edit_tool_calls / max(1, self.assistant_turn_count),
            "active_duration_sec": self.active_duration_sec,
            "max_tokens": self.max_tokens,
            "source_covered": self.source_covered,
            "prompt_linked": self.prompt_linked,
            "closed": self.closed,
            "eligible": self.eligible,
            "correction_class": self.correction_class,
            "correction_confidence": self.correction_confidence,
            "correction_signal_uid": self.correction_signal_uid,
            "invocationizer_version": self.invocationizer_version,
        }


def _active_duration(events: Sequence[Mapping[str, Any]]) -> int:
    stamps = [_timestamp(row.get("ts")) for row in events]
    valid = sorted(stamp for stamp in stamps if stamp is not None)
    return int(sum(min(max(0.0, (right - left).total_seconds()), ACTIVE_GAP_CAP_SEC)
                   for left, right in zip(valid, valid[1:])))


def _group_events(events: Sequence[Mapping[str, Any]]) -> list[list[dict[str, Any]]]:
    groups: list[list[dict[str, Any]]] = []
    for event in sorted(events, key=lambda row: (_timestamp(row.get("ts")) or datetime.max.replace(tzinfo=timezone.utc), str(row.get("event_uid") or ""))):
        stamp = _timestamp(event.get("ts"))
        if stamp is None:
            continue
        if not groups:
            groups.append([dict(event)])
            continue
        previous = groups[-1][-1]
        previous_stamp = _timestamp(previous.get("ts"))
        same_skill = (
            event.get("source") == previous.get("source")
            and event.get("skill") == previous.get("skill")
            and event.get("session_id") == previous.get("session_id")
        )
        gap = (stamp - previous_stamp).total_seconds() if previous_stamp else INVOCATION_GAP_SEC + 1
        if same_skill and gap <= INVOCATION_GAP_SEC:
            groups[-1].append(dict(event))
        else:
            groups.append([dict(event)])
    return groups


def build_invocations(
    normalized: Mapping[str, Any],
    *,
    now: Any | None = None,
    window_days: int = ROLLING_WINDOW_DAYS,
) -> list[dict[str, Any]]:
    """Build deterministic skill episodes from L2 activity and prompt signals."""
    now_stamp = _timestamp(now) or datetime.now(timezone.utc)
    lower = now_stamp - timedelta(days=window_days)
    events = [row for row in normalized.get("activity_events", []) if isinstance(row, Mapping)]
    events = [row for row in events if (_timestamp(row.get("ts")) or datetime.min.replace(tzinfo=timezone.utc)) >= lower]
    prompt_rows = [row for row in normalized.get("prompt_signals", []) if isinstance(row, Mapping)]
    invocations: list[dict[str, Any]] = []
    for group in _group_events(events):
        first, last = group[0], group[-1]
        start = _timestamp(first.get("ts"))
        end = _timestamp(last.get("ts"))
        if start is None or end is None:
            continue
        observation_end = end + timedelta(seconds=CORRECTION_WINDOW_SEC)
        closed = now_stamp >= observation_end
        source_covered = all(bool(row.get("source_covered", True)) for row in group)
        assistant_turns = sum(int(bool(row.get("assistant_turn", row.get("assistant_activity")))) for row in group)
        prompt_linked = any(
            prompt.get("source") == first.get("source")
            and prompt.get("session_id") == first.get("session_id")
            and canonical_skill(prompt.get("skill")) == canonical_skill(first.get("skill"))
            and prompt.get("source_kind") in _HUMAN_KINDS
            and (_timestamp(prompt.get("ts")) or datetime.min.replace(tzinfo=timezone.utc)) <= end
            and bool(prompt.get("source_covered", True))
            for prompt in prompt_rows
        )
        eligible = bool(
            canonical_skill(first.get("skill")) in ACTIVE_SKILLS
            and first.get("source")
            and first.get("session_id")
            and assistant_turns > 0
            and prompt_linked
            and closed
            and source_covered
        )
        corrections = []
        for prompt in prompt_rows:
            if prompt.get("source") != first.get("source") or prompt.get("session_id") != first.get("session_id"):
                continue
            prompt_ts = _timestamp(prompt.get("ts"))
            if prompt_ts is None or not (end < prompt_ts <= observation_end):
                continue
            if prompt.get("correction_class") in CORRECTION_CLASSES - {"none"}:
                corrections.append(prompt)
        corrections.sort(key=lambda row: (_timestamp(row.get("ts")) or datetime.max.replace(tzinfo=timezone.utc), str(row.get("signal_uid"))))
        correction = corrections[0] if corrections else None
        invocation_id = _uid(INVOCATIONIZER_VERSION, first.get("source"), first.get("session_id"), first.get("skill"), start.isoformat())
        invocation = Invocation(
            invocation_id=invocation_id,
            source=str(first.get("source")),
            session_id=str(first.get("session_id")),
            skill=str(canonical_skill(first.get("skill"))),
            start_ts=iso_timestamp(start) or "",
            end_ts=iso_timestamp(end) or "",
            observation_end_ts=iso_timestamp(observation_end) or "",
            assistant_turn_count=assistant_turns,
            edit_tool_calls=sum(int(row.get("edit_tool_calls") or 0) for row in group),
            active_duration_sec=_active_duration(group),
            max_tokens=any(str(row.get("finish_reason") or "").lower() == "max_tokens" for row in group),
            source_covered=source_covered,
            prompt_linked=prompt_linked,
            closed=closed,
            eligible=eligible,
            correction_class=str(correction.get("correction_class")) if correction else None,
            correction_confidence=float(correction.get("confidence")) if correction else None,
            correction_signal_uid=str(correction.get("signal_uid")) if correction else None,
        )
        invocations.append(invocation.as_dict())
    return invocations


def select_judge_samples(
    invocations: Iterable[Mapping[str, Any]],
    *,
    now: Any | None = None,
    max_per_skill: int = 1,
    local_salt: str = "",
) -> list[dict[str, Any]]:
    """Select a deterministic, per-skill rolling-window judge manifest.

    One sample is reserved for every skill with at least one explicit eligible
    invocation. Within each skill, correction/max-token/edit strata are ranked
    before recency and the stable hash, so global volume cannot starve a skill.
    """
    now_stamp = _timestamp(now) or datetime.now(timezone.utc)
    lower = now_stamp - timedelta(days=ROLLING_WINDOW_DAYS)
    candidates = [
        dict(row) for row in invocations
        if isinstance(row, Mapping)
        and bool(row.get("eligible"))
        and canonical_skill(row.get("skill")) in ACTIVE_SKILLS
        and lower <= (_timestamp(row.get("start_ts")) or datetime.min.replace(tzinfo=timezone.utc)) <= now_stamp
    ]
    by_skill: dict[str, list[dict[str, Any]]] = {}
    for row in candidates:
        skill = str(canonical_skill(row.get("skill")))
        row["skill"] = skill
        by_skill.setdefault(skill, []).append(row)
    selected: list[dict[str, Any]] = []
    window = "30d"
    for skill in sorted(by_skill):
        ranked = sorted(
            by_skill[skill],
            key=lambda row: (
                0 if row.get("correction_class") not in (None, "none") else 1,
                0 if row.get("max_tokens") else 1,
                -int(row.get("edit_tool_calls") or 0),
                -((_timestamp(row.get("start_ts")) or datetime.min.replace(tzinfo=timezone.utc)).timestamp()
                  if _timestamp(row.get("start_ts")) else 0.0),
                _uid(skill, window, str(row.get("invocation_id") or ""), local_salt),
            ),
        )
        for row in ranked[:max(1, int(max_per_skill))]:
            selected.append({
                "sample_key": _uid(skill, window, str(row.get("invocation_id") or ""), local_salt),
                "invocation_id": str(row.get("invocation_id") or ""),
                "invocation_id_hash": _uid(row.get("invocation_id")),
                "skill": skill,
                "source": str(row.get("source") or "unknown"),
                "stratum": "correction" if row.get("correction_class") not in (None, "none") else "behavior",
                "eligible": True,
            })
    return sorted(selected, key=lambda row: (row["skill"], row["sample_key"]))


def _percentile(values: Sequence[float], percentile: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return float(ordered[0])
    index = (len(ordered) - 1) * percentile
    lower, upper = math.floor(index), math.ceil(index)
    if lower == upper:
        return float(ordered[lower])
    return float(ordered[lower] + (ordered[upper] - ordered[lower]) * (index - lower))


def aggregate_behavior(
    invocations: Iterable[Mapping[str, Any]],
    *,
    now: Any | None = None,
    source_as_of: Any | None = None,
    source_status: str = "covered",
) -> list[dict[str, Any]]:
    now_stamp = _timestamp(now) or datetime.now(timezone.utc)
    start = now_stamp - timedelta(days=ROLLING_WINDOW_DAYS)
    rows = [
        row for row in invocations
        if isinstance(row, Mapping) and start <= (_timestamp(row.get("start_ts")) or now_stamp) <= now_stamp
    ]
    output: list[dict[str, Any]] = []
    for skill in ACTIVE_SKILLS:
        skill_rows = [row for row in rows if canonical_skill(row.get("skill")) == skill]
        eligible_rows = [row for row in skill_rows if bool(row.get("eligible"))]
        corrections = [row for row in eligible_rows if row.get("correction_class") not in (None, "none")]
        satisfaction_rows = [row for row in eligible_rows if not bool(row.get("max_tokens"))]
        satisfaction_corrections = [
            row for row in satisfaction_rows if row.get("correction_class") not in (None, "none")
        ]
        durations = [float(row.get("active_duration_sec") or 0) for row in eligible_rows]
        turns = sum(int(row.get("assistant_turn_count") or 0) for row in eligible_rows)
        edits = sum(int(row.get("edit_tool_calls") or 0) for row in eligible_rows)
        if source_status == "missing" and not skill_rows:
            coverage = "missing"
        elif not eligible_rows:
            coverage = "partial" if skill_rows else "unknown"
        elif all(bool(row.get("closed")) and bool(row.get("source_covered", True)) for row in skill_rows):
            coverage = "covered"
        else:
            coverage = "partial"
        output.append({
            "skill": skill,
            "registered": True,
            "observed_invocations": len(skill_rows),
            "eligible_invocations": len(eligible_rows),
            "eligible": bool(eligible_rows),
            "correction_count": len(corrections),
            "max_tokens_invocations": sum(1 for row in eligible_rows if bool(row.get("max_tokens"))),
            "satisfaction_eligible_invocations": len(satisfaction_rows),
            "first_pass_satisfaction_rate": (
                (len(satisfaction_rows) - len(satisfaction_corrections)) / len(satisfaction_rows)
                if satisfaction_rows else None
            ),
            "implicit_correction_rate": (
                len(satisfaction_corrections) / len(satisfaction_rows) if satisfaction_rows else None
            ),
            "edit_tool_calls": edits,
            "assistant_turn_count": turns,
            "normalized_edit_churn": edits / max(1, turns) if eligible_rows else None,
            "active_duration_median_sec": float(median(durations)) if durations else None,
            "active_duration_p90_sec": _percentile(durations, 0.9),
            "source_as_of": iso_timestamp(source_as_of) or max((str(row.get("end_ts")) for row in skill_rows), default=None),
            "window_start": iso_timestamp(start),
            "window_end": iso_timestamp(now_stamp),
            "window_cst": "30d",
            "coverage_status": coverage,
            "estimated": False,
        })
    return output


def aggregate_judge_coverage(
    invocations: Iterable[Mapping[str, Any]],
    verdicts: Iterable[Mapping[str, Any]],
    *,
    now: Any | None = None,
) -> dict[str, Any]:
    """Aggregate explicit eligible/judged populations without denominator drift."""
    now_stamp = _timestamp(now) or datetime.now(timezone.utc)
    lower = now_stamp - timedelta(days=ROLLING_WINDOW_DAYS)
    invocation_rows = [row for row in invocations if isinstance(row, Mapping)]
    invocation_rows = [
        row for row in invocation_rows
        if lower <= (_timestamp(row.get("start_ts")) or now_stamp) <= now_stamp
    ]
    eligible_ids = {str(row.get("invocation_id")) for row in invocation_rows if bool(row.get("eligible"))}
    eligible_by_skill = Counter(
        canonical_skill(row.get("skill")) for row in invocation_rows if bool(row.get("eligible")) and canonical_skill(row.get("skill"))
    )
    sampled_by_invocation: dict[str, list[Mapping[str, Any]]] = {}
    valid_by_invocation: dict[str, list[Mapping[str, Any]]] = {}
    verdict_rows = [verdict for verdict in verdicts if isinstance(verdict, Mapping)]
    for verdict in verdict_rows:
        invocation_id = str(verdict.get("invocation_id") or verdict.get("invocation_id_hash") or "")
        if invocation_id not in eligible_ids:
            continue
        sampled_by_invocation.setdefault(invocation_id, []).append(verdict)
        if verdict.get("status") == "valid" and not bool(verdict.get("abstained")):
            valid_by_invocation.setdefault(invocation_id, []).append(verdict)
    invocation_skill = {str(row.get("invocation_id")): canonical_skill(row.get("skill")) for row in invocation_rows}
    judged_by_skill = Counter(
        invocation_skill[invocation_id]
        for invocation_id in valid_by_invocation
        if invocation_skill.get(invocation_id)
    )
    sampled_by_skill = Counter(
        invocation_skill[invocation_id]
        for invocation_id in sampled_by_invocation
        if invocation_skill.get(invocation_id)
    )
    result_rows: list[dict[str, Any]] = []
    for skill in ACTIVE_SKILLS:
        skill_verdicts = [
            v for invocation_id, values in valid_by_invocation.items()
            if invocation_skill.get(invocation_id) == skill for v in values
        ]
        skill_sampled = [
            v for invocation_id, values in sampled_by_invocation.items()
            if invocation_skill.get(invocation_id) == skill for v in values
        ]
        eligible_count = int(eligible_by_skill.get(skill, 0))
        judged_count = int(judged_by_skill.get(skill, 0))
        if eligible_count == 0:
            status = "unknown"
        elif judged_count >= 1:
            status = "covered"
        else:
            status = "partial"
        scores = [float(v["overall_score"]) for v in skill_verdicts if isinstance(v.get("overall_score"), (int, float))]
        result_rows.append({
            "skill": skill,
            "registered": True,
            "eligible": eligible_count > 0,
            "eligible_invocations": eligible_count,
            "sampled": int(sampled_by_skill.get(skill, 0)),
            "judged": judged_count > 0,
            "valid_judgements": judged_count,
            "rejudged_count": max(0, len(skill_sampled) - int(sampled_by_skill.get(skill, 0))),
            "coverage_status": status,
            "coverage_pct": min(100.0, judged_count / eligible_count * 100.0) if eligible_count else None,
            "score_mean": sum(scores) / len(scores) if scores else None,
            "score_distribution": {str(score): scores.count(score) for score in sorted(set(scores))},
            "source_as_of": max((str(v.get("sampled_at")) for v in skill_sampled if v.get("sampled_at")), default=None),
            "window_cst": "30d",
            "rubric_version": RUBRIC_VERSION,
            "judge_model": next((str(v.get("judge_model")) for v in skill_verdicts if v.get("judge_model")), None),
            "estimated": False,
        })
    eligible_skill_count = sum(1 for skill in ACTIVE_SKILLS if eligible_by_skill.get(skill, 0) > 0)
    judged_skill_count = sum(1 for skill in ACTIVE_SKILLS if judged_by_skill.get(skill, 0) > 0)
    return {
        "skills": result_rows,
        "eligible_skill_count": eligible_skill_count,
        "judged_skill_count": judged_skill_count,
        "coverage_label": f"{judged_skill_count}/{eligible_skill_count}",
        "coverage_pct": min(100.0, judged_skill_count / eligible_skill_count * 100.0) if eligible_skill_count else None,
        "source_as_of": max((str(v.get("sampled_at")) for v in verdict_rows if v.get("sampled_at")), default=None),
        "window_cst": "30d",
        "rubric_version": RUBRIC_VERSION,
        "estimated": False,
    }
