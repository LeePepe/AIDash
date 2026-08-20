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

# Structural record patterns that trusted output uses as section headers.
# PR-controlled content (test bodies, paths, func names) must not contain
# these — a malicious test body could otherwise forge trusted structural
# records inside the nonce-authenticated coverage block.
# Matches the distinctive keyword phrases wherever they appear.
_STRUCTURAL_RECORD_RE = re.compile(
    r"COVERAGE CONTEXT|REMOVED TESTS|SEARCH SCOPE|"
    r"CANDIDATE EXISTING COVERAGE|"
    r"---\s+\S+[^(\n]*:\s+\w+[^(\n]*\(lines\s+\d+",
)


def sanitize_untrusted_content(text: str) -> str:
    """Remove or neutralize prompt-fence markers and structural record patterns
    in PR-controlled content.

    Replaces any sequence resembling the review prompt's trusted/untrusted
    boundary delimiters with a safe placeholder, preventing delimiter
    injection attacks where test source could escape the untrusted region.

    Also neutralizes structural record headers (SEARCH SCOPE, REMOVED TESTS,
    CANDIDATE EXISTING COVERAGE, excerpt headers) that could forge trusted
    records inside the nonce-authenticated coverage block.
    """
    result = _FENCE_PATTERNS.sub("[SANITIZED — fence marker removed]", text)
    result = _STRUCTURAL_RECORD_RE.sub(
        "[SANITIZED — structural record removed]", result
    )
    return result


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
_PYTHON_TEST_FUNC_RE = re.compile(
    r"^[ \t]*(?:async\s+)?def\s+(test_\w+)\s*\(", re.MULTILINE
)


def _find_all_test_functions(source: str) -> list[tuple[str, re.Match]]:
    """Find all test function declarations in source using all conventions.

    Supports:
    - XCTest: `func testFoo()`
    - Swift Testing: `@Test func arbitraryName()` / `@Test("label") func …`
    - Python: `def test_foo()` / `async def test_foo()`

    Returns (func_name, match) pairs. Preserves every declaration with a
    distinct captured-group position so that same-named tests in different
    suites/classes are all enumerated. Deduplicates only when multiple regexes
    match the same function declaration (same captured group(1) position).
    """
    seen_group_starts: set[int] = set()
    results: list[tuple[str, re.Match]] = []
    for rx in (_XCTEST_FUNC_RE, _SWIFT_TESTING_FUNC_RE, _PYTHON_TEST_FUNC_RE):
        for m in rx.finditer(source):
            # Use the start of the captured function name to identify unique
            # declarations: @Test func testFoo and func testFoo both capture
            # "testFoo" at the same position, so they are the same declaration.
            group_start = m.start(1)
            if group_start in seen_group_starts:
                continue
            seen_group_starts.add(group_start)
            results.append((m.group(1), m))
    return results


# Regex to find containing type declarations (class, struct, enum, extension)
_CONTAINING_TYPE_RE = re.compile(
    r"^\s*(?:final\s+)?(?:class|struct|enum|extension|actor)\s+(\w+)",
    re.MULTILINE,
)


def _find_containing_type(source: str, func_offset: int, path: str = "") -> str:
    """Find the enclosing type name for a function at the given character offset.

    Searches backwards from the function position for the nearest type
    declaration (class/struct/enum/extension/actor). Returns empty string
    if no containing type is found (top-level function).

    For Python files, uses indentation-aware scoping: a function is inside a
    class only if the function line is indented deeper than the class
    declaration line. This prevents module-level functions after a class from
    being incorrectly associated with that class.
    """
    is_python = path.endswith(".py")

    if is_python:
        # Python: indentation determines scope. Find the function's line and
        # its indentation, then look for the nearest preceding class whose
        # indentation is strictly less.
        func_line_start = source.rfind("\n", 0, func_offset) + 1
        func_line = source[func_line_start:func_offset + 80]  # enough for indent
        func_indent = len(func_line) - len(func_line.lstrip())

        best_name = ""
        for m in _CONTAINING_TYPE_RE.finditer(source):
            if m.start() >= func_offset:
                break
            class_line = source[m.start():m.end()]
            class_indent = len(class_line) - len(class_line.lstrip())
            if class_indent < func_indent:
                best_name = m.group(1)
            else:
                # A class at the same or deeper indentation cannot contain
                # this function — reset.
                best_name = ""
        return best_name

    # Non-Python (Swift etc.): nearest preceding type declaration
    best_name = ""
    for m in _CONTAINING_TYPE_RE.finditer(source):
        if m.start() < func_offset:
            best_name = m.group(1)
        else:
            break
    return best_name

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
    body_snippet: str  # first ~200 chars of the removed test body (for display)
    full_body: str = ""  # full extracted body for symbol analysis
    containing_type: str = ""  # enclosing class/struct/enum for qualified identity


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


