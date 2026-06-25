import Testing
import Foundation
@testable import AIDashCore

/// Tests for XPC transport error codes and the `XPCPendingRequests` lifecycle
/// table that `XPCClient` builds on.
///
/// `XPCClient` itself lives in the CLI target and cannot be imported here,
/// but its full lifecycle behaviour (per-request continuations, single-resume,
/// fail-all on connection death, request-id collision) is implemented in
/// `XPCPendingRequests`, which IS importable and exercised below. The tests
/// here are the actual behavioural contract; `XPCClient` only wires
/// `NSXPCConnection` callbacks into these primitives.
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
}

// MARK: - XPCPendingRequests lifecycle (the testable seam of XPCClient)

/// Direct behavioural tests for `XPCPendingRequests` — the per-request
/// continuation table that `XPCClient` uses. These tests cover every
/// lifecycle path that the AI Reviewer called out:
///
/// - Per-request continuations: registering two requests, completing one,
///   verifying the other is still pending.
/// - Single-resume guard: completing the same id twice resumes once and
///   the second call is a no-op.
/// - Fail-all (invalidation/interruption): every pending continuation gets
///   the error code, table is emptied.
/// - Request-id collision: re-registering an id resumes the prior
///   continuation with `xpc.request_id_collision` so it does not leak.
/// - Specific error codes propagate through both `complete` and `failAll`.
@Suite("XPCPendingRequests lifecycle")
struct XPCPendingRequestsTests {

    @Test func registerAndCompleteSingleRequest() async throws {
        let table = XPCPendingRequests()
        let requestId = UUID().uuidString

        let result: XPCResponse = try await withCheckedThrowingContinuation { cont in
            Task {
                await table.register(requestId: requestId, continuation: cont)
                #expect(await table.pendingCount == 1)
                await table.complete(requestId: requestId) { cont in
                    cont.resume(returning: makeResponse(requestId: requestId))
                }
            }
        }

        #expect(result.requestId == requestId)
        #expect(await table.pendingCount == 0)
    }

    @Test func overlappingRequestsDoNotInterfere() async throws {
        let table = XPCPendingRequests()
        let idA = "request-A"
        let idB = "request-B"

        async let valueA: XPCResponse = withCheckedThrowingContinuation { cont in
            Task { await table.register(requestId: idA, continuation: cont) }
        }
        async let valueB: XPCResponse = withCheckedThrowingContinuation { cont in
            Task { await table.register(requestId: idB, continuation: cont) }
        }

        // Wait until both are registered before completing.
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        #expect(await table.pendingCount == 2)

        // Complete B first; A must still be in-flight.
        await table.complete(requestId: idB) { cont in
            cont.resume(returning: makeResponse(requestId: idB))
        }
        let bResult = try await valueB
        #expect(bResult.requestId == idB)
        #expect(await table.pendingCount == 1)

        // Now complete A.
        await table.complete(requestId: idA) { cont in
            cont.resume(returning: makeResponse(requestId: idA))
        }
        let aResult = try await valueA
        #expect(aResult.requestId == idA)
        #expect(await table.pendingCount == 0)
    }

    @Test func completeTwiceIsSingleResume() async throws {
        let table = XPCPendingRequests()
        let requestId = UUID().uuidString

        let result: XPCResponse = try await withCheckedThrowingContinuation { cont in
            Task {
                await table.register(requestId: requestId, continuation: cont)
                // First complete wins.
                let firstFired = await table.complete(requestId: requestId) { cont in
                    cont.resume(returning: makeResponse(requestId: requestId, appVersion: "first"))
                }
                #expect(firstFired == true)
                // Second complete is a no-op — does NOT call the closure.
                let secondFired = await table.complete(requestId: requestId) { _ in
                    Issue.record("second complete must not invoke closure")
                }
                #expect(secondFired == false)
            }
        }

        #expect(result.appVersion == "first")
    }

