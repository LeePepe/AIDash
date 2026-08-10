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
    internal static func storeURL() -> URL? {
        #if os(macOS)
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AIDash", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            // A sandboxed build cannot write outside its container. Fall back
            // to SwiftData's default rather than failing container creation —
            // degrading to the old behavior beats not launching (§D).
            logger.warning("Pinned store dir unavailable (\(error.localizedDescription, privacy: .public)); using SwiftData default.")
            return nil
        }
        return dir.appendingPathComponent("AIDash.store")
        #else
        return nil
        #endif
    }

    private static func makeConfiguration(
        schema: Schema,
        mode: StorageMode
    ) -> ModelConfiguration {
        let url = storeURL()
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
