#!/usr/bin/env python3
"""Build exact-HEAD coverage context for the automated review gates.

When a diff removes test functions, this module searches full HEAD source for
remaining test functions that cover the same production symbols — preventing
the reviewer from reporting "missing coverage" when equivalent tests already
exist in files not shown in the diff.

The false positive this addresses (MY-1456):
  - A diff removes obsolete throw-path tests
  - An existing full-source test already covers the returned-response branch
  - The reviewer, seeing only the diff context, claims coverage is lost
  - The reviewer promotes this to a critical/high blocker

Fix: supply bounded exact-HEAD full changed-file context for related tests,
so the reviewer has evidence to verify coverage exists before claiming loss.

Called by `scripts/ci/review-common.sh` via `build_coverage_context`.
Security: same trust model as review_context.py — only reads git blobs from
the base checkout, never executes PR code.
"""

from __future__ import annotations

import re
import subprocess
import sys
from typing import NamedTuple, Optional, Sequence, Tuple

# Matches Swift test function declarations.
_TEST_FUNC_RE = re.compile(
    r"^\s*(?:@\w+\s+)*func\s+(test\w+)\s*\(", re.MULTILINE
)

# Matches production symbol names: types, functions, protocols.
_SYMBOL_RE = re.compile(
    r"(?:class|struct|enum|protocol|func|actor)\s+(\w+)"
)

# Byte caps — keep total output bounded.
COVERAGE_MAX_FILE_BYTES = 400_000
COVERAGE_MAX_EXCERPT_BYTES = 30_000
COVERAGE_MAX_TOTAL_BYTES = 80_000


class RemovedTest(NamedTuple):
    file: str
    func_name: str
    body_snippet: str  # first ~200 chars of the removed test body


class CoverageEvidence(NamedTuple):
    removed_tests: Tuple[RemovedTest, ...]
    related_existing_tests: Tuple[str, ...]  # rendered excerpts
    summary: str


