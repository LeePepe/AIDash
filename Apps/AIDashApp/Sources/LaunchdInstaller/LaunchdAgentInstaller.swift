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
                log.error("LaunchAgent registration failed: \(error.localizedDescription, privacy: .public)")
            }
        @unknown default:
            log.warning("Unknown SMAppService status: \(String(describing: status))")
        }
    }
}
#endif
