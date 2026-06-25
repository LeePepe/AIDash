#if os(macOS)
import Foundation
import ServiceManagement
import os

@MainActor
public final class LaunchdAgentInstaller {
    public static let shared = LaunchdAgentInstaller()

    private let log = Logger(subsystem: "com.tianpli.aidash", category: "launchd")
    private let agentService: SMAppService

    private init() {
        self.agentService = SMAppService.agent(plistName: "com.tianpli.aidash.plist")
    }

    /// Registers the LaunchAgent if it is not already enabled.
    /// Idempotent — safe to call on every app launch.
    ///
    /// Error surfacing beyond OSLog (menubar status, file logging) is
    /// intentionally deferred to a follow-up POLISH task per T110 scope.
    public func registerIfNeeded() {
        let status = agentService.status
        log.info("LaunchAgent current status: \(String(describing: status))")

        switch status {
        case .enabled, .requiresApproval:
            return
        case .notRegistered, .notFound:
            do {
                try agentService.register()
                log.info("LaunchAgent registered successfully.")
            } catch {
                log.error("LaunchAgent registration failed: \(error, privacy: .private)")
            }
        @unknown default:
            log.warning("Unknown SMAppService status: \(String(describing: status))")
        }
    }
}
#endif
