#if os(macOS)
import Foundation
import ServiceManagement
import os

/// Registers the app's XPC LaunchAgent (`com.tianpli.aidash.plist`, which
/// vends the `com.tianpli.aidash.xpc.v1` mach service) via `SMAppService`.
///
/// The registration outcome is now **observable** (`registerIfNeeded()` returns
/// a `RegistrationOutcome`) and **loud** on the states that leave XPC dead —
/// previously `.requiresApproval` and registration errors were swallowed into an
/// os_log line nobody reads, so a needs-approval LaunchAgent silently meant every
/// `aidash` CLI call returned `xpc.app_unavailable` with no user-facing signal.
///
/// The status→action decision is a pure function (`decide`) behind an injectable
/// `StatusReader`/`Registrar` seam so every branch is unit-testable without
/// touching the real `SMAppService` (which the test host cannot register).
@MainActor
public final class LaunchdAgentInstaller {
    public static let shared = LaunchdAgentInstaller()

    /// Observable result of a registration attempt. `requiresApproval` and
    /// `failed` are the states where the mach service will NOT come up until the
    /// user (or a rebuild) intervenes — callers should surface them.
    public enum RegistrationOutcome: Equatable, Sendable {
        /// The LaunchAgent is registered/enabled; XPC can come up.
        case registered
        /// The user must approve the agent in System Settings → Login Items.
        /// XPC stays down until then. This is terminal for this code path.
        case requiresApproval
        /// `SMAppService.register()` threw. XPC stays down. Carries a short
        /// reason for logging/surfacing.
        case failed(reason: String)

        /// Whether this outcome means XPC is expected to be reachable.
        public var isHealthy: Bool { self == .registered }
    }

    /// Reads the current `SMAppService` status. Injectable for tests.
    public typealias StatusReader = @MainActor () -> SMAppService.Status
    /// Performs the actual `register()` call (throwing). Injectable for tests.
    public typealias Registrar = @MainActor () throws -> Void

    private let log = Logger(subsystem: "com.tianpli.aidash", category: "launchd")
    private let readStatus: StatusReader
    private let register: Registrar

    private init() {
        let service = SMAppService.agent(plistName: "com.tianpli.aidash.plist")
        self.readStatus = { service.status }
        self.register = { try service.register() }
    }

    /// Test seam: inject a fake status reader + registrar.
    internal init(readStatus: @escaping StatusReader, register: @escaping Registrar) {
        self.readStatus = readStatus
        self.register = register
    }

    /// Registers the LaunchAgent if needed and reports the outcome.
    /// Idempotent — safe to call on every app launch.
    @discardableResult
    public func registerIfNeeded() -> RegistrationOutcome {
        let status = readStatus()
        log.info("LaunchAgent status before register: \(String(describing: status))")

        let outcome = Self.decide(status: status, register: register, log: log)

        switch outcome {
        case .registered:
            log.info("LaunchAgent registered; XPC mach service should be reachable.")
        case .requiresApproval:
            log.warning("LaunchAgent requires user approval in System Settings → Login Items. XPC will stay unavailable until enabled.")
        case .failed(let reason):
            log.error("LaunchAgent registration failed: \(reason, privacy: .public). XPC will stay unavailable.")
        }
        return outcome
    }

    /// Pure decision + effect: given the current status, decide what to do and
    /// return the resulting outcome. Extracted so all branches are unit-testable
    /// without the real `SMAppService`.
    ///
    /// `.requiresApproval` is terminal — re-registering can't clear it, so bail
    /// and report. For every other state we unconditionally re-register: BTM
    /// reports `.enabled` even after `launchctl bootout` unloaded the plist from
    /// launchd, and `register()` is the only call that re-synchronizes launchd
    /// with BTM. Without it a single `bootout` permanently strands the agent —
    /// BTM keeps reporting enabled, launchd never reloads, and the mach service
    /// has no broker (see xpc-protocol.md §"Launchd integration").
    static func decide(
        status: SMAppService.Status,
        register: @MainActor () throws -> Void,
        log: Logger
    ) -> RegistrationOutcome {
        if status == .requiresApproval {
            return .requiresApproval
        }
        do {
            try register()
            return .registered
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }
}
#endif
