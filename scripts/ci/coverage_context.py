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


# Characters used to build the untrusted-data fence in review prompts.
# Any occurrence of these markers in PR-controlled content (test source
# bodies) must be neutralized before embedding — otherwise a malicious test
# can prematurely close the untrusted region and inject forged instructions.
_FENCE_PATTERNS = re.compile(
    r"={4,}[^=\n]*(?:不可信|untrusted|数据结束|指令)[^=\n]*={4,}",
    re.IGNORECASE,
)


def sanitize_untrusted_content(text: str) -> str:
    """Remove or neutralize prompt-fence markers in PR-controlled content.

    Replaces any sequence resembling the review prompt's trusted/untrusted
    boundary delimiters with a safe placeholder, preventing delimiter
    injection attacks where test source could escape the untrusted region.
    """
    return _FENCE_PATTERNS.sub("[SANITIZED — fence marker removed]", text)


class AnalysisError(Exception):
    """Raised when Git/tool failures prevent reliable coverage analysis.

    Distinguished from 'no removed tests found' (normal empty result).
    The caller must treat this as fail-closed: the gate blocks because the
    analyzer cannot determine whether coverage was lost.
    """
    pass

# Matches Swift test function declarations — both XCTest (`func testFoo()`)
# and Swift Testing (`@Test func arbitraryName()` / `@Test("label") func …`).
_XCTEST_FUNC_RE = re.compile(
    r"^\s*(?:@\w+\s+)*func\s+(test\w+)\s*\(", re.MULTILINE
)
_SWIFT_TESTING_FUNC_RE = re.compile(
    r"^\s*@Test(?:\(.*?\))?\s+func\s+(\w+)\s*\(", re.MULTILINE
)


