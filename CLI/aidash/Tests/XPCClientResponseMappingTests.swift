import Foundation
import Testing
import AIDashCore

/// Tests for `XPCClient.decodeReply` — the production test seam that exposes
/// the decode-to-Result logic used by `handleReply`.
///
/// Since MY-1455, `handleReply` returns decoded responses (including `ok=false`)
/// directly to the caller. `decodeReply` is the public test seam that lets tests
/// feed encoded bytes through the same production decode path.
@Suite("XPCClient response mapping")
struct XPCClientResponseMappingTests {

    // MARK: - decodeReply: ok=true returns success

    @Test("decodeReply returns ok=true response without throwing")
    func decodeReplyOkTrue() throws {
        let response = XPCResponse(
            requestId: "req-1",
            appVersion: "1.0.0",
            ok: true,
            data: Data("{}".utf8),
            error: nil
        )
        let encoded = try JSONEncoder().encode(response)

        let decoded = try XPCClient.decodeReply(encoded)
        #expect(decoded.requestId == "req-1")
        #expect(decoded.ok == true)
    }

    // MARK: - decodeReply: ok=false is returned (not thrown)

    @Test("decodeReply returns ok=false response without throwing (MY-1455)")
    func decodeReplyOkFalseNotThrown() throws {
        let response = XPCResponse(
            requestId: "req-2",
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: XPCError(code: "briefing.not_found", message: "No briefing found")
        )
        let encoded = try JSONEncoder().encode(response)

        let decoded = try XPCClient.decodeReply(encoded)
        #expect(decoded.ok == false)
        #expect(decoded.requestId == "req-2")
        #expect(decoded.error?.code == "briefing.not_found")
    }

    // MARK: - decodeReply: invalid bytes throw xpc.decode_failure

    @Test("decodeReply throws xpc.decode_failure on invalid bytes")
    func decodeReplyThrowsOnInvalidBytes() {
        let garbage = Data("not json at all".utf8)

        do {
            _ = try XPCClient.decodeReply(garbage)
            Issue.record("Expected XPCError to be thrown")
        } catch let error as XPCError {
            #expect(error.code == "xpc.decode_failure")
        } catch {
            Issue.record("Expected XPCError, got: \(error)")
        }
    }

    // MARK: - MY-1455: ok=false with various error codes decoded correctly

    @Test(
        "decodeReply preserves error codes for all remote error categories",
        arguments: [
            "schema.unknown_card_type",
            "schema.invalid_date",
            "xpc.app_unavailable",
            "storage.quota_exceeded",
            "not_found",
            "internal",
        ]
    )
    func decodeReplyPreservesErrorCodes(code: String) throws {
        let response = XPCResponse(
            requestId: "req-codes",
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: XPCError(code: code, message: "synthesised")
        )
        let encoded = try JSONEncoder().encode(response)

        let decoded = try XPCClient.decodeReply(encoded)
        #expect(decoded.ok == false)
        #expect(decoded.error?.code == code)
        #expect(decoded.error?.message == "synthesised")
    }

    // MARK: - MY-1455: ok=false with nil error also decoded (not thrown)

    @Test("decodeReply returns ok=false with nil error without throwing")
    func decodeReplyOkFalseNilError() throws {
        let response = XPCResponse(
            requestId: "req-3",
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: nil
        )
        let encoded = try JSONEncoder().encode(response)

        let decoded = try XPCClient.decodeReply(encoded)
        #expect(decoded.ok == false)
        #expect(decoded.error == nil)
    }
}
