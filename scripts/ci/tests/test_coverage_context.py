#!/usr/bin/env python3
"""Deterministic coverage for the review gate's coverage context builder (MY-1456).

Reproduces the false-positive shape: a diff removes obsolete throw-path tests
while an existing full-source test already covers the returned-response branch.
The coverage context must surface the existing test, preventing the reviewer
from reporting "missing coverage" as a blocker.
"""

from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from coverage_context import (  # noqa: E402
    RemovedTest,
    build_coverage_evidence,
    extract_production_symbols,
    find_removed_test_functions,
    removed_line_numbers,
    render_coverage_evidence,
    _find_func_end,
)

# --- Fixture: mimics the PR #185 failure shape ---

# Production file that has a returned-ok=false branch
PROD_SOURCE = """\
import Foundation

struct BriefingPublishCommand {
    let client: APIClient

    func run() async throws -> PublishResult {
        let response = try await client.put(briefing)
        if response.ok {
            return .success(response.briefing)
        } else {
            // returned-ok=false production branch (line 10-12)
            return .failure(response.error ?? "unknown")
        }
    }
}
"""

# Test file at HEAD that STILL covers the returned-ok=false branch
EXISTING_TEST_SOURCE = """\
import XCTest
@testable import AIDashCLI

final class BriefingPublishCommandTests: XCTestCase {
    func testPublishSuccess() async throws {
        let client = MockAPIClient(response: .init(ok: true, briefing: .mock))
        let cmd = BriefingPublishCommand(client: client)
        let result = try await cmd.run()
        XCTAssertEqual(result, .success(.mock))
    }

    func testPublishReturnedFalse() async throws {
        // This test covers the returned-ok=false branch
        let client = MockAPIClient(response: .init(ok: false, error: "rate limited"))
        let cmd = BriefingPublishCommand(client: client)
        let result = try await cmd.run()
        XCTAssertEqual(result, .failure("rate limited"))
    }

    func testPublishReturnedFalseNilError() async throws {
        let client = MockAPIClient(response: .init(ok: false, error: nil))
        let cmd = BriefingPublishCommand(client: client)
        let result = try await cmd.run()
        XCTAssertEqual(result, .failure("unknown"))
    }
}
"""

# The diff removes an OBSOLETE throw-path test (the old API used to throw)
REMOVAL_DIFF = """\
diff --git a/CLI/aidash/Tests/BriefingPublishCommandTests.swift b/CLI/aidash/Tests/BriefingPublishCommandTests.swift
index abc1234..def5678 100644
--- a/CLI/aidash/Tests/BriefingPublishCommandTests.swift
+++ b/CLI/aidash/Tests/BriefingPublishCommandTests.swift
@@ -25,15 +25,0 @@ final class BriefingPublishCommandTests: XCTestCase {
-    func testPublishThrowsOnNetworkError() async throws {
-        // OBSOLETE: old API threw on network error; new API returns ok=false
-        let client = MockAPIClient(throwing: NetworkError.timeout)
-        let cmd = BriefingPublishCommand(client: client)
-        do {
-            _ = try await cmd.run()
-            XCTFail("should have thrown")
-        } catch {
-            XCTAssertTrue(error is NetworkError)
-        }
-    }
-
-    func testPublishThrowsOnInvalidPayload() async throws {
-        let client = MockAPIClient(throwing: ValidationError.invalid)
-        let cmd = BriefingPublishCommand(client: client)
-        await XCTAssertThrowsError(try await cmd.run())
-    }
"""

# Also test the BriefingPut equivalent coverage file
BRIEFING_PUT_TEST_SOURCE = """\
import XCTest
@testable import AIDashCLI

final class BriefingPutCommandTests: XCTestCase {
    func testPutReturnedFalse() async throws {
        let client = MockAPIClient(response: .init(ok: false, error: "quota"))
        let cmd = BriefingPutCommand(client: client)
        let result = try await cmd.run()
        XCTAssertEqual(result, .failure("quota"))
    }
}
"""


def _stub_git(monkeypatch, file_map, base_file_map=None):
    """Stub git to return sources from a dict of path→content.

    file_map is used for HEAD (default). base_file_map is used for base SHA
    lookups; if None, HEAD map is used for both.
    """
    import coverage_context

    def fake_run_git(args):
        if args[0] == "show":
            # git show <sha>:<path>
            ref_path = args[1]
            sha_part, _, path = ref_path.partition(":")
            if base_file_map and sha_part == "base123":
                return base_file_map.get(path)
            return file_map.get(path)
        if args[0] == "ls-tree":
            return "\n".join(file_map.keys())
        return None

    monkeypatch.setattr(coverage_context, "run_git", fake_run_git, raising=True)


# --- Tests ---


