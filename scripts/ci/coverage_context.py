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

import json
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


def _json_encode_untrusted(value: str) -> str:
    """Encode a PR-controlled value as a JSON string literal.

    All control characters (newlines, tabs, etc.), backslashes, and double
    quotes are escaped per RFC 8259. The result is always a single line
    surrounded by double quotes, making it impossible for an attacker to
    inject newlines that create additional output lines, structural record
    headers, or reviewer directives.

    Use this for every PR-controlled path/name value embedded in rendered
    evidence (REMOVED TESTS, SEARCH SCOPE, candidate headers). The
    analyzer's internal logic uses lossless original values; encoding is
    applied only at render time.
    """
    return json.dumps(value, ensure_ascii=False)


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
    r"^[ \t]*(?:final\s+)?(?:class|struct|enum|extension|actor)\s+(\w+)",
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

    # Non-Python (Swift etc.): lexical enclosure via brace tracking.
    # A function is "inside" a type only if the type's opening brace has been
    # reached and its scope has not yet closed at the function's position.
    # This correctly handles top-level functions after a closed type, and
    # nested types (innermost enclosing wins).
    #
    # Algorithm: scan the source up to func_offset character by character,
    # maintaining a stack of (type_name, depth_when_opened). When a type
    # declaration's opening `{` is found, push it. When depth returns to that
    # level, pop it. Whatever remains on the stack at func_offset is the
    # enclosing type chain; return the innermost (top of stack).
    type_stack: list[tuple[str, int]] = []  # (name, brace_depth_at_open)
    # Find all type declarations before func_offset
    type_positions: list[tuple[int, str]] = []
    for m in _CONTAINING_TYPE_RE.finditer(source):
        if m.start() >= func_offset:
            break
        type_positions.append((m.end(), m.group(1)))

    if not type_positions:
        return ""

    # Scan source up to func_offset tracking brace depth and type scopes
    depth = 0
    type_idx = 0  # next type_positions entry to process
    in_block_comment = 0
    in_multiline_string = False
    raw_string_hashes = 0
    i = 0
    src_limit = func_offset
    while i < src_limit:
        ch = source[i]

        # Block comment state
        if in_block_comment > 0:
            if ch == '/' and i + 1 < src_limit and source[i + 1] == '*':
                in_block_comment += 1
                i += 2
                continue
            if ch == '*' and i + 1 < src_limit and source[i + 1] == '/':
                in_block_comment -= 1
                i += 2
                continue
            i += 1
            continue

        # Multiline string state
        if in_multiline_string:
            if ch == '\\':
                i += 2
                continue
            if (ch == '"' and i + 2 < src_limit
                    and source[i + 1] == '"' and source[i + 2] == '"'):
                in_multiline_string = False
                i += 3
                continue
            i += 1
            continue

        # Raw string state
        if raw_string_hashes > 0:
            if ch == '"':
                closing = True
                for k in range(1, raw_string_hashes + 1):
                    if i + k >= src_limit or source[i + k] != '#':
                        closing = False
                        break
                if closing:
                    i += 1 + raw_string_hashes
                    raw_string_hashes = 0
                    continue
            i += 1
            continue

        # Single-line comment
        if ch == '/' and i + 1 < src_limit and source[i + 1] == '/':
            # Skip to end of line
            nl = source.find('\n', i)
            i = nl + 1 if nl != -1 else src_limit
            continue

        # Block comment start
        if ch == '/' and i + 1 < src_limit and source[i + 1] == '*':
            in_block_comment = 1
            i += 2
            continue

        # Raw string
        if ch == '#':
            hash_count = 0
            while i + hash_count < src_limit and source[i + hash_count] == '#':
                hash_count += 1
            if i + hash_count < src_limit and source[i + hash_count] == '"':
                raw_string_hashes = hash_count
                i += hash_count + 1
                continue
            i += 1
            continue

        # Multiline string
        if (ch == '"' and i + 2 < src_limit
                and source[i + 1] == '"' and source[i + 2] == '"'):
            in_multiline_string = True
            i += 3
            continue

        # Single-line string
        if ch == '"':
            i += 1
            while i < src_limit and source[i] != '"':
                if source[i] == '\\':
                    i += 1
                i += 1
            i += 1  # skip closing quote
            continue

        # Brace tracking
        if ch == '{':
            depth += 1
            # Check if any type declaration's end position is before this {
            # and hasn't been assigned yet — this { opens that type's scope.
            while (type_idx < len(type_positions)
                   and type_positions[type_idx][0] <= i):
                # This type's opening brace is at current depth
                type_stack.append((type_positions[type_idx][1], depth))
                type_idx += 1
        elif ch == '}':
            # Pop any types whose scope closes at this depth
            while type_stack and type_stack[-1][1] == depth:
                type_stack.pop()
            depth -= 1

        i += 1

    # Any remaining unprocessed types that appear before func_offset but
    # whose opening brace we haven't seen are not enclosing.
    return type_stack[-1][0] if type_stack else ""

