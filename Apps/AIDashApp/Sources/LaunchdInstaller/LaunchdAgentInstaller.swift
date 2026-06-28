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
        log.info("LaunchAgent status before register: \(String(describing: status))")

        // `.requiresApproval` is a terminal state for this code path — the
        // user must enable the agent in System Settings → Login Items, and
        // calling register() again won't change that. Surface and bail.
        if status == .requiresApproval {
            log.warning("LaunchAgent requires user approval in System Settings → Login Items.")
            return
        }

        // Unconditionally re-register on every launch. SMAppService.register()
        // is documented as idempotent and is the only call that re-synchronizes
        // launchd with the BTM database. `SMAppService.status` reflects BTM
        // (user intent) — it returns `.enabled` even when `launchctl bootout`
        // has unloaded the plist from launchd. Without this unconditional
        // re-register, a single `bootout` permanently strands the LaunchAgent:
        // BTM keeps reporting enabled, launchd never re-loads the plist, and
        // the mach service `com.tianpli.aidash.xpc.v1` has no broker, so every
        // CLI invocation hangs. See xpc-protocol.md §"Launchd integration".
        do {
            try agentService.register()
            log.info("LaunchAgent registered; status now: \(String(describing: self.agentService.status))")
        } catch {
            log.error("LaunchAgent registration failed: \(error, privacy: .private)")
        }
    }
}
#endif
