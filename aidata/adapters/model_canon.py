"""Model-name canonicalization.

Observed raven data spells the same model several ways (claude-opus-4.7 vs
claude-opus-4-7, claude-opus-4.6-1m vs claude-opus-4-6-1m). Aggregations and
price lookups split across these. `model_canon` maps any spelling to one
canonical id. Original `model` is preserved upstream; this is a derived value.

Rule for Claude models: dotted minor versions become hyphenated
(claude-opus-4.7 -> claude-opus-4-7). GPT models keep dotted versions
(gpt-5.5 is canonical). Unknown names pass through the same transform.
"""

from __future__ import annotations

import re

# Turn "claude-<family>-<major>.<minor>" into "claude-<family>-<major>-<minor>".
# Only applies to claude- models; gpt-5.5 etc. keep their dot.
_CLAUDE_DOTTED = re.compile(r"^(claude-[a-z]+-\d+)\.(\d+)")


def model_canon(model: str | None) -> str | None:
    """Return the canonical model id, or None for null/empty input."""
    if not model:
        return None
    m = model.strip()
    if m.startswith("claude-"):
        # claude-opus-4.7 -> claude-opus-4-7 ; claude-opus-4.6-1m -> claude-opus-4-6-1m
        m = _CLAUDE_DOTTED.sub(r"\1-\2", m)
    return m
