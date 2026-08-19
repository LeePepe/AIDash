import Foundation
import SwiftData
import os
import AIDashCore

// MARK: - Container Loading Protocol

/// Abstraction for off-MainActor container creation.
///
/// The protocol is `Sendable` so instances can cross into `Task.detached`.
/// The `load()` requirement is explicitly `nonisolated` — the compiler
/// enforces that conforming implementations cannot access any actor-isolated
/// state, providing compile-level proof that the heavy I/O (SQLite open,
/// schema construction) never executes on MainActor.
///
/// Implementations MUST:
/// - Call `CloudKitContainer.prepareStoreURL(sandboxRoot:)` BEFORE constructing
///   `ModelContainer` so legacy-store adoption runs on upgrade (prevents data
///   orphaning when the app transitions to the pinned store path).
///
/// Implementations MUST NOT:
/// - Use `nonisolated(unsafe)` or `@unchecked Sendable` escape hatches
/// - Enumerate, copy, move, or delete user store files outside the
///   `prepareStoreURL` contract
protocol ContainerLoading: Sendable {
    /// Create a `ModelContainer` off MainActor. May block the calling thread
    /// (SQLite open) but must never hop to MainActor.
    nonisolated func load() -> CloudKitContainer.InitState
}

// MARK: - Agent Loader (local-only, non-mutating)

#if os(macOS)
/// Production loader for the headless XPC agent. Creates a local-only
/// ModelContainer at the pinned store path. Calls `prepareStoreURL` to
/// ensure legacy-store adoption runs on upgrade before opening the container.
///
/// Agent mode ALWAYS uses `.localOnly` regardless of iCloud availability:
/// `NSPersistentCloudKitContainer` SIGTRAPs in a headless launchd-agent
/// context. The agent only needs SwiftData for XPC reads/writes.
///
/// Compile-level isolation proof: this struct has no actor annotation;
/// conformance to `ContainerLoading` requires the explicit `nonisolated`
/// `load()` — any accidental @MainActor access is a compile error.
struct AgentContainerLoader: ContainerLoading {
    /// nil in production; set by tests to confine legacy-store adoption
    /// inside a temp directory (prevents touching the real user store).
    let sandboxRoot: URL?

    init(sandboxRoot: URL? = nil) {
        self.sandboxRoot = sandboxRoot
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tianpli.aidash",
        category: "AgentContainerLoader"
    )

    nonisolated func load() -> CloudKitContainer.InitState {
        let schema = CloudKitContainer.makeSchema()
        let url = CloudKitContainer.prepareStoreURL(sandboxRoot: sandboxRoot)

        // Agent: ALWAYS local-only — no CloudKit mirror.
        let config = CloudKitContainer.makeConfiguration(
            schema: schema, mode: .localOnly, url: url
        )

        do {
            let container = try ModelContainer(for: schema, configurations: config)
            return .ready(container)
        } catch {
            Self.logger.error(
                "Agent container init failed: \(error.localizedDescription, privacy: .private)"
            )
            return .failed(
                reason: "Local store unavailable: \(error.localizedDescription)"
            )
        }
    }
}
#endif

// MARK: - GUI Loader (CloudKit-aware, off-MainActor)

/// Production loader for the GUI app (macOS + iOS). Constructs the
/// `ModelContainer` genuinely off MainActor while preserving the CloudKit-vs-
/// local configuration decision via CloudKitContainer's nonisolated statics.
///
/// Unlike `CloudKitContainer.shared`, this never blocks MainActor: SwiftUI
/// remains responsive, XPC dispatch continues, and the result is delivered
/// back to MainActor only after construction completes.
///
/// GUI mode decides `.cloudKit` vs `.localOnly` based on entitlement + account,
/// using the same gate that prevents the CloudKit-mirror crash.
///
/// Calls `prepareStoreURL(sandboxRoot:)` so legacy-store adoption runs
/// on upgrade before the container is opened — ensuring upgrade users'
/// data is carried forward to the pinned store path.
struct GUIContainerLoader: ContainerLoading {
    /// nil in production; set by tests to confine legacy-store adoption
    /// inside a temp directory (prevents touching the real user store).
    let sandboxRoot: URL?

    init(sandboxRoot: URL? = nil) {
        self.sandboxRoot = sandboxRoot
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tianpli.aidash",
        category: "GUIContainerLoader"
    )

    nonisolated func load() -> CloudKitContainer.InitState {
        let schema = CloudKitContainer.makeSchema()
        let cloudAvailable = CloudKitContainer.isCloudKitAvailable()
        let mode = CloudKitContainer.storageMode(cloudAvailable: cloudAvailable)

        let url = CloudKitContainer.prepareStoreURL(sandboxRoot: sandboxRoot)

        let config = CloudKitContainer.makeConfiguration(
            schema: schema, mode: mode, url: url
        )

        do {
            let container = try ModelContainer(for: schema, configurations: config)
            return .ready(container)
        } catch {
            Self.logger.error(
                "GUI container init failed: \(error.localizedDescription, privacy: .private)"
            )
            return .failed(reason: CloudKitContainer.iCloudUnavailableMessage)
        }
    }
}

// MARK: - Bootstrap Coordinator

/// Manages async container loading and publishes the result as observable
/// state. SwiftUI re-evaluates `App.body` when `containerState` changes;
/// on macOS, XPCHandlers gets the container injected on completion.
///
/// Single loading strategy for all modes:
/// - `startDetached(loader:)` — genuinely off-MainActor via Task.detached +
///   nonisolated loader. The MainActor is never blocked regardless of how
///   long the underlying SQLite/CloudKit open takes.
@MainActor @Observable
final class AppBootstrap {
    /// Current store state. Drives BriefingWindowScene content.
    /// Starts as `.failed(reason: "")` (loading sentinel); transitions to
    /// `.ready` or `.failed(reason:)` once loading completes.
    private(set) var containerState: CloudKitContainer.InitState = .failed(reason: "")

    #if os(macOS)
    private let handlers: XPCHandlers?

    init(handlers: XPCHandlers?) {
        self.handlers = handlers
    }
    #else
    init() {}
    #endif

    /// Load off MainActor via a nonisolated loader.
    ///
    /// The `loader.load()` call is guaranteed nonisolated by the protocol —
    /// even if the SQLite open hangs indefinitely, MainActor is never blocked:
    /// SwiftUI renders, XPC dispatches `ping`/`schema.list`, and store-
    /// dependent mutations return `internal.store_not_ready` until
    /// the container is delivered by the loader.
    @discardableResult
    func startDetached(loader: any ContainerLoading) -> Task<Void, Never> {
        let loader = loader
        return Task.detached {
            let state = loader.load()
            await MainActor.run { [weak self] in
                self?.deliver(state)
            }
        }
    }

    private func deliver(_ state: CloudKitContainer.InitState) {
        self.containerState = state
        #if os(macOS)
        if case .ready(let container) = state {
            self.handlers?.container = container
        }
        #endif
    }
}
