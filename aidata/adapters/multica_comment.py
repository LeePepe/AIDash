"""multica_comment adapter — issue comment threads (workflow health signals).

L1 collect: for each known issue (from multica_issue raw), fetch
`issue comment list <issue-uuid>` per workspace, incrementally via --since. These
comment threads carry the dev-team workflow signals the run table can't show:
who mentioned whom (@role hand-offs → rework sequences), reply threading, and
resolution state.

L2 normalize: one row per comment, STRUCTURED-FIRST. We keep the fields that
reconstruct the workflow (mention target, threading, resolution) and land only a
short redacted preview of the body — not the full prose (see the module note on
`content_preview` below).

Red line: every comment string is redacted (rawio.write_raw → redact_obj) before
it touches raw/, exactly like every other source — but comment bodies are the
highest-risk free text here (URLs, tokens, business detail), so this is not
optional.

Degrade-safe (ADR-23): a missing CLI short-circuits to 0; a single issue whose
comment query fails is skipped, never aborting the whole collect.

L2-only (unlike multica_run, which IS merged): NOT registered in MERGE_SOURCES,
so it never enters the warehouse. Two L4 queries already consume its clean DB
directly — health/planner-gap and health/rework-threads — but it is NOT yet
wired into the L5 digest (no digest section reads it).
"""

from __future__ import annotations

import re
from typing import Any

from config import MULTICA_WORKSPACES
from adapters._multica import multica_bin, run_json
from rawio import write_raw, read_raw
from cleanio import write_clean
from state import get_watermark, set_watermark
from adapters.multica_issue import SOURCE as ISSUE_SOURCE

SOURCE = "multica_comment"

# Preview length for the redacted body we land. Structured fields (mention_role,
# threading, resolution) drive workflow reconstruction; the body is kept only as
# a short scannable, already-redacted preview — never the full prose.
_PREVIEW_LEN = 200

# First mention target in a comment body: "[@Team Lead](mention://agent/…)".
# Captures the role name between "@" and the closing "]".
_MENTION = re.compile(r"@([A-Za-z ]+?)\]")


def _multica_bin() -> str | None:
    """Thin wrapper over the shared resolver (kept as a monkeypatch seam)."""
    return multica_bin()


def _run_json(args: list[str]) -> Any:
    """Thin wrapper over shared run_json; passes LOCAL _multica_bin() so that
    patching this module's _multica_bin still drives the CLI resolution."""
    return run_json(args, binp=_multica_bin())


def _known_issue_ids(ws_id: str) -> list[str]:
    """Issue UUIDs seen in multica_issue raw for one workspace (dedup, in order)."""
    seen: set[str] = set()
    ids: list[str] = []
    for rec in read_raw(ISSUE_SOURCE):
        if rec.get("workspace_id") != ws_id:
            continue
        iid = rec.get("id")
        if iid and iid not in seen:
            seen.add(iid)
            ids.append(iid)
    return ids


def _comment_ts(c: dict[str, Any]) -> str | None:
    """Per-comment activity timestamp used to advance the workspace watermark."""
    return c.get("last_activity_at") or c.get("created_at")


def collect() -> int:
    """Pull new comments per known issue across BOTH workspaces (EXT-2).

    Each workspace keeps its OWN timestamp watermark (max last_activity_at /
    created_at seen), never a shared global cursor — mirroring multica_issue.
    Comments are fetched with --since <watermark> so re-runs are incremental.
    """
    if not _multica_bin():
        return 0  # degrade: no CLI → nothing to collect
    total = 0
    for ws_id, _name in MULTICA_WORKSPACES:
        key = f"{SOURCE}:{ws_id}"
        watermark = get_watermark(key)
        newest = watermark
        batch: list[dict[str, Any]] = []

        for iid in _known_issue_ids(ws_id):
            args = ["issue", "comment", "list", iid,
                    "--workspace-id", ws_id, "--output", "json"]
            if watermark:
                args += ["--since", watermark]
            try:
                comments = _run_json(args)
            except RuntimeError:
                continue  # degrade: skip this issue, keep going
            if isinstance(comments, dict):
                comments = comments.get("comments", [])
            for c in (comments or []):
                rec = dict(c)
                rec["_workspace_id"] = ws_id
                batch.append(rec)
                ts = _comment_ts(c)
                if ts and (newest is None or ts > newest):
                    newest = ts
            if len(batch) >= 500:
                total += write_raw(SOURCE, batch)
                batch = []

        if batch:
            total += write_raw(SOURCE, batch)
        if newest and newest != watermark:
            set_watermark(key, newest)
    return total


def _mention_role(content: str | None) -> str | None:
    """First @role mention target in a body, or None."""
    if not content:
        return None
    m = _MENTION.search(content)
    return m.group(1).strip() if m else None


_CLEAN_DDL = """
CREATE TABLE comment (
    comment_id TEXT PRIMARY KEY, issue_id TEXT, parent_id TEXT,
    author_type TEXT, mention_role TEXT, type TEXT, reply_count INTEGER,
    is_reply INTEGER, resolved_at TEXT, created_at TEXT, content_preview TEXT
)
"""
_CLEAN_COLS = ("comment_id", "issue_id", "parent_id", "author_type",
               "mention_role", "type", "reply_count", "is_reply",
               "resolved_at", "created_at", "content_preview")


def normalize() -> int:
    rows: dict[str, dict[str, Any]] = {}
    for rec in read_raw(SOURCE):
        cid = rec.get("id")
        if not cid:
            continue
        # content is already redacted (write_raw redacted it on the way in) —
        # do NOT redact again here; just derive + preview.
        content = rec.get("content") or ""
        rows[cid] = {  # last write wins -> latest snapshot of each comment
            "comment_id": cid,
            "issue_id": rec.get("issue_id"),
            "parent_id": rec.get("parent_id"),
            "author_type": rec.get("author_type"),
            "mention_role": _mention_role(content),
            "type": rec.get("type"),
            "reply_count": rec.get("reply_count"),
            "is_reply": 1 if rec.get("parent_id") else 0,
            "resolved_at": rec.get("resolved_at"),
            "created_at": rec.get("created_at"),
            "content_preview": content[:_PREVIEW_LEN] or None,
        }
    return write_clean(SOURCE, "comment", _CLEAN_DDL, list(rows.values()),
                       _CLEAN_COLS)
