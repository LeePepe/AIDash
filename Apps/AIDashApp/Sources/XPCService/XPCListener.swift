#if os(macOS)
import Foundation
import AIDashCore

/// Registers and accepts incoming XPC connections on the AIDash Mach service
/// (`com.tianpli.aidash.xpc.v1`), and routes each connection to an injected
/// handlers object that conforms to `AIDashXPCServiceProtocol`.
///
/// The listener is intentionally **not** `@MainActor` (Constitution §Concurrency
/// "Off-actor framework callbacks"): `NSXPCListener` delivers
/// `shouldAcceptNewConnection` on its own internal serial queue, so any
/// main-actor assumption from inside that callback would trap instead of
/// accepting the connection. Keeping the listener nonisolated lets the
/// delegate callback read the stored handlers reference directly and safely.
/// Per-connection work that actually needs main-actor isolation is hopped
/// inside the exported handlers object (T061's `@MainActor XPCHandlers` hops
/// in `execute(requestData:reply:)`).
///
/// See `specs/001-core-briefing-cli/contracts/xpc-protocol.md` §"Service registration".
public final class XPCListener: NSObject, NSXPCListenerDelegate {

    private let listener: NSXPCListener
    private let handlers: NSObject & AIDashXPCServiceProtocol

    /// - Parameter handlers: An `NSObject` that conforms to
    ///   `AIDashXPCServiceProtocol`. Provided by the app at launch once the
    ///   `ModelContainer` is available. The handlers must remain alive for
    ///   the lifetime of the listener; `NSXPCConnection.exportedObject` holds
    ///   a strong reference.
    public init(handlers: NSObject & AIDashXPCServiceProtocol) {
        self.listener = NSXPCListener(machServiceName: XPCServiceConfiguration.machServiceName)
        self.handlers = handlers
        super.init()
        listener.delegate = self
    }

    /// Begin accepting incoming connections. Call once during app launch.
    public func start() {
        listener.resume()
    }

    // MARK: - NSXPCListenerDelegate

    public func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: AIDashXPCServiceProtocol.self)
        newConnection.exportedObject = handlers
        newConnection.invalidationHandler = {
            // Connection invalidated; no fatal action required.
            // Future enhancement: structured logging hook.
        }
        newConnection.resume()
        return true
    }
}
#endif
