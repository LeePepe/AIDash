#if os(macOS)
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.tianpli.aidash", category: "LaunchdAgentInstaller")

/// Manages the app's login item registration via SMAppService.
/// Uses the modern ServiceManagement API which works correctly under app sandbox.
/// TODO(T110): Full update, version check, and uninstall logic.
@MainActor
final class LaunchdAgentInstaller {
    static let shared = LaunchdAgentInstaller()

    private init() {}

    func registerIfNeeded() {
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            logger.info("Login item already registered.")
            return
        case .requiresApproval:
            logger.info("Login item requires user approval in System Settings.")
            return
        default:
            break
        }

        do {
            try service.register()
            logger.info("Login item registered successfully.")
        } catch {
            logger.error("Failed to register login item: \(error.localizedDescription, privacy: .auto)")
        }
    }
}
#endif
