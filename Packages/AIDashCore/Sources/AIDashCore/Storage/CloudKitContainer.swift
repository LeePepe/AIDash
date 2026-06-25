import SwiftData
import Foundation
import os

private let logger = Logger(subsystem: "com.tianpli.aidash", category: "CloudKitContainer")

/// Shared ModelContainer for AIDash persistent storage.
/// Configures a CloudKit-backed private database for cross-device sync.
/// TODO(T070): Add migration policies and observable sync state.
@MainActor
public final class CloudKitContainer {
    public static let shared = CloudKitContainer()

    /// The model container, or `nil` when creation failed.
    /// A nil value means the app should display an error state — data is NOT
    /// silently written to disposable in-memory storage.
    public let state: ModelContainer?

    /// Non-nil when container creation failed.
    public let initializationError: (any Error)?

    private init() {
        (state, initializationError) = Self.createContainer(
            schema: Self.appSchema,
            inMemoryOnly: false
        )
    }

    /// Creates an in-memory container for testing.
    init(inMemoryOnly: Bool) {
        (state, initializationError) = Self.createContainer(
            schema: Self.appSchema,
            inMemoryOnly: inMemoryOnly
        )
    }

    // MARK: - Private

    static let cloudKitContainerIdentifier = "iCloud.com.tianpli.aidash"

    private static let appSchema = Schema([
        BriefingModel.self,
        ContainerModel.self,
        CardModel.self,
        UserEventModel.self,
    ])

    private static func createContainer(
        schema: Schema,
        inMemoryOnly: Bool
    ) -> (ModelContainer?, (any Error)?) {
        if inMemoryOnly {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                let container = try ModelContainer(for: schema, configurations: [config])
                return (container, nil)
            } catch {
                logger.fault("In-memory ModelContainer failed: \(error.localizedDescription, privacy: .public)")
                return (nil, error)
            }
        }

        // Use CloudKit-backed persistent store for cross-device sync.
        // The .private database maps to the iCloud container configured in the
        // app's entitlements.
        let config = ModelConfiguration(
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            return (container, nil)
        } catch {
            logger.error("Persistent CloudKit ModelContainer failed: \(error.localizedDescription, privacy: .public)")
            return (nil, error)
        }
    }
}