    @Test func completeUnknownIdIsNoOp() async {
        let table = XPCPendingRequests()
        let fired = await table.complete(requestId: "never-registered") { _ in
            Issue.record("unknown id must not invoke closure")
        }
        #expect(fired == false)
        #expect(await table.pendingCount == 0)
    }

    @Test func failAllResumesEveryPendingWithError() async {
        let table = XPCPendingRequests()
        let idA = "fail-A"
        let idB = "fail-B"

        // Use a TaskGroup so we can collect both thrown errors.
        async let errorA: any Error = capturingError {
            try await withCheckedThrowingContinuation { cont in
                Task { await table.register(requestId: idA, continuation: cont) }
            } as XPCResponse
        }
        async let errorB: any Error = capturingError {
            try await withCheckedThrowingContinuation { cont in
                Task { await table.register(requestId: idB, continuation: cont) }
            } as XPCResponse
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await table.pendingCount == 2)

        await table.failAll(
            code: "xpc.connection_invalidated",
            message: "XPC connection was invalidated"
        )

        let caughtA = await errorA
        let caughtB = await errorB
        #expect((caughtA as? XPCError)?.code == "xpc.connection_invalidated")
        #expect((caughtB as? XPCError)?.code == "xpc.connection_invalidated")
        #expect(await table.pendingCount == 0)
    }

    @Test func failAllOnEmptyTableIsNoOp() async {
        let table = XPCPendingRequests()
        await table.failAll(code: "xpc.connection_interrupted", message: "interrupted")
        #expect(await table.pendingCount == 0)
    }

    @Test func registerCollisionResumesPriorContinuation() async throws {
        let table = XPCPendingRequests()
        let collidingId = "duplicate-id"

        // First continuation: must end up resumed with xpc.request_id_collision.
        async let priorError: any Error = capturingError {
            try await withCheckedThrowingContinuation { cont in
                Task { await table.register(requestId: collidingId, continuation: cont) }
            } as XPCResponse
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await table.pendingCount == 1)

        // Second continuation: takes over the id, eventually resolved.
        let secondResult: XPCResponse = try await withCheckedThrowingContinuation { cont in
            Task {
                await table.register(requestId: collidingId, continuation: cont)
                // Prior must already be evicted; only the new continuation is pending.
                #expect(await table.pendingCount == 1)
                await table.complete(requestId: collidingId) { cont in
                    cont.resume(returning: makeResponse(requestId: collidingId, appVersion: "winner"))
                }
            }
        }

        let caught = await priorError
        #expect((caught as? XPCError)?.code == "xpc.request_id_collision")
        #expect(secondResult.appVersion == "winner")
        #expect(await table.pendingCount == 0)
    }

    @Test func completePropagatesThrownError() async {
        let table = XPCPendingRequests()
        let requestId = UUID().uuidString

        let caught: any Error = await capturingError {
            try await withCheckedThrowingContinuation { cont in
                Task {
                    await table.register(requestId: requestId, continuation: cont)
                    await table.complete(requestId: requestId) { cont in
                        cont.resume(throwing: XPCError(
                            code: "xpc.decode_failure",
                            message: "garbage in reply"
                        ))
                    }
                }
            } as XPCResponse
        }

        #expect((caught as? XPCError)?.code == "xpc.decode_failure")
    }
}

// MARK: - Test helpers

private func makeResponse(
    requestId: String,
    appVersion: String = "1.0.0"
) -> XPCResponse {
    XPCResponse(
        requestId: requestId,
        appVersion: appVersion,
        ok: true,
        data: nil,
        error: nil
    )
}

/// Run an async throwing expression and return the thrown error. Fails the
/// surrounding test if no error is thrown.
private func capturingError<T>(_ body: () async throws -> T) async -> any Error {
    do {
        _ = try await body()
        Issue.record("expected an error but body returned normally")
        return XPCError(code: "test.no_error", message: "no error thrown")
    } catch {
        return error
    }
}