def _git_blob_size(ref_path: str) -> Optional[int]:
    """Get the byte size of a git blob without reading its content.

    Uses `git cat-file -s <ref>` which returns size without full capture.
    Returns None on failure.
    """
    result = run_git(["cat-file", "-s", ref_path])
    if result is None:
        return None
    try:
        return int(result.strip())
    except (ValueError, AttributeError):
        return None


def _bounded_blob_read(
    ref_path: str, max_bytes: int
) -> tuple[Optional[str], bool]:
    """Read a git blob only if it does not exceed max_bytes.

    Returns (content, was_oversize). If oversize, content is None and
    was_oversize is True. If the read fails for other reasons, content is None
    and was_oversize is False.
    """
    size = _git_blob_size(ref_path)
    if size is not None and size > max_bytes:
        return None, True
    # Size is within bounds (or unknown — fall through to full read and
    # check post-hoc for safety)
    content = run_git(["show", ref_path])
    if content is None:
        return None, False
    # Post-hoc check in case cat-file -s was unavailable
    if len(content.encode("utf-8", "replace")) > max_bytes:
        return None, True
    return content, False


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
    # Build HEAD qualified function identity set (type.func_name) for removal
    # check. Using qualified identity prevents a same-named test in a different
    # suite/class from hiding a true removal.
    head_qualified_names: set[str] = set()
    if head_source is not None:
        for name, m in _find_all_test_functions(head_source):
            containing = _find_containing_type(head_source, m.start(), path)
            qualified = f"{containing}.{name}" if containing else name
            head_qualified_names.add(qualified)

    results: list[RemovedTest] = []

    for func_name, match in _find_all_test_functions(base_source):
        func_start_line = base_source[: match.start()].count("\n") + 1
        func_end_line = _find_func_end(base_lines, func_start_line - 1, path)

        overlap = any(
            func_start_line <= ln <= func_end_line for ln in removed_lines
        )
        if not overlap:
            continue

        # Determine qualified identity for this function in base
        base_containing = _find_containing_type(base_source, match.start(), path)

        # Verify the function declaration is actually absent from HEAD.
        if head_read_succeeded:
            qualified = (
                f"{base_containing}.{func_name}" if base_containing
                else func_name
            )
            if qualified in head_qualified_names:
                # Function still exists at HEAD in the same type — modified, not removed
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
        # Full body for symbol extraction (bounded by func_end_line)
        full_body = "\n".join(base_lines[body_start:func_end_line])
        # Sanitize snippet — base content is also PR-controlled in principle
        snippet = sanitize_untrusted_content(snippet)
        full_body = sanitize_untrusted_content(full_body)
        results.append(RemovedTest(
            file=path, func_name=func_name, body_snippet=snippet,
            full_body=full_body, containing_type=base_containing,
        ))

    return results


