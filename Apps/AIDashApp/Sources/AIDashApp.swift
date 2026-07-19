import SwiftUI
import SwiftData
import AIDashCore
import AIDashUI

@main
struct AIDashApp: App {
    private let containerState: CloudKitContainer.InitState

    #if os(macOS)
    private let runMode: RunMode
    private let menuBarController: MenuBarController?
    private let xpcListener: XPCListener?
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

        // Resolve a ModelContainer for the listener. Agent mode forces local-only
        // (never touch CloudKit). GUI mode uses the normal CloudKit-or-local state
        // but — unlike before — still falls back to a local-only container when
        // CloudKit init failed, so the listener always has a container to serve.
        let state = mode.isAgent
            ? CloudKitContainer.localOnly().state
            : CloudKitContainer.shared.state
        self.containerState = state

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

        // Start the XPC listener in gui + agent modes with a guaranteed
        // container. Skip in test-host mode: the app is only loaded to host the
        // XCTest bundle, and resuming the machService listener there traps.
        if mode == .testHost {
            self.xpcListener = nil
        } else {
            let container = Self.resolveContainerForListener(state: state)
            let listener = XPCListener(handlers: XPCHandlers(container: container))
            listener.start()
            self.xpcListener = listener
        }
        #else
        self.containerState = CloudKitContainer.shared.state
        #endif
    }

    @SceneBuilder
    var body: some Scene {
        #if os(macOS)
        // Present the window only in a real GUI launch; agent + test-host are
        // headless (LSUIElement already hides the Dock).
        BriefingWindowScene(state: containerState, headless: runMode != .gui)
        #else
        BriefingWindowScene(state: containerState)
        #endif
    }

    #if os(macOS)
    /// The container the XPC listener serves: the ready CloudKit/local container
    /// when available, else a fresh local-only one so XPC never stays dead just
    /// because CloudKit couldn't start.
    private static func resolveContainerForListener(
        state: CloudKitContainer.InitState
    ) -> ModelContainer {
        switch state {
        case .ready(let container):
            return container
        case .failed:
            // Best-effort local-only; if even that fails, fall back to an
            // in-memory container so the process still serves (degraded).
            if case .ready(let c) = CloudKitContainer.localOnly().state { return c }
            return Self.inMemoryContainer()
        }
    }

    private static func inMemoryContainer() -> ModelContainer {
        // Schema mirrors CloudKitContainer's. In-memory is the last-resort floor.
        let schema = Schema([BriefingModel.self, ContainerModel.self,
                             CardModel.self, UserEventModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // Force-try is acceptable at the last-resort floor: an in-memory store
        // with a fixed schema cannot realistically fail to construct.
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: config)
    }

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

#if os(macOS)
/// Run mode decided once at launch:
/// - `agent`   = the headless process launchd spawned to serve XPC on-demand
///   (flagged by `AIDASH_XPC_AGENT=1` in the LaunchAgent plist).
/// - `testHost`= the app is loaded only to host an XCTest bundle (detected via
///   the `XCTestConfigurationFilePath` env var Xcode injects). Skips the launchd
///   install + the machService listener resume, which have side effects / trap
///   inside a test process.
/// - `gui`     = a normal user/Xcode launch.
enum RunMode: Equatable {
    case gui
    case agent
    case testHost

    var isAgent: Bool { self == .agent }

    /// Pure decision from the environment — unit-testable without launching.
    /// Agent takes precedence (a launchd spawn is never a test host).
    static func decide(env: [String: String]) -> RunMode {
        if env[LaunchdAgentInstaller.agentEnvVar] == "1" { return .agent }
        if env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil { return .testHost }
        return .gui
    }
}
#endif
