import Foundation
import os
#if os(macOS)
import Security
#endif
import SwiftData
import AIDashCore

@MainActor
public final class CloudKitContainer {
    public static let shared = CloudKitContainer()

    public enum InitState: Sendable {
        case ready(ModelContainer)
        case failed(reason: String)
    }

    public let state: InitState

    // `internal` (not `private`): the store-migration half lives in
    // CloudKitStoreMigration.swift and logs through the same category.
    nonisolated internal static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tianpli.aidash",
        category: "CloudKitContainer"
    )

    // MARK: - Nonisolated shared helpers
    //
    // These are explicitly `nonisolated` so both `GUIContainerLoader` and
    // `AgentContainerLoader` can call them from `Task.detached` without
    // hopping to MainActor. They access no actor-isolated state — only
    // pure computations, synchronous system APIs, and thread-safe frameworks
    // (Security, FileManager).

    /// The canonical SwiftData schema used by all container paths.
    nonisolated internal static func makeSchema() -> Schema {
        Schema([
            BriefingModel.self,
            ContainerModel.self,
            CardModel.self,
            UserEventModel.self,
        ])
    }

    /// Internal initializer for testing — allows injecting a specific state.
    internal init(state: InitState) {
        self.state = state
    }

    /// A container that NEVER attaches the CloudKit mirror — always local-only.
    ///
    /// Used by the headless XPC agent (launchd-spawned): even when an iCloud
    /// account is present, `NSPersistentCloudKitContainer` SIGTRAPs when brought
    /// up in a windowless launchd-agent context. Forcing local-only sidesteps
    /// that entirely; the agent only needs SwiftData to serve XPC reads/writes.
    static func localOnly() -> CloudKitContainer {
        let schema = Schema([
            BriefingModel.self, ContainerModel.self,
            CardModel.self, UserEventModel.self,
        ])
        let config = Self.makeConfiguration(schema: schema, mode: .localOnly)
        do {
            let container = try ModelContainer(for: schema, configurations: config)
            return CloudKitContainer(state: .ready(container))
        } catch {
            logger.error("Local-only container init failed: \(error.localizedDescription, privacy: .private)")
            return CloudKitContainer(state: .failed(reason: Self.iCloudUnavailableMessage))
        }
    }

    private init() {
        let schema = Schema([
            BriefingModel.self,
            ContainerModel.self,
            CardModel.self,
            UserEventModel.self,
        ])

        // Preflight iCloud availability BEFORE attaching the CloudKit mirror.
        //
        // `NSPersistentCloudKitContainer` (which SwiftData uses for
        // `cloudKitDatabase: .private`) brings CloudKit up asynchronously on
        // `com.apple.coredata.cloudkit.queue`. When the mirror cannot start —
        // no iCloud account, iCloud disabled for the app, region-ineligible, or
        // the `com.apple.developer.icloud-services` entitlement is missing —
        // CloudKit calls `os_crash`/`brk 1` and aborts the WHOLE process. That
        // failure can never reach the `do/catch` below, because
        // `ModelContainer(for:)` returns successfully and synchronously, then
        // the crash happens later off-thread. Attaching the mirror only when
        // BOTH preconditions hold turns the un-catchable crash into a clean
        // local-only fallback so the app still launches and works (sync off).
        let cloudAvailable = Self.isCloudKitAvailable()
        let configuration = Self.makeConfiguration(
            schema: schema,
            mode: Self.storageMode(cloudAvailable: cloudAvailable)
        )

        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            self.state = .ready(container)
        } catch {
            Self.logger.error("Model container init failed: \(error.localizedDescription, privacy: .private)")
            self.state = .failed(reason: Self.iCloudUnavailableMessage)
        }
    }

    /// Backing store mode chosen at init time.
    internal enum StorageMode: Equatable {
        /// CloudKit-mirrored private database (cross-device sync).
        case cloudKit
        /// Local-only store; used when iCloud is unavailable so the app still
        /// launches instead of letting the CloudKit mirror crash the process.
        case localOnly
    }

    /// Pure decision function: which backing store to use given whether an
    /// iCloud account is currently available. Extracted so the gate that
    /// prevents the CloudKit-mirror crash is deterministically testable.
    nonisolated internal static func storageMode(cloudAvailable: Bool) -> StorageMode {
        cloudAvailable ? .cloudKit : .localOnly
    }

    /// Synchronous preflight: is it safe to attach the CloudKit mirror right now?
    ///
    /// CloudKit fatally aborts the process if asked to mirror without BOTH:
    ///   1. the `com.apple.developer.icloud-services` entitlement granting
    ///      "CloudKit" (absent in unsigned/CI builds), and
    ///   2. an active iCloud account on the device (`ubiquityIdentityToken`).
    /// Both checks are synchronous, so they complete before `ModelContainer`
    /// spins up the async mirroring delegate that would otherwise crash.
    nonisolated internal static func isCloudKitAvailable() -> Bool {
        hasCloudKitEntitlement() && FileManager.default.ubiquityIdentityToken != nil
    }

    /// Reads the running binary's `com.apple.developer.icloud-services`
    /// entitlement and returns `true` only if it grants CloudKit access.
    /// Returns `false` for unsigned binaries or when the entitlement is absent
    /// — exactly the cases where attaching the mirror would crash the process.
    ///
    /// The SecCode path only exists on macOS. On iOS the app is always a
    /// provision-signed GUI process (no headless launchd agent context), the
    /// entitlement is guaranteed by the provisioning profile, and there is no
    /// equivalent SecCode API — so the gate degenerates to `true` and the
    /// downstream `ubiquityIdentityToken` check in `isCloudKitAvailable()`
    /// still gracefully falls back to local-only when the user has no iCloud
    /// account signed in.
    private nonisolated static func hasCloudKitEntitlement() -> Bool {
        #if os(macOS)
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode, SecCSFlags(rawValue: kSecCSRequirementInformation), &info
        ) == errSecSuccess,
              let entitlements = (info as? [String: Any])?["entitlements-dict"]
                as? [String: Any],
              let services = entitlements["com.apple.developer.icloud-services"]
                as? [String]
        else { return false }

        return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
        #else
        return true
        #endif
    }

    /// CloudKit private-database container identifier. Must match the
    /// `com.apple.developer.icloud-container-identifiers` entitlement.
    ///
    /// 从 app 自己的 bundle id 推导(约定 `iCloud.<bundle id>`),所以改
    /// `Configs/Identity.xcconfig` 的 `AIDASH_BUNDLE_ID` 后这里自动跟随 ——
    /// entitlement 用的 `$(AIDASH_CLOUDKIT_CONTAINER)` 默认也是同一个约定值。
    /// 若你的容器名不遵循该约定,在 xcconfig 里单独设 `AIDASH_CLOUDKIT_CONTAINER`,
    /// 并把下面的 fallback 常量改成同一个字符串。
    nonisolated internal static let cloudKitContainerIdentifier: String = {
        if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty {
            return "iCloud.\(bundleID)"
        }
        return "iCloud.com.tianpli.aidash"
    }()

    /// Explicit, sandbox-independent store location (macOS only).
    ///
    /// SwiftData's default store path is resolved relative to the *running
    /// process's* container, so it silently MOVES when the same app runs
    /// sandboxed (Xcode/dev build → `~/Library/Containers/<bundleID>/Data/…`)
    /// versus unsandboxed (the ad-hoc fixed install → `~/Library/…`). Two
    /// stores then exist side by side and neither can see the other's rows.
    ///
    /// That is not hypothetical: a star event recorded on 2026-08-03 was
    /// orphaned exactly this way when `scripts/dev/install-fixed-build.sh`
    /// deployed an unsandboxed Release build — `events pull` kept answering
    /// `ok:true, count:0` against a *different, freshly created* store while
    /// the event sat in the abandoned one. Append-only events (Constitution
    /// §I) must not be able to go missing because of a packaging change.
    ///
    /// Pinning the path makes the store identity independent of sandbox
    /// posture. iOS is deliberately excluded: it is always sandboxed, its
    /// container path is already stable, and an absolute home-relative URL
    /// would be wrong there.
    ///
    /// On first run the pinned location does not exist yet, so we ADOPT the
    /// legacy default store rather than silently starting empty beside it —
    /// see `adoptLegacyStoreIfNeeded`. Pinning without adopting would have
    /// re-created the exact bug this is meant to fix, one directory over.
    /// PURE path derivation — no filesystem writes, no migration. Safe to call
    /// from tests and from anywhere that just wants to know where the store
    /// lives. `prepareStoreURL()` is the one that has side effects.
    ///
    /// The path is the app container's Application Support directory, spelled
    /// ABSOLUTELY from the real home:
    ///   ~/Library/Containers/<bundleID>/Data/Library/Application Support/AIDash
    ///
    /// That choice is what actually makes the location sandbox-independent, and
    /// it is not the obvious one. Pinning to `~/Library/Application Support`
    /// looks cleaner but a SANDBOXED build cannot write there, so it would have
    /// to fall back to SwiftData's default — leaving sandboxed and unsandboxed
    /// builds on two different databases, i.e. the split-brain unfixed. The
    /// container path is the one location BOTH postures can reach: a sandboxed
    /// process resolves it as its own container (it is literally what
    /// `NSHomeDirectory()` returns there), and an unsandboxed process can open
    /// it as a plain absolute path. One path, one store, either way.
    nonisolated internal static func storeURL() -> URL? {
        #if os(macOS)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tianpli.aidash"
        return realHomeDirectory()
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Application Support/AIDash",
                                    isDirectory: true)
            .appendingPathComponent("AIDash.store")
        #else
        return nil
        #endif
    }

    /// Resolve the store URL AND make it usable: create the directory and, on
    /// first run, adopt any legacy store. Returns nil to fall back to
    /// SwiftData's default when the directory cannot be created.
    ///
    /// Redirects the WHOLE store-migration world — destination and legacy
    /// SOURCES — into one directory. Set by tests; `nil` in production.
    ///
    /// Why a sandbox ROOT rather than just a destination URL: the migration has
    /// two halves, and pinning only the destination leaves the dangerous half
    /// pointing at the real home. A test that redirected only `pinned` would
    /// still let `adoptLegacyStore` discover the developer's REAL legacy store,
    /// move it into the test's temp directory, and then delete it along with
    /// that directory on teardown — destroying data instead of merely
    /// relocating it. That is not hypothetical: it happened here.
    ///
    /// Tests are NOT naturally isolated in this target. `project.yml` pins
    /// `TEST_HOST` to the real `AIDash.app` (needed for RunMode /
    /// LaunchdAgentInstaller / live-XPC tests), so the test bundle is injected
    /// into the production app: `Bundle.main.bundleIdentifier` is the real
    /// bundle ID and `realHomeDirectory()` is the real home. Path derivation is
    /// byte-identical to production. Isolation must therefore be explicit in
    /// code — the environment provides none.
    ///
    /// Plain `@MainActor` state — NOT `nonisolated(unsafe)`. The enclosing type
    /// is already `@MainActor`, so the actor supplies the mutual exclusion that
    /// a `nonisolated(unsafe) static var` would have thrown away: swift-testing
    /// runs suites in parallel, and an unsynchronized read-modify-restore would
    /// let two tests clobber each other's override. Staying on the actor also
    /// keeps this inside the constitution's concurrency rule rather than
    /// needing the ADR that `nonisolated(unsafe)` demands.
    internal static var sandboxRoot: URL?

    /// Run `body` with the entire store world confined to `root`, restoring the
    /// previous value afterwards. Tests use this instead of touching the real
    /// home. Both the pinned destination and the legacy-source search live
    /// under `root`, so nothing outside it can be read, moved, or deleted.
    internal static func withStoreSandbox<T>(_ root: URL, _ body: () throws -> T) rethrows -> T {
        let previous = sandboxRoot
        sandboxRoot = root
        defer { sandboxRoot = previous }
        return try body()
    }

    /// Split from `storeURL()` on purpose. Folding these side effects into a
    /// getter meant merely *asking* for the path created a directory and moved
    /// real files — a unit test that called it relocated the developer's actual
    /// store and, worse, left an EMPTY pinned store behind, which permanently
    /// suppresses the real migration (adoption is skipped once the destination
    /// exists). Path math and data movement must not share a function.
    internal static func prepareStoreURL() -> URL? {
        #if os(macOS)
        // ORDER MATTERS. The test guard comes FIRST, before any override is
        // consulted. A previous revision checked the override first, so a test
        // that set one re-opened the full real-home migration path and skipped
        // this guard entirely. Under test, the only reachable locations are
        // inside an explicit sandbox — never the real home, under any override.
        if isRunningTests {
            guard let root = sandboxRoot else {
                logger.notice("Test process without a store sandbox: skipping pinned store + migration.")
                return nil
            }
            return prepare(pinned: root.appendingPathComponent("AIDash.store"),
                           legacyCandidates: legacyStoreURLs(under: root))
        }
        guard let pinned = storeURL() else { return nil }
        return prepare(pinned: pinned, legacyCandidates: legacyStoreURLs())
        #else
        return nil
        #endif
    }

    #if os(macOS)
    /// True when the process is hosting XCTest/swift-testing.
    internal static var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// Create the directory and adopt any legacy store for a given location.
    private static func prepare(pinned: URL, legacyCandidates: [URL]) -> URL? {
        let dir = pinned.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            // Both postures can normally create this directory — a sandboxed
            // process owns its container, and an unsandboxed one has full home
            // access — so reaching here means something genuinely unusual (disk
            // full, a file occupying the path, revoked permissions). Degrade to
            // SwiftData's default rather than failing container creation (§D):
            // the app still launches. It does mean THIS launch reads a
            // different store, so the failure is logged rather than swallowed.
            logger.warning("Pinned store dir unavailable (\(error.localizedDescription, privacy: .public)); using SwiftData default.")
            return nil
        }
        adoptLegacyStore(from: legacyCandidates, to: pinned)
        return pinned
    }
    #endif

    private static func makeConfiguration(
        schema: Schema,
        mode: StorageMode
    ) -> ModelConfiguration {
        let url = prepareStoreURL()
        return Self.makeConfiguration(schema: schema, mode: mode, url: url)
    }

    /// Nonisolated configuration builder for off-MainActor container creation.
    ///
    /// Unlike the private `makeConfiguration(schema:mode:)` which calls
    /// `prepareStoreURL()` (filesystem mutation + legacy adoption), this overload
    /// takes a pre-resolved URL and performs NO filesystem side effects beyond
    /// what `ModelContainer` itself does on open. Used by `AgentContainerLoader`
    /// and `GUIContainerLoader` in `AppBootstrap`.
    nonisolated internal static func makeConfiguration(
        schema: Schema,
        mode: StorageMode,
        url: URL?
    ) -> ModelConfiguration {
        switch mode {
        case .cloudKit:
            if let url {
                return ModelConfiguration(
                    schema: schema,
                    url: url,
                    allowsSave: true,
                    cloudKitDatabase: .private(cloudKitContainerIdentifier)
                )
            }
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                groupContainer: .none,
                cloudKitDatabase: .private(cloudKitContainerIdentifier)
            )
        case .localOnly:
            if let url {
                return ModelConfiguration(
                    schema: schema,
                    url: url,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
            }
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
        }
    }

    /// User-facing message used when CloudKit init fails. Resolved through the
    /// app's String Catalog (`Localizable.xcstrings`, key `cloudkit.unavailable.message`)
    /// so translations can be added without code changes (Constitution §F.1).
    nonisolated internal static var iCloudUnavailableMessage: String {
        String(
            localized: "cloudkit.unavailable.message",
            defaultValue: "iCloud data sync is unavailable. Please check your iCloud account in Settings.",
            bundle: .main,
            comment: "Shown in the iCloud unavailable scene when SwiftData CloudKit init fails."
        )
    }

    /// Returns the model container when state is `.ready`.
    ///
    /// - Returns: The shared `ModelContainer` for SwiftData operations.
    /// - Throws: `CloudKitContainerError.unavailable(reason:)` when `state` is
    ///   `.failed`. Callers MUST inspect `state` first; reaching this getter
    ///   while `.failed` is a programming error and the throw is the graceful
    ///   contract that replaces a crash.
    public var modelContainer: ModelContainer {
        get throws {
            switch state {
            case .ready(let container):
                return container
            case .failed(let reason):
                throw CloudKitContainerError.unavailable(reason: reason)
            }
        }
    }
}

public enum CloudKitContainerError: Error, LocalizedError {
    case unavailable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        }
    }
}
