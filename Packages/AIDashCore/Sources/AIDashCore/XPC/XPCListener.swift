#if os(macOS)
import Foundation

/// XPC listener that registers the app as a Mach service for CLI communication.
/// TODO(T060): Full NSXPCListener implementation with AIDashXPCServiceProtocol handler.
@MainActor
public final class XPCListener {
    public static let shared = XPCListener()

    private init() {}

    public func start() {
        // TODO(T060): Set up NSXPCListener and register the XPC service
    }
}
#endif
