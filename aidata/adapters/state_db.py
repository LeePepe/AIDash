"""state_db adapter — Hermes per-session store (~/.hermes/state.db) (EXT-5, ADR-7/13).

L1 collect: read-only SELECT of ALL `sessions` columns, including the prompt and
config fields (`system_prompt`, `model_config`, `origin_json`) and the billing
fields. `started_at` is a watermark (epoch SECONDS, float).

**Why full collection** (changed 2026-08-03, was a SAFE-columns allowlist): the
excluded fields are the ones that answer the questions the warehouse cannot
currently answer — what prompt/effort/iteration settings produced which cost,
and how the provider's own `actual_cost_usd` compares to aidata's notional cost
derived from token counts. Withholding them made those analyses impossible.

The safety posture that replaces the allowlist:
  - The repository is **private** (changed alongside this), so a mistake is not
    a public disclosure.
  - Every string still passes through `rawio.write_raw` -> `redact_obj`, which
    strips API keys, bearer tokens, and email local parts. That is a
    pattern matcher: it catches credential SHAPES, not sensitive prose. Free
    text in `system_prompt` (internal project names, business logic) is NOT
    redacted and never will be by regex — accept that or do not collect it.
  - `L1_collect/raw/`, `L2_normalize/clean/` and `L3_merge/*.db` are gitignored
    (verified: `git ls-files` over those paths is empty). Data has never been
    committed. **Do not weaken those ignore rules.**

Size: `system_prompt` alone is ~203 MB across ~13.9k sessions and is highly
repetitive (one agent's prompt barely varies). L2 therefore stores a hash +
short preview rather than the full text, so the clean DB stays queryable; the
full text remains in raw/ if it is ever needed.

L2 normalize: one row per session; derives `is_automated` from the `source`
dimension. Stays at L2 clean — NOT merged into the warehouse (ADR-13); the digest
queries the clean DB directly (like the memory_* sources).

Automation definition (ADR-7): AUTOMATED = {cron, subagent} — scheduled / agent-
spawned sessions with no human in the loop. Everything else (cli, acp, weixin,
unknown) is manual; `unknown` counts as manual (conservative — never overstates
automation). "Automation ratio" = automated / total per CST day.
"""

from __future__ import annotations

import hashlib
from typing import Any

from config import HERMES_STATE_DB
from rawio import write_raw, read_raw
from cleanio import write_clean
from sqlite_ro import query_ro
from state import get_watermark, set_watermark

SOURCE = "state_db"

# Sessions with no human in the loop. Everything else is treated as manual.
AUTOMATED_SOURCES = frozenset({"cron", "subagent"})

# Full-column read. `SELECT *` on purpose: the schema evolves upstream (Hermes
# adds columns over time) and an allowlist silently drops whatever is new — the
# failure mode is invisible, which is how the previous allowlist ended up
# excluding fields nobody had re-evaluated in months. raw/ is append-only JSONL,
# so extra columns cost storage, not correctness.
_SELECT = "SELECT * FROM sessions WHERE started_at > ? ORDER BY started_at ASC"


def collect() -> int:
    """Collect new sessions since the watermark. Returns count (0 on degrade)."""
    if not HERMES_STATE_DB.exists():
        return 0
    watermark = float(get_watermark(SOURCE) or 0)
    records = query_ro(HERMES_STATE_DB, _SELECT, (watermark,))
    if not records:
        return 0
    n = write_raw(SOURCE, records)
    set_watermark(SOURCE, max(float(r["started_at"]) for r in records))
    return n


