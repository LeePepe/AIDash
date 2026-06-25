import Foundation
import AIDashCore

/// Lightweight XPC client that sends requests to the AIDash macOS app.
///
/// Wraps `NSXPCConnection` for the `com.tianpli.aidash.xpc.v1` Mach service.
/// See `contracts/xpc-protocol.md` for the wire format.
///
/// - Important: The full `NSXPCConnection` request/reply/decode/invalidation
///   implementation is tracked in T041. This file currently provides the public
///   interface so that T044 (`canReachService`) and T042 (`AppLauncher`) can
///   compile and wire together. Once T041 lands, `execute(_:)` will be replaced
///   with the real transport layer.
public final class XPCClient: Sendable {
    private let serviceName: String

    public init(serviceName: String = "com.tianpli.aidash.xpc.v1") {
        self.serviceName = serviceName
    }

    /// Send a request to the XPC service and await the response.
    ///
    /// - Throws: `XPCError` with `xpc.app_unavailable` until T041 provides the
    ///   real `NSXPCConnection` implementation.
    public func execute(_ request: XPCRequest) async throws -> XPCResponse {
        // TODO: T041 — replace with NSXPCConnection send/receive/decode/invalidation.
        throw XPCError(
            code: "xpc.app_unavailable",
            message: "XPC transport not yet implemented (pending T041)."
        )
    }
}

// MARK: - Health probe (T044)

extension XPCClient {
    /// Returns `true` if the XPC service responds to a `ping` command.
    ///
    /// Used by `AppLauncher.launchAndWait(probe:)` to poll readiness.
    /// The app-side handler (T061) must accept `command == "ping"` as a no-op.
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
}
