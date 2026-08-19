import SwiftUI
import SwiftData
import AIDashCore
import AIDashUI

@main
struct AIDashApp: App {
    #if os(macOS)
    private let runMode: RunMode
    private let menuBarController: MenuBarController?
    private let xpcListener: XPCListener?
    @State private var bootstrap: AppBootstrap
    #else
    @State private var bootstrap: AppBootstrap
    #endif

    init() {
        #if os(macOS)
        // Decide GUI vs. headless-agent vs. test-host ONCE, before any GUI/
        // CloudKit bring-up. The launchd-spawned agent carries AIDASH_XPC_AGENT=1
        // (set by the LaunchAgent plist); a user/Xcode launch does not; an XCTest
        // host is detected via the injected bundle. Agent mode must NOT attach
        // CloudKit (SIGTRAPs headless); test-host mode must NOT install the
        // launchd job or resume the machService listener (real launchctl side
        // effects + `_xpc_api_misuse` on a machService resume inside a test proc).
        let mode = RunMode.decide(env: ProcessInfo.processInfo.environment)
        self.runMode = mode

        // GUI chrome only in GUI mode.
        self.menuBarController = mode == .gui ? MenuBarController() : nil

        // Install/refresh the launchd LaunchAgent so launchd brokers the mach
        // service to THIS build. Only from a real GUI launch — never the agent
        // process (it IS the spawned job) and never a test host (no real
        // launchctl side effects during `swift`/`xcodebuild test`).
        if mode == .gui {
            let outcome = LaunchdAgentInstaller.shared.registerIfNeeded()
            if !outcome.isHealthy {
                Self.recordLaunchAgentProblem(outcome)
            }
        }

        // Start the XPC listener IMMEDIATELY — before any store loading —
        // so the mach service is active from the moment the process starts.
        // Store-independent commands (ping, schema.list) are served nonisolated
        // in XPCHandlers.execute() and respond even while the store is loading.
        // Store-dependent mutations return `internal.store_not_ready` until
        // the container is delivered by the loader.
        let handlers: XPCHandlers?
        if mode == .testHost {
            self.xpcListener = nil
            handlers = nil
        } else {
            let h = XPCHandlers(container: nil)
            let listener = XPCListener(handlers: h)
            listener.start()
            self.xpcListener = listener
            handlers = h
        }

        let boot = AppBootstrap(handlers: handlers)
        _bootstrap = State(initialValue: boot)

        // Both agent and GUI modes load off-MainActor via nonisolated loaders.
        // Even if the SQLite/CloudKit open hangs indefinitely, MainActor is
        // never blocked: SwiftUI renders, XPC dispatches ping/schema.list.
        //
        // Agent mode: local-only container (no CloudKit mirror — headless
        // launchd context SIGTRAPs on CloudKit bring-up).
        // GUI mode: CloudKit-vs-local decided by entitlement + account check
        // via CloudKitContainer's nonisolated static methods.
        if mode.isAgent {
            boot.startDetached(loader: AgentContainerLoader())
        } else {
            boot.startDetached(loader: GUIContainerLoader())
        }

        #else
        // iOS/iPadOS: off-MainActor via GUIContainerLoader. Same guarantee as
        // macOS — MainActor never blocks on store open. The CloudKit-vs-local
        // decision runs nonisolated in CloudKitContainer's static methods.
        let boot = AppBootstrap()
        _bootstrap = State(initialValue: boot)
        boot.startDetached(loader: GUIContainerLoader())
        #endif
    }

    @SceneBuilder
    var body: some Scene {
        #if os(macOS)
        // Present the window only in a real GUI launch; agent + test-host are
        // headless (LSUIElement already hides the Dock).
        BriefingWindowScene(state: bootstrap.containerState, headless: runMode != .gui)
        #else
        BriefingWindowScene(state: bootstrap.containerState)
        #endif
    }

    #if os(macOS)
    /// Append a loud, actionable line to the shared push-error log when the
    /// LaunchAgent install failed, so a broken XPC bring-up is visible to whoever
    /// inspects why AIDash pushes stopped landing — the same log the aidata push
    /// path writes to. Best-effort: never throws from init.
    private static func recordLaunchAgentProblem(
        _ outcome: LaunchdAgentInstaller.RegistrationOutcome
    ) {
        guard case .failed(let reason) = outcome else { return }
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