def run_git(args: Sequence[str]) -> Optional[str]:
    """Run a read-only git command; None when it fails."""
    try:
        done = subprocess.run(
            ["git", *args],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except OSError:
        return None
    if done.returncode != 0:
        return None
    return done.stdout


def removed_line_numbers(diff_text: str, path: str) -> Tuple[int, ...]:
    """BASE-side line numbers removed from `path` by this diff."""
    hunk_re = re.compile(r"^@@ -(\d+)(?:,\d+)? \+\d+(?:,\d+)? @@")
    lines = diff_text.splitlines()
    removed: list[int] = []
    in_file = False
    in_hunk = False
    base_line = 0

    for line in lines:
        if line.startswith("diff --git "):
            in_file = line.endswith(f" b/{path}")
            in_hunk = False
            continue
        if not in_file:
            continue
        hunk = hunk_re.match(line)
        if hunk:
            base_line = int(hunk.group(1))
            in_hunk = True
            continue
        if not in_hunk and (line.startswith("+++") or line.startswith("---")):
            continue
        if line.startswith("-"):
            removed.append(base_line)
            base_line += 1
        elif line.startswith("+"):
            continue
        elif line.startswith("\\"):
            continue
        else:
            base_line += 1

    return tuple(removed)


def find_removed_test_functions(
    diff_text: str, path: str, base_sha: str
) -> list[RemovedTest]:
    """Identify test functions removed by the diff from a test file."""
    if "Test" not in path and "test" not in path:
        return []

    # Get the BASE version of the file to see what was there
    base_source = run_git(["show", f"{base_sha}:{path}"])
    if base_source is None:
        return []

    removed_lines = set(removed_line_numbers(diff_text, path))
    if not removed_lines:
        return []

    base_lines = base_source.splitlines()
    results: list[RemovedTest] = []

    for match in _TEST_FUNC_RE.finditer(base_source):
        func_name = match.group(1)
        # Find line number of this function (1-based)
        func_start_line = base_source[: match.start()].count("\n") + 1

        # Check if any removed line overlaps with this function's range
        # Approximate the function body range by finding its closing brace
        func_end_line = _find_func_end(base_lines, func_start_line - 1)

        overlap = any(
            func_start_line <= ln <= func_end_line for ln in removed_lines
        )
        if overlap:
            body_start = func_start_line - 1
            body_end = min(func_end_line, body_start + 10)
            snippet = "\n".join(base_lines[body_start:body_end])[:200]
            results.append(RemovedTest(
                file=path, func_name=func_name, body_snippet=snippet
            ))

    return results


def _find_func_end(lines: list[str], start_idx: int) -> int:
    """Find the closing line of a function starting at start_idx (0-based).

    Returns 1-based line number. Uses simple brace counting.
    """
    depth = 0
    started = False
    for i in range(start_idx, min(start_idx + 500, len(lines))):
        for ch in lines[i]:
            if ch == "{":
                depth += 1
                started = True
            elif ch == "}":
                depth -= 1
                if started and depth == 0:
                    return i + 1  # 1-based
    return min(start_idx + 50, len(lines))


def extract_production_symbols(removed_tests: list[RemovedTest]) -> set[str]:
    """Extract production symbol names referenced in removed test bodies."""
    symbols: set[str] = set()
    for test in removed_tests:
        # Look for CamelCase identifiers that look like production types/funcs
        words = re.findall(r"\b([A-Z]\w{2,})\b", test.body_snippet)
        symbols.update(words)
        # Also look for common patterns like `sut.methodName`, `Command.run`
        methods = re.findall(r"\.(\w+)\s*\(", test.body_snippet)
        symbols.update(m for m in methods if len(m) > 2)
    return symbols


def find_related_tests_in_head(
    head_sha: str,
    test_files: list[str],
    production_symbols: set[str],
    max_excerpt_bytes: int,
) -> list[str]:
    """Find existing test functions in HEAD that reference the same symbols."""
    if not production_symbols:
        return []

    excerpts: list[str] = []
    total_bytes = 0

    for test_file in test_files:
        source = run_git(["show", f"{head_sha}:{test_file}"])
        if source is None:
            continue
        if len(source.encode("utf-8", "replace")) > COVERAGE_MAX_FILE_BYTES:
            continue

        source_lines = source.splitlines()

        for match in _TEST_FUNC_RE.finditer(source):
            func_name = match.group(1)
            func_start = source[: match.start()].count("\n")
            func_end_idx = _find_func_end(source_lines, func_start)

            func_body = "\n".join(source_lines[func_start:func_end_idx])

            # Check if this test references any of the production symbols
            referenced = [
                sym for sym in production_symbols if sym in func_body
            ]
            if not referenced:
                continue

            excerpt = (
                f"--- {test_file}: {func_name} "
                f"(lines {func_start + 1}-{func_end_idx}, "
                f"references: {', '.join(sorted(referenced)[:5])})\n"
                f"{func_body}"
            )
            excerpt_bytes = len(excerpt.encode("utf-8", "replace"))
            if excerpt_bytes > max_excerpt_bytes:
                excerpt = excerpt[:max_excerpt_bytes] + "\n[truncated]"
                excerpt_bytes = max_excerpt_bytes

            if total_bytes + excerpt_bytes > COVERAGE_MAX_TOTAL_BYTES:
                excerpts.append(
                    f"[additional matching tests omitted — "
                    f"{COVERAGE_MAX_TOTAL_BYTES}-byte cap reached]"
                )
                break

            excerpts.append(excerpt)
            total_bytes += excerpt_bytes

    return excerpts


def find_test_files_in_changed_and_related(
    head_sha: str, changed_files: list[str]
) -> list[str]:
    """Find test files: both changed and related by naming convention."""
    test_files: list[str] = []

    for path in changed_files:
        if "Test" in path or "test" in path:
            test_files.append(path)

    # Also find sibling test files for changed production files
    for path in changed_files:
        if "Test" in path or "test" in path:
            continue
        if not path.endswith(".swift"):
            continue
        # Convention: FooCommand.swift → FooCommandTests.swift
        stem = path.rsplit("/", 1)[-1].replace(".swift", "")
        # Search in the same directory structure under Tests
        candidate_patterns = [
            f"{stem}Tests.swift",
            f"{stem}Test.swift",
        ]
        # Use git ls-tree to find matching test files
        tree = run_git(["ls-tree", "-r", "--name-only", head_sha])
        if tree:
            for line in tree.splitlines():
                for pattern in candidate_patterns:
                    if line.endswith(pattern) and line not in test_files:
                        test_files.append(line)

    return test_files


def build_coverage_evidence(
    head_sha: str,
    base_sha: str,
    diff_text: str,
    changed_files: list[str],
) -> str:
    """Main entry: build coverage context block for the review prompt.

    Returns empty string when no removed tests are detected (normal case).
    Returns non-empty evidence block when tests are removed and related
    coverage exists in HEAD.
    """
    # Step 1: Find removed test functions
    all_removed: list[RemovedTest] = []
    for path in changed_files:
        if not path.endswith(".swift") and not path.endswith(".py"):
            continue
        removed = find_removed_test_functions(diff_text, path, base_sha)
        all_removed.extend(removed)

    if not all_removed:
        return ""

    # Step 2: Extract production symbols from removed tests
    symbols = extract_production_symbols(all_removed)

    # Step 3: Find all test files that might have coverage
    test_files = find_test_files_in_changed_and_related(
        head_sha, changed_files
    )

    # Step 4: Find existing tests covering the same symbols
    related_excerpts = find_related_tests_in_head(
        head_sha, test_files, symbols, COVERAGE_MAX_EXCERPT_BYTES
    )

    # Step 5: Render
    return render_coverage_evidence(all_removed, related_excerpts)


def render_coverage_evidence(
    removed_tests: list[RemovedTest],
    related_excerpts: list[str],
) -> str:
    """Render the coverage evidence block."""
    if not removed_tests:
        return ""

    parts: list[str] = [
        "COVERAGE CONTEXT（由可信脚本在 base checkout 中，从 exact-HEAD 源码确定性搜索；"
        "PR 代码从未被执行）",
        "",
        "本 diff 移除了以下测试函数。下方列出 HEAD 中仍存在的、覆盖相同生产路径的测试。",
        "判断「测试覆盖丢失」时，必须先查看下方已有覆盖再下结论。",
        "",
        "REMOVED TESTS:",
    ]

    for rt in removed_tests:
        parts.append(f"  - {rt.file}: {rt.func_name}")

    parts.append("")

    if related_excerpts:
        parts.append(
            "EXISTING COVERAGE IN HEAD (tests covering the same production symbols):"
        )
        parts.append("")
        for excerpt in related_excerpts:
            parts.append(excerpt)
            parts.append("")
    else:
        parts.append(
            "No related existing tests found in HEAD for the removed symbols. "
            "This may indicate genuine coverage loss."
        )
        parts.append("")

    return "\n".join(parts)


if __name__ == "__main__":
    # Standalone usage for debugging; normally called via review-common.sh
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--base-sha", required=True)
    parser.add_argument("--diff-file", required=True)
    parser.add_argument("--changed-file", action="append", default=[])
    args = parser.parse_args()

    try:
        with open(args.diff_file, encoding="utf-8", errors="replace") as f:
            diff_text = f.read()
    except OSError as e:
        print(f"[coverage-context] cannot read diff file: {e}", file=sys.stderr)
        sys.exit(2)

    result = build_coverage_evidence(
        head_sha=args.head_sha,
        base_sha=args.base_sha,
        diff_text=diff_text,
        changed_files=args.changed_file,
    )
    sys.stdout.write(result)
