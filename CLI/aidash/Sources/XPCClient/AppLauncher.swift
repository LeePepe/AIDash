import Foundation
import AppKit
import AIDashCore

/// Launches AIDash.app on XPC failure and polls until the service becomes reachable.
///
/// See `research.md` §R-4 for rationale and timeout budget.
public struct AppLauncher: Sendable {
    /// R-4 hard budget: 10 attempts × 500ms = 5s max.
    private static let maxAttempts = 10
    private static let pollInterval: Duration = .milliseconds(500)

    /// Env override for explicit app path — highest priority in `resolveAppURL`.
    /// Set this when running the debug build straight out of Xcode /
    /// DerivedData without shipping the bundle to `/Applications`.
    public static let appPathEnvVar = "AIDASH_APP_PATH"

    /// Closure that performs the actual app launch. Defaults to `NSWorkspace`.
    private let launcher: @Sendable () async throws -> Void

    /// Closure that sleeps for the given duration. Injected for testability.
    private let sleeper: @Sendable (Duration) async throws -> Void

    public init(
        launcher: @Sendable @escaping () async throws -> Void = Self.defaultLauncher,
        sleeper: @Sendable @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.launcher = launcher
        self.sleeper = sleeper
    }

    /// Default launcher: resolves the app URL (env override → /Applications →
    /// latest DerivedData debug build) and opens it via NSWorkspace.
    ///
    /// Exposed as `public` so `init` can reference it as a default argument;
    /// callers should treat it as an implementation detail (use the `init()`
    /// default, don't call this directly).
    public static let defaultLauncher: @Sendable () async throws -> Void = {
        let url = try Self.resolveAppURL()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// Resolve which `AIDash.app` bundle to launch. Searches in priority order:
    ///
    ///   1. `$AIDASH_APP_PATH` env override — full path to an `AIDash.app`.
    ///      Escape hatch for dev / debug workflows and CI.
    ///   2. `/Applications/AIDash.app` — production install (SMAppService).
    ///   3. Most-recently-built `AIDash.app` under Xcode's DerivedData
    ///      (`~/Library/Developer/Xcode/DerivedData/AIDash-*/Build/Products/Debug/AIDash.app`),
    ///      so a raw `xcodebuild` / Xcode Run session picks up automatically
    ///      when the app is not installed under `/Applications`.
    ///
    /// Throws `XPCError(xpc.app_launch_failed)` listing every path attempted
    /// when none exist. Deps are injected so the search order is unit-testable
    /// without touching the real filesystem.
    public static func resolveAppURL(
        env: @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] },
        fileExists: @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        derivedDataCandidates: @Sendable () -> [URL] = { Self.defaultDerivedDataCandidates() }
    ) throws -> URL {
        var searched: [String] = []

        if let overridePath = env(appPathEnvVar), !overridePath.isEmpty {
            let url = URL(fileURLWithPath: overridePath)
            if fileExists(url) { return url }
            searched.append("$\(appPathEnvVar)=\(overridePath)")
        }

        let installed = URL(fileURLWithPath: "/Applications/AIDash.app")
        if fileExists(installed) { return installed }
        searched.append(installed.path)

        for candidate in derivedDataCandidates() where fileExists(candidate) {
            return candidate
        }
        for candidate in derivedDataCandidates().prefix(3) {
            searched.append(candidate.path)
        }

        throw XPCError(
            code: "xpc.app_launch_failed",
            message: "Could not launch AIDash.app: no bundle found. Searched: "
                + searched.joined(separator: "; ")
                + ". Install it to /Applications or set $\(appPathEnvVar) to an AIDash.app path."
        )
    }

    /// Enumerate `~/Library/Developer/Xcode/DerivedData/AIDash-*/Build/Products/Debug/AIDash.app`
    /// sorted by build recency (most-recent mtime first).
    ///
    /// Returns an empty array if DerivedData is missing or unreadable — the
    /// caller falls back to the launch failure path.
    public static func defaultDerivedDataCandidates() -> [URL] {
        let derivedData = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: derivedData,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let candidates = entries
            .filter { $0.lastPathComponent.hasPrefix("AIDash-") }
            .map { $0.appendingPathComponent("Build/Products/Debug/AIDash.app") }

        return candidates.sorted { lhs, rhs in
            let lm = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            let rm = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            return lm > rm
        }
    }

    /// Attempt to launch AIDash.app and wait for XPC to become reachable.
    ///
    /// Returns once `probe()` succeeds, or throws `XPCError` with code
    /// `xpc.app_unavailable` after exhausting the R-4 retry budget
    /// (10 attempts × 500ms = 5s).
    ///
    /// - Parameter probe: An async closure that returns `true` when the XPC service is reachable.
    public func launchAndWait(
        probe: @Sendable () async -> Bool
    ) async throws {
        do {
            try await launcher()
        } catch let error as XPCError {
            throw error
        } catch {
            throw XPCError(
                code: "xpc.app_launch_failed",
                message: "Could not launch AIDash.app: \(error.localizedDescription). "
                    + "Install it to /Applications or set $\(Self.appPathEnvVar) to an AIDash.app path."
            )
        }

        for _ in 0..<Self.maxAttempts {
            try await sleeper(Self.pollInterval)
            if await probe() { return }
        }

        throw XPCError(
            code: "xpc.app_unavailable",
            message: "AIDash.app launched but XPC service not reachable after \(Self.maxAttempts) attempts."
        )
    }
}
