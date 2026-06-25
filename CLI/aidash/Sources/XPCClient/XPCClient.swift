import Foundation
import AIDashCore

/// Async-Swift wrapper around `NSXPCConnection` to the AIDash app's XPC service.
/// Thread-safe by design: `actor` isolation ensures no data races on mutable state.
///
/// Lifecycle guarantees:
/// - Transport, proxy, decode, invalidation, and interruption failures all
///   resume the in-flight continuation with a typed `XPCError`.
/// - Any failure clears the cached connection so the next call recreates it.
/// - Single-resume semantics: `completePending` atomically takes the
///   continuation, preventing double-resume if multiple callbacks fire.
public actor XPCClient {
    private var connection: NSXPCConnection?
    private var pendingContinuation: CheckedContinuation<XPCResponse, any Error>?

    public init() {}

    /// Send an XPC request and await the response.
    /// Throws `XPCError` on transport failure or remote error.
    public func execute(_ request: XPCRequest) async throws -> XPCResponse {
        let conn = ensureConnection()
        let requestData = try JSONEncoder().encode(request)

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation

            let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self] err in
                Task { await self?.failPending(
                    code: "xpc.transport_failure",
                    message: err.localizedDescription
                )}
            } as? AIDashXPCServiceProtocol

            guard let proxy else {
                completePending { $0.resume(throwing: XPCError(
                    code: "xpc.proxy_unavailable",
                    message: "remote object proxy missing"
                ))}
                return
            }

            proxy.execute(requestData: requestData) { [weak self] responseData in
                Task { await self?.handleReply(responseData) }
            }
        }
    }

    /// Returns `true` if the XPC service responds.
    /// Used by `AppLauncher.launchAndWait(probe:)` to poll readiness.
    public func canReachService() async -> Bool {
        do {
            let req = XPCRequest(
                requestId: UUID().uuidString,
                cliVersion: "1.0.0",
                command: "ping",
                params: Data("{}".utf8)
            )
            _ = try await execute(req)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Continuation management

    private func failPending(code: String, message: String) {
        connection = nil
        completePending { $0.resume(throwing: XPCError(code: code, message: message)) }
    }

    private func handleReply(_ data: Data) {
        completePending { cont in
            do {
                let response = try JSONDecoder().decode(XPCResponse.self, from: data)
                cont.resume(returning: response)
            } catch {
                connection = nil
                cont.resume(throwing: XPCError(
                    code: "xpc.decode_failure",
                    message: error.localizedDescription
                ))
            }
        }
    }

    private func completePending(
        _ body: (CheckedContinuation<XPCResponse, any Error>) -> Void
    ) {
        guard let cont = pendingContinuation else { return }
        pendingContinuation = nil
        body(cont)
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
            Task { await self?.failPending(
                code: "xpc.connection_invalidated",
                message: "XPC connection was invalidated"
            )}
        }
        c.interruptionHandler = { [weak self] in
            Task { await self?.failPending(
                code: "xpc.connection_interrupted",
                message: "XPC connection was interrupted"
            )}
        }
        c.resume()
        connection = c
        return c
    }
}
