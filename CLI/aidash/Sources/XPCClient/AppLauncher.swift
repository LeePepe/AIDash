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

    /// Closure that performs the actual app launch. Defaults to `NSWorkspace`.
    private let launcher: @Sendable () async throws -> Void

    /// Closure that sleeps for the given duration. Injected for testability.
    private let sleeper: @Sendable (Duration) async throws -> Void

    public init(
        launcher: @Sendable @escaping () async throws -> Void = {
            let url = URL(fileURLWithPath: "/Applications/AIDash.app")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        },
        sleeper: @Sendable @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.launcher = launcher
        self.sleeper = sleeper
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
                    + "Is it installed at /Applications/AIDash.app?"
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
