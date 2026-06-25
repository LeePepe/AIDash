#if os(macOS)
import Foundation
import os

private let logger = Logger(subsystem: "com.tianpli.aidash", category: "XPCListener")

/// XPC listener that registers the app as a Mach service for CLI communication.
/// Registers the `NSXPCListener` with the Mach service name so the CLI can connect.
/// TODO(T060): Wire up real command dispatch in XPCServiceHandler.
@MainActor
public final class XPCListener {
    public static let shared = XPCListener()

    private var listener: NSXPCListener?
    private var delegate: XPCListenerDelegate?

    private init() {}

    public func start() {
        let xpcListener = NSXPCListener(machServiceName: XPCServiceConfiguration.machServiceName)
        let xpcDelegate = XPCListenerDelegate()
        xpcListener.delegate = xpcDelegate
        xpcListener.resume()
        self.listener = xpcListener
        self.delegate = xpcDelegate
        logger.info("XPC listener started on \(XPCServiceConfiguration.machServiceName, privacy: .public).")
    }
}

// MARK: - Listener Delegate

private final class XPCListenerDelegate: NSObject, NSXPCListenerDelegate, Sendable {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        let interface = NSXPCInterface(with: AIDashXPCServiceProtocol.self)
        newConnection.exportedInterface = interface
        newConnection.exportedObject = XPCServiceStub()
        newConnection.resume()
        return true
    }
}

// MARK: - Stub service handler

/// Stub XPC service handler that returns "not yet implemented" errors.
/// TODO(T060): Replace with real command dispatch logic.
private final class XPCServiceStub: NSObject, AIDashXPCServiceProtocol, Sendable {
    func execute(requestData: Data, reply: @escaping (Data) -> Void) {
        // Decode the request to extract requestId for a proper error response
        let requestId: String
        if let request = try? JSONDecoder().decode(XPCRequest.self, from: requestData) {
            requestId = request.requestId
        } else {
            requestId = "unknown"
        }

        let errorResponse = XPCResponse(
            requestId: requestId,
            appVersion: "0.0.1",
            ok: false,
            data: nil,
            error: XPCError(
                code: "system.not_implemented",
                message: "XPC command dispatch not yet available (pending T060)."
            )
        )

        let responseData = (try? JSONEncoder().encode(errorResponse)) ?? Data()
        reply(responseData)
    }
}
#endif
