import Foundation
import Testing
import AIDashCore

/// Tests for `XPCClient.resultForResponse` — the pure mapping utility that
/// classifies `XPCResponse.ok == false` into a `.failure(XPCError)`.
///
/// Since MY-1455, `handleReply` no longer calls `resultForResponse`; it
/// returns decoded responses (including `ok=false`) directly to the caller.
/// This means `execute()` only throws for transport/decode failures, and
/// remote errors are returned as `XPCResponse` values so commands can access
/// `response.requestId` for structured error output.
///
/// `resultForResponse` remains a public utility for callers that want the
/// old classification (e.g. `ExitCodeMapper` tests); these tests verify it
/// still works correctly as a standalone classifier.
@Suite("XPCClient response mapping")
struct XPCClientResponseMappingTests {

    // MARK: - Success path

    @Test("ok == true returns success with the original response")
    func okReturnsSuccess() throws {
        let response = XPCResponse(
            requestId: "req-1",
            appVersion: "1.0.0",
            ok: true,
            data: Data("{}".utf8),
            error: nil
        )

        let result = XPCClient.resultForResponse(response)

        switch result {
        case .success(let value):
            #expect(value.requestId == "req-1")
            #expect(value.ok == true)
        case .failure(let error):
            Issue.record("expected success, got \(error)")
        }
    }

    // MARK: - Failure paths — each forced category from the T044 acceptance

    @Test(
        "ok == false classifies the embedded XPCError for ExitCodeMapper",
        arguments: [
            "schema.unknown_card_type",
            "schema.invalid_date",
            "xpc.app_unavailable",
            "storage.quota_exceeded",
            "not_found",
            "internal",
        ]
    )
    func failedResponseClassifiesEmbeddedError(code: String) throws {
        let remote = XPCError(code: code, message: "synthesised")
        let response = XPCResponse(
            requestId: "req-2",
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: remote
        )

        let result = XPCClient.resultForResponse(response)

        switch result {
        case .success:
            Issue.record("expected failure for code \(code)")
        case .failure(let error):
            #expect(error.code == code)
            #expect(error.message == "synthesised")
        }
    }

    // MARK: - Defensive path — malformed reply with ok=false but no error

    @Test("ok == false with nil error returns synthetic internal error")
    func failedResponseWithoutErrorReturnsInternal() throws {
        let response = XPCResponse(
            requestId: "req-3",
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: nil
        )

        let result = XPCClient.resultForResponse(response)

        switch result {
        case .success:
            Issue.record("expected failure for ok=false response")
        case .failure(let error):
            #expect(error.code == "internal")
            #expect(error.message.contains("ok=false"))
        }
    }

    // MARK: - MY-1455: execute() returns ok=false responses (not throws)

    @Test("ok == false response preserves requestId for command-level emit")
    func okFalseResponsePreservesRequestId() {
        let response = XPCResponse(
            requestId: "req-remote-error-1",
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: XPCError(code: "briefing.not_found", message: "No briefing found for date '2026-08-20'")
        )

        // After MY-1455, execute() returns this response directly.
        // The command-level code can now access response.requestId.
        #expect(response.ok == false)
        #expect(response.requestId == "req-remote-error-1")
        #expect(response.error?.code == "briefing.not_found")
    }

    // MARK: - MY-1455: Remote error output includes requestId nested in error

    @Test("JSONOutput emits remote error with requestId nested inside error object")
    func remoteErrorOutputIncludesRequestId() throws {
        let remoteError = XPCError(
            code: "briefing.not_found",
            message: "No briefing found for date '2026-08-20'"
        )

        let pipe = Pipe()
        let saved = dup(FileHandle.standardError.fileDescriptor)
        dup2(pipe.fileHandleForWriting.fileDescriptor, FileHandle.standardError.fileDescriptor)

        try JSONOutput().emit(error: remoteError, requestId: "req-xpc-response-123")

        dup2(saved, FileHandle.standardError.fileDescriptor)
        close(saved)
        try pipe.fileHandleForWriting.close()
        let captured = pipe.fileHandleForReading.readDataToEndOfFile()

        let obj = try #require(
            try JSONSerialization.jsonObject(with: captured) as? [String: Any]
        )
        #expect(obj["ok"] as? Bool == false)
        // requestId must NOT be at root
        #expect(obj["requestId"] == nil)
        let errBody = try #require(obj["error"] as? [String: Any])
        #expect(errBody["code"] as? String == "briefing.not_found")
        // requestId MUST be nested inside error
        #expect(errBody["requestId"] as? String == "req-xpc-response-123")
    }
}