def _find_func_end(lines: list[str], start_idx: int, path: str = "") -> int:
    """Find the closing line of a function starting at start_idx (0-based).

    Returns 1-based line number. Language detection is path-based:
    - `.py` files: indentation-based (Python dict/set literals contain braces
      that would falsely terminate brace counting)
    - All other files: brace counting (Swift/C-family)

    The `path` parameter enables correct language dispatch. When omitted,
    falls back to brace-first with indentation fallback (legacy behavior).
    """
    # Language-aware dispatch: Python files MUST use indentation parsing
    # because dict/set literals ({...}) would terminate brace counting early.
    if path.endswith(".py"):
        return _find_func_end_python(lines, start_idx)

    # Swift/C-family: lexical-aware brace counting that skips braces
    # inside string literals, comments, and @Test(...) label parameters.
    depth = 0
    started = False
    for i in range(start_idx, min(start_idx + 500, len(lines))):
        line = lines[i]
        j = 0
        while j < len(line):
            ch = line[j]
            # Skip single-line comments
            if ch == '/' and j + 1 < len(line) and line[j + 1] == '/':
                break  # rest of line is comment
            # Skip string literals (double-quoted)
            if ch == '"':
                j += 1
                while j < len(line) and line[j] != '"':
                    if line[j] == '\\':
                        j += 1  # skip escaped char
                    j += 1
                j += 1  # skip closing quote
                continue
            if ch == "{":
                depth += 1
                started = True
            elif ch == "}":
                depth -= 1
                if started and depth == 0:
                    return i + 1  # 1-based
            j += 1
    if started:
        return min(start_idx + 50, len(lines))

    # No braces found at all — fall back to indentation (handles edge cases)
    return _find_func_end_python(lines, start_idx)


def _find_func_end_python(lines: list[str], start_idx: int) -> int:
    """Indentation-based function end detection for Python.

    The function body is everything indented more than the def line,
    including blank lines between indented lines.
    """
    def_line = lines[start_idx] if start_idx < len(lines) else ""
    base_indent = len(def_line) - len(def_line.lstrip())
    last_body = start_idx
    for i in range(start_idx + 1, min(start_idx + 500, len(lines))):
        line = lines[i]
        if line.strip() == "":
            continue  # blank lines are part of the body
        line_indent = len(line) - len(line.lstrip())
        if line_indent > base_indent:
            last_body = i
        else:
            break
    return last_body + 1  # 1-based


def extract_production_symbols(removed_tests: list[RemovedTest]) -> set[str]:
    """Extract production symbol names referenced in removed test bodies.

    Filters out common test/framework/mock identifiers that would cause
    spurious matches — only production-shaped symbols are returned.
    """
    # Symbols that are test infrastructure, not production code
    _NON_PRODUCTION_SYMBOLS = {
        # XCTest framework
        "XCTest", "XCTestCase", "XCTestExpectation", "XCTAssert",
        "XCTAssertEqual", "XCTAssertTrue", "XCTAssertFalse",
        "XCTAssertNil", "XCTAssertNotNil", "XCTAssertThrowsError",
        "XCTAssertNoThrow", "XCTFail", "XCTUnwrap", "XCTSkip",
        # Swift Testing framework
        "Test", "Testing", "Suite", "Tag", "Trait",
        "Expect", "Issue", "Confirmation",
        # Common mock/stub/fake prefixes handled below
        "Mock", "Stub", "Fake", "Spy",
        # Standard library / system frameworks / common stdlib types
        "Foundation", "Combine", "SwiftUI", "UIKit",
        "Task", "Result", "Error", "Optional",
        "String", "Int", "Bool", "Double", "Float", "Array", "Dictionary",
        "Set", "Data", "URL", "Date", "UUID",
        # Networking / system types frequently seen in test bodies
        "JSONDecoder", "JSONEncoder", "URLSession", "URLRequest",
        "HTTPURLResponse", "URLResponse",
        # Concurrency / system types
        "DispatchQueue", "OperationQueue",
        # Observation / notification
        "NotificationCenter", "UserDefaults", "FileManager",
        "Bundle", "ProcessInfo",
    }

    symbols: set[str] = set()
    for test in removed_tests:
        # Use full_body when available for complete symbol extraction;
        # fall back to body_snippet for backward compatibility.
        source_text = test.full_body if test.full_body else test.body_snippet
        # Look for CamelCase identifiers that look like production types/funcs
        words = re.findall(r"\b([A-Z]\w{2,})\b", source_text)
        symbols.update(words)
        # Also look for common patterns like `sut.methodName`, `Command.run`
        methods = re.findall(r"\.(\w+)\s*\(", source_text)
        symbols.update(m for m in methods if len(m) > 2)

    # Filter non-production symbols
    symbols -= _NON_PRODUCTION_SYMBOLS
    # Also filter anything starting with Mock/Stub/Fake prefix
    symbols = {
        s for s in symbols
        if not s.startswith("Mock") and not s.startswith("Stub")
        and not s.startswith("Fake") and not s.startswith("Spy")
    }
    # Suppress low-signal lowercase method tokens (init, run, shared, map,
    # etc.) that cause false matches against unrelated candidates. These are
    # too common to be meaningful search terms on their own. Only keep them
    # if a domain-type CamelCase signal also exists — the CamelCase symbol
    # already provides the selectivity needed.
    _LOW_SIGNAL_METHODS = {
        "init", "run", "shared", "map", "get", "set", "start", "stop",
        "reset", "update", "delete", "create", "load", "save", "parse",
        "handle", "execute", "call", "send", "receive", "fetch", "post",
        "put", "remove", "add", "build", "make", "setup", "teardown",
        "configure", "validate", "process", "perform", "apply", "cancel",
        "close", "open", "read", "write", "main", "test", "value",
    }
    symbols -= _LOW_SIGNAL_METHODS
    return symbols


