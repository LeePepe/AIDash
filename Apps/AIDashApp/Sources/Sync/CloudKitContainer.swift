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
    internal static func storeURL() -> URL? {
        #if os(macOS)
        return realHomeDirectory()
            .appendingPathComponent("Library/Application Support/AIDash", isDirectory: true)
            .appendingPathComponent("AIDash.store")
        #else
        return nil
        #endif
    }

    /// Resolve the store URL AND make it usable: create the directory and, on
    /// first run, adopt any legacy store. Returns nil to fall back to
    /// SwiftData's default when the directory cannot be created.
    ///
    /// Split from `storeURL()` on purpose. Folding these side effects into a
    /// getter meant merely *asking* for the path created a directory and moved
    /// real files — a unit test that called it relocated the developer's actual
    /// store and, worse, left an EMPTY pinned store behind, which permanently
    /// suppresses the real migration (adoption is skipped once the destination
    /// exists). Path math and data movement must not share a function.
    internal static func prepareStoreURL() -> URL? {
        #if os(macOS)
        guard let pinned = storeURL() else { return nil }
        let dir = pinned.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            // A sandboxed build genuinely cannot create a directory under the
            // real home, so it degrades to SwiftData's default rather than
            // failing container creation (§D). NOTE: that also means the
            // sandboxed/unsandboxed split-brain is NOT fixed for sandboxed
            // builds — the pin only holds for the unsandboxed install.
            logger.warning("Pinned store dir unavailable (\(error.localizedDescription, privacy: .public)); using SwiftData default.")
            return nil
        }
        adoptLegacyStoreIfNeeded(pinned: pinned)
        return pinned
        #else
        return nil
        #endif
    }

    #if os(macOS)
    /// The user's REAL home directory, even inside the App Sandbox.
    ///
    /// `FileManager.homeDirectoryForCurrentUser` / `NSHomeDirectory()` are
    /// container-relative: in a sandboxed process they return
    /// `~/Library/Containers/<bundleID>/Data`, NOT `/Users/<name>`. Building the
    /// "pinned" path from either of those would just re-derive a container path
    /// and leave the store forking on sandbox posture — the exact bug this is
    /// meant to close. `getpwuid_r` reads the passwd database directly and is
    /// the documented sandbox-independent answer.
    ///
    /// A sandboxed build then genuinely CANNOT create that directory (no
    /// entitlement for it), which is what makes `storeURL()`'s catch branch
    /// reachable and meaningful: it degrades to SwiftData's default instead of
    /// failing launch.
    internal static func realHomeDirectory() -> URL {
        var buffer = [CChar](repeating: 0, count: 4096)
        var pw = passwd()
        var result: UnsafeMutablePointer<passwd>?
        if getpwuid_r(getuid(), &pw, &buffer, buffer.count, &result) == 0,
           result != nil, let dir = pw.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
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

    /// Testable core of the migration: `candidates` is injected so the behavior
    /// can be exercised against a temp directory instead of the real home.
    internal static func adoptLegacyStore(from candidates: [URL], to pinned: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: pinned.path) else { return }

        let existing = candidates.filter { fm.fileExists(atPath: $0.path) }
        guard let legacy = existing.max(by: { lhs, rhs in
            let l = (try? fm.attributesOfItem(atPath: lhs.path)[.modificationDate] as? Date) ?? nil
            let r = (try? fm.attributesOfItem(atPath: rhs.path)[.modificationDate] as? Date) ?? nil
            return (l ?? .distantPast) < (r ?? .distantPast)
        }) else { return }

        // Move the main store FIRST and bail out if it fails. The sidecars must
        // never be moved away from a store that stayed behind: a legacy store
        // stripped of its -wal loses every committed-but-not-checkpointed row,
        // which is precisely the loss this function exists to prevent. Failing
        // here leaves the legacy set intact and recoverable by hand.
        do {
            try fm.moveItem(at: legacy, to: pinned)
        } catch {
            logger.error("Legacy store adopt aborted; leaving it intact: \(error.localizedDescription, privacy: .public)")
            return
        }

        // -wal / -shm must travel with the store or committed rows are lost.
        for suffix in ["-wal", "-shm"] {
            let from = URL(fileURLWithPath: legacy.path + suffix)
            let to = URL(fileURLWithPath: pinned.path + suffix)
            guard fm.fileExists(atPath: from.path) else { continue }
            do {
                try fm.moveItem(at: from, to: to)
            } catch {
                logger.error("Legacy store adopt failed for \(suffix, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
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
