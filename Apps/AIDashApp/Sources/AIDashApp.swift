import SwiftUI
import SwiftData
import AIDashCore
import AIDashUI

@main
struct AIDashApp: App {
    private let containerState: CloudKitContainer.InitState

    #if os(macOS)
    private let menuBarController: MenuBarController
    private let xpcListener: XPCListener?
    #endif

    init() {
        let state = CloudKitContainer.shared.state
        self.containerState = state
        #if os(macOS)
        self.menuBarController = MenuBarController()
        // Register the LaunchAgent (T110). Idempotent — safe on every launch.
        // The outcome is observed: when the agent isn't healthy (needs approval
        // or registration failed) the mach service won't come up, so XPC stays
        // dead. Record it loudly instead of swallowing — a silent needs-approval
        // state was a root cause of "the app is up but every CLI call fails".
        let launchAgentOutcome = LaunchdAgentInstaller.shared.registerIfNeeded()
        if !launchAgentOutcome.isHealthy {
            Self.recordLaunchAgentProblem(launchAgentOutcome)
        }
        // T060: start the XPC listener once the ModelContainer is ready, so
        // the `aidash` CLI can reach us. If CloudKit init failed, skip the
        // listener — handlers need a real ModelContainer (Constitution §D.2
        // graceful degradation: surface failure in UI, do not crash).
        switch state {
        case .ready(let container):
            let listener = XPCListener(handlers: XPCHandlers(container: container))
            listener.start()
            self.xpcListener = listener
        case .failed:
            self.xpcListener = nil
        }
        #endif
    }

    var body: some Scene {
        BriefingWindowScene(state: containerState)
    }

    #if os(macOS)
    /// Append a loud, actionable line to the shared push-error log when the
    /// LaunchAgent isn't healthy, so a needs-approval / failed registration is
    /// visible to whoever inspects why AIDash pushes stopped landing — the same
    /// log the aidata push path writes to. Best-effort: never throws from init.
    private static func recordLaunchAgentProblem(
        _ outcome: LaunchdAgentInstaller.RegistrationOutcome
    ) {
        let reason: String
        switch outcome {
        case .registered:
            return
        case .requiresApproval:
            reason = "LaunchAgent needs approval in System Settings → Login Items "
                + "(XPC mach service will not start until enabled)"
        case .failed(let r):
            reason = "LaunchAgent registration failed: \(r)"
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) — AIDash XPC LaunchAgent problem: \(reason)\n"
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Development/AIDash/.aidash-state/aidash-push-errors.log")
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let handle = try? FileHandle(forWritingTo: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = line.data(using: .utf8) { try? handle.write(contentsOf: data) }
        } else {
            try? line.data(using: .utf8)?.write(to: path)
        }
    }
    #endif
}
