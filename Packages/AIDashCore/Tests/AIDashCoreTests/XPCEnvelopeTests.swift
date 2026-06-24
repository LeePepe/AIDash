import Foundation
import Testing
@testable import AIDashCore

// MARK: - T033: XPC envelope JSON round-trip tests

@Test func xpcRequestRoundTrip() throws {
    let original = XPCRequest(
        requestId: "550e8400-e29b-41d4-a716-446655440000",
        cliVersion: "1.0.0",
        command: "card.put",
        params: Data("{\"key\":\"value\"}".utf8)
    )

    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(XPCRequest.self, from: encoded)

    #expect(decoded.requestId == original.requestId)
    #expect(decoded.cliVersion == original.cliVersion)
    #expect(decoded.command == original.command)
    #expect(decoded.params == original.params)
}

@Test func xpcResponseSuccessRoundTrip() throws {
    let original = XPCResponse(
        requestId: "550e8400-e29b-41d4-a716-446655440000",
        appVersion: "2.0.0",
        ok: true,
        data: Data("{\"id\":\"abc\"}".utf8),
        error: nil
    )

    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(XPCResponse.self, from: encoded)

    #expect(decoded.requestId == original.requestId)
    #expect(decoded.appVersion == original.appVersion)
    #expect(decoded.ok == true)
    #expect(decoded.data == original.data)
    #expect(decoded.error == nil)
}

@Test func xpcResponseErrorRoundTrip() throws {
    let error = XPCError(
        code: "schema.unknown_card_type",
        message: "Unknown card type",
        field: "type",
        got: "bogus",
        allowed: ["metric", "chart", "text"],
        cause: "validation failed"
    )
    let original = XPCResponse(
        requestId: "550e8400-e29b-41d4-a716-446655440000",
        appVersion: "2.0.0",
        ok: false,
        data: nil,
        error: error
    )

    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(XPCResponse.self, from: encoded)

    #expect(decoded.ok == false)
    #expect(decoded.data == nil)
    #expect(decoded.error?.code == "schema.unknown_card_type")
    #expect(decoded.error?.message == "Unknown card type")
    #expect(decoded.error?.field == "type")
    #expect(decoded.error?.got == "bogus")
    #expect(decoded.error?.allowed == ["metric", "chart", "text"])
    #expect(decoded.error?.cause == "validation failed")
}

@Test func xpcErrorMinimalRoundTrip() throws {
    let original = XPCError(
        code: "internal.unexpected",
        message: "Something went wrong"
    )

    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(XPCError.self, from: encoded)

    #expect(decoded.code == original.code)
    #expect(decoded.message == original.message)
    #expect(decoded.field == nil)
    #expect(decoded.got == nil)
    #expect(decoded.allowed == nil)
    #expect(decoded.cause == nil)
}

@Test func xpcErrorIsThrowable() throws {
    func throwingFunction() throws {
        throw XPCError(
            code: "schema.unknown_card_type",
            message: "Bad type"
        )
    }

    #expect(throws: XPCError.self) {
        try throwingFunction()
    }
}