def find_related_tests_in_head(
    head_sha: str,
    test_files: list[str],
    production_symbols: set[str],
    max_excerpt_bytes: int,
) -> tuple[list[str], list[str]]:
    """Find existing test functions in HEAD that reference the same symbols.

    Results are ADVISORY CANDIDATES — symbol co-occurrence is necessary but
    not sufficient proof of equivalent branch coverage. The reviewer must
    verify that a candidate actually exercises the same production branch
    before concluding coverage is preserved.

    Returns (excerpts, file_outcomes) where file_outcomes tracks what
    actually happened to each candidate file:
    - "read: <path>" — successfully read and scanned
    - "skipped-oversize: <path>" — exceeded COVERAGE_MAX_FILE_BYTES
    - "budget-omitted: <path>" — not reached due to COVERAGE_MAX_TOTAL_BYTES
    """
    if not production_symbols:
        return [], []

    excerpts: list[str] = []
    file_outcomes: list[str] = []
    total_bytes = 0
    budget_exhausted = False
    # Pre-compute omission marker so its bytes can be reserved in budget
    _OMISSION_MARKER = (
        f"[additional matching tests omitted — "
        f"{COVERAGE_MAX_TOTAL_BYTES}-byte cap reached]"
    )
    _OMISSION_MARKER_BYTES = len(_OMISSION_MARKER.encode("utf-8", "replace"))

    for test_file in test_files:
        if budget_exhausted:
            file_outcomes.append(f"budget-omitted: {test_file}")
            continue

        # Bounded read: check blob size BEFORE capturing full content to
        # prevent oversized PR-controlled blobs from consuming runner memory.
        source, was_oversize = _bounded_blob_read(
            f"{head_sha}:{test_file}", COVERAGE_MAX_FILE_BYTES
        )
        if was_oversize:
            file_outcomes.append(f"skipped-oversize: {test_file}")
            continue
        if source is None:
            raise AnalysisError(
                f"HEAD blob read failed for candidate test file "
                f"'{test_file}' (claimed in SEARCH SCOPE but unreadable)"
            )

        file_outcomes.append(f"read: {test_file}")
        source_lines = source.splitlines()

        for func_name, match in _find_all_test_functions(source):
            func_start = source[: match.start()].count("\n")
            func_end_idx = _find_func_end(source_lines, func_start, test_file)

            func_body = "\n".join(source_lines[func_start:func_end_idx])

            # Check if this test references any of the production symbols
            # using word-boundary matching to avoid false positives from
            # substring containment (e.g. "run" matching "runtime"/"rerun")
            referenced = [
                sym for sym in production_symbols
                if re.search(r'\b' + re.escape(sym) + r'\b', func_body)
            ]
            if not referenced:
                continue

            # Sanitize PR-controlled content before embedding in the prompt
            # to prevent delimiter injection attacks (MY-1456 security fix).
            safe_body = sanitize_untrusted_content(func_body)
            # Path and func name are also PR-controlled — sanitize them
            safe_file = sanitize_untrusted_content(test_file)
            safe_func = sanitize_untrusted_content(func_name)

            excerpt = (
                f"--- {safe_file}: {safe_func} "
                f"(lines {func_start + 1}-{func_end_idx}, "
                f"references: {', '.join(sorted(referenced)[:5])})\n"
                f"{safe_body}"
            )
            excerpt_bytes = len(excerpt.encode("utf-8", "replace"))
            if excerpt_bytes > max_excerpt_bytes:
                # True UTF-8 byte truncation: encode, slice bytes, decode.
                # Use errors="ignore" to drop partial multibyte sequences at
                # the boundary (not "replace" which expands them to 3-byte
                # U+FFFD and overshoots the cap).
                _TRUNC_MARKER = "\n[truncated]"
                _TRUNC_MARKER_BYTES = len(_TRUNC_MARKER.encode("utf-8"))
                usable = max(0, max_excerpt_bytes - _TRUNC_MARKER_BYTES)
                excerpt = (
                    excerpt.encode("utf-8", "replace")[:usable]
                    .decode("utf-8", "ignore")
                    + _TRUNC_MARKER
                )
                excerpt_bytes = len(excerpt.encode("utf-8", "replace"))

            if total_bytes + excerpt_bytes + _OMISSION_MARKER_BYTES > COVERAGE_MAX_TOTAL_BYTES:
                # Include omission marker bytes in budget accounting
                total_bytes += _OMISSION_MARKER_BYTES
                excerpts.append(_OMISSION_MARKER)
                budget_exhausted = True
                break

            excerpts.append(excerpt)
            total_bytes += excerpt_bytes

    return excerpts, file_outcomes