def _find_all_test_functions(source: str) -> list[tuple[str, re.Match]]:
    """Find all test function declarations in source using both conventions.

    Returns (func_name, match) pairs. Deduplicates by name (a function that
    matches both regexes is returned once).
    """
    seen: dict[str, re.Match] = {}
    for rx in (_XCTEST_FUNC_RE, _SWIFT_TESTING_FUNC_RE):
        for m in rx.finditer(source):
            name = m.group(1)
            if name not in seen:
                seen[name] = m
    return list(seen.items())

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
    diff_text: str, path: str, base_sha: str, head_sha: str = ""
) -> list[RemovedTest]:
    """Identify test functions truly removed (not merely modified) by the diff.

    A function is considered removed only if its declaration line is absent from
    HEAD source. Functions that merely had lines modified remain and are not
    reported as removed — this distinguishes removal from refactoring.

    Recognizes both XCTest (`func testFoo()`) and Swift Testing
    (`@Test func arbitraryName()`) conventions.
    """
    if "Test" not in path and "test" not in path:
        return []

    # Get the BASE version of the file to see what was there.
    # A None return means git failed — could be a real error or file not in
    # base. Use ls-tree to distinguish: if the path is absent from the base
    # tree, there are genuinely no removed tests (return []).  If ls-tree
    # also fails, we can't determine anything → raise AnalysisError.
    base_source = run_git(["show", f"{base_sha}:{path}"])
    if base_source is None:
        # Check whether the file simply doesn't exist in base (new file)
        base_tree = run_git(["ls-tree", base_sha, "--", path])
        if base_tree is not None and base_tree.strip() == "":
            # File genuinely absent from base — no tests to have removed
            return []
        if base_tree is not None and base_tree.strip():
            # File exists in base tree but blob read failed — analysis error
            raise AnalysisError(
                f"BASE blob read failed for {base_sha}:{path} "
                f"(file exists in tree but content unreadable)"
            )
        # ls-tree itself failed — can't determine anything
        raise AnalysisError(
            f"Cannot read BASE source for {path}: both git-show and "
            f"ls-tree failed (git tool error)"
        )

    removed_lines = set(removed_line_numbers(diff_text, path))
    if not removed_lines:
        return []

    # Get HEAD version to verify removal (not just modification).
    # Distinguish three states: verified-present, verified-absent, unknown.
    head_source: Optional[str] = None
    head_read_succeeded = False
    if head_sha:
        head_source = run_git(["show", f"{head_sha}:{path}"])
        if head_source is not None:
            head_read_succeeded = True
        else:
            # Verify file is truly deleted vs blob read failure by checking
            # ls-tree (lightweight, path-only — no blob content needed).
            tree_out = run_git(["ls-tree", head_sha, "--", path])
            if tree_out is not None and tree_out.strip() == "":
                # File confirmed absent from HEAD tree — genuine deletion.
                head_read_succeeded = True  # "successfully determined absent"
            elif tree_out is not None and tree_out.strip():
                # File exists in HEAD tree but blob read failed — tool error.
                # Will be caught when we try to verify specific functions below.
                pass
            else:
                # ls-tree itself failed → can't confirm anything.
                # Will be caught when we try to verify specific functions below.
                pass

    base_lines = base_source.splitlines()
    # Build HEAD function name set once (empty if HEAD unavailable)
    head_func_names: set[str] = set()
    if head_source is not None:
        for name, _ in _find_all_test_functions(head_source):
            head_func_names.add(name)

    results: list[RemovedTest] = []

    for func_name, match in _find_all_test_functions(base_source):
        func_start_line = base_source[: match.start()].count("\n") + 1
        func_end_line = _find_func_end(base_lines, func_start_line - 1)

        overlap = any(
            func_start_line <= ln <= func_end_line for ln in removed_lines
        )
        if not overlap:
            continue

        # Verify the function declaration is actually absent from HEAD.
        if head_read_succeeded:
            if func_name in head_func_names:
                # Function still exists at HEAD — modified, not removed
                continue
            # else: confirmed absent, proceed to report
        else:
            # HEAD read failed (blob error, not confirmed deletion).
            # Cannot prove absence — this is an analysis error, not a
            # normal "no removal" result. Raise so the gate fails closed.
            raise AnalysisError(
                f"Cannot verify HEAD state for {path}: both git-show and "
                f"ls-tree failed; cannot determine if {func_name} was removed"
            )

        body_start = func_start_line - 1
        body_end = min(func_end_line, body_start + 10)
        snippet = "\n".join(base_lines[body_start:body_end])[:200]
        # Sanitize snippet — base content is also PR-controlled in principle
        snippet = sanitize_untrusted_content(snippet)
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
    """Extract production symbol names referenced in removed test bodies.

    Filters out common test/framework/mock identifiers that would cause
    spurious matches — only production-shaped symbols are returned.
    """
    # Symbols that are test infrastructure, not production code
    _NON_PRODUCTION_SYMBOLS = {
        "XCTest", "XCTestCase", "XCTestExpectation", "XCTAssert",
        "XCTAssertEqual", "XCTAssertTrue", "XCTAssertFalse",
        "XCTAssertNil", "XCTAssertNotNil", "XCTAssertThrowsError",
        "XCTFail", "XCTUnwrap", "XCTSkip",
        "Mock", "Stub", "Fake", "Spy",
        "Foundation", "Combine", "SwiftUI", "UIKit",
        "Task", "Result", "Error", "Optional",
        "String", "Int", "Bool", "Double", "Float", "Array", "Dictionary",
        "Set", "Data", "URL", "Date", "UUID",
    }

    symbols: set[str] = set()
    for test in removed_tests:
        # Look for CamelCase identifiers that look like production types/funcs
        words = re.findall(r"\b([A-Z]\w{2,})\b", test.body_snippet)
        symbols.update(words)
        # Also look for common patterns like `sut.methodName`, `Command.run`
        methods = re.findall(r"\.(\w+)\s*\(", test.body_snippet)
        symbols.update(m for m in methods if len(m) > 2)

    # Filter non-production symbols
    symbols -= _NON_PRODUCTION_SYMBOLS
    # Also filter anything starting with Mock/Stub/Fake prefix
    symbols = {
        s for s in symbols
        if not s.startswith("Mock") and not s.startswith("Stub")
        and not s.startswith("Fake") and not s.startswith("Spy")
    }
    return symbols


