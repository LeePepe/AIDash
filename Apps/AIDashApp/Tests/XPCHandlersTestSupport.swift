#if os(macOS)
import Testing
import Foundation
import SwiftData
@testable import AIDashApp
import AIDashCore

/// Shared fixture for the XPCHandlers integration suites.
///
/// XPCHandlers bridges the CLI's XPC requests to SwiftData. Its private handler
/// methods are exercised through the public AIDashXPCServiceProtocol surface:
/// build an XPCRequest envelope, call `execute(requestData:reply:)`, decode the
/// XPCResponse and assert. Every helper uses an in-memory SwiftData
/// ModelContainer (no CloudKit), so the suites are hermetic and run in <1s.
@MainActor
enum XPCTestSupport {

    static func makeHandlers() throws -> XPCHandlers {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: BriefingModel.self,
            ContainerModel.self,
            CardModel.self,
            UserEventModel.self,
            configurations: config
        )
        return XPCHandlers(container: container)
    }

    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Send a request through the public AIDashXPCServiceProtocol surface
    /// and synchronously await the reply by hopping back to the main actor.
    static func send<Params: Encodable>(
        _ handlers: XPCHandlers,
        command: String,
        params: Params
    ) async throws -> XPCResponse {
        let request = XPCRequest(
            requestId: UUID().uuidString,
            cliVersion: "test",
            command: command,
            params: try jsonEncoder.encode(params)
        )
        let requestData = try jsonEncoder.encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            handlers.execute(requestData: requestData) { responseData in
                do {
                    let response = try jsonDecoder.decode(XPCResponse.self, from: responseData)
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func decodeResult<R: Decodable>(
        _ type: R.Type,
        from response: XPCResponse
    ) throws -> R {
        let data = try #require(response.data, "XPCResponse.data must be non-nil for ok=true")
        return try jsonDecoder.decode(type, from: data)
    }
}
#endif
