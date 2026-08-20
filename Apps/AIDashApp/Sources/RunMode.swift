import Foundation

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

    /// Which container loader strategy this mode requires.
    /// Used by `AIDashApp.init` to select the off-MainActor loader.
    enum LoaderStrategy: Equatable {
        /// Local-only container (headless agent, no CloudKit).
        case agent
        /// CloudKit-vs-local decision based on entitlement + account.
        case gui
        /// No loader — test host must not open the production store.
        case none
    }

    var loaderStrategy: LoaderStrategy {
        switch self {
        case .agent: return .agent
        case .gui: return .gui
        case .testHost: return .none
        }
    }
}
#endif
