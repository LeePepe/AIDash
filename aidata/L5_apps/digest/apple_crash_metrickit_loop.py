"""Loop 6B: Apple Official Crash & MetricKit Quality Diagnostic Loop.

Implements the 3-layer Wake-on-Actionable diagnostic loop for personal Apple apps
(`AIDash`, `VitalStride`, `VoxPocket`, `Financial`):

1. Layer 0 (`collect_crash_and_metrickit_diagnostics`):
   - Parses Apple `MetricKit` `MXCrashDiagnostic` / `MXHangDiagnostic` JSON payloads
     (`callStackTree.callStacks[].callStackRootFrames` recursive `subFrames`,
     `exceptionType`, `exceptionCode`, `signal`, `terminationReason`, `hangDuration`);
   - Parses App Store Connect API `diagnosticSignatures` & `diagnosticLogs` JSON payloads
     (`diagnosticType`, `signature`, `weight`, stack frames);
   - Parses local macOS/iOS `.ips` (JSON header + JSON body `threads[].frames`) and
     `.xcresult` crash summary payloads for personal apps;
   - Queries `L4_serve/queries/retro/app_crash_and_perf.sql` via `serve.run_query`
     (or an injected `--warehouse-db` / `query_runner`) for 7d crash count,
     `new_crash_signature_count`, `crash_free_rate_7d`, `p95_metric_ms_7d` vs
     `p95_metric_ms_prev_7d`, `p95_regression_pct`, and `is_perf_regressed` (`>20%`).
   - Extracts the top application-owned responsible frame (`symbol` + `file:line`),
     skipping Apple system frameworks (`SwiftUI`, `UIKitCore`, `AppKit`, `CoreFoundation`,
     `Foundation`, `libsystem_*`, `libobjc.A.dylib`, `libdispatch.dylib`, `dyld`),
     deduplicates by `(app_name, event_kind, signature)`, and flags actionable 7d new
     crash signatures (`new_crash_signature_count > 0`) or P95 regressions `> 20.0%`.
   - Returns `SKIPPED_NO_DELTA` (`token_cost = 0`) when no new crash signature or
     `>20%` P95 regression is present or when the watermark is unchanged.

2. Layer 1 (`evaluate_jev_decision`):
   - Calls `jev_decide()` (`127.0.0.1:19823/v1/systemone`, `falcon_only=True`,
     supporting `--mock-jev-json`) with the truth table:
     - `prob > 0.70` -> `actionable = True`
     - `prob < 0.30` or (`delivery_route == "ignore"` and `delivery_route_match >= 0.50`
       and `prob <= 0.70`) -> `actionable = False`
     - `0.30 <= prob <= 0.70` grey zone or Falcon offline -> deterministic fallback:
       `actionable = True` iff `new_crash_signature_count > 0` or `p95_regression_pct > 20.0`.

3. Layer 2 (`sync_autopilot`, `render_dual_zone_bug_issue`, `run_loop_pipeline`):
   - Idempotently registers Multica Autopilot:
     `Apple Crash & MetricKit Quality Diagnostic Autopilot (Loop 6B -> Owner)`
     (Loop ID `loop-apple-crash-metrickit`, Cron `50 4 * * *`, `Asia/Shanghai`).
   - Emits and verifies a Dual-Zone (`verify_issue_format.py`) Bug issue with
     `<= 15` Upper Zone Chinese lines, `<!-- multica-cursor:loop-apple-crash-metrickit-YYYY-MM-DD -->`,
     `**一句话结论**：...`, checkable `- [ ] 1. ...` items, and zero forbidden internal codes/SHAs/UUIDs/tables
     in the Upper Zone.
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib.util
import json
import math
import os
import re
import shutil
import sqlite3
import subprocess  # nosec B404 - fixed CLI invocation for multica autopilot/issue
import sys
import tempfile
from collections.abc import Callable, Mapping, Sequence
from contextlib import contextmanager
from dataclasses import asdict, dataclass, replace
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import serve
from config import HOME, QUERIES_DIR
from redaction import redact

LOOP_ID = "loop-apple-crash-metrickit"
AUTOPILOT_TITLE = "Apple Crash & MetricKit Quality Diagnostic Autopilot (Loop 6B -> Owner)"
AUTOPILOT_CRON = "50 4 * * *"
AUTOPILOT_TIMEZONE = "Asia/Shanghai"
AUTOPILOT_TRIGGER_LABEL = "Daily CST 04:50 Apple Crash & MetricKit Quality Diagnostic"

PERSONAL_APPS: tuple[str, ...] = ("AIDash", "VitalStride", "VoxPocket", "Financial")
PERSONAL_APP_PREFIXES: tuple[str, ...] = ("AIDash", "VitalStride", "VoxPocket", "Financial")
P95_REGRESSION_THRESHOLD_PCT = 20.0

SYSTEM_FRAMEWORK_EXACT: frozenset[str] = frozenset({
    "SwiftUI",
    "UIKit",
    "UIKitCore",
    "AppKit",
    "CoreFoundation",
    "Foundation",
    "Combine",
    "SwiftData",
    "CoreData",
    "CloudKit",
    "QuartzCore",
    "CoreGraphics",
    "GraphicsServices",
    "FrontBoardServices",
    "BackBoardServices",
    "RunningBoardServices",
    "CFNetwork",
    "Security",
    "libobjc.A.dylib",
    "libdispatch.dylib",
    "dyld",
    "libswiftCore.dylib",
    "libswiftConcurrency.dylib",
    "libswiftDispatch.dylib",
    "libswiftFoundation.dylib",
    "libsystem_kernel.dylib",
    "libsystem_pthread.dylib",
    "libsystem_c.dylib",
    "libsystem_platform.dylib",
    "libsystem_malloc.dylib",
    "libsystem_trace.dylib",
    "libsystem_blocks.dylib",
    "libxpc.dylib",
})

SYSTEM_FRAMEWORK_PREFIXES: tuple[str, ...] = (
    "libsystem_",
    "libswift",
    "libobjc",
    "libdispatch",
    "libxpc",
    "dyld",
    "com.apple.",
    "/System/Library/",
    "/usr/lib/",
)

CST = timezone(timedelta(hours=8))

CANONICAL_AI_SUMMARY = "🤖 AI 执行上下文与确定性证据（人无需展开）"
CANONICAL_DETAILS_OPEN = f"<details><summary>{CANONICAL_AI_SUMMARY}</summary>"

DEFAULT_DIAGNOSTICS_DIRS: tuple[Path, ...] = (
    HOME / "Library" / "Logs" / "DiagnosticReports",
)
DEFAULT_WATERMARK_PATH = HOME / ".cache" / "multica-loop-runner" / f"{LOOP_ID}.json"
DEFAULT_SERVER_URL = os.environ.get("MULTICA_SERVER_URL", "")
DEFAULT_WORKSPACE_ID = os.environ.get("MULTICA_WORKSPACE_ID", "")
DEFAULT_OWNER_ID = os.environ.get("MULTICA_OWNER_ID", "")
DEFAULT_AGENT_ID = os.environ.get("MULTICA_AGENT_ID", "")

_FILE_LINE_RE = re.compile(r"([A-Za-z0-9_+.-]+\.(?:swift|m|mm|c|cc|cpp|h)):(\d+)")
_INTERNAL_CODE_RE = re.compile(
    r"(?<![A-Za-z0-9_-])"
    r"(?:S(?:1[0-2]|[1-9])|M[1-5]|EV-\d{1,4}|DC-\d{1,4}|H[1-5]|R10|V[1-5])"
    r"(?![A-Za-z0-9_-])"
)
_UUID_RE = re.compile(
    r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"
)
_HEX_SHA_RE = re.compile(r"(?<![A-Za-z0-9_-])[0-9a-f]{7,40}(?![A-Za-z0-9_-])")
_HTML_COMMENT_BLOCK_RE = re.compile(r"<!--[\s\S]*?-->")
_HTML_COMMENT_LINE_RE = re.compile(r"^\s*<!--.*-->\s*$")
_CURSOR_RE = re.compile(r"<!--\s*(?:multica-cursor|issue-brief-cursor)\s*:\s*([^\s>][^>]*?)\s*-->")
_DETAILS_OPEN_RE = re.compile(
    r"<details>\s*<summary>\s*" + re.escape(CANONICAL_AI_SUMMARY) + r"\s*</summary>",
    re.MULTILINE,
)
_DETAILS_ANY_OPEN_RE = re.compile(r"<details\b[^>]*>", re.IGNORECASE)
_DETAILS_CLOSE_RE = re.compile(r"</details>", re.IGNORECASE)
_TLDR_RE = re.compile(r"^(?:>\s*)?\*\*一句话结论\*\*\s*[：:]\s*\S+")
_CHECKBOX_ITEM_RE = re.compile(r"^\s*[-*+]\s*\[[ xX]\]\s+\S+")
_FENCE_RE = re.compile(r"^\s*(?:```|~~~)")
_CLI_COMMAND_RE = re.compile(
    r"(?:(?<![A-Za-z0-9_/-])(?:python3?|pytest|bash|sh|curl|gh|multica|git)\s+\S+(?:\s+--?[A-Za-z0-9_-]+|\s+\S+\.py\b))"
    r"|(?:\./scripts/[A-Za-z0-9_./-]+)"
    r"|(?:\bskills/[A-Za-z0-9_-]+/scripts/[A-Za-z0-9_.-]+\.py\b)"
)
_MARKDOWN_TABLE_ROW_RE = re.compile(r"^\s*\|.*\|.*$")


@dataclass(frozen=True)
class ResponsibleFrame:
    module: str
    symbol: str
    file_line: str
    is_app_owned: bool


@dataclass(frozen=True)
class DiagnosticFinding:
    app_name: str
    platform: str
    source_kind: str  # metrickit | asc | ips | xcresult | warehouse
    event_kind: str   # crash | hang | perf
    signature: str
    responsible_symbol: str
    responsible_file_line: str
    exception_summary: str
    crash_count_7d: int
    new_crash_signature_count: int
    crash_free_rate_7d: float | None
    p95_metric_ms_7d: float | None
    p95_metric_ms_prev_7d: float | None
    p95_regression_pct: float
    is_perf_regressed: bool
    hang_duration_ms: float | None
    is_new_crash_signature: bool
    actionable_reason: str
    occurred_at: str = ""
    stack_summary: tuple[str, ...] = ()
    source_weight: float | None = None


def _canonical_app_name(raw_name: Any) -> str | None:
    text = str(raw_name or "").strip()
    if not text:
        return None
    lower = text.lower()
    for app in PERSONAL_APPS:
        app_lower = app.lower()
        if lower == app_lower or lower.startswith(app_lower) or f".{app_lower}" in lower:
            return app
    return None


def is_system_framework(binary_or_module: str | None, symbol: str | None = None) -> bool:
    """Return True if the frame belongs to an Apple system framework rather than app code."""
    mod = str(binary_or_module or "").strip()
    sym = str(symbol or "").strip()
    if not mod and not sym:
        return True
    base_mod = mod.rsplit("/", 1)[-1]
    if base_mod in SYSTEM_FRAMEWORK_EXACT or mod in SYSTEM_FRAMEWORK_EXACT:
        return True
    for prefix in SYSTEM_FRAMEWORK_PREFIXES:
        if base_mod.startswith(prefix) or mod.startswith(prefix):
            return True
    if any(base_mod.startswith(app) for app in PERSONAL_APP_PREFIXES):
        return False
    if any(sym.startswith((f"{app}.", f"{app}Core.", f"{app}UI.")) for app in PERSONAL_APP_PREFIXES):
        return False
    return bool(
        sym.startswith((
            "$s7SwiftUI",
            "$s10Foundation",
            " specialized SwiftUI.",
            "objc_msgSend",
            "_dispatch_",
            "start_wqthread",
        ))
    )


def _is_app_owned_frame(app_name: str | None, module: str, symbol: str, file_line: str) -> bool:
    if is_system_framework(module, symbol):
        return False
    base_mod = module.rsplit("/", 1)[-1]
    if any(base_mod.startswith(prefix) for prefix in PERSONAL_APP_PREFIXES):
        return True
    if app_name and (base_mod.startswith(app_name) or symbol.startswith(app_name)):
        return True
    return any(
        symbol.startswith(prefix) or re.match(r"^\$s\d+" + re.escape(prefix), symbol)
        for prefix in PERSONAL_APP_PREFIXES
    )


def _extract_file_line(*candidates: Any) -> str:
    for item in candidates:
        if not item:
            continue
        match = _FILE_LINE_RE.search(str(item))
        if match:
            return f"{match.group(1)}:{match.group(2)}"
    return ""


def extract_responsible_frame(
    frames: Sequence[Mapping[str, Any]],
    *,
    app_name: str | None = None,
) -> ResponsibleFrame:
    """Locate the first top frame belonging to the application module (`file:line` + symbol)."""
    normalized: list[ResponsibleFrame] = []
    for raw in frames:
        if not isinstance(raw, Mapping):
            continue
        module = str(
            raw.get("binaryName")
            or raw.get("module")
            or raw.get("imageName")
            or raw.get("library")
            or raw.get("target")
            or ""
        ).strip()
        symbol = str(
            raw.get("symbol")
            or raw.get("symbolName")
            or raw.get("function")
            or raw.get("rawSymbol")
            or ""
        ).strip()
        explicit_file = str(raw.get("file") or raw.get("fileName") or raw.get("sourceFile") or "").strip()
        explicit_line = raw.get("line") or raw.get("lineNumber") or raw.get("sourceLine")
        combined_file_line = (
            f"{Path(explicit_file).name}:{int(explicit_line)}"
            if explicit_file and isinstance(explicit_line, (int, str)) and str(explicit_line).isdigit()
            else _extract_file_line(explicit_file, symbol, raw.get("description"), raw.get("rawFrame"))
        )
        if not symbol and combined_file_line:
            symbol = combined_file_line
        app_owned = _is_app_owned_frame(app_name, module, symbol, combined_file_line)
        normalized.append(
            ResponsibleFrame(
                module=module or (app_name or "UnknownModule"),
                symbol=symbol or combined_file_line or "unknown_symbol",
                file_line=combined_file_line,
                is_app_owned=app_owned,
            )
        )

    for candidate in normalized:
        if candidate.is_app_owned:
            return candidate
    return ResponsibleFrame(
        module=app_name or "UnknownApp",
        symbol="unknown_symbol",
        file_line="",
        is_app_owned=False,
    )


def _objects(value: Any, depth: int = 0):
    if depth > 64:
        return
    if isinstance(value, Mapping):
        yield value
        for child in value.values():
            yield from _objects(child, depth + 1)
    elif isinstance(value, list):
        for child in value:
            yield from _objects(child, depth + 1)


def _frames(value: Any) -> list[dict[str, Any]]:
    return [dict(node) for node in _objects(value) if
            any(key in node for key in ('binaryName', 'module', 'symbol', 'symbolName', 'imageName'))
            and not any(key in node for key in ('callStackTree', 'callStacks'))]


def _timestamp(value: Any) -> datetime | None:
    if not value:
        return None
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value, timezone(timedelta(0)))
    try:
        parsed = datetime.fromisoformat(str(value).replace('Z', '+00:00'))  # noqa: FURB162 - gate uses Python 3.9
        return parsed.replace(tzinfo=CST) if parsed.tzinfo is None else parsed
    except ValueError:
        for fmt in ('%Y-%m-%d %H:%M:%S.%f %z', '%Y-%m-%d %H:%M:%S %z'):
            try:
                return datetime.strptime(str(value), fmt)
            except ValueError:
                continue
    return None


def _observed_at(*values: Mapping[str, Any]) -> str:
    for value in values:
        for key in ('occurred_at', 'captureTime', 'timestamp', 'timeStampEnd', 'timeStampBegin', 'finishTime', 'date'):
            parsed = _timestamp(value.get(key))
            if parsed:
                return parsed.isoformat()
    return ''


def _app_from_frames(frames: Sequence[Mapping[str, Any]]) -> str | None:
    for frame in frames:
        for key in ('binaryName', 'module', 'imageName', 'symbol', 'symbolName'):
            value = str(frame.get(key) or '')
            app = _canonical_app_name(value)
            if app:
                return app
            for app in PERSONAL_APPS:
                if re.match(r'^\$s\d+' + re.escape(app), value):
                    return app
    return None


def _parsed_finding(app: str, kind: str, source: str, frames: list[dict[str, Any]],
                    payload: Mapping[str, Any], parent: Mapping[str, Any]) -> DiagnosticFinding:
    frame = extract_responsible_frame(frames, app_name=app)
    metadata = payload.get('diagnosticMetaData') or {}
    if not isinstance(metadata, Mapping):
        metadata = {}
    exception = payload.get('exception') or {}
    if not isinstance(exception, Mapping):
        exception = {'type': exception}
    exception_summary = ' / '.join(str(value) for value in (
        payload.get('exceptionType', metadata.get('exceptionType', exception.get('type'))),
        payload.get('exceptionCode', metadata.get('exceptionCode', exception.get('codes'))),
        payload.get('signal', metadata.get('signal', exception.get('signal'))),
        payload.get('terminationReason', metadata.get('terminationReason')),
    ) if value is not None)
    signature = _normalize_signature(app, kind, payload.get('signature'), exception_summary, frame)
    return DiagnosticFinding(
        app_name=app, platform=str(payload.get('platform') or parent.get('platform') or 'unknown'),
        source_kind=source, event_kind=kind, signature=signature,
        responsible_symbol=_safe_evidence(frame.symbol) if frame.is_app_owned else 'unknown_symbol',
        responsible_file_line=frame.file_line if frame.is_app_owned else '',
        exception_summary=_safe_evidence(exception_summary), crash_count_7d=0, new_crash_signature_count=0,
        crash_free_rate_7d=None, p95_metric_ms_7d=None, p95_metric_ms_prev_7d=None,
        p95_regression_pct=0.0, is_perf_regressed=False,
        hang_duration_ms=_parse_duration_ms(payload.get('hangDuration', metadata.get('hangDuration'))),
        is_new_crash_signature=False, actionable_reason='未完成时间窗与历史签名对账',
        occurred_at=_observed_at(payload, parent),
        source_weight=float(payload['weight']) if isinstance(payload.get('weight'), (int, float)) else None,
        stack_summary=tuple(_safe_evidence(f.get('symbol') or f.get('symbolName') or 'unsymbolicated')[:240]
                            for f in frames[:12]),
    )


def _flatten_metrickit_frames(root_frames: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    return _frames(list(root_frames))


def _parse_duration_ms(raw_val: Any) -> float | None:
    if raw_val is None or isinstance(raw_val, bool):
        return None
    if isinstance(raw_val, (int, float)):
        return float(raw_val)
    text = str(raw_val).strip().lower()
    if not text:
        return None
    m_ms = re.match(r"^([0-9]+(?:\.[0-9]+)?)\s*ms$", text)
    if m_ms:
        return float(m_ms.group(1))
    m_sec = re.match(r"^([0-9]+(?:\.[0-9]+)?)\s*s(?:ec(?:onds?)?)?$", text)
    if m_sec:
        return float(m_sec.group(1)) * 1000.0
    try:
        return float(text)
    except ValueError:
        return None


def _safe_evidence(value: Any) -> str:
    text = redact(str(value or ""))
    return re.sub(r"/[^\s)]+\.(?:swift|mm?|cc?|cpp|h)(?::\d+)?|/(?:Users|home)/[^\s)]+",
                  lambda match: Path(match.group()).name, text)[:1000]


def _normalize_signature(
    app_name: str,
    event_kind: str,
    explicit_sig: str | None,
    exception_summary: str,
    frame: ResponsibleFrame,
) -> str:
    if explicit_sig and str(explicit_sig).strip():
        return _safe_evidence(explicit_sig).strip()
    anchor = _safe_evidence(frame.file_line or frame.symbol or "unknown")
    anchor = re.sub(r"0x[0-9a-fA-F]+|\s+\+\s+\d+", "", anchor).strip()
    exc_head = _safe_evidence(exception_summary or event_kind).split(":", 1)[0].strip().replace(" ", "_")
    return f"{app_name}:{event_kind}:{exc_head}@{anchor}"


def parse_metrickit_payload(payload: Mapping[str, Any]) -> list[DiagnosticFinding]:
    """Read MXDiagnosticPayload and individual diagnostics; never infer novelty here."""
    findings = []
    groups = [('crash', payload.get('crashDiagnostics') or []),
              ('hang', payload.get('hangDiagnostics') or [])]
    if not any(group for _, group in groups) and 'callStackTree' in payload:
        metadata = payload.get('diagnosticMetaData') or {}
        kind = 'hang' if 'hangDuration' in payload or 'hangDuration' in metadata else 'crash'
        groups = [(kind, [payload])]
    for kind, diagnostics in groups:
        for diagnostic in diagnostics:
            if not isinstance(diagnostic, Mapping):
                continue
            tree = diagnostic.get('callStackTree') or {}
            stacks = [node for node in _objects(tree) if 'callStackRootFrames' in node]
            stacks.sort(key=lambda node: not bool(node.get('threadAttributed')))
            frames = [frame for stack in stacks for frame in _frames(stack['callStackRootFrames'])]
            app = next((name for node in (diagnostic, diagnostic.get('diagnosticMetaData') or {}, payload)
                        for key in ('app_name', 'applicationName', 'bundleIdentifier')
                        if (name := _canonical_app_name(node.get(key)))), None) or _app_from_frames(frames)
            if app:
                findings.append(_parsed_finding(app, kind, 'metrickit', frames, diagnostic, payload))
    return findings


def parse_asc_diagnostics_payload(payload: Mapping[str, Any]) -> list[DiagnosticFinding]:
    """Read JSON:API signatures and Apple's productData/diagnosticLogs downloads."""
    findings = []
    signatures = {}
    entries = payload.get('diagnosticSignatures') or payload.get('data') or []
    if isinstance(entries, Mapping):
        entries = [entries]
    for entry in entries:
        if isinstance(entry, Mapping):
            signatures[str(entry.get('id') or '')] = entry
    products = payload.get('productData') or []
    for product in products:
        if isinstance(product, Mapping):
            key = str(product.get('signatureId') or '')
            entry = dict(signatures.get(key) or {})
            entry.update(product)
            signatures[key] = entry
    for entry in signatures.values():
        attrs = entry.get('attributes') or entry
        logs = entry.get('diagnosticLogs') or attrs.get('diagnosticLogs') or [entry]
        if not isinstance(logs, list):
            logs = [logs]
        for log in logs:
            if not isinstance(log, Mapping):
                continue
            frames = _frames(log)
            app = (_canonical_app_name(entry.get('app_name') or attrs.get('app_name')
                                       or attrs.get('bundleId') or payload.get('app_name'))
                   or _app_from_frames(frames))
            metadata = log.get('diagnosticMetaData') or {}
            diagnostic_type = str(attrs.get('diagnosticType') or metadata.get('event') or '').upper()
            if not app or not any(kind in diagnostic_type for kind in ('CRASH', 'HANG')):
                continue
            kind = 'hang' if 'HANG' in diagnostic_type else 'crash'
            merged = {**attrs, **log, 'signature': attrs.get('signature') or entry.get('signatureId') or entry.get('id')}
            findings.append(_parsed_finding(app, kind, 'asc', frames, merged, payload))
    return findings


