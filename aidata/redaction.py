"""Secret redaction — a HARD red line before any data hits L1 raw storage.

Memory sources were verified to embed live credentials (GitHub x-access-token
URLs, SSO accounts, bearer tokens). Every adapter MUST pass string content
through `redact()` before writing to raw/. Landing a plaintext secret is a bug.

Immutable: functions return new strings, never mutate inputs.
"""

from __future__ import annotations

import re
from typing import Any

_PLACEHOLDER = "<REDACTED>"

# Ordered, specific -> general. Each pattern captures a secret-bearing token.
# Kept deliberately broad: over-redaction is safe, under-redaction is a leak.
_PATTERNS: tuple[re.Pattern[str], ...] = (
    # Provider / tool API keys with known prefixes
    re.compile(r"\brvn_[A-Za-z0-9]{8,}"),
    re.compile(r"\bmul_[A-Za-z0-9]{8,}"),
    re.compile(r"\bsk-[A-Za-z0-9\-_]{16,}"),
    re.compile(r"\bghp_[A-Za-z0-9]{20,}"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"),
    # GitHub token embedded in a clone URL: https://x-access-token:TOKEN@github.com/...
    re.compile(r"x-access-token:[^@\s/]+@"),
    re.compile(r"https://[^:@\s/]+:[^@\s/]+@github\.com"),
    # Authorization: Bearer <token>
    re.compile(r"(?i)\bBearer\s+[A-Za-z0-9\-._~+/]{16,}=*"),
    # Generic "token"/"password"/"secret"/"api_key" = value assignments
    re.compile(
        r'(?i)\b(token|password|passwd|secret|api[_-]?key|access[_-]?token)'
        r'\b\s*[:=]\s*["\']?[A-Za-z0-9\-._~+/]{12,}=*["\']?'
    ),
)

# Emails: keep the domain shape but drop the local part (SSO accounts are PII).
_EMAIL = re.compile(r"\b[A-Za-z0-9._%+\-]+@([A-Za-z0-9.\-]+\.[A-Za-z]{2,})\b")


def redact(text: str) -> str:
    """Return a copy of `text` with secrets and email local-parts removed."""
    if not text:
        return text
    out = text
    for pat in _PATTERNS:
        out = pat.sub(_PLACEHOLDER, out)
    out = _EMAIL.sub(lambda m: f"{_PLACEHOLDER}@{m.group(1)}", out)
    return out


def redact_obj(obj: Any) -> Any:
    """Recursively redact all string values in a JSON-like structure.

    Returns a NEW structure; the input is never mutated.
    """
    if isinstance(obj, str):
        return redact(obj)
    if isinstance(obj, dict):
        return {k: redact_obj(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [redact_obj(v) for v in obj]
    return obj
