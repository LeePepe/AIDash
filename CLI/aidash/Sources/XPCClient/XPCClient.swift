import Foundation
import AIDashCore

/// Async-Swift wrapper around `NSXPCConnection` to the AIDash app's XPC service.
/// Thread-safe by design: `actor` isolation ensures no data races on the
/// mutable `connection` property.
public actor XPCClient {
    private var connection: NSXPCConnection?

    public init() {}

    /// Send an XPC request and await the response.
    /// Throws `XPCError` on transport failure or remote error.
    public func execute(_ request: XPCRequest) async throws -> XPCResponse {
        let conn = ensureConnection()
        let requestData = try JSONEncoder().encode(request)

        return try await withCheckedThrowingContinuation { continuation in
            let proxy = conn.remoteObjectProxyWithErrorHandler { err in
                continuation.resume(throwing: XPCError(
                    code: "xpc.transport_failure",
                    message: err.localizedDescription
                ))
            } as? AIDashXPCServiceProtocol

            guard let proxy else {
                continuation.resume(throwing: XPCError(
                    code: "xpc.proxy_unavailable",
                    message: "remote object proxy missing"
                ))
                return
            }

            proxy.execute(requestData: requestData) { responseData in
                do {
                    let response = try JSONDecoder().decode(XPCResponse.self, from: responseData)
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: XPCError(
                        code: "xpc.decode_failure",
                        message: error.localizedDescription
                    ))
                }
            }
        }
    }

    private func ensureConnection() -> NSXPCConnection {
        if let c = connection { return c }
        let c = NSXPCConnection(
            machServiceName: XPCServiceConfiguration.machServiceName,
            options: []
        )
        c.remoteObjectInterface = NSXPCInterface(with: AIDashXPCServiceProtocol.self)
        c.invalidationHandler = { [weak self] in
            Task { await self?.clearConnection() }
        }
        c.interruptionHandler = { [weak self] in
            Task { await self?.clearConnection() }
        }
        c.resume()
        connection = c
        return c
    }

    private func clearConnection() { connection = nil }
}
