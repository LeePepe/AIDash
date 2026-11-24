"""Operator-controlled offline quality judge runner.

The default mode is ``dry_run``. A caller must supply a local callable adapter
for execution; there is no network client, scheduler, credential lookup, or
cron integration here. Judge inputs are bounded transient previews and only the
strict redacted verdict envelope is returned for persistence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import time
import uuid
from collections.abc import Iterable, Mapping
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError
from datetime import datetime, timezone
import signal
from threading import Lock, current_thread, main_thread
from typing import Any, Protocol

from quality_contracts import (
    JUDGE_COMPONENT_MAX,
    JUDGE_COMPONENT_MIN,
    JUDGE_PASS_THRESHOLD,
    JUDGE_REASON_CODES,
    JUDGE_SCORE_MAX,
    JUDGE_SCORE_MIN,
    MAX_JUDGE_OUTPUT_BYTES,
    MAX_PREVIEW_CHARS,
    REDACTION_VERSION,
    RUBRIC_VERSION,
    RUNNER_VERSION,
)


class JudgeAdapter(Protocol):
    def __call__(self, request: Mapping[str, Any]) -> Mapping[str, Any]: ...


def _hash(value: Any) -> str:
    return hashlib.sha256(str(value or "").encode("utf-8", errors="replace")).hexdigest()


def _stamp(value: Any | None = None) -> str:
    if isinstance(value, datetime):
        stamp = value
    else:
        stamp = datetime.now(timezone.utc) if value is None else datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
    return stamp.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def sample_key(skill: str, window: str, invocation_id: str, local_salt: str = "") -> str:
    """Return the deterministic local sample key; salt is never persisted."""
    return _hash(f"{skill}\0{window}\0{invocation_id}\0{local_salt}")


def build_request(
    invocation: Mapping[str, Any],
    *,
    prompt: str,
    response: str,
    source_kind: str = "typed",
    redaction_version: str = REDACTION_VERSION,
    local_salt: str = "",
) -> dict[str, Any]:
    """Build the transient strict input passed to a local judge adapter."""
    skill = str(invocation.get("skill") or "")
    invocation_id = str(invocation.get("invocation_id") or "")
    window = str(invocation.get("window_cst") or "30d")
    bounded_prompt = prompt[:MAX_PREVIEW_CHARS]
    bounded_response = response[:MAX_PREVIEW_CHARS]
    return {
        "request_uid": str(uuid.uuid4()),
        "invocation_id": invocation_id,
        "invocation_id_hash": _hash(invocation_id),
        "skill": skill,
        "source": str(invocation.get("source") or "unknown"),
        "source_kind": source_kind,
        "rubric_version": RUBRIC_VERSION,
        "window_cst": window,
        "sample_key": sample_key(skill, window, invocation_id, local_salt),
        "prompt_preview": bounded_prompt,
        "response_preview": bounded_response,
        "input_sha256": _hash(prompt),
        "response_sha256": _hash(response),
        "input_len": len(prompt),
        "response_len": len(response),
        "redaction_version": redaction_version,
    }


def _score(value: Any, minimum: float, maximum: float) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if minimum <= number <= maximum else None


class JudgeBusyError(RuntimeError):
    """Another timed-out off-main adapter is still running."""


_OFF_MAIN_ADAPTER = Lock()


def _invoke_adapter(adapter: JudgeAdapter, request: Mapping[str, Any], timeout_sec: float) -> Mapping[str, Any]:
    """Invoke with a hard main-thread alarm; use a bounded future off-thread."""
    timeout = max(0.01, float(timeout_sec))
    if current_thread() is main_thread():
        if not _OFF_MAIN_ADAPTER.acquire(blocking=False):
            raise JudgeBusyError("judge_busy")
        class _AdapterTimeout(Exception):
            pass

        def alarm_handler(_signum, _frame):
            raise _AdapterTimeout

        previous = signal.getsignal(signal.SIGALRM)
        signal.signal(signal.SIGALRM, alarm_handler)
        signal.setitimer(signal.ITIMER_REAL, timeout)
        try:
            return adapter(request)
        except _AdapterTimeout as exc:
            raise TimeoutError from exc
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, previous)
            _OFF_MAIN_ADAPTER.release()
    if not _OFF_MAIN_ADAPTER.acquire(blocking=False):
        raise JudgeBusyError("judge_busy")
    executor = ThreadPoolExecutor(max_workers=1)
    try:
        future = executor.submit(adapter, request)
    except Exception:
        _OFF_MAIN_ADAPTER.release()
        executor.shutdown(wait=False, cancel_futures=True)
        raise
    future.add_done_callback(lambda _future: _OFF_MAIN_ADAPTER.release())
    try:
        return future.result(timeout=timeout)
    except FutureTimeoutError as exc:
        future.cancel()
        raise TimeoutError from exc
    finally:
        # A timed-out callable may continue; its done callback owns the
        # single-flight release. Normal completion releases before shutdown.
        executor.shutdown(wait=False, cancel_futures=True)


def normalize_verdict(
    raw: Mapping[str, Any],
    request: Mapping[str, Any],
    *,
    judge_run_uid: str,
    judge_provider: str,
    judge_model: str,
    runner_version: str = RUNNER_VERSION,
) -> tuple[dict[str, Any] | None, str | None]:
    """Validate a provider response and discard all free-form rationale."""
    if not isinstance(raw, Mapping):
        return None, "malformed_json"
    abstained_value = raw.get("abstained", False)
    if not isinstance(abstained_value, bool):
        return None, "malformed_json"
    abstained = abstained_value
    confidence = raw.get("confidence")
    if isinstance(confidence, bool) or not isinstance(confidence, (int, float)) or not 0 <= float(confidence) <= 1:
        return None, "malformed_json"
    status = "abstained" if abstained else "valid"
    reason_code = str(raw.get("reason_code") or ("low_confidence_abstention" if abstained else "accepted"))
    if reason_code not in JUDGE_REASON_CODES:
        return None, "malformed_json"
    scores: dict[str, float] = {}
    for key in ("correctness_score", "instruction_following_score", "actionability_score"):
        score = _score(raw.get(key), JUDGE_COMPONENT_MIN, JUDGE_COMPONENT_MAX)
        if not abstained and score is None:
            return None, "malformed_json"
        if score is not None:
            scores[key] = score
    overall = _score(raw.get("overall_score"), JUDGE_SCORE_MIN, JUDGE_SCORE_MAX)
    if not abstained and overall is None:
        return None, "malformed_json"
    judgement_uid = str(raw.get("judgement_uid") or _hash(f"{judge_run_uid}\0{request.get('invocation_id')}\0{request.get('sample_key')}"))
    result = {
        "judgement_uid": judgement_uid,
        "judge_run_uid": judge_run_uid,
        "invocation_id": str(request.get("invocation_id") or ""),
        "invocation_id_hash": str(request.get("invocation_id_hash") or _hash(request.get("invocation_id"))),
        "skill": str(request.get("skill") or ""),
        "source": str(request.get("source") or "unknown"),
        "sample_key": str(request.get("sample_key") or ""),
        "sampled_at": _stamp(),
        "judge_provider": judge_provider,
        "judge_model": judge_model,
        "rubric_version": RUBRIC_VERSION,
        "runner_version": runner_version,
        "correctness_score": scores.get("correctness_score"),
        "instruction_following_score": scores.get("instruction_following_score"),
        "actionability_score": scores.get("actionability_score"),
        "overall_score": overall,
        "pass_flag": bool(overall is not None and overall >= JUDGE_PASS_THRESHOLD) if not abstained else False,
        "confidence": float(confidence),
        "abstained": abstained,
        "reason_code": reason_code,
        "input_sha256": str(request.get("input_sha256") or ""),
        "response_sha256": str(request.get("response_sha256") or ""),
        "input_len": int(request.get("input_len") or 0),
        "response_len": int(request.get("response_len") or 0),
        "redaction_version": str(request.get("redaction_version") or REDACTION_VERSION),
        "latency_ms": max(0, int(raw.get("latency_ms") or 0)),
        "status": status,
    }
    return result, None


_SINGLE_FLIGHT = Lock()


def _run_judge(
    requests: Iterable[Mapping[str, Any]],
    *,
    adapter: JudgeAdapter | None = None,
    dry_run: bool = True,
    judge_provider: str = "local",
    judge_model: str = "offline-fake",
    judge_run_uid: str | None = None,
    max_items: int = 100,
    adapter_timeout_sec: float = 5.0,
    max_output_bytes: int = MAX_JUDGE_OUTPUT_BYTES,
) -> dict[str, Any]:
    """Run or preview one bounded batch and return a redacted immutable receipt."""
    run_uid = judge_run_uid or str(uuid.uuid4())
    selected = [dict(request) for request in requests][:max(0, max_items)]
    manifest = [
        {
            "sample_key": str(request.get("sample_key") or ""),
            "invocation_id_hash": str(request.get("invocation_id_hash") or _hash(request.get("invocation_id"))),
            "skill": str(request.get("skill") or ""),
        }
        for request in selected
    ]
    receipt: dict[str, Any] = {
        "judge_run_uid": run_uid,
        "runner_version": RUNNER_VERSION,
        "rubric_version": RUBRIC_VERSION,
        "judge_provider": judge_provider,
        "judge_model": judge_model,
        "started_at": _stamp(),
        "dry_run": dry_run,
        "sampled": len(selected),
        "valid": 0,
        "abstained": 0,
        "excluded": 0,
        "exclusion_reasons": {},
        "manifest": manifest,
        "verdicts": [],
        "status": "dry_run" if dry_run else "completed",
    }
    if dry_run:
        receipt["finished_at"] = _stamp()
        return receipt
    if adapter is None:
        receipt["status"] = "error"
        receipt["error_code"] = "provider_missing"
        receipt["finished_at"] = _stamp()
        return receipt
    seen_keys: set[str] = set()
    for request in selected:
        key = str(request.get("sample_key") or "")
        if not key or key in seen_keys:
            receipt["excluded"] += 1
            receipt["exclusion_reasons"]["duplicate_sample"] = receipt["exclusion_reasons"].get("duplicate_sample", 0) + 1
            continue
        seen_keys.add(key)
        started = time.monotonic()
        try:
            raw = _invoke_adapter(adapter, request, adapter_timeout_sec)
            if not isinstance(raw, Mapping):
                raise ValueError("provider did not return an object")
            raw = dict(raw)
            try:
                encoded = json.dumps(raw, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            except (TypeError, ValueError, UnicodeError) as exc:
                raise ValueError("malformed_json") from exc
            if len(encoded) > max(1, int(max_output_bytes)):
                raise OverflowError("output_too_large")
            raw.setdefault("latency_ms", int((time.monotonic() - started) * 1000))
            verdict, error = normalize_verdict(
                raw, request, judge_run_uid=run_uid, judge_provider=judge_provider, judge_model=judge_model
            )
            if verdict is None:
                raise ValueError(error or "malformed_json")
            receipt["verdicts"].append(verdict)
            if verdict["abstained"]:
                receipt["abstained"] += 1
            else:
                receipt["valid"] += 1
        except TimeoutError:
            receipt["excluded"] += 1
            receipt["exclusion_reasons"]["timeout"] = receipt["exclusion_reasons"].get("timeout", 0) + 1
        except Exception as exc:  # noqa: BLE001 - provider boundary is fail-closed
            if isinstance(exc, JudgeBusyError):
                reason = "judge_busy"
            elif isinstance(exc, OverflowError):
                reason = "output_too_large"
            elif isinstance(exc, (ValueError, json.JSONDecodeError)):
                reason = "malformed_json"
            else:
                reason = "provider_error"
            receipt["excluded"] += 1
            receipt["exclusion_reasons"][reason] = receipt["exclusion_reasons"].get(reason, 0) + 1
    receipt["status"] = "partial" if receipt["excluded"] else "completed"
    receipt["finished_at"] = _stamp()
    return receipt


def run_judge(requests: Iterable[Mapping[str, Any]], **kwargs: Any) -> dict[str, Any]:
    """Run one bounded batch; concurrent batches fail closed as ``busy``.

    ``persist_path`` is an explicit operator opt-in for atomic receipt storage;
    dry runs never write a database.
    """
    persist_path = kwargs.pop("persist_path", None)
    if not _SINGLE_FLIGHT.acquire(blocking=False):
        run_uid = str(kwargs.get("judge_run_uid") or uuid.uuid4())
        return {
            "judge_run_uid": run_uid,
            "runner_version": RUNNER_VERSION,
            "rubric_version": RUBRIC_VERSION,
            "dry_run": bool(kwargs.get("dry_run", True)),
            "sampled": 0,
            "valid": 0,
            "abstained": 0,
            "excluded": 0,
            "exclusion_reasons": {"judge_busy": 1},
            "manifest": [],
            "verdicts": [],
            "status": "busy",
            "error_code": "judge_busy",
            "started_at": _stamp(),
            "finished_at": _stamp(),
        }
    try:
        receipt = _run_judge(requests, **kwargs)
        if persist_path is not None and receipt.get("status") in {"completed", "partial"}:
            receipt["persisted_judgements"] = persist_receipt(receipt, db_path=persist_path)
        return receipt
    finally:
        _SINGLE_FLIGHT.release()


def persist_receipt(receipt: Mapping[str, Any], *, db_path=None) -> int:
    """Atomically append a validated receipt to an ignored L2 judge database."""
    import fcntl
    import os
    import shutil
    import sqlite3
    import tempfile
    from pathlib import Path

    if db_path is None:
        from config import clean_path
        db_path = clean_path("quality_judge")
    path = Path(db_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_name(path.name + ".lock")
    temporary: Path | None = None
    with lock_path.open("a+") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RuntimeError("judge_busy") from exc
        try:
            with tempfile.NamedTemporaryFile(
                prefix=f".{path.name}.", suffix=".tmp", dir=path.parent, delete=False
            ) as handle:
                temporary = Path(handle.name)
            if path.exists():
                shutil.copyfile(path, temporary)
            connection = sqlite3.connect(temporary)
            try:
                connection.execute("""
                    CREATE TABLE IF NOT EXISTS run (
                        judge_run_uid TEXT PRIMARY KEY, runner_version TEXT NOT NULL,
                        rubric_version TEXT NOT NULL, judge_provider TEXT NOT NULL,
                        judge_model TEXT NOT NULL, started_at TEXT NOT NULL, finished_at TEXT,
                        dry_run INTEGER NOT NULL, sampled INTEGER NOT NULL, valid INTEGER NOT NULL,
                        abstained INTEGER NOT NULL, excluded INTEGER NOT NULL, status TEXT NOT NULL,
                        exclusion_reasons TEXT
                    )
                """)
                connection.execute("""
                    CREATE TABLE IF NOT EXISTS judgement (
                        judgement_uid TEXT PRIMARY KEY, judge_run_uid TEXT NOT NULL,
                        invocation_id TEXT NOT NULL, invocation_id_hash TEXT NOT NULL,
                        skill TEXT NOT NULL, source TEXT NOT NULL, sample_key TEXT NOT NULL,
                        sampled_at TEXT NOT NULL, judge_provider TEXT NOT NULL, judge_model TEXT NOT NULL,
                        rubric_version TEXT NOT NULL, runner_version TEXT NOT NULL,
                        correctness_score REAL CHECK(correctness_score IS NULL OR correctness_score BETWEEN 0 AND 3),
                        instruction_following_score REAL CHECK(instruction_following_score IS NULL OR instruction_following_score BETWEEN 0 AND 3),
                        actionability_score REAL CHECK(actionability_score IS NULL OR actionability_score BETWEEN 0 AND 3),
                        overall_score REAL CHECK(overall_score IS NULL OR overall_score BETWEEN 1 AND 5),
                        pass_flag INTEGER NOT NULL, confidence REAL NOT NULL,
                        abstained INTEGER NOT NULL, reason_code TEXT NOT NULL,
                        input_sha256 TEXT NOT NULL, response_sha256 TEXT NOT NULL,
                        input_len INTEGER NOT NULL, response_len INTEGER NOT NULL,
                        redaction_version TEXT NOT NULL, latency_ms INTEGER NOT NULL, status TEXT NOT NULL
                    )
                """)
                connection.execute(
                    "INSERT OR IGNORE INTO run VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        receipt.get("judge_run_uid"), receipt.get("runner_version"), receipt.get("rubric_version"),
                        receipt.get("judge_provider"), receipt.get("judge_model"), receipt.get("started_at"),
                        receipt.get("finished_at"), int(bool(receipt.get("dry_run"))), receipt.get("sampled", 0),
                        receipt.get("valid", 0), receipt.get("abstained", 0), receipt.get("excluded", 0),
                        receipt.get("status"), json.dumps(receipt.get("exclusion_reasons") or {}, sort_keys=True),
                    ),
                )
                columns = (
                    "judgement_uid", "judge_run_uid", "invocation_id", "invocation_id_hash", "skill", "source",
                    "sample_key", "sampled_at", "judge_provider", "judge_model", "rubric_version", "runner_version",
                    "correctness_score", "instruction_following_score", "actionability_score", "overall_score", "pass_flag",
                    "confidence", "abstained", "reason_code", "input_sha256", "response_sha256", "input_len", "response_len",
                    "redaction_version", "latency_ms", "status",
                )
                rows = [tuple(verdict.get(column) for column in columns) for verdict in receipt.get("verdicts", [])]
                if rows:
                    connection.executemany(
                        f"INSERT OR IGNORE INTO judgement ({', '.join(columns)}) VALUES ({', '.join('?' for _ in columns)})",
                        rows,
                    )
                connection.commit()
            finally:
                connection.close()
            with temporary.open("rb") as handle:
                os.fsync(handle.fileno())
            os.replace(temporary, path)
            temporary = None
            directory = os.open(path.parent, os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
            return len(rows)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)


class FakeJudgeAdapter:
    """Deterministic local adapter used by hermetic tests and dry-run demos."""

    def __init__(self, *, score: float = 4.5, component_score: float = 3.0, confidence: float = 0.95, abstain_skills: Iterable[str] = ()):
        self.score = float(score)
        self.component_score = float(component_score)
        self.confidence = float(confidence)
        self.abstain_skills = frozenset(str(skill) for skill in abstain_skills)

    def __call__(self, request: Mapping[str, Any]) -> Mapping[str, Any]:
        if request.get("skill") in self.abstain_skills:
            return {"abstained": True, "confidence": 0.2, "reason_code": "low_confidence_abstention"}
        return {
            "correctness_score": self.component_score,
            "instruction_following_score": self.component_score,
            "actionability_score": self.component_score,
            "overall_score": self.score,
            "confidence": self.confidence,
            "abstained": False,
            "reason_code": "accepted",
        }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=str, default=None, help="JSON request manifest")
    parser.add_argument("--dry-run", action="store_true", help="emit a sample manifest without judging (default)")
    parser.add_argument("--execute", action="store_true", help="execute with the local fake adapter")
    parser.add_argument("--fake", action="store_true", help="use the deterministic fake adapter")
    args = parser.parse_args(argv)
    if args.dry_run and args.execute:
        parser.error("--dry-run and --execute are mutually exclusive")
    requests: list[Mapping[str, Any]] = []
    if args.manifest:
        with open(args.manifest, encoding="utf-8") as handle:
            loaded = json.load(handle)
        if isinstance(loaded, list):
            requests = [item for item in loaded if isinstance(item, Mapping)]
    execute = bool(args.execute or args.fake)
    receipt = run_judge(requests, adapter=FakeJudgeAdapter() if execute else None, dry_run=not execute)
    if execute and receipt.get("status") in {"completed", "partial"}:
        try:
            receipt["persisted_judgements"] = persist_receipt(receipt)
        except Exception as exc:  # noqa: BLE001 - persistence is an explicit operator boundary
            receipt["status"] = "error"
            receipt["error_code"] = "persist_failed"
            receipt["error_type"] = type(exc).__name__
    print(json.dumps(receipt, ensure_ascii=False, sort_keys=True))
    return 0 if receipt.get("status") in {"dry_run", "completed", "partial"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