def parse_ips_text(raw_text: str, *, source_name: str = '') -> list[DiagnosticFinding]:
    """Read the JSON stream in an IPS file; do not read process paths or user fields."""
    decoder = json.JSONDecoder()
    objects = []
    text = raw_text.strip()
    try:
        while text:
            value, end = decoder.raw_decode(text)
            if isinstance(value, Mapping):
                objects.append(value)
            text = text[end:].lstrip()
    except ValueError:
        return []
    if not objects:
        return []
    body, header = objects[-1], objects[0]
    app = _canonical_app_name(body.get('procName') or header.get('app_name') or source_name)
    if not app:
        return []
    images = body.get('usedImages') or []
    threads = body.get('threads') or []
    faulting = body.get('faultingThread')
    selected = [thread for index, thread in enumerate(threads) if isinstance(thread, Mapping)
                and (index == faulting or thread.get('triggered'))]
    # Never blame unrelated worker threads when the faulting thread is available.
    if not selected:
        selected = [thread for thread in threads if isinstance(thread, Mapping)]
    frames = []
    for thread in selected:
        for raw in thread.get('frames') or []:
            if not isinstance(raw, Mapping):
                continue
            frame = dict(raw)
            index = frame.get('imageIndex')
            if isinstance(index, int) and 0 <= index < len(images) and isinstance(images[index], Mapping):
                frame['binaryName'] = images[index].get('name') or ''
            frames.append(frame)
    kind = 'hang' if str(header.get('bug_type') or body.get('bug_type')) in {'298', '202', '142'} else 'crash'
    return [_parsed_finding(app, kind, 'ips', frames, body, header)]


