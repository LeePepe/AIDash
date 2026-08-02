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

import re
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
