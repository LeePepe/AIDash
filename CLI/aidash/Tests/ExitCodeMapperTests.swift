import Foundation
import Testing
import AIDashCore

@Suite("ExitCodeMapper")
struct ExitCodeMapperTests {

    // MARK: - Schema errors → exit 1

    @Test("schema.* prefix maps to exit code 1")
    func schemaErrors() {
        let cases = [
            "schema.unknown_card_type",
            "schema.invalid_date",
            "schema.missing_field",
        ]
        for code in cases {
            let error = XPCError(code: code, message: "test")
            #expect(ExitCodeMapper.code(for: error) == 1, "Expected 1 for \(code)")
        }
    }

    // MARK: - XPC transport errors → exit 2

    @Test("xpc.* prefix maps to exit code 2")
    func xpcErrors() {
        let cases = [
            "xpc.app_unavailable",
            "xpc.app_launch_failed",
            "xpc.timeout",
        ]
        for code in cases {
            let error = XPCError(code: code, message: "test")
            #expect(ExitCodeMapper.code(for: error) == 2, "Expected 2 for \(code)")
        }
    }

    // MARK: - Remote/other errors → exit 3

    @Test("non-schema non-xpc codes map to exit code 3")
    func remoteErrors() {
        let cases = [
            "storage.quota_exceeded",
            "not_found",
            "internal",
            "briefing.not_found",
            "cloudkit.conflict",
        ]
        for code in cases {
            let error = XPCError(code: code, message: "test")
            #expect(ExitCodeMapper.code(for: error) == 3, "Expected 3 for \(code)")
        }
    }

    // MARK: - Edge cases

    @Test("empty code maps to exit code 3")
    func emptyCode() {
        let error = XPCError(code: "", message: "unknown")
        #expect(ExitCodeMapper.code(for: error) == 3)
    }

    @Test("code containing but not prefixed with schema maps to 3")
    func containsSchemaButNotPrefix() {
        let error = XPCError(code: "invalid.schema.error", message: "test")
        #expect(ExitCodeMapper.code(for: error) == 3)
    }

    @Test("code containing but not prefixed with xpc maps to 3")
    func containsXpcButNotPrefix() {
        let error = XPCError(code: "internal.xpc.wrapped", message: "test")
        #expect(ExitCodeMapper.code(for: error) == 3)
    }
}
