import Foundation
import Testing
import AIDashCore

/// Tests for `XPCClient.deliverReply` — the production delivery-policy seam
/// that determines whether a decoded reply is returned or thrown.
///
/// Since MY-1455, `handleReply` delegates to `deliverReply` which returns
/// decoded responses (including `ok=false`) directly to the caller. Only
/// bytes that fail JSON decoding are thrown as `XPCError`.
@Suite("XPCClient response mapping")
struct XPCClientResponseMappingTests {

    // MARK: - deliverReply: ok=true returns success

    @Test("deliverReply returns ok=true response without throwing")
    func deliverReplyOkTrue() throws {
        let response = XPCResponse(
            requestId: "req-1",
            appVersion: "1.0.0",
            ok: true,
            data: Data("{}".utf8),
            error: nil
        )
        let encoded = try JSONEncoder().encode(response)

        let decoded = try XPCClient.deliverReply(encoded)
        #expect(decoded.requestId == "req-1")
        #expect(decoded.ok == true)
    }

    // MARK: - deliverReply: ok=false is returned (not thrown)

    @Test("deliverReply returns ok=false response without throwing (MY-1455)")
    func deliverReplyOkFalseNotThrown() throws {
        let response = XPCResponse(
            requestId: "req-2",
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: XPCError(code: "briefing.not_found", message: "No briefing found")
        )
        let encoded = try JSONEncoder().encode(response)

        let decoded = try XPCClient.deliverReply(encoded)
        #expect(decoded.ok == false)
        #expect(decoded.requestId == "req-2")
        #expect(decoded.error?.code == "briefing.not_found")
    }

    // MARK: - deliverReply: invalid bytes throw xpc.decode_failure

    @Test("deliverReply throws xpc.decode_failure on invalid bytes")
    func deliverReplyThrowsOnInvalidBytes() {
        let garbage = Data("not json at all".utf8)

        do {
            _ = try XPCClient.deliverReply(garbage)
            Issue.record("Expected XPCError to be thrown")
        } catch let error as XPCError {
            #expect(error.code == "xpc.decode_failure")
        } catch {
            Issue.record("Expected XPCError, got: \(error)")
        }
    }

    // MARK: - MY-1455: ok=false with various error codes decoded correctly

    @Test(
        "deliverReply preserves error codes for all remote error categories",
        arguments: [
            "schema.unknown_card_type",
            "schema.invalid_date",
            "xpc.app_unavailable",
            "storage.quota_exceeded",
            "not_found",
            "internal",
        ]
    )
    func deliverReplyPreservesErrorCodes(code: String) throws {
        let response = XPCResponse(
            requestId: "req-codes",
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: XPCError(code: code, message: "synthesised")
        )
        let encoded = try JSONEncoder().encode(response)

        let decoded = try XPCClient.deliverReply(encoded)
        #expect(decoded.ok == false)
        #expect(decoded.error?.code == code)
        #expect(decoded.error?.message == "synthesised")
    }

    // MARK: - MY-1455: ok=false with nil error also decoded (not thrown)

    @Test("deliverReply returns ok=false with nil error without throwing")
    func deliverReplyOkFalseNilError() throws {
        let response = XPCResponse(
            requestId: "req-3",
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: nil
        )
        let encoded = try JSONEncoder().encode(response)

        let decoded = try XPCClient.deliverReply(encoded)
        #expect(decoded.ok == false)
        #expect(decoded.error == nil)
    }
}
