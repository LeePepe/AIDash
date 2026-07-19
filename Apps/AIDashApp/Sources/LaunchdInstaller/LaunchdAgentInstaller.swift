#if os(macOS)
import Foundation
import AIDashCore
import os

/// Installs the app's XPC LaunchAgent that vends the `com.tianpli.aidash.xpc.v1`
/// mach service — using a **plain `launchctl bootstrap` of a hand-written plist**
/// in `~/Library/LaunchAgents/`, NOT `SMAppService`.
///
/// Why not SMAppService (root cause, 2026-07-19): `SMAppService.agent(...)`
/// attaches a Lightweight Code Requirement / Launch Constraint (LWCR) to the
/// registered job. A DerivedData Debug build is re-signed with a fresh cdhash on
/// every build, so the cached LWCR no longer matches and macOS SIGKILLs launchd's
/// on-demand spawn (`CODESIGNING` / "Launch Constraint Violation", exit 78
/// EX_CONFIG), wedging the mach port. A job created by plain `launchctl
/// bootstrap` carries **no LWCR** and spawns fine (verified: hand-bootstrapped
/// plist loads with `last exit = never exited`, gets past the code-signature
/// gate). This installer owns the plist so a rebuild re-points `Program` and
/// re-bootstraps instead of stranding a stale job.
///
/// The launchd-spawned process is told it's the headless agent via the plist's
/// `EnvironmentVariables` (`AIDASH_XPC_AGENT=1`), which `AIDashApp` reads to take
/// the listener-only boot path (no CloudKit mirror, no GUI) — see `RunMode`.
///
/// The status→action decision is a pure function (`decide`) behind injectable
/// effect seams so every branch is unit-testable without touching real
/// `launchctl` or the real `~/Library/LaunchAgents` directory.
@MainActor
public final class LaunchdAgentInstaller {
    public static let shared = LaunchdAgentInstaller()

    /// Observable result of an install attempt.
    public enum RegistrationOutcome: Equatable, Sendable {
        /// The LaunchAgent plist is written and the job is bootstrapped.
        case registered
        /// The install could not complete (couldn't write the plist, or
        /// `launchctl bootstrap` failed). XPC stays down; carries a reason.
        case failed(reason: String)

        /// Whether this outcome means XPC is expected to be reachable.
        public var isHealthy: Bool { self == .registered }
    }

    public static let label = "com.tianpli.aidash"
    public static let machServiceName = XPCServiceConfiguration.machServiceName
    /// Env var the plist sets so the launchd-spawned process knows it is the
    /// headless XPC agent (listener-only boot). A user/Xcode launch lacks it.
    /// `nonisolated` so `RunMode.decide` (off the main actor) can read it.
    public nonisolated static let agentEnvVar = "AIDASH_XPC_AGENT"

    // MARK: - Injectable effect seams (real impls hit the filesystem + launchctl)

    /// Absolute path to the executable the LaunchAgent should launch.
    public typealias ExecPathProvider = @MainActor () -> String
    /// Path to the LaunchAgent plist we own.
    public typealias PlistURLProvider = @MainActor () -> URL
    /// Reads the plist's current `Program` value (nil if absent/unreadable).
    public typealias InstalledExecReader = @MainActor (URL) -> String?
    /// Writes the plist contents to the URL (throws on failure).
    public typealias PlistWriter = @MainActor (URL, Data) throws -> Void
    /// Runs `launchctl bootout`/`bootstrap`; returns whether it succeeded.
    public typealias Launchctl = @MainActor (_ args: [String]) -> Bool

    private let log = Logger(subsystem: "com.tianpli.aidash", category: "launchd")
    private let execPath: ExecPathProvider
    private let plistURL: PlistURLProvider
    private let installedExec: InstalledExecReader
    private let writePlist: PlistWriter
    private let launchctl: Launchctl

    private init() {
        self.execPath = { Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? "" }
        self.plistURL = { Self.defaultPlistURL() }
        self.installedExec = { Self.readProgram(from: $0) }
        self.writePlist = { url, data in try data.write(to: url, options: .atomic) }
        self.launchctl = { Self.runLaunchctl($0) }
    }

    /// Test seam: inject every effect.
    internal init(execPath: @escaping ExecPathProvider,
                  plistURL: @escaping PlistURLProvider,
                  installedExec: @escaping InstalledExecReader,
                  writePlist: @escaping PlistWriter,
                  launchctl: @escaping Launchctl) {
        self.execPath = execPath
        self.plistURL = plistURL
        self.installedExec = installedExec
        self.writePlist = writePlist
        self.launchctl = launchctl
    }

    // MARK: - Install

    /// Ensure the LaunchAgent is installed and pointing at the current build.
    /// Idempotent — safe on every launch. Only rewrites + rebootstraps when the
    /// plist is absent or its `Program` differs from the running executable
    /// (i.e. a rebuild), so a steady-state launch is a cheap no-op.
    @discardableResult
    public func registerIfNeeded() -> RegistrationOutcome {
        let exec = execPath()
        let url = plistURL()
        let plan = Self.decide(currentExec: exec, installedExec: installedExec(url))
        log.info("LaunchAgent install plan: \(String(describing: plan)) for exec \(exec, privacy: .public)")

        switch plan {
        case .upToDate:
            return .registered
        case .install:
            return performInstall(exec: exec, url: url)
        }
    }

    /// What to do given the running executable and the plist's recorded one.
    /// Pure + injectable-free so tests exercise the branch logic directly.
    enum Plan: Equatable { case upToDate, install }

    static func decide(currentExec: String, installedExec: String?) -> Plan {
        installedExec == currentExec ? .upToDate : .install
    }

    private func performInstall(exec: String, url: URL) -> RegistrationOutcome {
        let data = Self.plistData(execPath: exec)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writePlist(url, data)
        } catch {
            log.error("Could not write LaunchAgent plist: \(error.localizedDescription, privacy: .public)")
            return .failed(reason: "write plist: \(error.localizedDescription)")
        }
        // Reload: bootout any stale job (ignore failure — may not exist), then
        // bootstrap the freshly-written plist into the GUI domain.
        let domain = "gui/\(getuid())"
        _ = launchctl(["bootout", "\(domain)/\(Self.label)"])
        guard launchctl(["bootstrap", domain, url.path]) else {
            log.error("launchctl bootstrap failed for \(url.path, privacy: .public)")
            return .failed(reason: "launchctl bootstrap failed")
        }
        log.info("LaunchAgent bootstrapped; XPC mach service should broker to this build.")
        return .registered
    }

    // MARK: - Plist authoring

    /// The LaunchAgent plist for `execPath`. On-demand (no RunAtLoad/KeepAlive):
    /// launchd spawns it when the CLI connects to the mach service. The agent
    /// env var flags the spawned process as headless (listener-only boot).
    static func plistData(execPath: String) -> Data {
        let dict: [String: Any] = [
            "Label": label,
            "Program": execPath,
            "MachServices": [machServiceName: true],
            "EnvironmentVariables": [agentEnvVar: "1"],
            "ProcessType": "Interactive",
        ]
        // PropertyListSerialization can't fail for this static shape.
        return (try? PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0)) ?? Data()
    }

    static func defaultPlistURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    static func readProgram(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return plist["Program"] as? String
    }

    static func runLaunchctl(_ args: [String]) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
}
#endif
