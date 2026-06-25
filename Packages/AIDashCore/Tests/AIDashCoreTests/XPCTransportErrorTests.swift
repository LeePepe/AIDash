import Testing
import Foundation
@testable import AIDashCore

@Suite("XPC transport error codes")
struct XPCTransportErrorTests {

    @Test func transportFailureError() throws {
        let error = XPCError(
            code: "xpc.transport_failure",
            message: "connection interrupted"
        )
        #expect(error.code == "xpc.transport_failure")
        #expect(error.message == "connection interrupted")
        #expect(error.field == nil)
        #expect(error.got == nil)
        #expect(error.allowed == nil)
        #expect(error.cause == nil)

        // XPCError conforms to Error — verify it can be thrown and caught
        do {
            throw error
        } catch let caught as XPCError {
            #expect(caught.code == "xpc.transport_failure")
        }
    }

    @Test func proxyUnavailableError() throws {
        let error = XPCError(
            code: "xpc.proxy_unavailable",
            message: "remote object proxy missing"
        )
        #expect(error.code == "xpc.proxy_unavailable")
        #expect(error.message == "remote object proxy missing")

        // Verify roundtrip encoding
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(XPCError.self, from: data)
        #expect(decoded.code == error.code)
        #expect(decoded.message == error.message)
    }

    @Test func decodeFailureError() throws {
        let error = XPCError(
            code: "xpc.decode_failure",
            message: "The data couldn't be read because it is missing."
        )
        #expect(error.code == "xpc.decode_failure")
        #expect(error.message.contains("missing"))
    }

    @Test func machServiceNameConstant() {
        #expect(XPCServiceConfiguration.machServiceName == "com.tianpli.aidash.xpc.v1")
    }

    @Test func xpcRequestEncodesForTransport() throws {
        let request = XPCRequest(
            requestId: UUID().uuidString,
            cliVersion: "1.0.0",
            command: "briefing.get",
            params: Data("{}".utf8)
        )
        // Verify the request can be encoded (as XPCClient does before sending)
        let encoded = try JSONEncoder().encode(request)
        #expect(!encoded.isEmpty)

        // Verify roundtrip
        let decoded = try JSONDecoder().decode(XPCRequest.self, from: encoded)
        #expect(decoded.requestId == request.requestId)
        #expect(decoded.command == "briefing.get")
    }

    @Test func xpcResponseDecodesFromTransport() throws {
        let response = XPCResponse(
            requestId: UUID().uuidString,
            appVersion: "1.0.0",
            ok: true,
            data: Data("{}".utf8),
            error: nil
        )
        let encoded = try JSONEncoder().encode(response)

        // Verify the response can be decoded (as XPCClient does after receiving)
        let decoded = try JSONDecoder().decode(XPCResponse.self, from: encoded)
        #expect(decoded.ok == true)
        #expect(decoded.error == nil)
        #expect(decoded.data != nil)
    }

    @Test func xpcErrorResponseDecodesFromTransport() throws {
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
}
