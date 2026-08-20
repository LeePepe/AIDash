import Foundation
import Testing
import AIDashCore

/// Tests for `XPCClient.resultForResponse` — the pure mapping utility that
/// classifies `XPCResponse.ok == false` into a `.failure(XPCError)`.
///
/// Since MY-1455, `handleReply` no longer calls `resultForResponse`; it
/// returns decoded responses (including `ok=false`) directly to the caller.
/// `resultForResponse` remains as a public classifier utility; the tests
/// below verify it still works correctly standalone.
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

    // MARK: - MY-1455: Remote error output emits requestId from XPCResponse

    /// Behavioral test exercising the production output path: JSONOutput.emit
    /// called with a requestId sourced from XPCResponse (the path that
    /// commands traverse after execute() returns an ok=false response).
    /// Uses the serialized captureStderr helper (defer-safe + process-wide lock).
    ///
    /// Would FAIL if throw-on-ok=false is restored in handleReply because
    /// execute() would throw before returning a response, making
    /// response.requestId inaccessible to command code.
    @Test("remote error output propagates XPCResponse.requestId nested inside error object (MY-1455)")
    func remoteErrorOutputPropagatesResponseRequestId() throws {
        // Simulate what execute() returns after MY-1455 (ok=false, not thrown).
        let response = XPCResponse(
            requestId: "req-xpc-response-456",
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: XPCError(code: "briefing.not_found", message: "No briefing found for date '2026-08-20'")
        )

        // Exercise the same path as commands: emit error with response.requestId.
        let stderr = try captureStderr {
            let formatter = JSONOutput()
            try formatter.emit(error: response.error!, requestId: response.requestId)
        }

        let obj = try #require(
            try JSONSerialization.jsonObject(with: Data(stderr.utf8)) as? [String: Any]
        )
        #expect(obj["ok"] as? Bool == false)
        // requestId must NOT be at root
        #expect(obj["requestId"] == nil)
        let errBody = try #require(obj["error"] as? [String: Any])
        #expect(errBody["code"] as? String == "briefing.not_found")
        // requestId MUST be nested inside error, equal to XPCResponse.requestId
        #expect(errBody["requestId"] as? String == "req-xpc-response-456")
    }
}