# Matches production symbol names: types, functions, protocols.
_SYMBOL_RE = re.compile(
    r"(?:class|struct|enum|protocol|func|actor)\s+(\w+)"
)

# Byte caps — keep total output bounded.
COVERAGE_MAX_FILE_BYTES = 400_000
COVERAGE_MAX_EXCERPT_BYTES = 30_000
COVERAGE_MAX_TOTAL_BYTES = 80_000

# Global work budget: maximum number of file-level blob read operations
# across content-discovery and candidate-read routes combined. This
# prevents unbounded work even when many files match naming conventions.
# Path-only operations (changed/sibling enumeration, filename-stem matching)
# do NOT charge this budget since they use the already-fetched tree list.
COVERAGE_GLOBAL_WORK_BUDGET = 50

# Minimum operations reserved for primary candidate reads (changed/sibling
# files). Content discovery cannot consume more than
# COVERAGE_GLOBAL_WORK_BUDGET - COVERAGE_PRIMARY_RESERVE operations.
# This guarantees that genuine candidates from changed/sibling paths are
# always readable, even in repos with many test files.
COVERAGE_PRIMARY_RESERVE = 15


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
    was_oversize is True. If the size preflight fails (cat-file -s returns
    None), content is None and was_oversize is False — the caller must
    treat this as a read failure and fail closed. No fallback to unbounded
    git show is performed.
    """
    size = _git_blob_size(ref_path)
    if size is None:
        # Size preflight failed — cannot determine if blob is safe to read.
        # Fail closed: do NOT fall through to an unbounded git show.
        return None, False
    if size > max_bytes:
        return None, True
    # Size confirmed within bounds — safe to read content.
    content = run_git(["show", ref_path])
    if content is None:
        return None, False
    return content, False


def _unquote_git_path(raw: str) -> str:
    """Decode a Git C-quoted path back to its literal form.

    Git C-quotes paths containing special characters (newlines, backslashes,
    double quotes, non-ASCII bytes): the path is surrounded by double quotes
    and special bytes are backslash-escaped (\\n, \\t, \\\\, \\", \\ooo octal).
    Unquoted paths are returned unchanged.
    """
    if not raw.startswith('"') or not raw.endswith('"'):
        return raw
    inner = raw[1:-1]
    result: list[str] = []
    i = 0
    while i < len(inner):
        if inner[i] == '\\' and i + 1 < len(inner):
            c = inner[i + 1]
            if c == 'n':
                result.append('\n')
                i += 2
            elif c == 't':
                result.append('\t')
                i += 2
            elif c == '\\':
                result.append('\\')
                i += 2
            elif c == '"':
                result.append('"')
                i += 2
            elif c == 'a':
                result.append('\a')
                i += 2
            elif c == 'b':
                result.append('\b')
                i += 2
            elif c == 'f':
                result.append('\f')
                i += 2
            elif c == 'r':
                result.append('\r')
                i += 2
            elif c == 'v':
                result.append('\v')
                i += 2
            elif '0' <= c <= '7':
                # Octal escape: up to 3 digits
                end = min(i + 4, len(inner))
                octal = ''
                j = i + 1
                while j < end and '0' <= inner[j] <= '7':
                    octal += inner[j]
                    j += 1
                result.append(chr(int(octal, 8)))
                i = j
            else:
                result.append(inner[i])
                i += 1
        else:
            result.append(inner[i])
            i += 1
    return ''.join(result)


def removed_line_numbers(diff_text: str, path: str) -> Tuple[int, ...]:
    """BASE-side line numbers removed from `path` by this diff.

    Handles Git's C-quoting of paths with special characters: paths containing
    newlines, backslashes, double quotes, or non-ASCII bytes are surrounded by
    double quotes with backslash escapes in the `diff --git` header.
    """
    hunk_re = re.compile(r"^@@ -(\d+)(?:,\d+)? \+\d+(?:,\d+)? @@")
    lines = diff_text.splitlines()
    removed: list[int] = []
    in_file = False
    in_hunk = False
    base_line = 0

    for line in lines:
        if line.startswith("diff --git "):
            # Parse the `diff --git a/<path> b/<path>` header.
            # Git may C-quote paths with special characters.
            rest = line[len("diff --git "):]
            # Extract the b/ path: it may be C-quoted with spaces inside.
            # Strategy: find the b/ portion by scanning from the end.
            diff_path = _extract_b_path(rest)
            in_file = (diff_path == path)
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


def _extract_b_path(ab_spec: str) -> str:
    """Extract the b/ path from a `diff --git a/... b/...` payload.

    Handles both plain and C-quoted paths. The payload is everything after
    'diff --git '. For C-quoted paths, finds the opening quote of b/ path.
    """
    # Case 1: b/ path is C-quoted — look for ' "b/' or ' b/"' pattern
    # The pattern is: <a-spec> "b/<quoted-path>"
    idx = ab_spec.find(' "b/')
    if idx != -1:
        quoted = ab_spec[idx + 1:]  # includes the opening quote
        return _unquote_git_path(quoted)[2:]  # strip b/ prefix

    # Case 2: a/ path is C-quoted, b/ path is plain
    # Pattern: "a/<quoted>" b/<plain>
    idx = ab_spec.find('" b/')
    if idx != -1:
        return ab_spec[idx + 4:]  # everything after b/

    # Case 3: both plain — a/<path> b/<path> where both paths are equal.
    # Cannot simply find(' b/') because the path itself may contain ' b/'.
    # Since both sides are equal: total = "a/" + path + " b/" + path
    # Length = 2 + len(path) + 3 + len(path) = 5 + 2*len(path)
    # So len(path) = (len(ab_spec) - 5) / 2 and b-path starts at len(ab_spec) - 2 - len(path).
    # For renamed files (a != b) this doesn't apply, but Git uses C-quoting for those.
    if ab_spec.startswith("a/") and len(ab_spec) >= 7:
        # Verify: length must be odd+5 pattern: "a/" + path + " b/" + path
        remainder = len(ab_spec) - 5  # subtract "a/" + " b/"
        if remainder > 0 and remainder % 2 == 0:
            path_len = remainder // 2
            b_start = 2 + path_len + 3  # skip "a/<path> b/"
            candidate = ab_spec[b_start:]
            # Verify a-path == b-path for consistency
            a_path = ab_spec[2:2 + path_len]
            if a_path == candidate:
                return candidate
    # Fallback: last occurrence of ' b/' (most specific split point)
    idx = ab_spec.rfind(' b/')
    if idx != -1:
        return ab_spec[idx + 3:]

    return ""


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

    # Get the BASE version of the file via bounded preflight reader.
    # BASE is trusted content (from the base checkout), but we still enforce
    # explicit bounded/fail-closed policy to prevent unbounded memory capture.
    base_source, base_oversize = _bounded_blob_read(
        f"{base_sha}:{path}", COVERAGE_MAX_FILE_BYTES
    )
    if base_oversize:
        raise AnalysisError(
            f"BASE blob for {base_sha}:{path} exceeds "
            f"{COVERAGE_MAX_FILE_BYTES}-byte limit; cannot analyze"
        )
    if base_source is None:
        # Bounded read failed — check whether the file simply doesn't exist
        # in base (new file) vs a real read/tool error.
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
            f"Cannot read BASE source for {path}: both bounded-read and "
            f"ls-tree failed (git tool error)"
        )

    removed_lines = set(removed_line_numbers(diff_text, path))
    if not removed_lines:
        return []

    # Get HEAD version via bounded preflight reader to verify removal.
    # HEAD blobs are PR-controlled — must never be captured without size check.
    # Distinguish three states: verified-present, verified-absent, unknown.
    head_source: Optional[str] = None
    head_read_succeeded = False
    if head_sha:
        head_source, head_oversize = _bounded_blob_read(
            f"{head_sha}:{path}", COVERAGE_MAX_FILE_BYTES
        )
        if head_oversize:
            # Oversized HEAD blob — fail closed, never capture full content.
            raise AnalysisError(
                f"HEAD blob for {head_sha}:{path} exceeds "
                f"{COVERAGE_MAX_FILE_BYTES}-byte limit; "
                f"cannot verify test removal (fail-closed)"
            )
        if head_source is not None:
            head_read_succeeded = True
        else:
            # Bounded read returned None (size preflight failed or blob read
            # failed). Verify file is truly deleted vs tool error by checking
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
    - All other files: lexical-aware brace counting (Swift/C-family)

    The `path` parameter enables correct language dispatch. When omitted,
    falls back to brace-first with indentation fallback (legacy behavior).

    The Swift lexical scanner handles:
    - Single-line comments (`// ...`)
    - Block comments (`/* ... */`), including nested (`/* /* */ */`)
    - Single-line string literals (`"..."` with backslash escapes)
    - Multiline string literals (`\"\"\"...\"\"\"`)
    - Raw strings (`#"..."#`, `##"..."##`, etc.)

    When braces do not balance within the 500-line scan window, this is an
    explicit truncation — never a silent fallback to an unrelated body size.
    The returned line number is capped at start_idx + 500 (the scan limit).
    """
    # Language-aware dispatch: Python files MUST use indentation parsing
    # because dict/set literals ({...}) would terminate brace counting early.
    if path.endswith(".py"):
        return _find_func_end_python(lines, start_idx)

    # Swift/C-family: full lexical-aware brace counting.
    depth = 0
    started = False
    in_block_comment = 0  # nesting depth for block comments
    in_multiline_string = False
    # Raw string state: 0 = not in raw string; >0 = number of # in delimiter
    raw_string_hashes = 0

    scan_end = min(start_idx + 500, len(lines))
    for i in range(start_idx, scan_end):
        line = lines[i]
        j = 0
        while j < len(line):
            ch = line[j]

            # --- Inside block comment: only look for nested /* or closing */
            if in_block_comment > 0:
                if ch == '/' and j + 1 < len(line) and line[j + 1] == '*':
                    in_block_comment += 1
                    j += 2
                    continue
                if ch == '*' and j + 1 < len(line) and line[j + 1] == '/':
                    in_block_comment -= 1
                    j += 2
                    continue
                j += 1
                continue

            # --- Inside multiline string (""" ... """)
            if in_multiline_string:
                if ch == '\\':
                    j += 2  # skip escaped char
                    continue
                if (ch == '"' and j + 2 < len(line)
                        and line[j + 1] == '"' and line[j + 2] == '"'):
                    in_multiline_string = False
                    j += 3
                    continue
                j += 1
                continue

            # --- Inside raw string (#"..."#, ##"..."##, etc.)
            if raw_string_hashes > 0:
                if ch == '"':
                    # Check if followed by the right number of #
                    closing = True
                    for k in range(1, raw_string_hashes + 1):
                        if j + k >= len(line) or line[j + k] != '#':
                            closing = False
                            break
                    if closing:
                        j += 1 + raw_string_hashes
                        raw_string_hashes = 0
                        continue
                j += 1
                continue

            # --- Normal code parsing ---

            # Single-line comment
            if ch == '/' and j + 1 < len(line) and line[j + 1] == '/':
                break  # rest of line is comment

            # Block comment start
            if ch == '/' and j + 1 < len(line) and line[j + 1] == '*':
                in_block_comment = 1
                j += 2
                continue

            # Raw string literal: #"..."#, ##"..."##, etc.
            if ch == '#':
                hash_count = 0
                while j + hash_count < len(line) and line[j + hash_count] == '#':
                    hash_count += 1
                if j + hash_count < len(line) and line[j + hash_count] == '"':
                    raw_string_hashes = hash_count
                    j += hash_count + 1  # skip hashes + opening quote
                    continue
                # Not a raw string — just a # character
                j += 1
                continue

            # Multiline string literal (""")
            if (ch == '"' and j + 2 < len(line)
                    and line[j + 1] == '"' and line[j + 2] == '"'):
                in_multiline_string = True
                j += 3
                continue

            # Single-line string literal
            if ch == '"':
                j += 1
                while j < len(line) and line[j] != '"':
                    if line[j] == '\\':
                        j += 1  # skip escaped char
                    j += 1
                j += 1  # skip closing quote
                continue

            # Brace counting
            if ch == "{":
                depth += 1
                started = True
            elif ch == "}":
                depth -= 1
                if started and depth == 0:
                    return i + 1  # 1-based

            j += 1

    # Explicit truncation: braces did not balance within the scan window.
    # Return the scan limit — never a silent 50-line arbitrary body.
    if started:
        return scan_end

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
    work_budget_remaining: int = COVERAGE_GLOBAL_WORK_BUDGET,
    blob_cache: Optional[dict[str, str]] = None,
) -> tuple[list[str], list[str]]:
    """Find existing test functions in HEAD that reference the same symbols.

    Results are ADVISORY CANDIDATES — symbol co-occurrence is necessary but
    not sufficient proof of equivalent branch coverage. The reviewer must
    verify that a candidate actually exercises the same production branch
    before concluding coverage is preserved.

    work_budget_remaining: number of file-level operations allowed. Each file
    read counts. When exhausted, remaining files are reported as budget-omitted.
    Cached reads (from blob_cache) do NOT consume budget operations.

    blob_cache: optional dict of path → content from content-discovery reads.
    Files found in the cache are used without re-reading the blob, saving
    both a budget operation and a git call.

    Returns (excerpts, file_outcomes) where file_outcomes tracks what
    actually happened to each candidate file:
    - "read: <path>" — successfully read and scanned
    - "cached: <path>" — used cached content from discovery
    - "skipped-oversize: <path>" — exceeded COVERAGE_MAX_FILE_BYTES
    - "budget-omitted: <path>" — not reached due to global work budget
    - "read-failed: <path>" — preflight/read tool error (fail-closed)
    """
    if not production_symbols:
        return [], []

    if blob_cache is None:
        blob_cache = {}

    excerpts: list[str] = []
    file_outcomes: list[str] = []
    total_bytes = 0
    budget_exhausted = False
    work_used = 0  # count against work_budget_remaining
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

        # Check blob cache first — cached reads don't consume budget
        if test_file in blob_cache:
            source = blob_cache[test_file]
            file_outcomes.append(f"cached: {test_file}")
        else:
            # Global work budget: each uncached file read counts
            if work_used >= work_budget_remaining:
                file_outcomes.append(f"budget-omitted: {test_file}")
                continue
            work_used += 1

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
            # Path and func name are PR-controlled — sanitize then JSON-encode
            # so they are single-line, preventing newline injection of fake
            # structural records or reviewer directives.
            enc_file = _json_encode_untrusted(sanitize_untrusted_content(test_file))
            enc_func = _json_encode_untrusted(sanitize_untrusted_content(func_name))

            excerpt = (
                f"--- {enc_file}: {enc_func} "
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
) -> tuple[list[str], list[str], int, dict[str, str]]:
    """Find test files: changed, naming-convention siblings, and repo-wide
    symbol matches. Returns (test_files, searched_paths_summary, work_remaining,
    blob_cache).

    work_remaining is the number of file-level operations left in the global
    work budget after discovery. Downstream readers (find_related_tests_in_head)
    must respect this budget for their candidate reads.

    blob_cache maps path → content for blobs already read during content
    discovery. Downstream readers should use cached content instead of
    re-reading the same blob (saves a work-budget operation).

    Only includes files proven present in the HEAD tree — deleted test files
    are excluded so downstream readers do not raise AnalysisError on expected
    absent blobs.

    The searched_paths_summary lists what was actually searched, so the
    evidence block can report scope and the reviewer can judge completeness.

    Budget allocation:
    - Changed/sibling files are enumerated without charging the read budget
      (they are path-only operations against the already-fetched tree).
    - Filename-stem matching is also read-free (string matching only).
    - Only actual blob reads (content discovery) charge the work budget.
    - A minimum of COVERAGE_PRIMARY_RESERVE operations is reserved for
      downstream candidate reads, so primary changed/sibling files are always
      readable even in repos with many test files.
    """
    test_files: list[str] = []
    searched: list[str] = []
    blob_cache: dict[str, str] = {}  # path → content from content-discovery reads
    work_used = 0  # counts only actual blob read operations

    # Fetch the full HEAD tree once for existence checks and symbol search.
    # Uses -z for NUL-delimited output to handle paths with newlines, quotes,
    # backslashes, and non-ASCII losslessly.
    # A None return means git/tool failure — must fail-closed, not silently
    # produce empty results (which would be indistinguishable from "no tests").
    tree = run_git(["ls-tree", "-r", "--name-only", "-z", head_sha])
    if tree is None:
        raise AnalysisError(
            f"Cannot list HEAD tree ({head_sha}): ls-tree failed "
            f"(git tool error); cannot determine which test files exist"
        )
    # Split on NUL; filter empty strings from trailing NUL
    all_tree_files = [f for f in tree.split("\0") if f]
    head_paths: set[str] = set(all_tree_files)

    # 1. Changed test files (only if still present in HEAD)
    # No blob read — path-only check against the already-fetched tree.
    for path in changed_files:
        if "Test" in path or "test" in path:
            if path in head_paths:
                test_files.append(path)
                searched.append(f"changed: {path}")
            else:
                searched.append(f"changed-deleted: {path} (excluded — absent from HEAD)")

    # 2. Sibling test files by naming convention
    # Also read-free: string matching against the already-fetched tree list.
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
    #
    # Content discovery budget: reserve COVERAGE_PRIMARY_RESERVE for
    # downstream candidate reads so changed/sibling files are always readable.
    content_budget = max(0, COVERAGE_GLOBAL_WORK_BUDGET - COVERAGE_PRIMARY_RESERVE)
    if production_symbols:
        # Build search stems from production symbols (CamelCase type names)
        search_stems = sorted({
            sym for sym in production_symbols
            if len(sym) > 3 and sym[0].isupper()
        })
        # 3a. Filename-stem matching (fast — no blob reads, no budget charge)
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
        # that reference exact domain identifiers. Bounded by content_budget.
        content_candidates = [
            f for f in all_tree_files
            if f not in test_files
            and (f.endswith(".swift") or f.endswith(".py"))
            and ("Test" in f or "test" in f)
        ]
        for candidate in content_candidates:
            if work_used >= content_budget:
                searched.append(
                    f"budget-cap: (content-discovery budget "
                    f"{content_budget} exhausted; "
                    f"{COVERAGE_PRIMARY_RESERVE} reserved for candidate reads)"
                )
                break
            # Count every candidate attempted toward the work cap, including
            # oversized/unreadable files, so the bounded-work claim is literal.
            work_used += 1
            # Bounded read — oversize files are a bounded outcome (skip).
            # Read/preflight failure is a tool error — fail closed.
            source, was_oversize = _bounded_blob_read(
                f"{head_sha}:{candidate}", COVERAGE_MAX_FILE_BYTES
            )
            if was_oversize:
                searched.append(
                    f"content-skipped-oversize: {candidate} "
                    f"(exceeded {COVERAGE_MAX_FILE_BYTES}-byte file limit)"
                )
                continue
            if source is None:
                raise AnalysisError(
                    f"Content-discovery read failed for candidate "
                    f"'{candidate}' (size preflight or blob read error); "
                    f"cannot determine if file contains relevant tests"
                )
            # Cache the read content so downstream doesn't re-read
            blob_cache[candidate] = source
            # Check for word-boundary matches of production symbols
            for sym in search_stems:
                if re.search(r'\b' + re.escape(sym) + r'\b', source):
                    test_files.append(candidate)
                    searched.append(f"content-match({sym}): {candidate}")
                    break

    if not searched:
        searched.append("(no test files found in scope)")

    # Remaining budget for downstream: global budget minus content-discovery
    # reads, but at least COVERAGE_PRIMARY_RESERVE for changed/sibling reads.
    work_remaining = max(
        COVERAGE_PRIMARY_RESERVE,
        COVERAGE_GLOBAL_WORK_BUDGET - work_used,
    )
    return test_files, searched, work_remaining, blob_cache


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
        elif outcome == "cached":
            merged.append(f"{entry} [cached]")
        elif outcome == "skipped-oversize":
            merged.append(f"{entry} [skipped — exceeded {COVERAGE_MAX_FILE_BYTES}-byte file limit]")
        elif outcome == "budget-omitted":
            merged.append(f"{entry} [not reached — global work budget exhausted]")
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
                merged.append(f"budget-omitted: {path} [not reached — global work budget exhausted]")
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
    test_files, searched_summary, work_remaining, blob_cache = (
        find_test_files_in_changed_and_related(
            head_sha, changed_files, symbols
        )
    )

    # Step 4: Find existing tests covering the same symbols
    # Pass remaining work budget and blob cache so candidate reads share the
    # global cap and avoid re-reading already-fetched blobs.
    related_excerpts, file_outcomes = find_related_tests_in_head(
        head_sha, test_files, symbols, COVERAGE_MAX_EXCERPT_BYTES,
        work_budget_remaining=work_remaining,
        blob_cache=blob_cache,
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
        # JSON-encode path and func_name — they are PR-controlled values.
        # JSON encoding escapes all control characters (newlines, tabs),
        # backslashes, and quotes into a single-line string, preventing
        # injection of new lines/records/directives into the evidence block.
        # Sanitize first (neutralize structural keywords), then encode.
        enc_file = _json_encode_untrusted(sanitize_untrusted_content(rt.file))
        enc_name = _json_encode_untrusted(sanitize_untrusted_content(rt.func_name))
        parts.append(f"  - {enc_file}: {enc_name}")

    parts.append("")

    # Report search scope so the reviewer can judge completeness
    if searched_summary:
        parts.append("SEARCH SCOPE (files actually searched for related tests):")
        for s in searched_summary:
            # JSON-encode the entire entry — path values within are
            # PR-controlled and could contain newlines/control chars.
            # Sanitize first (structural keywords), then encode.
            parts.append(f"  - {_json_encode_untrusted(sanitize_untrusted_content(s))}")
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
        # Determine if any files were actually read — only "[read]" or
        # "[cached]" annotations in searched_summary represent genuine searches.
        # If zero files were read and we have scope info, cannot support
        # negative evidence claims.
        actually_read = False
        if searched_summary:
            for s in searched_summary:
                if "[read]" in s or "[cached]" in s:
                    actually_read = True
                    break
        if searched_summary is not None and not actually_read:
            parts.append(
                "INCONCLUSIVE — no test files were actually read within the work "
                "budget. Cannot determine whether related coverage exists. "
                "Reviewer must not claim coverage loss based on this result."
            )
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
