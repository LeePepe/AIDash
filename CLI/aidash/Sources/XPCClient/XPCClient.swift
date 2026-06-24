import AIDashCore
import Foundation

/// Thin wrapper around NSXPCConnection for communicating with the AIDash app.
struct XPCClient: Sendable {

    /// Execute an XPC request and return the decoded response.
    /// Throws `XPCError` with code `xpc.*` on transport failure.
    func execute(_ request: XPCRequest) async throws -> XPCResponse {
        let connection = NSXPCConnection(
            machServiceName: XPCServiceConfiguration.machServiceName
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: AIDashXPCServiceProtocol.self
        )
        connection.activate()

        defer { connection.invalidate() }

        let requestData = try JSONEncoder().encode(request)

        let replyData: Data = try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            connection.invalidationHandler = {
                guard !didResume else { return }
                didResume = true
                continuation.resume(throwing: XPCError(
                    code: "xpc.connection_invalidated",
                    message: "XPC connection was invalidated before receiving a reply"
                ))
            }

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                guard !didResume else { return }
                didResume = true
                continuation.resume(throwing: XPCError(
                    code: "xpc.app_unavailable",
                    message: "Could not connect to AIDash app: \(error.localizedDescription)"
                ))
            }) as? AIDashXPCServiceProtocol else {
                guard !didResume else { return }
                didResume = true
                continuation.resume(throwing: XPCError(
                    code: "xpc.app_unavailable",
                    message: "Failed to obtain XPC proxy"
                ))
                return
            }

            proxy.execute(requestData: requestData) { data in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: data)
            }
        }

        let response = try JSONDecoder().decode(XPCResponse.self, from: replyData)
        return response
    }
}
