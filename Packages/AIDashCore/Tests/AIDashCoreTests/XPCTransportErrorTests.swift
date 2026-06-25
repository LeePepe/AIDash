import Testing
import Foundation
@testable import AIDashCore

/// Tests for XPC transport error codes used by XPCClient.
///
/// XPCClient lives in the CLI target (not importable here), so these tests
/// verify the error contracts it depends on: construction, throwability,
/// encoding roundtrip, and single-resume guard pattern for all five XPC
/// transport error codes.
@Suite("XPC transport error codes")
struct XPCTransportErrorTests {

    // MARK: - All five XPCClient error codes

    /// All error codes that XPCClient can surface. Each must be constructible
    /// with just code + message, throwable as `Error`, and survive JSON roundtrip.
    static let allTransportCodes: [(code: String, message: String)] = [
        ("xpc.transport_failure", "connection lost"),
        ("xpc.proxy_unavailable", "remote object proxy missing"),
        ("xpc.decode_failure", "The data couldn't be read because it is missing."),
        ("xpc.connection_invalidated", "XPC connection was invalidated"),
        ("xpc.connection_interrupted", "XPC connection was interrupted"),
    ]

    @Test(arguments: allTransportCodes)
    func transportErrorConstructAndThrow(code: String, message: String) throws {
        let error = XPCError(code: code, message: message)

        // All optional fields default to nil
        #expect(error.code == code)
        #expect(error.message == message)
        #expect(error.field == nil)
        #expect(error.got == nil)
        #expect(error.allowed == nil)
        #expect(error.cause == nil)

        // Must be throwable and catchable as XPCError
        do {
            throw error
        } catch let caught as XPCError {
            #expect(caught.code == code)
            #expect(caught.message == message)
        }
    }

    @Test(arguments: allTransportCodes)
    func transportErrorJsonRoundtrip(code: String, message: String) throws {
        let error = XPCError(code: code, message: message)
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(XPCError.self, from: data)
        #expect(decoded.code == error.code)
        #expect(decoded.message == error.message)
        #expect(decoded.field == nil)
        #expect(decoded.cause == nil)
    }

    // MARK: - XPCError wrapped in XPCResponse (simulates XPCClient decode path)

    @Test(arguments: allTransportCodes)
    func errorResponseRoundtrip(code: String, message: String) throws {
        let error = XPCError(code: code, message: message)
        let response = XPCResponse(
            requestId: UUID().uuidString,
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: error
        )
        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(XPCResponse.self, from: encoded)
        #expect(decoded.ok == false)
        #expect(decoded.data == nil)
        #expect(decoded.error?.code == code)
        #expect(decoded.error?.message == message)
    }

    // MARK: - Service configuration constant

    @Test func machServiceNameConstant() {
        #expect(XPCServiceConfiguration.machServiceName == "com.tianpli.aidash.xpc.v1")
    }

    // MARK: - Request encode (simulates XPCClient.execute pre-send)

    @Test func requestEncodesForTransport() throws {
        let request = XPCRequest(
            requestId: UUID().uuidString,
            cliVersion: "1.0.0",
            command: "briefing.get",
            params: Data("{}".utf8)
        )
        let encoded = try JSONEncoder().encode(request)
        #expect(!encoded.isEmpty)

        let decoded = try JSONDecoder().decode(XPCRequest.self, from: encoded)
        #expect(decoded.requestId == request.requestId)
        #expect(decoded.command == "briefing.get")
    }

    // MARK: - Response decode (simulates XPCClient reply handling)

    @Test func successResponseDecodesFromTransport() throws {
        let response = XPCResponse(
            requestId: UUID().uuidString,
            appVersion: "1.0.0",
            ok: true,
            data: Data("{}".utf8),
            error: nil
        )
        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(XPCResponse.self, from: encoded)
        #expect(decoded.ok == true)
        #expect(decoded.error == nil)
        #expect(decoded.data != nil)
    }

    @Test func malformedDataTriggersDecodeFailure() {
        let garbage = Data("not valid json".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(XPCResponse.self, from: garbage)
        }
    }

    @Test func errorResponseWithSchemaFields() throws {
        let error = XPCError(
            code: "schema.unknown_card_type",
            message: "Unknown card type",
            field: "type",
            got: "unicorn",
            allowed: ["metric", "insight"]
        )
        let response = XPCResponse(
            requestId: UUID().uuidString,
            appVersion: "1.0.0",
            ok: false,
            data: nil,
            error: error
        )
        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(XPCResponse.self, from: encoded)
        #expect(decoded.ok == false)
        #expect(decoded.error?.code == "schema.unknown_card_type")
        #expect(decoded.error?.field == "type")
        #expect(decoded.error?.got == "unicorn")
        #expect(decoded.error?.allowed == ["metric", "insight"])
    }

    // MARK: - Continuation guard pattern validation

    /// Simulates the `completePending` single-resume pattern used by XPCClient.
    /// Two concurrent "callbacks" race to resume; only the first should win.
    @Test func singleResumeGuardPattern() async {
        actor ContinuationHolder {
            var pending: CheckedContinuation<String, any Error>?

            func setPending(_ c: CheckedContinuation<String, any Error>) {
                pending = c
            }

            func completePending(
                _ body: (CheckedContinuation<String, any Error>) -> Void
            ) {
                guard let cont = pending else { return }
                pending = nil
                body(cont)
            }
        }

        let holder = ContinuationHolder()
        let result: String = try! await withCheckedThrowingContinuation { cont in
            Task {
                await holder.setPending(cont)
                // First callback wins
                await holder.completePending { $0.resume(returning: "first") }
                // Second callback is a no-op (continuation already consumed)
                await holder.completePending { $0.resume(returning: "second") }
            }
        }
        #expect(result == "first")
    }
}