def find_test_files_in_changed_and_related(
    head_sha: str,
    changed_files: list[str],
    production_symbols: Optional[set[str]] = None,
) -> tuple[list[str], list[str]]:
    """Find test files: changed, naming-convention siblings, and repo-wide
    symbol matches. Returns (test_files, searched_paths_summary).

    Only includes files proven present in the HEAD tree — deleted test files
    are excluded so downstream readers do not raise AnalysisError on expected
    absent blobs.

    The searched_paths_summary lists what was actually searched, so the
    evidence block can report scope and the reviewer can judge completeness.
    """
    test_files: list[str] = []
    searched: list[str] = []

    # Fetch the full HEAD tree once for existence checks and symbol search.
    # A None return means git/tool failure — must fail-closed, not silently
    # produce empty results (which would be indistinguishable from "no tests").
    tree = run_git(["ls-tree", "-r", "--name-only", head_sha])
    if tree is None:
        raise AnalysisError(
            f"Cannot list HEAD tree ({head_sha}): ls-tree failed "
            f"(git tool error); cannot determine which test files exist"
        )
    all_tree_files = tree.splitlines()
    head_paths: set[str] = set(all_tree_files)

    # 1. Changed test files (only if still present in HEAD)
    for path in changed_files:
        if "Test" in path or "test" in path:
            if path in head_paths:
                test_files.append(path)
                searched.append(f"changed: {path}")
            else:
                searched.append(f"changed-deleted: {path} (excluded — absent from HEAD)")

    # 2. Sibling test files by naming convention
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

    # 3. Repo-wide bounded symbol search: find test files by filename stems
    # AND by content. First tries filename matching (fast, no blob reads),
    # then does bounded content-based discovery for generically named test
    # files that contain exact domain identifiers.
    if production_symbols:
        # Build search stems from production symbols (CamelCase type names)
        search_stems = {
            sym for sym in production_symbols
            if len(sym) > 3 and sym[0].isupper()
        }
        # 3a. Filename-stem matching (fast — no blob reads needed)
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

        # 3b. Content-based discovery: for test files not yet selected,
        # do a bounded read and check if they contain any production symbol.
        # This catches generically named files (e.g. "IntegrationTests.swift")
        # that reference exact domain identifiers. Bounded by work cap.
        _CONTENT_DISCOVERY_MAX_FILES = 20
        _CONTENT_DISCOVERY_MAX_BYTES = COVERAGE_MAX_FILE_BYTES
        content_candidates = [
            f for f in all_tree_files
            if f not in test_files
            and (f.endswith(".swift") or f.endswith(".py"))
            and ("Test" in f or "test" in f)
        ]
        content_scanned = 0
        for candidate in content_candidates:
            if content_scanned >= _CONTENT_DISCOVERY_MAX_FILES:
                break
            # Bounded read — skip oversized files without full capture
            source, was_oversize = _bounded_blob_read(
                f"{head_sha}:{candidate}", _CONTENT_DISCOVERY_MAX_BYTES
            )
            if was_oversize or source is None:
                continue
            content_scanned += 1
            # Check for word-boundary matches of production symbols
            for sym in search_stems:
                if re.search(r'\b' + re.escape(sym) + r'\b', source):
                    test_files.append(candidate)
                    searched.append(f"content-match({sym}): {candidate}")
                    break

    if not searched:
        searched.append("(no test files found in scope)")

    return test_files, searched


