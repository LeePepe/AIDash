#if os(macOS)
import Foundation
import AIDashCore
import os
import Synchronization

/// Installs the app's XPC LaunchAgent that vends the `<bundle id>.xpc.v1`
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

    // MARK: - LaunchctlResult

    /// Captures the full outcome of a `launchctl` invocation: termination status,
    /// captured stdout/stderr, and any launch-level error (e.g. executable not found).
    public struct LaunchctlResult: Equatable, Sendable {
        /// The arguments passed to launchctl.
        public let arguments: [String]
        /// Process termination status (0 = success).
        public let terminationStatus: Int32
        /// Captured standard output (empty when launchctl produces none).
        public let stdout: String
        /// Captured standard error (contains launchctl diagnostics on failure).
        public let stderr: String
        /// Non-nil when the process could not be launched at all.
        public let launchError: String?

        public var succeeded: Bool { launchError == nil && terminationStatus == 0 }

        /// A one-line summary suitable for logging or embedding in failure messages.
        public var diagnosticSummary: String {
            if let err = launchError {
                return "launchctl \(arguments.joined(separator: " ")): launch error: \(err)"
            }
            if terminationStatus != 0 {
                let stderrTrimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = stderrTrimmed.isEmpty ? "(no stderr)" : stderrTrimmed
                return "launchctl \(arguments.joined(separator: " ")): exit \(terminationStatus) — \(detail)"
            }
            return "launchctl \(arguments.joined(separator: " ")): ok"
        }
    }

    /// launchd job label. 从 app 的 bundle id 推导,所以改
    /// `Configs/Identity.xcconfig` 的 `AIDASH_BUNDLE_ID` 后自动跟随。
    /// ⚠️ 改了之后必须卸载旧 agent(`launchctl bootout`),否则旧 label 的
    /// agent 仍在注册旧 mach service。见 README「Fork 本项目」。
    public static let label: String = Bundle.main.bundleIdentifier ?? "com.tianpli.aidash"
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
    /// Runs `launchctl` with the given arguments and returns a full result
    /// including termination status, stdout, stderr, and any launch error.
    public typealias Launchctl = @MainActor (_ args: [String]) -> LaunchctlResult

    private let log = Logger(subsystem: LaunchdAgentInstaller.label, category: "launchd")
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

    /// Classification of a `launchctl print` result into actionable categories.
    enum PrintStatus: Equatable {
        /// The job is loaded and running in launchd.
        case loaded
        /// The job is known absent (exit 113 "Could not find service" or similar
        /// documented absence codes). Safe to self-heal via reinstall.
        case knownAbsent
        /// An unexpected command or launch failure (permission error, launchctl
        /// binary missing, unknown exit code). NOT safe to assume absence — the
        /// job may exist but we failed to query it. Return `.failed` to the caller.
        case commandFailure
    }

    /// Classifies the result of `launchctl print gui/<uid>/<label>` into one of
    /// three states. Known absence exit codes (documented by launchd):
    /// - 113: "Could not find service" — the job genuinely does not exist.
    /// - 3: "No such process" — the domain/service path is invalid (absent).
    /// Any other non-zero or a process launch error is treated as a command
    /// failure where we cannot determine job state.
    static func classifyPrint(_ result: LaunchctlResult) -> PrintStatus {
        if result.succeeded { return .loaded }
        if result.launchError != nil { return .commandFailure }
        // Known launchd "absent" exit codes.
        switch result.terminationStatus {
        case 3, 113:
            return .knownAbsent
        default:
            return .commandFailure
        }
    }

    /// Ensure the LaunchAgent is installed and pointing at the current build.
    /// Idempotent — safe on every launch. Only rewrites + rebootstraps when the
    /// plist is absent or its `Program` differs from the running executable
    /// (i.e. a rebuild), so a steady-state launch is a cheap no-op.
    @discardableResult
    public func registerIfNeeded() -> RegistrationOutcome {
        let exec = execPath()
        let url = plistURL()
        let recordedExec = installedExec(url)
        let printResult = launchctl(["print", "gui/\(getuid())/\(Self.label)"])
        let printStatus = Self.classifyPrint(printResult)

        // Command failure: we cannot determine job state. Do NOT blindly
        // reinstall — the job might exist and we'd clobber it.
        if printStatus == .commandFailure {
            log.error("launchctl print failed unexpectedly: \(printResult.diagnosticSummary, privacy: .public)")
            return .failed(reason: printResult.diagnosticSummary)
        }

        let loaded = (printStatus == .loaded)
        let plan = Self.decide(currentExec: exec, installedExec: recordedExec,
                               jobLoaded: loaded)
        log.info("LaunchAgent install plan: \(String(describing: plan), privacy: .public) for exec \(exec, privacy: .public) (plistExec=\(recordedExec ?? "nil", privacy: .public), jobLoaded=\(loaded, privacy: .public))")

        switch plan {
        case .upToDate:
            return .registered
        case .install:
            if recordedExec == exec && !loaded {
                log.info("LaunchAgent plist matches but launchd job is not loaded — self-healing via reinstall.")
            }
            return performInstall(exec: exec, url: url)
        }
    }

    /// What to do given the running executable, the plist's recorded one, and
    /// whether launchd actually has the job loaded. Pure + injectable-free so
    /// tests exercise the branch logic directly.
    enum Plan: Equatable { case upToDate, install }

    /// A launch is up-to-date ONLY when both hold:
    ///   1. the plist's `Program` matches the running exec (no rebuild since), AND
    ///   2. launchd currently has the job loaded.
    ///
    /// The second condition is the root-cause fix (2026-07): a plist file can
    /// sit on disk with a matching path while the launchd job is booted out
    /// (reset-xpc, logout/reboot, manual bootout, DerivedData purge). The old
    /// path-only check short-circuited to `.upToDate` in that state and skipped
    /// bootstrap, so the mach service had no vendor and every push failed with
    /// "listener never checked in" until someone ran reset-xpc by hand. Gating
    /// on `jobLoaded` makes any subsequent app launch self-heal via `.install`.
    static func decide(currentExec: String, installedExec: String?,
                       jobLoaded: Bool) -> Plan {
        (installedExec == currentExec && jobLoaded) ? .upToDate : .install
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
        let bootoutResult = launchctl(["bootout", "\(domain)/\(Self.label)"])
        if !bootoutResult.succeeded {
            // Bootout failure is expected when no prior job exists; log but continue.
            log.debug("bootout returned non-zero (expected if no prior job): \(bootoutResult.diagnosticSummary, privacy: .public)")
        }

        let bootstrapResult = launchctl(["bootstrap", domain, url.path])
        guard bootstrapResult.succeeded else {
            let summary = bootstrapResult.diagnosticSummary
            log.error("launchctl bootstrap failed: \(summary, privacy: .public)")
            return .failed(reason: summary)
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

    /// Maximum bytes to capture per pipe stream. launchctl diagnostics are
    /// short; 64 KB is generous. Beyond this we truncate and append an indicator.
    static let maxPipeCapture = 65_536

    static func runLaunchctl(_ args: [String]) -> LaunchctlResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
            // Drain both pipes concurrently BEFORE waitUntilExit to avoid
            // deadlock when either pipe's buffer fills (pipe capacity ~64 KB).
            // Each reader is capped to `maxPipeCapture` bytes; excess is
            // drained (to let the child exit) but discarded with a truncation
            // indicator appended to the captured portion.
            let stdoutBox = Mutex(CappedRead(text: "", truncated: false))
            let stderrBox = Mutex(CappedRead(text: "", truncated: false))
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let (text, trunc) = readCapped(from: stdoutPipe.fileHandleForReading, limit: maxPipeCapture)
                stdoutBox.withLock { $0 = CappedRead(text: text, truncated: trunc) }
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let (text, trunc) = readCapped(from: stderrPipe.fileHandleForReading, limit: maxPipeCapture)
                stderrBox.withLock { $0 = CappedRead(text: text, truncated: trunc) }
                group.leave()
            }
            group.wait()
            proc.waitUntilExit()
            let stdoutCap = stdoutBox.withLock { $0 }
            let stderrCap = stderrBox.withLock { $0 }
            return LaunchctlResult(
                arguments: args,
                terminationStatus: proc.terminationStatus,
                stdout: stdoutCap.truncated ? stdoutCap.text + "\n[truncated at \(maxPipeCapture) bytes]" : stdoutCap.text,
                stderr: stderrCap.truncated ? stderrCap.text + "\n[truncated at \(maxPipeCapture) bytes]" : stderrCap.text,
                launchError: nil
            )
        } catch {
            return LaunchctlResult(
                arguments: args,
                terminationStatus: -1,
                stdout: "",
                stderr: "",
                launchError: error.localizedDescription
            )
        }
    }

    /// Value type for thread-safe capture of capped pipe output via `Mutex`.
    struct CappedRead: Sendable {
        let text: String
        let truncated: Bool
    }

    /// Reads up to `limit` bytes from `handle`, then drains any remainder so
    /// the writing process can exit. Returns the captured string and whether
    /// the output was truncated.
    static func readCapped(from handle: FileHandle, limit: Int) -> (String, Bool) {
        var captured = Data()
        var truncated = false
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break } // EOF
            let remaining = limit - captured.count
            if remaining > 0 {
                captured.append(chunk.prefix(remaining))
            }
            if captured.count >= limit {
                truncated = true
            }
        }
        let str = String(data: captured, encoding: .utf8) ?? ""
        return (str, truncated)
    }
}
#endif
