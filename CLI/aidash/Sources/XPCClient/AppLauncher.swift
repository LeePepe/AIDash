import Foundation
import AppKit
import AIDashCore

/// Launches AIDash.app on XPC failure and polls until the service becomes reachable.
///
/// See `research.md` §R-4 for rationale and timeout budget.
public struct AppLauncher: Sendable {
    /// Closure that performs the actual app launch. Defaults to `NSWorkspace`.
    /// Injected for testability.
    private let launcher: @Sendable () async throws -> Void

    public init(
        launcher: @Sendable @escaping () async throws -> Void = {
            let url = URL(fileURLWithPath: "/Applications/AIDash.app")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    ) {
        self.launcher = launcher
    }

    /// Attempt to launch AIDash.app and wait for XPC to become reachable.
    ///
    /// Returns once `probe()` succeeds, or throws `XPCError` with code
    /// `xpc.app_unavailable` after exhausting the retry budget.
    ///
    /// - Parameters:
    ///   - probe: An async closure that returns `true` when the XPC service is reachable.
    ///   - maxAttempts: Number of poll attempts after launch (default 10).
    ///   - pollInterval: Duration between poll attempts (default 500ms).
    public func launchAndWait(
        probe: @Sendable () async -> Bool,
        maxAttempts: Int = 10,
        pollInterval: Duration = .milliseconds(500)
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

        for _ in 0..<maxAttempts {
            try await Task.sleep(for: pollInterval)
            if await probe() { return }
        }

        throw XPCError(
            code: "xpc.app_unavailable",
            message: "AIDash.app launched but XPC service not reachable after \(maxAttempts) attempts."
        )
    }
}
