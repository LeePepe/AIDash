import Foundation
import AIDashCore

/// Async-Swift wrapper around `NSXPCConnection` to the AIDash app's XPC service.
/// Thread-safe by design: `actor` isolation ensures no data races on mutable state.
///
/// Lifecycle guarantees:
/// - Each `execute` call registers a per-request continuation keyed by
///   `XPCRequest.requestId`. Overlapping calls never overwrite each other.
/// - Transport, proxy, decode, invalidation, and interruption failures all
///   resume the affected continuation(s) with a typed `XPCError`.
/// - Any connection-level failure (transport / proxy / invalidation /
///   interruption / decode) clears the cached connection so the next call
///   recreates it.
/// - Single-resume semantics: `XPCPendingRequests.complete` atomically takes
///   the continuation, preventing double-resume if multiple callbacks race.
public actor XPCClient {
    private var connection: NSXPCConnection?
    private let pending = XPCPendingRequests()

    public init() {}

    /// Send an XPC request and await the response.
    /// Throws `XPCError` on transport failure or remote error.
    public func execute(_ request: XPCRequest) async throws -> XPCResponse {
        let conn = ensureConnection()
        let requestData = try JSONEncoder().encode(request)
        let requestId = request.requestId

        return try await withCheckedThrowingContinuation { continuation in
            Task {
                await pending.register(requestId: requestId, continuation: continuation)

                let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] err in
                    Task { await self?.failRequest(
                        requestId: requestId,
                        code: "xpc.transport_failure",
                        message: err.localizedDescription
                    )}
                } as? AIDashXPCServiceProtocol

                guard let proxy else {
                    await failRequest(
                        requestId: requestId,
                        code: "xpc.proxy_unavailable",
                        message: "remote object proxy missing"
                    )
                    return
                }

                proxy.execute(requestData: requestData) { [weak self] responseData in
                    Task { await self?.handleReply(requestId: requestId, data: responseData) }
                }
            }
        }
    }

    // MARK: - Continuation management

    /// Fail one specific request and clear the cached connection so the next
    /// call recreates it. Used for transport failure, proxy unavailable, and
    /// decode failure paths that affect only the calling request.
    private func failRequest(requestId: String, code: String, message: String) async {
        connection = nil
        await pending.complete(requestId: requestId) { cont in
            cont.resume(throwing: XPCError(code: code, message: message))
        }
    }

    /// Fail every in-flight request (connection died). Used for invalidation
    /// and interruption — both kill the entire connection, not a single call.
    private func failAll(code: String, message: String) async {
        connection = nil
        await pending.failAll(code: code, message: message)
    }

    /// Decode the reply and resume the matching pending continuation.
    private func handleReply(requestId: String, data: Data) async {
        let decoded: Result<XPCResponse, any Error>
        do {
            decoded = .success(try JSONDecoder().decode(XPCResponse.self, from: data))
        } catch {
            decoded = .failure(XPCError(
                code: "xpc.decode_failure",
                message: error.localizedDescription
            ))
        }

        switch decoded {
        case .success(let response):
            await pending.complete(requestId: requestId) { cont in
                cont.resume(returning: response)
            }
        case .failure(let error):
            connection = nil
            await pending.complete(requestId: requestId) { cont in
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: - Connection lifecycle

    private func ensureConnection() -> NSXPCConnection {
        if let c = connection { return c }
        let c = NSXPCConnection(
            machServiceName: XPCServiceConfiguration.machServiceName,
            options: []
        )
        c.remoteObjectInterface = NSXPCInterface(with: AIDashXPCServiceProtocol.self)
        c.invalidationHandler = { [weak self] in
            Task { await self?.failAll(
                code: "xpc.connection_invalidated",
                message: "XPC connection was invalidated"
            )}
        }
        c.interruptionHandler = { [weak self] in
            Task { await self?.failAll(
                code: "xpc.connection_interrupted",
                message: "XPC connection was interrupted"
            )}
        }
        c.resume()
        connection = c
        return c
    }
}