def _merge_search_outcomes(
    discovery: list[str], file_outcomes: list[str],
    *, no_symbols: bool = False,
) -> list[str]:
    """Merge discovery labels with actual read outcomes.

    Discovery labels (from find_test_files_in_changed_and_related) say HOW
    each file was found (changed, sibling, symbol-match). File outcomes (from
    find_related_tests_in_head) say WHAT happened when we tried to read it.

    Only files with outcome "read:" are reported as successfully searched.
    Files skipped or budget-omitted get distinct labels so the reviewer knows
    the scope limitation.

    When no_symbols is True, no production symbols were extracted from the
    removed tests, so find_related_tests_in_head was not invoked with any
    search terms. All discovery entries must be marked not-searched so they
    cannot support negative evidence claims.
    """
    # When no production symbols exist, nothing was actually searched —
    # mark every discovery entry accordingly.
    if no_symbols:
        merged: list[str] = []
        for entry in discovery:
            if "deleted" in entry or "absent" in entry or "excluded" in entry:
                merged.append(entry)
            else:
                merged.append(
                    f"{entry} [not searched — no production symbols extracted]"
                )
        return merged if merged else [
            "(no test files searched — no production symbols extracted)"
        ]
    # Parse outcomes into a lookup: path -> status
    outcome_map: dict[str, str] = {}
    for entry in file_outcomes:
        status, _, path = entry.partition(": ")
        outcome_map[path.strip()] = status.strip()

    merged: list[str] = []
    for entry in discovery:
        # Discovery entries look like "changed: path", "sibling: path", etc.
        # Extract the path portion
        _, _, path_part = entry.partition(": ")
        path = path_part.strip()

        # Entries about deleted files pass through unchanged
        if "deleted" in entry or "absent" in entry or "excluded" in entry:
            merged.append(entry)
            continue

        # Check the actual read outcome for this path
        outcome = outcome_map.get(path, "")
        if outcome == "read":
            merged.append(f"{entry} [read]")
        elif outcome == "skipped-oversize":
            merged.append(f"{entry} [skipped — exceeded {COVERAGE_MAX_FILE_BYTES}-byte file limit]")
        elif outcome == "budget-omitted":
            merged.append(f"{entry} [not reached — {COVERAGE_MAX_TOTAL_BYTES}-byte total budget exhausted]")
        else:
            # File was in discovery but not in test_files passed to
            # find_related_tests_in_head, or no outcome recorded
            merged.append(entry)

    # Add any budget-omitted files not in the original discovery list
    discovery_paths = set()
    for entry in discovery:
        _, _, p = entry.partition(": ")
        discovery_paths.add(p.strip())
    for entry in file_outcomes:
        status, _, path = entry.partition(": ")
        path = path.strip()
        if path not in discovery_paths:
            if status.strip() == "budget-omitted":
                merged.append(f"budget-omitted: {path} [not reached — {COVERAGE_MAX_TOTAL_BYTES}-byte total budget exhausted]")
            elif status.strip() == "skipped-oversize":
                merged.append(f"skipped-oversize: {path} [skipped — exceeded {COVERAGE_MAX_FILE_BYTES}-byte file limit]")

    return merged if merged else ["(no test files found in scope)"]


