"""Append-only raw shard writer for L1.

Every record a collector emits is redacted then appended to a dated JSONL
shard under raw/<source>/<YYYY-MM-DD>.jsonl. Append-only: we never rewrite
existing shards, preserving the immutable source-of-truth property.
"""

from __future__ import annotations

import hashlib
import json
from datetime import date
from typing import Any, Iterable

from config import raw_source_dir
from redaction import redact_obj


def write_raw(source: str, records: Iterable[dict[str, Any]], shard_date: str | None = None) -> int:
    """Redact and append records to a source's dated raw shard.

    Returns the count written. Each record is passed through redact_obj first —
    this is the enforced red line, not an optional step.
    """
    day = shard_date or date.today().isoformat()
    out_dir = raw_source_dir(source)
    out_dir.mkdir(parents=True, exist_ok=True)
    shard = out_dir / f"{day}.jsonl"

    count = 0
    with shard.open("a", encoding="utf-8") as fh:
        for rec in records:
            safe = redact_obj(rec)
            fh.write(json.dumps(safe, ensure_ascii=False) + "\n")
            count += 1
    return count


def write_raw_snapshot(source: str, records: list[dict[str, Any]]) -> int:
    """Append a full snapshot only if it differs from the last one.

    For sources with no natural watermark (small, fully re-read each collect:
    pr_cache, memory markdown). Hashes the redacted snapshot and skips the write
    when identical to the previous run, keeping raw append-only *and* dupe-free.
    Returns records written (0 if unchanged).
    """
    safe = [redact_obj(r) for r in records]
    digest = hashlib.sha256(
        json.dumps(safe, sort_keys=True, ensure_ascii=False).encode("utf-8")
    ).hexdigest()

    out_dir = raw_source_dir(source)
    out_dir.mkdir(parents=True, exist_ok=True)
    hash_file = out_dir / ".last_hash"
    if hash_file.exists() and hash_file.read_text(encoding="utf-8").strip() == digest:
        return 0  # identical snapshot — skip

    day = date.today().isoformat()
    shard = out_dir / f"{day}.jsonl"
    with shard.open("a", encoding="utf-8") as fh:
        for rec in safe:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    hash_file.write_text(digest, encoding="utf-8")
    return len(safe)


def read_raw(source: str) -> list[dict[str, Any]]:
    """Read all raw records for a source across all shards (for L2)."""
    out_dir = raw_source_dir(source)
    if not out_dir.exists():
        return []
    records: list[dict[str, Any]] = []
    for shard in sorted(out_dir.glob("*.jsonl")):
        with shard.open("r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line:
                    records.append(json.loads(line))
    return records
