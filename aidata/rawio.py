"""Append-only raw shard writer for L1 with source-level lock coordination.

Every record a collector emits is redacted then appended to a dated JSONL
shard under raw/<source>/<YYYY-MM-DD>.jsonl. Collectors remain strictly
append-only; lock-coordinated Last-Write-Wins cross-shard deduplication may
atomically compact superseded older duplicate primary keys while holding the
same per-source advisory lock (`raw_source_lock`), ensuring zero lost appends.
"""

from __future__ import annotations

import fcntl
import hashlib
import json
import time
from collections.abc import Iterable, Iterator
from contextlib import contextmanager
from datetime import date
from pathlib import Path
from typing import Any

from config import raw_source_dir
from redaction import redact_obj


@contextmanager
def raw_source_lock(out_dir: Path, *, timeout: float = 30.0) -> Iterator[None]:
    """Acquire an exclusive per-source advisory lock across raw shard writes/compaction."""
    out_dir.mkdir(parents=True, exist_ok=True)
    lock_path = out_dir / ".source.lock"
    with lock_path.open("a+", encoding="utf-8") as handle:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"raw source lock timeout for {out_dir.name}")
                time.sleep(0.02)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def write_raw(source: str, records: Iterable[dict[str, Any]], shard_date: str | None = None) -> int:
    """Redact and append records to a source's dated raw shard.

    Returns the count written. Each record is passed through redact_obj first —
    this is the enforced red line, not an optional step.
    """
    day = shard_date or date.today().isoformat()
    out_dir = raw_source_dir(source)
    with raw_source_lock(out_dir):
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
    with raw_source_lock(out_dir):
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
