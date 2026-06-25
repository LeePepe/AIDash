import Foundation
import os
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

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .private("iCloud.com.tianpli.aidash")
        )

        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            self.state = .ready(container)
        } catch {
            Self.logger.error("CloudKit container init failed: \(error.localizedDescription, privacy: .private)")
            self.state = .failed(reason: Self.iCloudUnavailableMessage)
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