def build_coverage_evidence(
    head_sha: str,
    base_sha: str,
    diff_text: str,
    changed_files: list[str],
) -> str:
    """Main entry: build coverage context block for the review prompt.

    Returns empty string when the analyzer detects no removed tests (normal case).
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
    related_excerpts, file_outcomes = find_related_tests_in_head(
        head_sha, test_files, symbols, COVERAGE_MAX_EXCERPT_BYTES
    )

    # Step 5: Render with accurate search scope — merge discovery context
    # from find_test_files_in_changed_and_related with actual read outcomes
    # from find_related_tests_in_head so the output only claims "searched"
    # for files that were actually read.
    # When production_symbols is empty, find_related_tests_in_head returns
    # no outcomes — discovery entries must be marked not-searched so they
    # cannot support negative evidence.
    accurate_scope = _merge_search_outcomes(
        searched_summary, file_outcomes, no_symbols=not symbols
    )

    return render_coverage_evidence(
        all_removed, related_excerpts, accurate_scope
    )


def render_coverage_evidence(
    removed_tests: list[RemovedTest],
    related_excerpts: list[str],
    searched_summary: Optional[list[str]] = None,
) -> str:
    """Render the coverage evidence block.

    Path/name values from removed_tests and searched_summary originate from
    PR-controlled content (file paths can be attacker-chosen). They are
    sanitized before embedding to prevent injection into the reviewer prompt.

    Enforces COVERAGE_MAX_TOTAL_BYTES over the ENTIRE rendered output —
    including removed-test records, SEARCH SCOPE metadata, headers, excerpts,
    and exactly one omission marker. This prevents unbounded metadata from
    consuming runner memory.
    """
    if not removed_tests:
        return ""

    _TOTAL_OMISSION = (
        f"\n[output truncated — {COVERAGE_MAX_TOTAL_BYTES}-byte total cap reached]\n"
    )
    _TOTAL_OMISSION_BYTES = len(_TOTAL_OMISSION.encode("utf-8"))

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
        # Sanitize path and func_name — they are PR-controlled values
        safe_file = sanitize_untrusted_content(rt.file)
        safe_name = sanitize_untrusted_content(rt.func_name)
        parts.append(f"  - {safe_file}: {safe_name}")

    parts.append("")

    # Report search scope so the reviewer can judge completeness
    if searched_summary:
        parts.append("SEARCH SCOPE (files actually searched for related tests):")
        for s in searched_summary:
            # Sanitize — path values within are PR-controlled
            parts.append(f"  - {sanitize_untrusted_content(s)}")
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

    # Enforce COVERAGE_MAX_TOTAL_BYTES over the entire rendered output.
    result = "\n".join(parts)
    result_bytes = len(result.encode("utf-8", "replace"))
    if result_bytes > COVERAGE_MAX_TOTAL_BYTES:
        # Truncate to fit within budget including the omission marker
        usable = max(0, COVERAGE_MAX_TOTAL_BYTES - _TOTAL_OMISSION_BYTES)
        result = (
            result.encode("utf-8", "replace")[:usable]
            .decode("utf-8", "ignore")
            + _TOTAL_OMISSION
        )

    return result


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
