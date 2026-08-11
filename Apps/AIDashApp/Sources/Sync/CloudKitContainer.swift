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

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tianpli.aidash",
        category: "CloudKitContainer"
    )

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
    internal static func storageMode(cloudAvailable: Bool) -> StorageMode {
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
    internal static func isCloudKitAvailable() -> Bool {
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
    private static func hasCloudKitEntitlement() -> Bool {
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
    internal static let cloudKitContainerIdentifier: String = {
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
    internal static func storeURL() -> URL? {
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
    /// Overrides the pinned store location. Set by tests; `nil` in production.
    ///
    /// Exists because `prepareStoreURL()` is genuinely side-effecting: it
    /// creates a directory and migrates a legacy store. Any test that reaches
    /// container construction — including one that only asserts on
    /// `CloudKitContainer.shared.state` — would otherwise run that migration
    /// against the developer's REAL home. That is not hypothetical: repeated
    /// `xcodebuild test` runs moved a real store into the pinned location and
    /// made macOS prompt for file-access permission on every run.
    ///
    /// A test sets this to a temp directory (see `withStoreLocation`) so the
    /// whole prepare/adopt path stays inside that sandbox.
    nonisolated(unsafe) internal static var storeURLOverride: URL?

    /// Run `body` with the store pinned inside `url`, restoring the previous
    /// value afterwards. Tests use this instead of touching the real home.
    internal static func withStoreLocation<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
        let previous = storeURLOverride
        storeURLOverride = url
        defer { storeURLOverride = previous }
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
        if let override = storeURLOverride {
            return prepare(pinned: override)
        }
        // Belt and braces: an override that a test FORGOT to set would silently
        // fall through to the real home and migrate the developer's data — the
        // exact accident this change exists to prevent, and one that only shows
        // up as an OS permission prompt hours later. Under XCTest, refuse to
        // touch the real home at all and let SwiftData use its own default.
        if isRunningTests {
            logger.notice("Test process: skipping pinned store + migration; using SwiftData default.")
            return nil
        }
        guard let pinned = storeURL() else { return nil }
        return prepare(pinned: pinned)
        #else
        return nil
        #endif
    }

    #if os(macOS)
    /// True when the process is hosting XCTest/swift-testing.
    private static var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// Create the directory and adopt any legacy store for a given location.
    private static func prepare(pinned: URL) -> URL? {
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
        adoptLegacyStoreIfNeeded(pinned: pinned)
        return pinned
    }
    #endif

    #if os(macOS)
    /// The user's REAL home directory, even inside the App Sandbox.
    ///
    /// `FileManager.homeDirectoryForCurrentUser` / `NSHomeDirectory()` are
    /// container-relative: in a sandboxed process they return
    /// `~/Library/Containers/<bundleID>/Data`, NOT `/Users/<name>`. Deriving the
    /// pinned path from either would make it mean a DIFFERENT directory in each
    /// sandbox posture — the exact fork this is meant to close. `getpwuid_r`
    /// reads the passwd database directly and is the documented
    /// sandbox-independent answer, so the absolute container path it builds
    /// names the same bytes to a sandboxed and an unsandboxed process alike.
    internal static func realHomeDirectory() -> URL {
        // `pw.pw_dir` points INTO `buffer`, so the string must be copied out
        // while the buffer pointer is still guaranteed valid. Swift only
        // guarantees an `&array` pointer for the duration of the call it is
        // passed to, so reading pw_dir after the call returns would be UB.
        // withUnsafeMutableBufferPointer keeps the lifetime explicit.
        var buffer = [CChar](repeating: 0, count: 4096)
        let home: String? = buffer.withUnsafeMutableBufferPointer { buf in
            var pw = passwd()
            var result: UnsafeMutablePointer<passwd>?
            guard getpwuid_r(getuid(), &pw, buf.baseAddress, buf.count, &result) == 0,
                  result != nil, let dir = pw.pw_dir else { return nil }
            return String(cString: dir)
        }
        if let home, !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        // Fall back rather than trap; a container-relative home is still a
        // usable location, just not sandbox-independent.
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Legacy SwiftData default store locations, newest-usable first.
    ///
    /// `default.store` is what SwiftData creates when no `url:` is given. It
    /// resolves differently depending on the running process's sandbox state,
    /// which is exactly how the app ended up with two divergent stores.
    internal static func legacyStoreURLs() -> [URL] {
        let home = realHomeDirectory()
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tianpli.aidash"
        return [
            // Unsandboxed (ad-hoc fixed install) — the most recently active one.
            home.appendingPathComponent("Library/Application Support/default.store"),
            // Sandboxed (Xcode/dev build).
            home.appendingPathComponent(
                "Library/Containers/\(bundleID)/Data/Library/Application Support/default.store"
            ),
        ]
    }

    /// Move an existing legacy store into the pinned location, ONCE.
    ///
    /// Without this, pinning the path would itself orphan data: on the first
    /// launch after the change the pinned file does not exist, SwiftData would
    /// happily create a fresh empty store, and every row already on disk —
    /// including append-only events that may never have synced — would become
    /// invisible. That is the very failure this whole change exists to stop,
    /// just relocated one directory over.
    ///
    /// Picks the legacy candidate with the most recent modification time (the
    /// store the app actually used last) and moves it plus its `-wal`/`-shm`
    /// sidecars, which carry committed-but-not-checkpointed rows. Copying only
    /// the main file would silently drop whatever is still in the WAL.
    ///
    /// Deliberately a MOVE, not a copy: leaving the original behind invites a
    /// future build resolving the old path and resurrecting stale data as a
    /// third divergent store. Best-effort throughout — a failure here must
    /// never block launch (§D); worst case the app starts on the pinned store
    /// and the legacy file stays untouched for manual recovery.
    internal static func adoptLegacyStoreIfNeeded(pinned: URL) {
        adoptLegacyStore(from: legacyStoreURLs(), to: pinned)
    }

    /// Newest activity across a store's WHOLE file set, not just the `.store`.
    ///
    /// SQLite in WAL mode appends commits to `-wal` and only folds them into
    /// the main file at a checkpoint, so the `.store` mtime can lag its own
    /// live data by hours. Ranking candidates by the main file alone would
    /// therefore pick the STALER database whenever the busier one simply had
    /// not checkpointed yet — and the newest append-only events would stay
    /// orphaned, which is the precise failure this migration exists to end.
    /// (Measured on a real machine: the `-wal` was 14 hours newer than its
    /// own `.store`.)
    internal static func lastActivity(of store: URL) -> Date {
        let fm = FileManager.default
        return ["", "-wal", "-shm"].compactMap { suffix -> Date? in
            let path = store.path + suffix
            guard let attrs = try? fm.attributesOfItem(atPath: path) else { return nil }
            return attrs[.modificationDate] as? Date
        }.max() ?? .distantPast
    }

    /// Testable core of the migration: `candidates` is injected so the behavior
    /// can be exercised against a temp directory instead of the real home.
    ///
    /// COPY-then-publish, never move-in-place. The destination is only put in
    /// its final position once the WHOLE file set (store + `-wal` + `-shm`) has
    /// landed. A partial migration is unrecoverable: `adopt` is skipped forever
    /// once `pinned` exists, so a store published without its `-wal` would
    /// permanently strand every committed-but-not-checkpointed row.
    ///
    /// Staging into a sibling directory and publishing at the end makes the
    /// visible outcome all-or-nothing. On any failure everything published so
    /// far is rolled back and the legacy set is left exactly as it was, so the
    /// next launch simply retries.
    internal static func adoptLegacyStore(from candidates: [URL], to pinned: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: pinned.path) else { return }

        let existing = candidates.filter { fm.fileExists(atPath: $0.path) }
        guard let legacy = existing.max(by: {
            lastActivity(of: $0) < lastActivity(of: $1)
        }) else { return }

        // More than one legacy store means the split-brain left data on BOTH
        // sides. Only the most recently used one is adopted — SwiftData stores
        // cannot be merged file-wise, and adopting one is strictly better than
        // adopting none. Say so loudly: the other store still holds rows this
        // migration does NOT recover, and only a human can decide what to do
        // with them.
        if existing.count > 1 {
            let others = existing.filter { $0 != legacy }.map(\.path).joined(separator: ", ")
            logger.warning("Multiple legacy stores found; adopting the one with the newest activity across store/-wal/-shm. NOT migrated: \(others, privacy: .public)")
        }

        let staging = pinned.deletingLastPathComponent()
            .appendingPathComponent(".adopt-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }

        var published: [String] = []
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            // Copy the whole set first — the legacy files stay intact until the
            // publish step, so any failure here costs nothing.
            for suffix in ["", "-wal", "-shm"] {
                let from = URL(fileURLWithPath: legacy.path + suffix)
                guard fm.fileExists(atPath: from.path) else { continue }
                try fm.copyItem(
                    at: from,
                    to: staging.appendingPathComponent(pinned.lastPathComponent + suffix)
                )
            }
            // Publish sidecars first and the main store LAST, so `pinned` never
            // exists while its sidecars are missing — that ordering is what
            // makes the "skip if pinned exists" guard safe.
            //
            // Clear the destination first. The guard only checks `pinned`
            // itself, so an ORPHAN `pinned-wal` (left by an interrupted run on
            // an older build) would make every future moveItem throw and the
            // migration would fail-and-roll-back forever. Removing a sidecar
            // that has no store to belong to is safe — it is unreadable on its
            // own — and it is the difference between self-healing and a
            // permanent deadlock.
            for suffix in ["-shm", "-wal", ""] {
                let staged = staging.appendingPathComponent(pinned.lastPathComponent + suffix)
                guard fm.fileExists(atPath: staged.path) else { continue }
                let dest = URL(fileURLWithPath: pinned.path + suffix)
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: staged, to: dest)
                published.append(suffix)
            }
        } catch {
            // Roll back whatever was already published: a half-written pinned
            // set would block the retry on every future launch.
            for suffix in published {
                try? fm.removeItem(at: URL(fileURLWithPath: pinned.path + suffix))
            }
            logger.error("Legacy store adopt failed; legacy left intact, will retry: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Only now retire the originals. Leaving them behind invites a future
        // build resolving the old path and reviving stale data as a third
        // divergent store; failing to delete is harmless, so it is best-effort.
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: legacy.path + suffix))
        }
        logger.notice("Adopted legacy SwiftData store into the pinned location.")
    }
    #endif

    private static func makeConfiguration(
        schema: Schema,
        mode: StorageMode
    ) -> ModelConfiguration {
        let url = prepareStoreURL()
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
            logger.notice("iCloud unavailable; using local-only store without CloudKit sync.")
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
    internal static var iCloudUnavailableMessage: String {
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