def parse_xcresult_summary_payload(payload: Mapping[str, Any]) -> list[DiagnosticFinding]:
    """Read exported crash summaries and xcresulttool testFailures/ActionIssueSummary."""
    findings = []
    for node in _objects(payload):
        for key in ('xcresultCrashes', 'crashes', 'testFailures', 'testFailureSummaries'):
            entries = node.get(key) or []
            if isinstance(entries, Mapping):
                entries = entries.get('_values') or []
            for entry in entries:
                if not isinstance(entry, Mapping):
                    continue
                def scalar(value):
                    return value.get('_value', '') if isinstance(value, Mapping) else value
                message = str(scalar(entry.get('failureText') or entry.get('failureMessage') or entry.get('message')) or '')
                if key not in ('xcresultCrashes', 'crashes') and not re.search(r'crash|EXC_|SIG(?:ABRT|SEGV|TRAP|BUS)', message, re.IGNORECASE):
                    continue
                frames = _frames(entry.get('frames') or [])
                app = (_canonical_app_name(scalar(entry.get('app_name') or entry.get('target')
                                                 or entry.get('targetName') or entry.get('testIdentifier')))
                       or _canonical_app_name(payload.get('app_name')) or _app_from_frames(frames))
                if not app:
                    continue
                if not frames:
                    symbol = str(entry.get('stack_top_symbol') or message)
                    frames = [{'module': app, 'symbol': symbol}]
                findings.append(_parsed_finding(app, 'crash', 'xcresult', frames, entry, payload))
    return findings


def _query_warehouse_crash_and_perf(
    *,
    warehouse_db: Path | None = None,
    query_runner: Callable[[str], tuple[list[tuple[Any, ...]], list[str]]] | None = None,
) -> list[dict[str, Any]]:
    """Run `retro/app_crash_and_perf` against the warehouse or an explicit SQLite DB."""
    if query_runner is not None:
        rows, cols = query_runner("retro/app_crash_and_perf")
    elif warehouse_db is not None:
        if not warehouse_db.is_file():
            return []
        sql_path = QUERIES_DIR / "retro" / "app_crash_and_perf.sql"
        sql = sql_path.read_text(encoding="utf-8")
        conn = sqlite3.connect(f"{warehouse_db.resolve().as_uri()}?mode=ro", uri=True)
        try:
            cur = conn.execute(sql)
            rows = cur.fetchall()
            cols = [d[0] for d in cur.description] if cur.description else []
        finally:
            conn.close()
    else:
        rows, cols = serve.run_query("retro/app_crash_and_perf")

    col_idx = {name: idx for idx, name in enumerate(cols)}
    results: list[dict[str, Any]] = []
    for row in rows:
        item = {name: row[idx] for name, idx in col_idx.items()}
        results.append(item)
    return results


