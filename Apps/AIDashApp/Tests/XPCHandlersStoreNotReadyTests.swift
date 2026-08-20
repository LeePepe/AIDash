#if os(macOS)
import Testing
import Foundation
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif
import AIDashCore

// MARK: - Store-not-ready behavior tests

/// Verifies that when the persistent store is still loading (container == nil),
/// store-independent commands respond promptly while store-dependent mutations
/// return a typed retryable `internal.store_not_ready` error.

@MainActor
@Test(.timeLimit(.minutes(1)))
func pingSucceedsWithNilContainer() async throws {
    let handlers = XPCHandlers(container: nil)
    let response = try await sendRaw(
        handlers,
        command: "ping",
        paramsJSON: Data("{}".utf8)
    )
    #expect(response.ok == true)
    #expect(response.error == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func schemaListSucceedsWithNilContainer() async throws {
    let handlers = XPCHandlers(container: nil)
    let response = try await sendRaw(
        handlers,
        command: "schema.list",
        paramsJSON: Data("{}".utf8)
    )
    #expect(response.ok == true)
    #expect(response.error == nil)
    #expect(response.data != nil)
}

@MainActor
@Test func briefingPutReturnsStoreNotReadyWithNilContainer() async throws {
    let handlers = XPCHandlers(container: nil)
    let response = try await sendRaw(
        handlers,
        command: "briefing.put",
        paramsJSON: Data(#"{"date":"2025-01-01","generatedBy":"test","published":false}"#.utf8)
    )
    #expect(response.ok == false)
    #expect(response.error?.code == "internal.store_not_ready")
    #expect(response.error?.cause == "retryable")
}

@MainActor
@Test func containerPutReturnsStoreNotReadyWithNilContainer() async throws {
    let handlers = XPCHandlers(container: nil)
    let response = try await sendRaw(
        handlers,
        command: "container.put",
        paramsJSON: Data(#"{"id":"c1","briefingDate":"2025-01-01","title":"T","order":0,"layout":"single","style":"default"}"#.utf8)
    )
    #expect(response.ok == false)
    #expect(response.error?.code == "internal.store_not_ready")
    #expect(response.error?.cause == "retryable")
}

@MainActor
@Test func cardPutReturnsStoreNotReadyWithNilContainer() async throws {
    let handlers = XPCHandlers(container: nil)
    let response = try await sendRaw(
        handlers,
        command: "card.put",
        paramsJSON: Data(#"{"containerId":"c1","id":"k1","type":"metric","size":"small","style":"default","payload":{}}"#.utf8)
    )
    #expect(response.ok == false)
    #expect(response.error?.code == "internal.store_not_ready")
    #expect(response.error?.cause == "retryable")
}

@MainActor
@Test func eventsPullReturnsStoreNotReadyWithNilContainer() async throws {
    let handlers = XPCHandlers(container: nil)
    let response = try await sendRaw(
        handlers,
        command: "events.pull",
        paramsJSON: Data(#"{"since":"2025-01-01T00:00:00Z"}"#.utf8)
    )
    #expect(response.ok == false)
    #expect(response.error?.code == "internal.store_not_ready")
    #expect(response.error?.cause == "retryable")
}

// MARK: - Terminal store failure tests

/// Verifies that when the store has terminally failed (storeFailureReason set),
/// store-dependent commands return a non-retryable `internal.store_failed` error
/// instead of the retryable `internal.store_not_ready`, preventing infinite
/// client retries on a permanently broken store.

@MainActor
@Test(.timeLimit(.minutes(1)))
func pingSucceedsAfterTerminalStoreFailure() async throws {
    let handlers = XPCHandlers(container: nil, storeFailureReason: "SQLite corruption")
    let response = try await sendRaw(
        handlers,
        command: "ping",
        paramsJSON: Data("{}".utf8)
    )
    #expect(response.ok == true)
    #expect(response.error == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func schemaListSucceedsAfterTerminalStoreFailure() async throws {
    let handlers = XPCHandlers(container: nil, storeFailureReason: "SQLite corruption")
    let response = try await sendRaw(
        handlers,
        command: "schema.list",
        paramsJSON: Data("{}".utf8)
    )
    #expect(response.ok == true)
    #expect(response.error == nil)
    #expect(response.data != nil)
}

@MainActor
@Test func briefingPutReturnsStoreFailedAfterTerminalFailure() async throws {
    let handlers = XPCHandlers(container: nil, storeFailureReason: "Local store unavailable")
    let response = try await sendRaw(
        handlers,
        command: "briefing.put",
        paramsJSON: Data(#"{"date":"2025-01-01","generatedBy":"test","published":false}"#.utf8)
    )
    #expect(response.ok == false)
    #expect(response.error?.code == "internal.store_failed")
    #expect(response.error?.cause != "retryable")
}

@MainActor
@Test func containerPutReturnsStoreFailedAfterTerminalFailure() async throws {
    let handlers = XPCHandlers(container: nil, storeFailureReason: "Local store unavailable")
    let response = try await sendRaw(
        handlers,
        command: "container.put",
        paramsJSON: Data(#"{"id":"c1","briefingDate":"2025-01-01","title":"T","order":0,"layout":"single","style":"default"}"#.utf8)
    )
    #expect(response.ok == false)
    #expect(response.error?.code == "internal.store_failed")
    #expect(response.error?.cause != "retryable")
}

@MainActor
@Test func cardPutReturnsStoreFailedAfterTerminalFailure() async throws {
    let handlers = XPCHandlers(container: nil, storeFailureReason: "Local store unavailable")
    let response = try await sendRaw(
        handlers,
        command: "card.put",
        paramsJSON: Data(#"{"containerId":"c1","id":"k1","type":"metric","size":"small","style":"default","payload":{}}"#.utf8)
    )
    #expect(response.ok == false)
    #expect(response.error?.code == "internal.store_failed")
    #expect(response.error?.cause != "retryable")
}

@MainActor
@Test func eventsPullReturnsStoreFailedAfterTerminalFailure() async throws {
    let handlers = XPCHandlers(container: nil, storeFailureReason: "Local store unavailable")
    let response = try await sendRaw(
        handlers,
        command: "events.pull",
        paramsJSON: Data(#"{"since":"2025-01-01T00:00:00Z"}"#.utf8)
    )
    #expect(response.ok == false)
    #expect(response.error?.code == "internal.store_failed")
    #expect(response.error?.cause != "retryable")
}

// MARK: - Helpers

/// Minimal send helper that takes raw JSON params data, avoiding coupling to
/// the specific Codable param types (which would fail to encode if the schema
/// changes). This exercises the full `execute(requestData:reply:)` path.
@MainActor
private func sendRaw(
    _ handlers: XPCHandlers,
    command: String,
    paramsJSON: Data
) async throws -> XPCResponse {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let request = XPCRequest(
        requestId: UUID().uuidString,
        cliVersion: "test",
        command: command,
        params: paramsJSON
    )
    let requestData = try encoder.encode(request)
    return try await withCheckedThrowingContinuation { continuation in
        handlers.execute(requestData: requestData) { responseData in
            do {
                let response = try decoder.decode(XPCResponse.self, from: responseData)
                continuation.resume(returning: response)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
#endif
