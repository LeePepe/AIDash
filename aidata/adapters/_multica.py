"""Shared Multica CLI subprocess helper (T3 dedup).

The three Multica adapters (``multica_issue`` / ``multica_run`` /
``multica_comment``) each carried a near-identical ``_multica_bin()`` +
``_run_json()``. This module centralizes both so there is a single source of
truth for how we resolve the ``multica`` CLI and shell out to it.

Behaviour-equivalence notes (the three copies were NOT byte-identical):
  * ``multica_issue._multica_bin`` used to return the config *name* (``MULTICA_BIN``)
    when it was on PATH, while run/comment returned the ``shutil.which`` *resolved
    path*. We unify on the resolved-path form (2-of-3 majority). Both strings
    execute the same binary; no test asserts the return value.
  * ``multica_issue._run_json`` used slightly different error text
    ("...not found on PATH", "...failed: {stderr[:200]}") than run/comment
    ("...not found", "...: {stderr[:150]}"). We unify on the run/comment form.
    No test asserts these strings; the raise / return-[] *timing* is identical
    across all three, which is what callers depend on.

Each adapter keeps a same-named thin local wrapper (``_multica_bin`` /
``_run_json``) so existing test monkeypatch seams keep working. The ``_run_json``
wrapper passes its LOCAL ``_multica_bin()`` in as ``binp`` so that patching
``<adapter>._multica_bin`` still influences ``_run_json`` (the seam stays live).
"""

from __future__ import annotations

import json
import shutil
import subprocess
from typing import Any

from config import MULTICA_BIN

# Per-call subprocess timeout (seconds); matches all three original adapters.
_TIMEOUT = 180
# stderr truncation on a nonzero exit; matches run/comment (issue used 200).
_STDERR_TRUNC = 150


def multica_bin() -> str | None:
    """Resolve the ``multica`` CLI path, or ``None`` when it is absent."""
    return shutil.which(MULTICA_BIN) or shutil.which("multica")


def run_json(args: list[str], binp: str | None = None) -> Any:
    """Run ``multica <args>`` and parse its JSON stdout.

    Raises ``RuntimeError`` when the CLI is absent or exits nonzero. Returns
    ``[]`` on empty stdout, otherwise the parsed JSON. ``binp`` lets a caller
    inject a binary it already resolved via its own (patchable) ``_multica_bin``
    so test monkeypatch seams stay intact.
    """
    binp = binp or multica_bin()
    if not binp:
        raise RuntimeError("multica CLI not found")
    proc = subprocess.run(
        [binp, *args], capture_output=True, text=True, timeout=_TIMEOUT)
    if proc.returncode != 0:
        raise RuntimeError(
            f"multica {' '.join(args)}: {proc.stderr.strip()[:_STDERR_TRUNC]}")
    return json.loads(proc.stdout) if proc.stdout.strip() else []
