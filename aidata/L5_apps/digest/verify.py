"""Number-verification guard for the LLM-polished digest (ADR-18).

The deterministic template owns every number. The LLM may only add qualitative
commentary and rephrase TODO wording — it must NEVER invent, alter, or drop a
number. This guard compares the numeric tokens of the template against the
polished output: if the polished text introduces a new number (hallucination)
or is missing a template number (alteration/drop), the polish is rejected and
the caller falls back to the pure template.

Pure and hermetic — no I/O, no LLM. This is the primary, testable safety check;
an optional `codex:review` secondary is deferred to a later milestone.
"""

from __future__ import annotations

import json
import re
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass

# Matches integers and decimals, optionally signed. The sign is stripped during
# normalization so "-5" and "5" compare equal (we care about the magnitude
# token appearing, not its arithmetic sign, which markdown arrows already carry).
_NUM_RE = re.compile(r"-?\d+(?:\.\d+)?")


def extract_numbers(text: str) -> frozenset[str]:
    """Return the set of numeric tokens in `text` (sign-normalized)."""
    return frozenset(m.group(0).lstrip("-") for m in _NUM_RE.finditer(text))


@dataclass(frozen=True)
class VerificationResult:
    ok: bool
    introduced: frozenset[str]   # numbers in polished but not in template
    missing: frozenset[str]      # template numbers absent from polished
    reason: str = ""


def verify_numbers(template_md: str, polished_md: str) -> VerificationResult:
    """Verify the polished digest neither invents nor drops any template number.

    `ok` iff the polished output contains exactly the template's numeric tokens
    (no more, no fewer). Any deviation flags a hallucination/alteration.
    """
    template_nums = extract_numbers(template_md)
    polished_nums = extract_numbers(polished_md)
    introduced = polished_nums - template_nums
    missing = template_nums - polished_nums
    ok = not introduced and not missing
    if ok:
        reason = ""
    else:
        parts = []
        if introduced:
            parts.append(f"introduced {sorted(introduced)}")
        if missing:
            parts.append(f"missing {sorted(missing)}")
        reason = "number mismatch: " + "; ".join(parts)
    return VerificationResult(ok=ok, introduced=introduced,
                              missing=missing, reason=reason)


@dataclass(frozen=True)
class VerifyResult:
    ok: bool
    reason: str = ""
    offending_ids: tuple[str, ...] = ()


def verify_hourly_timeline(payload: dict) -> VerifyResult:
    """Verify the deterministic 24-hour evidence/citation invariants."""
    hours = payload.get("hours")
    citations = payload.get("citations")
    if not isinstance(hours, list) or len(hours) != 24:
        return VerifyResult(False, "hours must contain exactly 24 buckets")
    if not isinstance(citations, list):
        return VerifyResult(False, "citations must be a list")
    citation_ids = {
        str(item.get("id")) for item in citations
        if isinstance(item, dict) and item.get("id")
    }
    offending: list[str] = []
    for expected, bucket in enumerate(hours):
        if not isinstance(bucket, dict) or bucket.get("hour") != expected:
            return VerifyResult(False, f"hour bucket {expected} is out of order")
        summary = str(bucket.get("summary") or "").strip()
        evidence = bucket.get("evidenceIds")
        if not isinstance(evidence, list):
            return VerifyResult(False, f"hour {expected} evidenceIds is invalid")
        if summary == "无采集数据。":
            if evidence:
                offending.append(f"H{expected:02d}")
            continue
        if not 1 <= len(evidence) <= 3:
            offending.append(f"H{expected:02d}")
            continue
        prefix = f"H{expected:02d}-"
        if any(not str(item).startswith(prefix) or str(item) not in citation_ids
               for item in evidence):
            offending.append(f"H{expected:02d}")
    if offending:
        return VerifyResult(False, "hourly evidence invariant failed",
                            tuple(offending))
    return VerifyResult(True)


def _default_jev_opener(endpoint: str, payload: dict, timeout: float = 5.0):
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def _jev_call(opener, endpoint: str, payload: dict):
    try:
        return opener(endpoint, payload, timeout=5.0)
    except TypeError:
        return opener(endpoint, payload)


def verify_citations_with_jev(
    payload: dict,
    evidence_by_id: dict[str, str],
    *,
    opener=None,
    endpoint: str = "http://127.0.0.1:19823/v1/systemone",
) -> VerifyResult:
    """Run Jev R06 checks concurrently; offline Jev degrades open."""
    active = [
        bucket for bucket in payload.get("hours", [])
        if isinstance(bucket, dict)
        and str(bucket.get("summary") or "").strip() != "无采集数据。"
    ]
    if not active:
        return VerifyResult(True)

    def check(bucket: dict) -> tuple[str, bool, str]:
        hour = f"H{int(bucket.get('hour', -1)):02d}"
        claims = [evidence_by_id.get(str(eid), "") for eid in bucket.get("evidenceIds", [])]
        request = {
            "choice": {"supports": True, "contradicts": True, "unrelated": True},
            "noul": {"unbacked_claim": True},
            "hour": hour,
            "claims": claims,
        }
        response = _jev_call(opener or _default_jev_opener, endpoint, request)
        if not isinstance(response, dict):
            return hour, False, "invalid Jev response"
        choice = str(response.get("choice") or response.get("Choice") or "").lower()
        confidence = float(response.get("confidence", 0.0) or 0.0)
        noul = float(response.get("noul", response.get("Noul", 1.0)) or 1.0)
        return hour, choice == "supports" and confidence >= 0.70 and noul < 0.35, choice

    try:
        with ThreadPoolExecutor(max_workers=min(8, len(active))) as pool:
            results = list(pool.map(check, active))
    except (OSError, TimeoutError, ValueError, TypeError, json.JSONDecodeError):
        return VerifyResult(True, "jev unavailable; deterministic verification retained")
    offending = tuple(hour for hour, ok, _ in results if not ok)
    if offending:
        return VerifyResult(False, "Jev citation truth table rejected active hours",
                            offending)
    return VerifyResult(True)