def find_related_tests_in_head(
    head_sha: str,
    test_files: list[str],
    production_symbols: set[str],
    max_excerpt_bytes: int,
) -> list[str]:
    """Find existing test functions in HEAD that reference the same symbols.

    Results are ADVISORY CANDIDATES — symbol co-occurrence is necessary but
    not sufficient proof of equivalent branch coverage. The reviewer must
    verify that a candidate actually exercises the same production branch
    before concluding coverage is preserved.
    """
    if not production_symbols:
        return []

    excerpts: list[str] = []
    total_bytes = 0

    for test_file in test_files:
        source = run_git(["show", f"{head_sha}:{test_file}"])
        if source is None:
            raise AnalysisError(
                f"HEAD blob read failed for candidate test file "
                f"'{test_file}' (claimed in SEARCH SCOPE but unreadable)"
            )
        if len(source.encode("utf-8", "replace")) > COVERAGE_MAX_FILE_BYTES:
            continue

        source_lines = source.splitlines()

        for func_name, match in _find_all_test_functions(source):
            func_start = source[: match.start()].count("\n")
            func_end_idx = _find_func_end(source_lines, func_start)

            func_body = "\n".join(source_lines[func_start:func_end_idx])

            # Check if this test references any of the production symbols
            referenced = [
                sym for sym in production_symbols if sym in func_body
            ]
            if not referenced:
                continue

            # Sanitize PR-controlled content before embedding in the prompt
            # to prevent delimiter injection attacks (MY-1456 security fix).
            safe_body = sanitize_untrusted_content(func_body)

            excerpt = (
                f"--- {test_file}: {func_name} "
                f"(lines {func_start + 1}-{func_end_idx}, "
                f"references: {', '.join(sorted(referenced)[:5])})\n"
                f"{safe_body}"
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
    head_sha: str,
    changed_files: list[str],
    production_symbols: Optional[set[str]] = None,
) -> tuple[list[str], list[str]]:
    """Find test files: changed, naming-convention siblings, and repo-wide
    symbol matches. Returns (test_files, searched_paths_summary).

    The searched_paths_summary lists what was actually searched, so the
    evidence block can report scope and the reviewer can judge completeness.
    """
    test_files: list[str] = []
    searched: list[str] = []

    # 1. Changed test files
    for path in changed_files:
        if "Test" in path or "test" in path:
            test_files.append(path)
            searched.append(f"changed: {path}")

    # 2. Sibling test files by naming convention
    tree = run_git(["ls-tree", "-r", "--name-only", head_sha])
    all_tree_files = tree.splitlines() if tree else []

    for path in changed_files:
        if "Test" in path or "test" in path:
            continue
        if not path.endswith(".swift"):
            continue
        stem = path.rsplit("/", 1)[-1].replace(".swift", "")
        candidate_patterns = [
            f"{stem}Tests.swift",
            f"{stem}Test.swift",
        ]
        for line in all_tree_files:
            for pattern in candidate_patterns:
                if line.endswith(pattern) and line not in test_files:
                    test_files.append(line)
                    searched.append(f"sibling: {line}")

    # 3. Repo-wide bounded symbol search: find any test file in the tree
    # whose name contains a production symbol stem (e.g. BriefingPut appears
    # in BriefingPutCommandTests.swift). This catches differently-named test
    # files that cover the same production code but aren't naming-convention
    # siblings of the changed files.
    if production_symbols:
        # Build search stems from production symbols (CamelCase type names)
        search_stems = {
            sym for sym in production_symbols
            if len(sym) > 3 and sym[0].isupper()
        }
        for line in all_tree_files:
            if line in test_files:
                continue
            if not (line.endswith(".swift") or line.endswith(".py")):
                continue
            if "Test" not in line and "test" not in line:
                continue
            basename = line.rsplit("/", 1)[-1]
            for stem in search_stems:
                if stem in basename:
                    test_files.append(line)
                    searched.append(f"symbol-match({stem}): {line}")
                    break

    if not searched:
        searched.append("(no test files found in scope)")

    return test_files, searched


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

    Raises AnalysisError when Git/tool failures prevent reliable analysis.
    The caller must treat this as fail-closed (exit nonzero).
    """
    # Step 1: Find removed test functions (verified absent from HEAD)
    all_removed: list[RemovedTest] = []
    for path in changed_files:
        if not path.endswith(".swift") and not path.endswith(".py"):
            continue
        removed = find_removed_test_functions(
            diff_text, path, base_sha, head_sha
        )
        all_removed.extend(removed)

    if not all_removed:
        return ""

    # Step 2: Extract production symbols from removed tests
    symbols = extract_production_symbols(all_removed)

    # Step 3: Find all test files that might have coverage (bounded repo-wide)
    test_files, searched_summary = find_test_files_in_changed_and_related(
        head_sha, changed_files, symbols
    )

    # Step 4: Find existing tests covering the same symbols
    related_excerpts = find_related_tests_in_head(
        head_sha, test_files, symbols, COVERAGE_MAX_EXCERPT_BYTES
    )

    # Step 5: Render with search scope
    return render_coverage_evidence(
        all_removed, related_excerpts, searched_summary
    )


def render_coverage_evidence(
    removed_tests: list[RemovedTest],
    related_excerpts: list[str],
    searched_summary: Optional[list[str]] = None,
) -> str:
    """Render the coverage evidence block."""
    if not removed_tests:
        return ""

    parts: list[str] = [
        "COVERAGE CONTEXT（由可信脚本在 base checkout 中，从 exact-HEAD 源码确定性搜索；"
        "PR 代码从未被执行）",
        "",
        "本 diff 移除了以下测试函数（已确认其声明在 HEAD 中不存在）。"
        "下方列出 HEAD 中仍存在的、引用相同生产符号的测试作为 ADVISORY CANDIDATES。",
        "",
        "⚠️  ADVISORY — 以下候选测试基于符号共现检索，不等同于等价分支覆盖证明。",
        "Reviewer 必须验证候选测试确实测试了相同生产分支后，才能判定覆盖未丢失。",
        "若无法确认等价性，降级为 note，不得判 blocker。",
        "",
        "REMOVED TESTS (declaration absent from HEAD):",
    ]

    for rt in removed_tests:
        parts.append(f"  - {rt.file}: {rt.func_name}")

    parts.append("")

    # Report search scope so the reviewer can judge completeness
    if searched_summary:
        parts.append("SEARCH SCOPE (files actually searched for related tests):")
        for s in searched_summary:
            parts.append(f"  - {s}")
        parts.append("")

    if related_excerpts:
        parts.append(
            "CANDIDATE EXISTING COVERAGE IN HEAD "
            "(tests referencing same production symbols — verify branch equivalence):"
        )
        parts.append("")
        for excerpt in related_excerpts:
            parts.append(excerpt)
            parts.append("")
    else:
        parts.append(
            "No related existing tests found in HEAD within the searched scope. "
            "This may indicate genuine coverage loss — reviewer should verify "
            "within the searched scope above; claims beyond searched scope are notes."
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

    try:
        result = build_coverage_evidence(
            head_sha=args.head_sha,
            base_sha=args.base_sha,
            diff_text=diff_text,
            changed_files=args.changed_file,
        )
    except AnalysisError as e:
        print(
            f"[coverage-context] analysis failed (fail-closed): {e}",
            file=sys.stderr,
        )
        sys.exit(1)

    sys.stdout.write(result)
