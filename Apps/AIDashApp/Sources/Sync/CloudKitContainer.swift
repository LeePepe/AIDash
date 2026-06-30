import Foundation
import os
import Security
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
        subsystem: "com.tianpli.aidash",
        category: "CloudKitContainer"
    )

    /// Internal initializer for testing — allows injecting a specific state.
    internal init(state: InitState) {
        self.state = state
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
    private static func hasCloudKitEntitlement() -> Bool {
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
    }

    /// CloudKit private-database container identifier. Must match the
    /// `com.apple.developer.icloud-container-identifiers` entitlement.
    internal static let cloudKitContainerIdentifier = "iCloud.com.tianpli.aidash"

    private static func makeConfiguration(
        schema: Schema,
        mode: StorageMode
    ) -> ModelConfiguration {
        switch mode {
        case .cloudKit:
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                groupContainer: .none,
                cloudKitDatabase: .private(cloudKitContainerIdentifier)
            )
        case .localOnly:
            logger.notice("iCloud unavailable; using local-only store without CloudKit sync.")
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