_CLEAN_DDL = """
CREATE TABLE session (
    session_id TEXT PRIMARY KEY, started_at REAL, ended_at REAL,
    message_count INTEGER, tool_call_count INTEGER,
    input_tokens INTEGER, output_tokens INTEGER,
    cache_read_tokens INTEGER, cache_write_tokens INTEGER,
    reasoning_tokens INTEGER, end_reason TEXT,
    source TEXT, model TEXT, is_automated INTEGER,
    -- Prompt identity, not prompt text: the full system_prompt averages ~15 KB
    -- and repeats across sessions, so storing it here would bloat the clean DB
    -- for no query benefit. The hash groups sessions by prompt ("did prompt X
    -- cost more than prompt Y?"), the preview makes a group recognizable, and
    -- the full text stays in raw/ if it is ever genuinely needed.
    system_prompt_sha TEXT, system_prompt_preview TEXT, system_prompt_len INTEGER,
    -- Model config, flattened. The raw JSON is ~100 chars of run parameters;
    -- these three are the ones that plausibly move cost/quality.
    reasoning_effort TEXT, reasoning_enabled INTEGER, max_iterations INTEGER,
    -- Provider-reported cost. DISTINCT from aidata's own cost_usd, which is
    -- derived from tokens x dim_model at L2 (adapters/raven.py::_cost). Keeping
    -- both enables reconciliation — a persistent gap means the price table
    -- missed a model. Never substitute one for the other silently.
    estimated_cost_usd REAL, actual_cost_usd REAL, cost_status TEXT,
    billing_mode TEXT,
    git_branch TEXT, git_repo_root TEXT, cwd TEXT
)
"""
_CLEAN_COLS = ("session_id", "started_at", "ended_at", "message_count",
               "tool_call_count", "input_tokens", "output_tokens",
               "cache_read_tokens", "cache_write_tokens", "reasoning_tokens",
               "end_reason", "source", "model", "is_automated",
               "system_prompt_sha", "system_prompt_preview", "system_prompt_len",
               "reasoning_effort", "reasoning_enabled", "max_iterations",
               "estimated_cost_usd", "actual_cost_usd", "cost_status",
               "billing_mode", "git_branch", "git_repo_root", "cwd")

# Preview length — enough to tell two prompts apart in a query result, short
# enough that the clean DB stays small.
_PREVIEW_CHARS = 200


def _prompt_identity(text: Any) -> tuple[str | None, str | None, int | None]:
    """(sha256, preview, length) for a system prompt. All None when absent."""
    if not isinstance(text, str) or not text:
        return None, None, None
    sha = hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]
    return sha, text[:_PREVIEW_CHARS], len(text)


def _model_config(raw: Any) -> tuple[str | None, int | None, int | None]:
    """(reasoning_effort, reasoning_enabled, max_iterations) from model_config JSON.

    Degrade-safe (ADR-23): malformed or absent JSON yields all-None rather than
    raising — a config-shape change upstream must not break the whole normalize.
    """
    if not isinstance(raw, str) or not raw:
        return None, None, None
    try:
        import json
        cfg = json.loads(raw)
    except (ValueError, TypeError):
        return None, None, None
    if not isinstance(cfg, dict):
        return None, None, None
    reasoning = cfg.get("reasoning_config")
    if not isinstance(reasoning, dict):
        reasoning = {}
    enabled = reasoning.get("enabled")
    return (
        reasoning.get("effort"),
        None if enabled is None else int(bool(enabled)),
        cfg.get("max_iterations"),
    )


def normalize() -> int:
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        sid = rec.get("id")
        if not sid:
            continue
        source = rec.get("source")
        sha, preview, plen = _prompt_identity(rec.get("system_prompt"))
        effort, reasoning_on, max_iter = _model_config(rec.get("model_config"))
        rows[sid] = {  # last write wins -> latest snapshot of each session
            "session_id": sid,
            "started_at": rec.get("started_at"),
            "ended_at": rec.get("ended_at"),
            "message_count": rec.get("message_count"),
            "tool_call_count": rec.get("tool_call_count"),
            "input_tokens": rec.get("input_tokens"),
            "output_tokens": rec.get("output_tokens"),
            "cache_read_tokens": rec.get("cache_read_tokens"),
            "cache_write_tokens": rec.get("cache_write_tokens"),
            "reasoning_tokens": rec.get("reasoning_tokens"),
            "end_reason": rec.get("end_reason"),
            "source": source,
            "model": rec.get("model"),
            "is_automated": 1 if source in AUTOMATED_SOURCES else 0,
            "system_prompt_sha": sha,
            "system_prompt_preview": preview,
            "system_prompt_len": plen,
            "reasoning_effort": effort,
            "reasoning_enabled": reasoning_on,
            "max_iterations": max_iter,
            "estimated_cost_usd": rec.get("estimated_cost_usd"),
            "actual_cost_usd": rec.get("actual_cost_usd"),
            "cost_status": rec.get("cost_status"),
            "billing_mode": rec.get("billing_mode"),
            "git_branch": rec.get("git_branch"),
            "git_repo_root": rec.get("git_repo_root"),
            "cwd": rec.get("cwd"),
        }
    return write_clean(SOURCE, "session", _CLEAN_DDL, list(rows.values()), _CLEAN_COLS)