def _read_diagnostic_json(path: Path) -> Any:
    if path.stat().st_size > 16_000_000:
        raise ValueError('diagnostic payload exceeds size limit')
    return json.loads(path.read_text(encoding='utf-8'))


def _scan_diagnostics_dir(diagnostics_dir: Path, errors: list[str] | None = None) -> list[DiagnosticFinding]:
    errors = errors if errors is not None else []
    if not diagnostics_dir.is_dir():
        return []
    findings = []
    for path in sorted(diagnostics_dir.iterdir()):
        if path.is_symlink():
            continue
        try:
            if path.is_dir() and path.suffix == '.xcresult':
                # A fixture/exported summary is portable; xcresulttool reads real bundles without launching tests.
                summary_path = path / 'summary.json'
                if summary_path.is_file():
                    payload = _read_diagnostic_json(summary_path)
                else:
                    result = subprocess.run(
                        ['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(path), '--compact'],
                        capture_output=True, text=True, timeout=30, check=True,
                    )
                    payload = json.loads(result.stdout)
                parsed = parse_xcresult_summary_payload(payload)
            elif path.is_file() and path.suffix == '.ips':
                if not any(app.lower() in path.name.lower() for app in PERSONAL_APPS):
                    continue
                if path.stat().st_size > 16_000_000:
                    raise ValueError('diagnostic payload exceeds size limit')
                parsed = parse_ips_text(path.read_text(encoding='utf-8'), source_name=path.stem)
            elif path.is_file() and path.suffix == '.json':
                payload = _read_diagnostic_json(path)
                if not isinstance(payload, Mapping):
                    raise ValueError('diagnostic payload must be an object')
                hint = _canonical_app_name(path.stem)
                if hint and not payload.get('app_name'):
                    payload = {**payload, 'app_name': hint}
                parsed = _parse_any_diagnostic_dict(payload)
            else:
                continue
            mtime = datetime.fromtimestamp(path.stat().st_mtime, timezone(timedelta(0))).isoformat()
            findings.extend(replace(item, occurred_at=item.occurred_at or mtime) for item in parsed)
        except (OSError, ValueError, TypeError, subprocess.SubprocessError):
            errors.append(f'{path.suffix or "file"}: unreadable diagnostic payload')
    return findings


def _parse_any_diagnostic_dict(obj: Mapping[str, Any]) -> list[DiagnosticFinding]:
    results = []
    if any(key in obj for key in ('crashDiagnostics', 'hangDiagnostics', 'callStackTree')):
        results.extend(parse_metrickit_payload(obj))
    if any(key in obj for key in ('diagnosticSignatures', 'data', 'productData')):
        results.extend(parse_asc_diagnostics_payload(obj))
    if any(key in node for node in _objects(obj) for key in ('xcresultCrashes', 'crashes', 'testFailures', 'testFailureSummaries')):
        results.extend(parse_xcresult_summary_payload(obj))
    if 'procName' in obj and 'threads' in obj:
        results.extend(parse_ips_text(json.dumps(obj)))
    return results


def _compute_signature_hash(payload: Any) -> str:
    serialized = json.dumps(payload, ensure_ascii=False, sort_keys=True, default=str)
    return hashlib.sha256(serialized.encode("utf-8")).hexdigest()[:16]


def _sanitize_human_zone_text(text: str) -> str:
    """Ensure no raw hex SHA, UUID, or internal metric code leaks into the Upper Zone."""
    cleaned = _UUID_RE.sub("标识", str(text or ""))
    cleaned = _INTERNAL_CODE_RE.sub("指标", cleaned)

    def _replace_hex(match: re.Match[str]) -> str:
        tok = match.group(0)
        if any(ch in "abcdef" for ch in tok) or len(tok) >= 12:
            return "摘要"
        return tok

    return _HEX_SHA_RE.sub(_replace_hex, cleaned)


def verify_dual_zone_markdown(markdown_text: str, *, max_human_lines: int = 15) -> dict[str, Any]:
    """Verify Dual-Zone issue markdown using `verify_issue_format.py` (with identical built-in fallback)."""
    user_skills_verifier = (
        HOME / "Development" / "user-skills" / "skills" / "issue-brief" / "scripts" / "verify_issue_format.py"
    )
    if user_skills_verifier.is_file():
        spec = importlib.util.spec_from_file_location("aidata_issue_brief_verifier", user_skills_verifier)
        if spec and spec.loader:
            mod = importlib.util.module_from_spec(spec)
            old_flag = sys.dont_write_bytecode
            try:
                sys.dont_write_bytecode = True
                spec.loader.exec_module(mod)
                return dict(mod.verify_dual_zone_issue(markdown_text, max_human_lines=max_human_lines))
            finally:
                sys.dont_write_bytecode = old_flag

    text = str(markdown_text or "")
    violations: list[dict[str, Any]] = []
    cursor_matches = _CURSOR_RE.findall(text)
    cursor_value = cursor_matches[0].strip() if cursor_matches else None
    if not cursor_value:
        violations.append({"code": "missing-cursor", "message": "Missing <!-- multica-cursor:... --> watermark."})

    details_match = _DETAILS_OPEN_RE.search(text)
    all_opens = list(_DETAILS_ANY_OPEN_RE.finditer(text))
    all_closes = list(_DETAILS_CLOSE_RE.finditer(text))
    if details_match is None:
        violations.append({"code": "missing-ai-details", "message": "Missing canonical <details> block."})
        upper_raw = text
    else:
        if len(all_opens) != len(all_closes) or all_closes[-1].start() < details_match.end():
            violations.append({"code": "unbalanced-details", "message": "Unbalanced <details> tags."})
        upper_raw = text[: details_match.start()]
        close_after = [m for m in all_closes if m.start() >= details_match.end()]
        lower_raw = text[details_match.end() : close_after[-1].start()] if close_after else ""
        if not lower_raw.strip():
            violations.append({"code": "empty-ai-context", "message": "Empty lower <details> block."})

    upper_without_comments = _HTML_COMMENT_BLOCK_RE.sub("", upper_raw)
    human_visible_lines: list[tuple[int, str]] = []
    in_fence = False
    fence_detected = False
    for line_no, raw_line in enumerate(upper_without_comments.splitlines(), 1):
        stripped = raw_line.strip()
        if _FENCE_RE.match(raw_line):
            fence_detected = True
            in_fence = not in_fence
            human_visible_lines.append((line_no, stripped))
            continue
        if not stripped or _HTML_COMMENT_LINE_RE.match(raw_line) or re.fullmatch(r"-{3,}|\*{3,}|_{3,}", stripped):
            continue
        human_visible_lines.append((line_no, stripped))

    if len(human_visible_lines) > max_human_lines:
        violations.append({"code": "human-zone-line-budget", "human_zone_lines": len(human_visible_lines)})
    if fence_detected or in_fence:
        violations.append({"code": "human-zone-fenced-code"})
    if not any(_TLDR_RE.match(line) for _, line in human_visible_lines):
        violations.append({"code": "missing-tldr"})
    checkbox_count = sum(1 for _, line in human_visible_lines if _CHECKBOX_ITEM_RE.match(line))
    if checkbox_count == 0:
        violations.append({"code": "missing-checkable-items"})

    for line_no, line in human_visible_lines:
        if _INTERNAL_CODE_RE.search(line):
            violations.append({"code": "human-zone-internal-code", "line": line_no})
        if _UUID_RE.search(line):
            violations.append({"code": "human-zone-uuid", "line": line_no})
        else:
            sha_hits = [
                tok for tok in _HEX_SHA_RE.findall(line)
                if any(ch in "abcdef" for ch in tok) or len(tok) >= 12
            ]
            if sha_hits:
                violations.append({"code": "human-zone-commit-sha", "line": line_no, "tokens": sha_hits})
        if _CLI_COMMAND_RE.search(line):
            violations.append({"code": "human-zone-cli-command", "line": line_no})
        if _MARKDOWN_TABLE_ROW_RE.match(line):
            violations.append({"code": "human-zone-markdown-table", "line": line_no})

    return {
        "ok": len(violations) == 0,
        "human_zone_lines": len(human_visible_lines),
        "max_human_lines": max_human_lines,
        "checkbox_count": checkbox_count,
        "cursor": cursor_value,
        "violations": violations,
    }


def render_dual_zone_bug_issue(
    *,
    target_date: str,
    tldr: str,
    items: Sequence[Mapping[str, str]],
    findings: Sequence[DiagnosticFinding],
    watermark: str,
    jev_verdict: Mapping[str, Any] | None = None,
) -> str:
    """Render a Dual-Zone Bug Repair issue compliant with `verify_issue_format.py`."""
    cursor = f"{LOOP_ID}-{target_date}"
    clean_tldr = _sanitize_human_zone_text(tldr)
    lines: list[str] = [
        f"<!-- multica-cursor:{cursor} -->",
        "",
        f"**一句话结论**：{clean_tldr}",
        "",
    ]

    bounded_items = list(items)[:6]
    if not bounded_items:
        bounded_items = [
            {
                "what": "核查今日个人应用崩溃与性能监控巡检结果",
                "why": "保持线上版本无新增崩溃签名且启动与交互耗时稳定",
            }
        ]

    for idx, item in enumerate(bounded_items, 1):
        what = _sanitize_human_zone_text(str(item.get("what") or "修复线上质量退化项").strip())
        why = _sanitize_human_zone_text(str(item.get("why") or "消除新增崩溃或性能退化").strip())
        lines.append(f"- [ ] {idx}. {what} — {why}")

    table_lines = [
        "### 1. 责任帧与签名汇总表",
        "",
        "| 应用 | 平台 | 来源 | 类型 | 签名 | 责任帧 (`file:line`) | 7d 新签名数 | P95 当前(ms) | P95 基线(ms) | 退化幅度 |",
        "|---|---|---|---|---|---|---:|---:|---:|---:|",
    ]
    for f in findings:
        p95_cur = f"{f.p95_metric_ms_7d:.1f}" if f.p95_metric_ms_7d is not None else "—"
        p95_prev = f"{f.p95_metric_ms_prev_7d:.1f}" if f.p95_metric_ms_prev_7d is not None else "—"
        reg_str = f"{f.p95_regression_pct:+.1f}%" if f.p95_regression_pct else "0.0%"
        table_lines.append(
            f"| `{f.app_name}` | `{f.platform}` | `{f.source_kind}` | `{f.event_kind}` | "
            f"`{f.signature}` | `{f.responsible_file_line}` | {f.new_crash_signature_count} | "
            f"{p95_cur} | {p95_prev} | {reg_str} |"
        )

    payload_json = json.dumps(
        {
            "loop_id": LOOP_ID,
            "date": target_date,
            "watermark": watermark,
            "findings": [asdict(f) for f in findings],
            "jev": dict(jev_verdict) if isinstance(jev_verdict, Mapping) else None,
        },
        ensure_ascii=False,
        indent=2,
    )

    lines.extend([
        "",
        CANONICAL_DETAILS_OPEN,
        "",
        "\n".join(table_lines),
        "",
        "### 2. 结构化诊断载荷",
        "",
        f"```json\n{payload_json}\n```",
        "",
        "</details>",
        "",
    ])
    rendered = "\n".join(lines)
    verification = verify_dual_zone_markdown(rendered)
    if not verification["ok"]:
        raise ValueError(f"Dual-Zone Bug issue failed format verification: {verification['violations']}")
    return rendered


def collect_crash_and_metrickit_diagnostics(
    *, target_date: date | str | None = None, diagnostics_dir: Path | None = None,
    warehouse_db: Path | None = None,
    fixture_json: Path | Mapping[str, Any] | Sequence[Mapping[str, Any]] | None = None,
    query_runner: Callable[[str], tuple[list[tuple[Any, ...]], list[str]]] | None = None,
    seen_signatures: Sequence[str] = (),
) -> dict[str, Any]:
    """Read-only L0. Undated diagnostics are evidence, not proof of seven-day novelty.

    SQL keeps its canonical latest-observation anchor; raw reports use the requested
    seven CST calendar days. Neither sample-based crash-free rate nor a single hang
    is promoted into a session crash-free metric or a P95 estimate.
    """
    day = (target_date if isinstance(target_date, date) else date.fromisoformat(target_date)
           if target_date and target_date != 'today' else datetime.now(CST).date())
    date_str = day.isoformat()
    end = datetime.combine(day + timedelta(days=1), datetime.min.time(), CST)
    start = end - timedelta(days=7)
    errors: list[str] = []
    raw_findings: list[DiagnosticFinding] = []
    diagnostics_status = 'missing'
    if fixture_json is not None:
        loaded = _read_diagnostic_json(Path(fixture_json)) if isinstance(fixture_json, (str, Path)) else fixture_json
        entries = [loaded] if isinstance(loaded, Mapping) else loaded
        for entry in entries:
            if isinstance(entry, Mapping):
                raw_findings.extend(_parse_any_diagnostic_dict(entry))
        diagnostics_status = 'ok'
    else:
        directories = (Path(diagnostics_dir).expanduser(),) if diagnostics_dir is not None else DEFAULT_DIAGNOSTICS_DIRS
        for directory in directories:
            if directory.is_dir():
                diagnostics_status = 'ok'
                try:
                    raw_findings.extend(_scan_diagnostics_dir(directory, errors))
                except OSError:
                    errors.append('diagnostics directory unreadable')
    warehouse_status = 'missing'
    warehouse_rows = []
    try:
        if fixture_json is not None and query_runner is None and warehouse_db is None:
            warehouse_status = 'not_requested'
        elif warehouse_db is not None and not Path(warehouse_db).is_file():
            warehouse_status = 'missing'
        else:
            warehouse_rows = _query_warehouse_crash_and_perf(warehouse_db=warehouse_db, query_runner=query_runner)
            warehouse_status = 'ok' if warehouse_rows else 'empty'
    except (OSError, sqlite3.Error, ValueError):
        errors.append('warehouse crash/perf query unavailable')
        warehouse_status = 'error'

    def identity(finding):
        return json.dumps([finding.app_name, finding.event_kind, finding.signature], separators=(',', ':'))

    prior = set(seen_signatures)
    for finding in raw_findings:
        observed = _timestamp(finding.occurred_at)
        if observed and observed < start:
            prior.add(identity(finding))
    known_warehouse = {(str(row.get('app_name')), str(row.get('signature')))
                       for row in warehouse_rows if int(row.get('new_crash_signature_count') or 0) == 0}
    findings = []
    seen_all = set(seen_signatures)
    for finding in raw_findings:
        observed = _timestamp(finding.occurred_at)
        if not observed:
            errors.append('diagnostic timestamp missing; novelty unknown')
        elif observed >= end:
            continue
        recent = bool(observed and start <= observed < end)
        key = identity(finding)
        is_new = (recent and finding.event_kind == 'crash' and key not in prior
                  and (finding.app_name, finding.signature) not in known_warehouse)
        if observed and observed < end:
            seen_all.add(key)
        findings.append(replace(finding, is_new_crash_signature=bool(is_new),
                                new_crash_signature_count=int(bool(is_new)),
                                crash_count_7d=int(recent and finding.event_kind == 'crash'),
                                actionable_reason='七日内首次观测的原始诊断签名' if is_new else '历史或未对账诊断'))
    for row in warehouse_rows:
        app = _canonical_app_name(row.get('app_name'))
        if not app:
            continue
        new_count = max(0, int(row.get('new_crash_signature_count') or 0))
        current = row.get('p95_metric_ms_7d')
        previous = row.get('p95_metric_ms_prev_7d')
        regression = (100.0 * (float(current) - float(previous)) / float(previous)
                      if current is not None and previous is not None and float(previous) > 0 else None)
        signature = str(row.get('signature') or '')
        symbol = _safe_evidence(row.get('stack_top_symbol'))
        for kind in ('crash', 'perf'):
            if kind == 'crash' and not int(row.get('crash_count_7d') or 0) and not new_count:
                continue
            if kind == 'perf' and (regression is None or regression <= P95_REGRESSION_THRESHOLD_PCT):
                continue
            frame = ResponsibleFrame(app, symbol, _extract_file_line(symbol), True)
            sig = _normalize_signature(app, kind, signature, '', frame)
            findings.append(DiagnosticFinding(
                app_name=app, platform=str(row.get('platform') or 'unknown'), source_kind='warehouse',
                event_kind=kind, signature=sig, responsible_symbol=symbol,
                responsible_file_line=frame.file_line, exception_summary='L4 七日窗口聚合',
                crash_count_7d=int(row.get('crash_count_7d') or 0) if kind == 'crash' else 0,
                new_crash_signature_count=new_count if kind == 'crash' else 0,
                crash_free_rate_7d=row.get('crash_free_rate_7d'), p95_metric_ms_7d=current,
                p95_metric_ms_prev_7d=previous, p95_regression_pct=regression or 0.0,
                is_perf_regressed=kind == 'perf', hang_duration_ms=None,
                is_new_crash_signature=kind == 'crash' and new_count > 0,
                actionable_reason='L4 新崩溃签名' if kind == 'crash' else '同签名七日 P95 退化超过百分之二十',
            ))
    by_key = {}
    for finding in findings:
        key = identity(finding)
        existing = by_key.get(key)
        if existing and finding.source_kind == 'warehouse':
            # L4's historical/new flag is authoritative when the signature matches.
            finding = replace(finding, responsible_symbol=existing.responsible_symbol or finding.responsible_symbol,
                              responsible_file_line=existing.responsible_file_line or finding.responsible_file_line,
                              stack_summary=existing.stack_summary)
        by_key[key] = finding
    findings = sorted(by_key.values(), key=lambda finding: (finding.app_name, finding.event_kind, finding.signature))
    actionable = [finding for finding in findings if finding.is_new_crash_signature or finding.is_perf_regressed]
    # An L4 row represents all new signatures for an app, not an additional per-call row.
    counts = {}
    for finding in actionable:
        if finding.event_kind == 'crash':
            raw_count, warehouse_count = counts.get(finding.app_name, (0, 0))
            if finding.source_kind == 'warehouse':
                warehouse_count = max(warehouse_count, finding.new_crash_signature_count)
            else:
                raw_count += 1
            counts[finding.app_name] = raw_count, warehouse_count
    new_total = sum(max(counts_) for counts_ in counts.values())
    perf_count = sum(finding.event_kind == 'perf' for finding in actionable)
    max_regression = max((finding.p95_regression_pct for finding in actionable if finding.is_perf_regressed), default=0.0)
    coverage = ('error' if errors else 'healthy' if warehouse_status == 'ok' else
                'partial' if raw_findings else 'missing')
    summary = (f'发现 {new_total} 个七日内新崩溃签名和 {perf_count} 项超过百分之二十的高分位耗时退化。'
               if actionable else '已读取的诊断中未发现新增异常；数据覆盖不足，不能判断整体线上质量。'
               if coverage != 'healthy' else '已采集窗口未发现新崩溃签名或超过百分之二十的高分位耗时退化。')
    items = []
    for finding in actionable[:6]:
        items.append({'what': '定位并修复新增崩溃' if finding.event_kind == 'crash' else '定位并修复高分位耗时退化',
                      'why': '依据折叠区责任帧和已观测证据验证修复，未符号化帧需先补充符号'})
    watermark = f'{LOOP_ID}:' + _compute_signature_hash([
        (finding.app_name, finding.event_kind, finding.signature, finding.new_crash_signature_count,
         round(finding.p95_regression_pct, 2)) for finding in actionable])
    markdown = render_dual_zone_bug_issue(target_date=date_str, tldr=summary, items=items,
                                         findings=actionable, watermark=watermark) if actionable else ''
    return {
        'ok': True, 'loop_id': LOOP_ID, 'date': date_str,
        'has_delta': bool(actionable), 'delta_count': len(actionable),
        'new_crash_signature_count': new_total, 'perf_regressed_count': perf_count,
        'max_p95_regression_pct': max_regression, 'severity': 'high' if new_total else 'medium' if perf_count else 'low',
        'watermark': watermark, 'cursor': f'{LOOP_ID}-{date_str}',
        'title': f'{date_str} 个人应用线上崩溃与性能退化修复清单',
        'summary': summary, 'items': items, 'dual_zone_markdown': markdown,
        'findings': [asdict(finding) for finding in actionable],
        'all_findings': [asdict(finding) for finding in findings],
        'coverage_status': coverage, 'errors': sorted(set(errors)),
        'raw': {'warehouse_status': warehouse_status, 'diagnostics_status': diagnostics_status,
                'warehouse_app_count': len(warehouse_rows), 'source_as_of': max(
                    (finding.occurred_at for finding in raw_findings), default=None),
                'raw_window_start': start.isoformat(), 'raw_window_end_exclusive': end.isoformat(),
                'warehouse_window_anchor': 'latest observed cst_day (canonical L4 query)',
                'seen_signatures': sorted(seen_all)},
    }


def _extract_prob(raw: Any, field: str) -> float | None:
    if isinstance(raw, Mapping):
        raw = raw.get(field, raw.get("value"))
    if isinstance(raw, bool) or raw is None:
        return None
    try:
        val = float(raw)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(val) or val < 0.0 or val > 1.0:
        return None
    return val


def _load_local_module(name: str, relative: str):
    path = HOME / 'Development' / 'user-skills' / 'skills' / relative
    if not path.is_file():
        return None
    if name in sys.modules:
        return sys.modules[name]
    module_spec = importlib.util.spec_from_file_location(name, path)
    if module_spec is None or module_spec.loader is None:
        return None
    module = importlib.util.module_from_spec(module_spec)
    sys.modules[name] = module
    try:
        module_spec.loader.exec_module(module)
    except (OSError, ImportError):
        sys.modules.pop(name, None)
        return None
    return module


def _call_falcon_systemone(state: Mapping[str, Any], questions: Mapping[str, Mapping[str, Any]],
                         *, timeout_sec: float = 1.5, mock_response: Any = None) -> dict[str, Any] | None:
    candidate = mock_response if mock_response is not None else os.environ.get('GTT_JEV_MOCK_JSON')
    if candidate is not None:
        try:
            if isinstance(candidate, Mapping):
                return dict(candidate)
            if str(candidate).lstrip().startswith('{'):
                parsed = json.loads(str(candidate))
            else:
                parsed = _read_diagnostic_json(Path(candidate).expanduser())
            return dict(parsed) if isinstance(parsed, Mapping) else None
        except (OSError, ValueError, TypeError):
            return None
    if 'pytest' in sys.modules and os.environ.get('GTT_JEV_LIVE') != '1':
        return None
    client = _load_local_module('aidata_crash_jev', 'team-lead/scripts/jev_client.py')
    if client:
        return client.jev_decide(state=dict(state), questions=dict(questions), agent_role='retro-loop',
                                 goal_id=LOOP_ID, timeout_sec=timeout_sec, falcon_only=True)
    # No local credentials/client in CI: use the deterministic verdict, never an unauthenticated remote fallback.
    return None


def evaluate_jev_decision(
    collected: Mapping[str, Any],
    *,
    mock_jev_json: Any = None,
    jev_fn: Callable[..., dict[str, Any] | None] | None = None,
) -> dict[str, Any]:
    """Layer 1: Jev fast-thinking judgment (`>0.70` actionable, `<0.30` ignore, `0.30..0.70` deterministic fallback)."""
    new_crashes = int(collected.get("new_crash_signature_count") or 0)
    max_reg_pct = float(collected.get("max_p95_regression_pct") or 0.0)
    perf_regressed_count = int(collected.get("perf_regressed_count") or 0)
    deterministic_fallback_actionable = bool(
        new_crashes > 0
        or max_reg_pct > P95_REGRESSION_THRESHOLD_PCT
    )
    default_route = "dual_zone_issue"

    questions = {
        "actionable_probability": {
            "type": "noul",
            "instructions": (
                "Is this Apple Crash / MetricKit diagnostic delta concrete and severe enough "
                "to file a Dual-Zone Bug Repair issue or trigger an Autopilot today?"
            ),
        },
        "delivery_route": {
            "type": "choice",
            "instructions": "Choose the lightest sufficient delivery route for this crash/perf regression.",
            "criteria": {
                "dual_zone_issue": "Materialize a Dual-Zone Bug Repair issue with top app responsible frame file:line.",
                "autopilot_trigger": "Trigger the registered Multica Autopilot for deeper multi-repo synthesis.",
                "ignore": "Benign noise or non-actionable fluctuation; do not wake an agent or open an issue.",
            },
        },
        "delivery_route_match": {
            "type": "noul",
            "instructions": "Does the selected delivery_route accurately match the severity of the crash/perf delta?",
        },
        "urgency_score": {
            "type": "score",
            "instructions": "Score urgency from 0.0 (benign) to 1.0 (critical user-facing crash or severe hang).",
        },
    }
    state_payload = {
        "loop_id": LOOP_ID,
        "date": collected.get("date"),
        "new_crash_signature_count": new_crashes,
        "perf_regressed_count": perf_regressed_count,
        "max_p95_regression_pct": max_reg_pct,
        "summary": str(collected.get("summary") or "")[:300],
        "findings": list(collected.get("findings") or [])[:5],
    }

    if jev_fn is not None:
        response = jev_fn(
            state=state_payload,
            questions=questions,
            mock_response=mock_jev_json,
            falcon_only=True,
            timeout_sec=1.5,
        )
    else:
        response = _call_falcon_systemone(
            state_payload,
            questions,
            mock_response=mock_jev_json,
        )

    if not isinstance(response, Mapping) or response.get("fallback_reason"):
        return {
            "actionable": deterministic_fallback_actionable,
            "route": default_route if deterministic_fallback_actionable else "ignore",
            "probability": None,
            "urgency_score": None,
            "decision_source": "deterministic_fallback_unavailable",
        }

    answers = response.get("answers", response)
    if not isinstance(answers, Mapping):
        return {
            "actionable": deterministic_fallback_actionable,
            "route": default_route if deterministic_fallback_actionable else "ignore",
            "probability": None,
            "urgency_score": None,
            "decision_source": "deterministic_fallback_malformed",
        }

    prob = _extract_prob(answers.get("actionable_probability"), "noul")
    route_raw = answers.get("delivery_route")
    if isinstance(route_raw, Mapping):
        route_raw = route_raw.get("choice")
    route_match = _extract_prob(answers.get("delivery_route_match"), "noul")
    urgency = _extract_prob(answers.get("urgency_score"), "score")

    valid_route = (
        str(route_raw)
        if isinstance(route_raw, str)
        and route_raw in {"dual_zone_issue", "autopilot_trigger", "ignore"}
        and route_match is not None and route_match >= 0.50
        else default_route
    )

    if prob is None:
        return {
            "actionable": deterministic_fallback_actionable,
            "route": default_route if deterministic_fallback_actionable else "ignore",
            "probability": None,
            "urgency_score": urgency,
            "decision_source": "deterministic_fallback_missing_prob",
        }

    if route_raw == "ignore" and route_match is not None and route_match >= 0.50 and prob <= 0.70:
        return {
            "actionable": False,
            "route": "ignore",
            "probability": prob,
            "urgency_score": urgency,
            "decision_source": "jev_choice_ignore",
        }

    if prob > 0.70:
        chosen = default_route if valid_route == "ignore" else valid_route
        return {
            "actionable": True,
            "route": chosen,
            "probability": prob,
            "urgency_score": urgency,
            "decision_source": "jev_high_confidence",
        }

    if prob < 0.30:
        return {
            "actionable": False,
            "route": "ignore",
            "probability": prob,
            "urgency_score": urgency,
            "decision_source": "jev_low_confidence_reject",
        }

    return {
        "actionable": deterministic_fallback_actionable,
        "route": (default_route if valid_route == "ignore" else valid_route) if deterministic_fallback_actionable else "ignore",
        "probability": prob,
        "urgency_score": urgency,
        "decision_source": "jev_grey_zone_fallback",
    }


def _resolve_multica_bin(explicit: str | None = None) -> str:
    if explicit:
        return explicit
    env_bin = os.environ.get("MULTICA_BIN")
    if env_bin:
        return env_bin
    if Path("/opt/homebrew/bin/multica").is_file():
        return "/opt/homebrew/bin/multica"
    return shutil.which("multica") or "/opt/homebrew/bin/multica"


def _default_multica_runner(
    args: Sequence[str],
    *,
    stdin_text: str | None = None,
    multica_bin: str | None = None,
    server_url: str | None = None,
    workspace_id: str | None = None,
) -> subprocess.CompletedProcess[str]:
    binary = _resolve_multica_bin(multica_bin)
    cmd = [binary]
    if server_url:
        cmd.extend(["--server-url", server_url])
    if workspace_id:
        cmd.extend(["--workspace-id", workspace_id])
    cmd.extend(args)
    env = dict(os.environ)
    if server_url:
        env["MULTICA_SERVER_URL"] = server_url
    if workspace_id:
        env["MULTICA_WORKSPACE_ID"] = workspace_id
    return subprocess.run(  # nosec B603
        cmd,
        input=stdin_text,
        capture_output=True,
        text=True,
        env=env,
        check=False,
        timeout=30,
    )


def _parse_multica_json(proc: subprocess.CompletedProcess[str], context: str) -> Any:
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        raise RuntimeError(f"multica {context} failed (exit {proc.returncode}): {detail}")
    raw = (proc.stdout or "").strip()
    if not raw:
        return {}
    return json.loads(raw)


def build_autopilot_description() -> str:
    return (
        f'# {AUTOPILOT_TITLE}\n\n- **Loop ID**: `{LOOP_ID}`\n\n'
        'Scheduled precheck (read-only diagnostics, 0-Agent before actionable evidence):\n'
        '```bash\ncd "$HOME/Development/AIDash/aidata" && '
        'python3 -m L5_apps.digest.apple_crash_metrickit_loop run --json\n```\n\n'
        'If explicitly triggered for synthesis, do NOT rerun the pipeline or trigger this autopilot recursively. '
        f'Read `$HOME/.cache/multica-loop-runner/{LOOP_ID}-collect.json`, '
        'verify symbolication, seven-day novelty and matched-signature P95 baseline, '
        'then file/update the verified Dual-Zone Bug issue for the configured Owner. '
        'Do not include device identifiers, absolute source paths or complete raw crash payloads.\n'
    )


def _multica_settings(server_url: str = '', workspace_id: str = '', owner_id: str = '', agent_id: str = '') -> dict[str, str]:
    import config
    local = {}
    path = HOME / '.multica' / 'config.json'
    if path.is_file():
        try:
            local = json.loads(path.read_text(encoding='utf-8'))
        except (OSError, ValueError):
            pass
    if not isinstance(local, Mapping):
        local = {}
    # Identity stays in ignored runtime config or installed operator tooling, never in this public module.
    hub = _load_local_module('aidata_crash_loop_hub', 'team-lead/scripts/multica_loop_runner.py')
    settings = {}
    for key, explicit, default_name in (
        ('server_url', server_url, 'DEFAULT_SERVER_URL'), ('workspace_id', workspace_id, 'DEFAULT_WORKSPACE_ID'),
        ('owner_id', owner_id, 'DEFAULT_OWNER_ID'), ('agent_id', agent_id, 'DEFAULT_AGENT_ID'),
    ):
        settings[key] = str(explicit or os.environ.get('MULTICA_' + key.upper())
                            or getattr(config, 'MULTICA_' + key.upper(), '') or local.get(key)
                            or getattr(hub, default_name, '') or '')
    return settings


def _registry_rows(value: Any, key: str) -> list[Mapping[str, Any]]:
    rows = value.get(key, []) if isinstance(value, Mapping) else value
    return [row for row in rows if isinstance(row, Mapping)] if isinstance(rows, list) else []


def _find_autopilot(runner, options) -> str | None:
    rows = _registry_rows(_parse_multica_json(runner(['autopilot', 'list', '--output', 'json'], **options),
                                            'autopilot list'), 'autopilots')
    return next((str(row['id']) for row in rows if row.get('id') and
                 (row.get('title') == AUTOPILOT_TITLE or f'`{LOOP_ID}`' in str(row.get('description') or ''))), None)


def sync_autopilot(
    *, server_url: str = DEFAULT_SERVER_URL, workspace_id: str = DEFAULT_WORKSPACE_ID,
    agent_id: str = DEFAULT_AGENT_ID, subscriber_id: str = DEFAULT_OWNER_ID,
    tz_name: str = AUTOPILOT_TIMEZONE, dry_run: bool = False,
    runner: Callable[..., subprocess.CompletedProcess[str]] = _default_multica_runner,
    multica_bin: str | None = None,
) -> dict[str, Any]:
    if dry_run:
        return {'ok': True, 'action': 'dry_run', 'loop_id': LOOP_ID, 'title': AUTOPILOT_TITLE,
                'cron': AUTOPILOT_CRON, 'timezone': tz_name}
    settings = _multica_settings(server_url, workspace_id, subscriber_id, agent_id)
    if not all(settings.values()):
        raise RuntimeError('Multica runtime identity missing; configure local MULTICA_* values')
    options = {'server_url': settings['server_url'], 'workspace_id': settings['workspace_id'], 'multica_bin': multica_bin}
    autopilot_id = _find_autopilot(runner, options)
    action = 'updated' if autopilot_id else 'created'
    command = ['autopilot', 'update', autopilot_id] if autopilot_id else ['autopilot', 'create']
    command += ['--title', AUTOPILOT_TITLE, '--agent', settings['agent_id'], '--mode', 'run_only',
                '--description', build_autopilot_description(), '--subscriber', settings['owner_id'], '--output', 'json']
    if autopilot_id:
        command += ['--status', 'active']
    response = _parse_multica_json(runner(command, **options), 'autopilot ' + action)
    autopilot_id = autopilot_id or str(response.get('id') or (response.get('autopilot') or {}).get('id') or '')
    if not autopilot_id:
        raise RuntimeError('Autopilot create returned no ID')
    triggers = _registry_rows(_parse_multica_json(
        runner(['autopilot', 'trigger-list', autopilot_id, '--output', 'json'], **options), 'trigger-list'), 'triggers')
    schedules = [row for row in triggers if row.get('kind') == 'schedule']
    sched = schedules[0] if schedules else None
    fields = ['--cron', AUTOPILOT_CRON, '--timezone', tz_name, '--label', AUTOPILOT_TRIGGER_LABEL, '--output', 'json']
    if sched is None:
        _parse_multica_json(runner(['autopilot', 'trigger-add', autopilot_id, '--kind', 'schedule', *fields], **options), 'trigger-add')
        trigger_action = 'created'
    elif (sched.get('cron') != AUTOPILOT_CRON or sched.get('timezone') != tz_name or not sched.get('enabled', True)):
        _parse_multica_json(runner(['autopilot', 'trigger-update', autopilot_id, str(sched['id']),
                                   '--enabled=true', *fields], **options), 'trigger-update')
        trigger_action = 'updated'
    else:
        trigger_action = 'kept'
    for duplicate in schedules[1:]:
        _parse_multica_json(runner(['autopilot', 'trigger-delete', autopilot_id, str(duplicate['id']), '--output', 'json'], **options), 'trigger-delete')
    return {'ok': True, 'loop_id': LOOP_ID, 'autopilot_id': autopilot_id, 'title': AUTOPILOT_TITLE,
            'action': action, 'trigger_action': trigger_action, 'cron': AUTOPILOT_CRON, 'timezone': tz_name}


def _load_watermarks(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return dict(data) if isinstance(data, Mapping) else {}
    except (OSError, ValueError):
        return {}


def _save_watermarks(state: Mapping[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=path.parent, delete=False) as handle:
        temporary = Path(handle.name)
        try:
            json.dump(dict(state), handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.flush()
            os.fsync(handle.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


@contextmanager
def _loop_lock(path: Path, dry_run: bool):
    if dry_run:
        yield
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix('.lock').open('a') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RuntimeError('another Loop 6B tick holds the state lease') from exc
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def _deliver_issue(collected, markdown, owner_id, runner, options):
    hub = _load_local_module('aidata_crash_loop_hub', 'team-lead/scripts/multica_loop_runner.py')
    if hub is not None:
        return hub.upsert_multica_dual_zone_issue(
            title=collected['title'], description=markdown, cursor=collected['cursor'], assignee_id=owner_id,
            priority='medium', status='todo', runner=runner, **options)
    listed = _parse_multica_json(runner(['issue', 'list', '--limit', '100', '--output', 'json'], **options), 'issue list')
    token = f"multica-cursor:{collected['cursor']}"
    existing = next((row for row in _registry_rows(listed, 'issues') if
                     row.get('status') not in ('cancelled', 'canceled') and
                     (token in str(row.get('description') or '') or row.get('title') == collected['title'])), None)
    command = ['issue', 'update', str(existing['id'])] if existing else ['issue', 'create']
    command += ['--title', collected['title'], '--description-stdin', '--priority', 'medium',
                '--assignee-id', owner_id, '--status', 'todo', '--output', 'json']
    if existing:
        command.append('--no-start')
    response = _parse_multica_json(runner(command, stdin_text=markdown, **options), 'issue upsert')
    return {'ok': True, 'action': 'updated' if existing else 'created', 'issue': response}


def run_loop_pipeline(
    *, target_date: date | str | None = None, diagnostics_dir: Path | None = None,
    warehouse_db: Path | None = None,
    fixture_json: Path | Mapping[str, Any] | Sequence[Mapping[str, Any]] | None = None,
    state_path: Path | None = None, force: bool = False, dry_run: bool = False, mock_jev_json: Any = None,
    server_url: str = DEFAULT_SERVER_URL, workspace_id: str = DEFAULT_WORKSPACE_ID, owner_id: str = DEFAULT_OWNER_ID,
    query_runner: Callable[[str], tuple[list[tuple[Any, ...]], list[str]]] | None = None,
    jev_fn: Callable[..., dict[str, Any] | None] | None = None,
    runner: Callable[..., subprocess.CompletedProcess[str]] = _default_multica_runner,
    multica_bin: str | None = None,
) -> dict[str, Any]:
    path = Path(state_path).expanduser() if state_path else DEFAULT_WATERMARK_PATH
    with _loop_lock(path, dry_run):
        watermarks = _load_watermarks(path)
        previous = watermarks.get(LOOP_ID) or {}
        collected = collect_crash_and_metrickit_diagnostics(
            target_date=target_date, diagnostics_dir=diagnostics_dir, warehouse_db=warehouse_db,
            fixture_json=fixture_json, query_runner=query_runner,
            seen_signatures=() if force else previous.get('seen_signatures', ()),
        )
        watermark = collected['watermark']
        result = {'ok': True, 'loop_id': LOOP_ID, 'watermark': watermark,
                  'previous_watermark': previous.get('watermark', ''), 'collected': collected}
        if not force and (not collected['has_delta'] or watermark == previous.get('watermark')):
            return {**result, 'status': 'SKIPPED_NO_DELTA', 'layer_reached': 0, 'token_cost': 0}
        try:
            verdict = evaluate_jev_decision(collected, mock_jev_json=mock_jev_json, jev_fn=jev_fn)
        except (OSError, TimeoutError, ValueError):
            verdict = evaluate_jev_decision(collected, jev_fn=lambda **_: None)
        result['jev'] = verdict
        status = 'SKIPPED_NOT_ACTIONABLE'
        reached = 1
        if verdict['actionable']:
            findings = [DiagnosticFinding(**finding) for finding in collected['findings']]
            markdown = render_dual_zone_bug_issue(target_date=collected['date'], tldr=collected['summary'],
                                                 items=collected['items'], findings=findings,
                                                 watermark=watermark, jev_verdict=verdict)
            verification = verify_dual_zone_markdown(markdown)
            if dry_run:
                delivery = {'ok': True, 'action': 'dry_run_autopilot_trigger' if verdict['route'] == 'autopilot_trigger' else 'dry_run',
                            'dual_zone_verification': verification, 'markdown': markdown}
            else:
                settings = _multica_settings(server_url, workspace_id, owner_id)
                if not all(settings[key] for key in ('server_url', 'workspace_id', 'owner_id')):
                    raise RuntimeError('Multica runtime identity missing; configure local MULTICA_* values')
                options = {'server_url': settings['server_url'], 'workspace_id': settings['workspace_id'], 'multica_bin': multica_bin}
                autopilot_id = _find_autopilot(runner, options) if verdict['route'] == 'autopilot_trigger' else None
                if autopilot_id:
                    snapshot = HOME / '.cache' / 'multica-loop-runner' / f'{LOOP_ID}-collect.json'
                    _save_watermarks(collected, snapshot)
                    response = _parse_multica_json(runner(['autopilot', 'trigger', autopilot_id, '--output', 'json'], **options), 'autopilot trigger')
                    delivery = {'ok': True, 'action': 'triggered_autopilot', 'autopilot_id': autopilot_id, 'response': response}
                else:
                    delivery = _deliver_issue(collected, markdown, settings['owner_id'], runner, options)
            result['delivery'] = delivery
            status = 'ACTIONABLE_DELIVERED' if not dry_run else 'ACTIONABLE_DRY_RUN'
            reached = 2
        if not dry_run:
            watermarks[LOOP_ID] = {'watermark': watermark, 'seen_signatures': collected['raw']['seen_signatures'],
                                   'updated_at': datetime.now(CST).isoformat(), 'last_status': status}
            _save_watermarks(watermarks, path)
        return {**result, 'status': status, 'layer_reached': reached}


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="apple_crash_metrickit_loop",
        description="Loop 6B: Apple Official Crash & MetricKit Quality Diagnostic Loop",
    )
    sub = parser.add_subparsers(dest="subcommand", required=True)

    p_collect = sub.add_parser("collect", help="Run Layer 0 deterministic Crash & MetricKit collection")
    p_collect.add_argument("--date", default="today")
    p_collect.add_argument("--diagnostics-dir", type=Path, default=None)
    p_collect.add_argument("--warehouse-db", type=Path, default=None)
    p_collect.add_argument("--fixture-json", type=Path, default=None)
    p_collect.add_argument("--json", action="store_true", default=True)

    p_sync = sub.add_parser("sync-autopilot", help="Idempotently register Loop 6B in Multica Autopilot")
    p_sync.add_argument("--server-url", default=DEFAULT_SERVER_URL)
    p_sync.add_argument("--workspace-id", default=DEFAULT_WORKSPACE_ID)
    p_sync.add_argument("--agent-id", default=DEFAULT_AGENT_ID)
    p_sync.add_argument("--subscriber-id", default=DEFAULT_OWNER_ID)
    p_sync.add_argument("--timezone", default=AUTOPILOT_TIMEZONE)
    p_sync.add_argument("--dry-run", action="store_true")
    p_sync.add_argument("--json", action="store_true", default=True)

    p_run = sub.add_parser("run", help="Execute Layer 0 -> Layer 1 Jev -> Layer 2 Dual-Zone Bug Issue")
    p_run.add_argument("--date", default="today")
    p_run.add_argument("--diagnostics-dir", type=Path, default=None)
    p_run.add_argument("--warehouse-db", type=Path, default=None)
    p_run.add_argument("--fixture-json", type=Path, default=None)
    p_run.add_argument("--state-file", type=Path, default=None)
    p_run.add_argument("--mock-jev-json", default=None)
    p_run.add_argument("--force", action="store_true")
    p_run.add_argument("--dry-run", action="store_true")
    p_run.add_argument("--server-url", default=DEFAULT_SERVER_URL)
    p_run.add_argument("--workspace-id", default=DEFAULT_WORKSPACE_ID)
    p_run.add_argument("--owner-id", default=DEFAULT_OWNER_ID)
    p_run.add_argument("--json", action="store_true", default=True)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = _build_parser()
    ns = parser.parse_args(sys.argv[1:] if argv is None else argv)

    if ns.subcommand == "collect":
        res = collect_crash_and_metrickit_diagnostics(
            target_date=ns.date,
            diagnostics_dir=ns.diagnostics_dir,
            warehouse_db=ns.warehouse_db,
            fixture_json=ns.fixture_json,
        )
        print(json.dumps(res, ensure_ascii=False, indent=2))
        return 0

    if ns.subcommand == "sync-autopilot":
        res = sync_autopilot(
            server_url=ns.server_url,
            workspace_id=ns.workspace_id,
            agent_id=ns.agent_id,
            subscriber_id=ns.subscriber_id,
            tz_name=ns.timezone,
            dry_run=ns.dry_run,
        )
        print(json.dumps(res, ensure_ascii=False, indent=2))
        return 0 if res.get("ok") else 1

    if ns.subcommand == "run":
        res = run_loop_pipeline(
            target_date=ns.date,
            diagnostics_dir=ns.diagnostics_dir,
            warehouse_db=ns.warehouse_db,
            fixture_json=ns.fixture_json,
            state_path=ns.state_file,
            force=ns.force,
            dry_run=ns.dry_run,
            mock_jev_json=ns.mock_jev_json,
            server_url=ns.server_url,
            workspace_id=ns.workspace_id,
            owner_id=ns.owner_id,
        )
        print(json.dumps(res, ensure_ascii=False, indent=2))
        return 0 if res.get("ok") else 1

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