def test_removed_line_numbers_tracks_base_side():
    path = "CLI/aidash/Tests/BriefingPublishCommandTests.swift"
    numbers = removed_line_numbers(REMOVAL_DIFF, path)
    # Lines 25-41 are removed (17 lines starting at base line 25)
    assert 25 in numbers
    assert 41 in numbers
    assert len(numbers) == 17


def test_removed_line_numbers_ignores_other_files():
    numbers = removed_line_numbers(REMOVAL_DIFF, "unrelated/File.swift")
    assert numbers == ()


def test_find_removed_test_functions_detects_obsolete_tests(monkeypatch):
    # Stub git: BASE has the removed tests, HEAD does NOT have them (truly removed)
    base_source = EXISTING_TEST_SOURCE + """
    func testPublishThrowsOnNetworkError() async throws {
        // OBSOLETE: old API threw on network error
        let client = MockAPIClient(throwing: NetworkError.timeout)
        let cmd = BriefingPublishCommand(client: client)
        do {
            _ = try await cmd.run()
            XCTFail("should have thrown")
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }

    func testPublishThrowsOnInvalidPayload() async throws {
        let client = MockAPIClient(throwing: ValidationError.invalid)
        let cmd = BriefingPublishCommand(client: client)
        await XCTAssertThrowsError(try await cmd.run())
    }
}
"""
    # HEAD source: only the existing tests remain (removed tests are absent)
    head_source = EXISTING_TEST_SOURCE

    import coverage_context

    def fake_run_git(args):
        if args[0] == "show":
            ref_path = args[1]
            if ref_path.startswith("base123:"):
                return base_source
            if ref_path.startswith("head456:"):
                return head_source
        return None

    monkeypatch.setattr(
        coverage_context, "run_git", fake_run_git, raising=True
    )

    path = "CLI/aidash/Tests/BriefingPublishCommandTests.swift"
    removed = find_removed_test_functions(REMOVAL_DIFF, path, "base123", "head456")
    func_names = [r.func_name for r in removed]
    assert "testPublishThrowsOnNetworkError" in func_names
    assert "testPublishThrowsOnInvalidPayload" in func_names


def test_find_removed_test_functions_ignores_modified_not_removed(monkeypatch):
    """A function that has removed lines but still exists at HEAD is not 'removed'."""
    base_source = EXISTING_TEST_SOURCE + """
    func testPublishThrowsOnNetworkError() async throws {
        // Old implementation
        let client = MockAPIClient(throwing: NetworkError.timeout)
        let cmd = BriefingPublishCommand(client: client)
        do {
            _ = try await cmd.run()
            XCTFail("should have thrown")
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }
}
"""
    # HEAD still has the function (it was modified, not removed)
    head_source = EXISTING_TEST_SOURCE + """
    func testPublishThrowsOnNetworkError() async throws {
        // Refactored: now tests the new API
        let client = MockAPIClient(response: .init(ok: false, error: "timeout"))
        let cmd = BriefingPublishCommand(client: client)
        let result = try await cmd.run()
        XCTAssertEqual(result, .failure("timeout"))
    }
}
"""
    import coverage_context

    def fake_run_git(args):
        if args[0] == "show":
            ref_path = args[1]
            if ref_path.startswith("base123:"):
                return base_source
            if ref_path.startswith("head456:"):
                return head_source
        return None

    monkeypatch.setattr(
        coverage_context, "run_git", fake_run_git, raising=True
    )

    path = "CLI/aidash/Tests/BriefingPublishCommandTests.swift"
    removed = find_removed_test_functions(REMOVAL_DIFF, path, "base123", "head456")
    # testPublishThrowsOnNetworkError still exists at HEAD — not reported as removed
    func_names = [r.func_name for r in removed]
    assert "testPublishThrowsOnNetworkError" not in func_names


def test_extract_production_symbols_finds_relevant_types():
    removed = [
        RemovedTest(
            file="Tests/FooTests.swift",
            func_name="testPublishThrowsOnNetworkError",
            body_snippet="let cmd = BriefingPublishCommand(client: client)\n_ = try await cmd.run()",
        )
    ]
    symbols = extract_production_symbols(removed)
    assert "BriefingPublishCommand" in symbols
    assert "run" in symbols
    # Mock/framework symbols should be filtered out
    assert "MockAPIClient" not in symbols


def test_extract_production_symbols_filters_framework_symbols():
    removed = [
        RemovedTest(
            file="Tests/FooTests.swift",
            func_name="testSomething",
            body_snippet="XCTAssertEqual(result, .failure)\nlet mock = MockService()",
        )
    ]
    symbols = extract_production_symbols(removed)
    assert "XCTAssertEqual" not in symbols
    assert "MockService" not in symbols


