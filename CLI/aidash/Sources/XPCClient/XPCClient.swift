import Foundation
import AIDashCore

/// Minimal XPC client for the aidash CLI.
/// Connects to the AIDash.app Mach service, sends an `XPCRequest`, and returns an `XPCResponse`.
struct XPCClient: Sendable {
    private static let serviceName = XPCServiceConfiguration.machServiceName
    private static let timeoutSeconds: TimeInterval = 5

    /// Execute an XPC request against the AIDash app.
    /// Throws `XPCError` with code `xpc.*` on transport failures.
    func execute(_ request: XPCRequest) async throws -> XPCResponse {
        let requestData = try JSONEncoder().encode(request)

        // Attempt connection; if service unreachable, launch app and retry.
        let responseData: Data
        do {
            responseData = try await sendViaXPC(requestData)
        } catch {
            // App not running — attempt launch and retry.
            let launcher = AppLauncher()
            try await launcher.launchAndWait { await probe() }
            do {
                responseData = try await sendViaXPC(requestData)
            } catch {
                throw XPCError(
                    code: "xpc.app_unavailable",
                    message: "AIDash.app XPC service not reachable after launch."
                )
            }
        }

        let response = try JSONDecoder().decode(XPCResponse.self, from: responseData)
        return response
    }

    /// Probe whether the XPC service is reachable.
    private func probe() -> Bool {
        let connection = NSXPCConnection(machServiceName: Self.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: AIDashXPCServiceProtocol.self)
        connection.activate()
        defer { connection.invalidate() }
        return connection.remoteObjectProxy != nil
    }

    /// Send raw request data over XPC and return raw response data.
    private func sendViaXPC(_ requestData: Data) async throws -> Data {
        let connection = NSXPCConnection(machServiceName: Self.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: AIDashXPCServiceProtocol.self)
        connection.activate()

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false

            connection.invalidationHandler = {
                guard !didResume else { return }
                didResume = true
                continuation.resume(throwing: XPCError(
                    code: "xpc.connection_invalidated",
                    message: "XPC connection was invalidated."
                ))
            }

            connection.interruptionHandler = {
                guard !didResume else { return }
                didResume = true
                continuation.resume(throwing: XPCError(
                    code: "xpc.connection_invalidated",
                    message: "XPC connection was interrupted."
                ))
            }

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                guard !didResume else { return }
                didResume = true
                continuation.resume(throwing: XPCError(
                    code: "xpc.connection_invalidated",
                    message: "XPC proxy error: \(error.localizedDescription)"
                ))
            }) as? AIDashXPCServiceProtocol else {
                if !didResume {
                    didResume = true
                    continuation.resume(throwing: XPCError(
                        code: "xpc.connection_invalidated",
                        message: "Failed to obtain XPC proxy."
                    ))
                }
                return
            }

            proxy.execute(requestData: requestData) { replyData in
                connection.invalidate()
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: replyData)
            }
        }
    }
}
