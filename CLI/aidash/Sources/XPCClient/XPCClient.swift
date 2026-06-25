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
            responseData = try await sendWithTimeout(requestData)
        } catch {
            // App not running — attempt launch and retry.
            let launcher = AppLauncher()
            try await launcher.launchAndWait { await probe() }
            do {
                responseData = try await sendWithTimeout(requestData)
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

    /// Probe whether the XPC service is actually reachable by performing a
    /// lightweight round-trip handshake (empty request → any reply or error).
    private func probe() async -> Bool {
        let connection = NSXPCConnection(machServiceName: Self.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: AIDashXPCServiceProtocol.self)
        connection.activate()
        defer { connection.invalidate() }

        // Use a short timeout: if we don't get a reply within 1s, service isn't ready.
        let isReachable: Bool = await withCheckedContinuation { continuation in
            var didResume = false

            connection.invalidationHandler = {
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: false)
            }

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: false)
            }) as? AIDashXPCServiceProtocol else {
                if !didResume {
                    didResume = true
                    continuation.resume(returning: false)
                }
                return
            }

            // Send a minimal ping — an empty request. The service will reply
            // (possibly with an error response), proving it's listening.
            proxy.execute(requestData: Data()) { _ in
                connection.invalidate()
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: true)
            }

            // Timeout after 1 second — if no reply, consider not reachable.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: false)
            }
        }

        return isReachable
    }

    /// Send raw request data over XPC with the 5-second timeout contract.
    private func sendWithTimeout(_ requestData: Data) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await self.sendViaXPC(requestData)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(Self.timeoutSeconds))
                throw XPCError(
                    code: "xpc.connection_invalidated",
                    message: "XPC request timed out after \(Int(Self.timeoutSeconds))s."
                )
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
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