def test_render_coverage_evidence_includes_removed_and_existing():
    removed = [
        RemovedTest(
            file="Tests/Foo.swift",
            func_name="testOldThrowPath",
            body_snippet="let cmd = FooCommand()",
        )
    ]
    excerpts = [
        "--- Tests/Foo.swift: testNewCoverage (lines 10-20, references: FooCommand)\nfunc testNewCoverage() { ... }"
    ]
    result = render_coverage_evidence(removed, excerpts)
    assert "COVERAGE CONTEXT" in result
    assert "testOldThrowPath" in result
    assert "testNewCoverage" in result
    assert "CANDIDATE EXISTING COVERAGE" in result
    assert "ADVISORY" in result


def test_render_coverage_evidence_empty_when_no_removed():
    result = render_coverage_evidence([], [])
    # No removed tests → nothing rendered
    assert result == ""


def test_render_coverage_evidence_states_no_related_tests():
    removed = [
        RemovedTest(
            file="Tests/Foo.swift",
            func_name="testSomething",
            body_snippet="XCTAssert(true)",
        )
    ]
    result = render_coverage_evidence(removed, [])
    assert "No related existing tests found" in result


def test_full_pipeline_surfaces_existing_coverage(monkeypatch):
    """The main false-positive shape from MY-1456: obsolete throw-path tests
    are removed, but returned-ok=false coverage exists at HEAD. The coverage
    context must surface testPublishReturnedFalse as existing coverage."""

    # HEAD file map: the existing tests remain, obsolete ones are gone
    head_file_map = {
        "CLI/aidash/Tests/BriefingPublishCommandTests.swift": EXISTING_TEST_SOURCE,
        "CLI/aidash/Sources/BriefingPublishCommand.swift": PROD_SOURCE,
        "CLI/aidash/Tests/BriefingPutCommandTests.swift": BRIEFING_PUT_TEST_SOURCE,
    }

    # BASE file map: includes the obsolete tests that were removed
    base_test_source = EXISTING_TEST_SOURCE.rstrip().rstrip("}") + """
    func testPublishThrowsOnNetworkError() async throws {
        // OBSOLETE: old API threw on network error
        let client = MockAPIClient(throwing: NetworkError.timeout)
        let cmd = BriefingPublishCommand(client: client)
        do {
            _ = try await cmd.run()
            XCTFail("should have thrown")
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }

    func testPublishThrowsOnInvalidPayload() async throws {
        let client = MockAPIClient(throwing: ValidationError.invalid)
        let cmd = BriefingPublishCommand(client: client)
        await XCTAssertThrowsError(try await cmd.run())
    }
}
"""
    base_file_map = {
        "CLI/aidash/Tests/BriefingPublishCommandTests.swift": base_test_source,
        "CLI/aidash/Sources/BriefingPublishCommand.swift": PROD_SOURCE,
        "CLI/aidash/Tests/BriefingPutCommandTests.swift": BRIEFING_PUT_TEST_SOURCE,
    }

    _stub_git(monkeypatch, head_file_map, base_file_map)

    result = build_coverage_evidence(
        head_sha="ef2754a",
        base_sha="base123",
        diff_text=REMOVAL_DIFF,
        changed_files=[
            "CLI/aidash/Tests/BriefingPublishCommandTests.swift",
            "CLI/aidash/Sources/BriefingPublishCommand.swift",
        ],
    )

    # The coverage context must mention existing tests as advisory candidates
    assert "COVERAGE CONTEXT" in result
    assert "testPublishReturnedFalse" in result or "CANDIDATE EXISTING COVERAGE" in result


def test_no_removed_tests_yields_empty(monkeypatch):
    """When no tests are removed, coverage context is empty (normal case)."""
    import coverage_context
    monkeypatch.setattr(
        coverage_context, "run_git", lambda args: PROD_SOURCE, raising=True
    )

    # A diff that only adds lines (no removals)
    add_only_diff = """\
diff --git a/CLI/aidash/Sources/Foo.swift b/CLI/aidash/Sources/Foo.swift
--- a/CLI/aidash/Sources/Foo.swift
+++ b/CLI/aidash/Sources/Foo.swift
@@ -1,2 +1,3 @@
 import Foundation
+import Logging
 struct Foo {}
"""
    result = build_coverage_evidence(
        head_sha="abc123",
        base_sha="base123",
        diff_text=add_only_diff,
        changed_files=["CLI/aidash/Sources/Foo.swift"],
    )
    assert result == ""


def test_find_func_end_handles_simple_function():
    lines = [
        "    func testFoo() {",
        "        XCTAssert(true)",
        "    }",
        "",
        "    func testBar() {",
    ]
    end = _find_func_end(lines, 0)
    assert end == 3  # 1-based line number of closing brace


def test_find_func_end_handles_nested_braces():
    lines = [
        "    func testComplex() {",
        "        if condition {",
        "            doSomething()",
        "        }",
        "        for x in items {",
        "            process(x)",
        "        }",
        "    }",
    ]
    end = _find_func_end(lines, 0)
    assert end == 8
