import Foundation
import Testing
import AIDashCore

/// Tests for `XPCClient.resultForResponse` — the pure mapping that ensures
/// `XPCResponse.ok == false` surfaces the embedded `XPCError` so the global
/// `ExitCodeMapper` can pick the right exit code.
///
/// This is the T044 contract: forced `schema.*` → 1, `xpc.*` → 2, and
/// `storage.*` / `not_found` → 3 require the remote error to actually be
/// thrown by `execute(_:)` rather than swallowed inside an `ok == false`
/// response.
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
        "ok == false throws the embedded XPCError so ExitCodeMapper sees it",
        arguments: [
            "schema.unknown_card_type",
            "schema.invalid_date",
            "xpc.app_unavailable",
            "storage.quota_exceeded",
            "not_found",
            "internal",
        ]
    )
    func failedResponseThrowsEmbeddedError(code: String) throws {
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
}
