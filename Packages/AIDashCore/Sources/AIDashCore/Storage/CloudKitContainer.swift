import SwiftData
import Foundation
import os

private let logger = Logger(subsystem: "com.tianpli.aidash", category: "CloudKitContainer")

/// Shared ModelContainer for AIDash persistent storage.
/// TODO(T070): Add CloudKit sync, migration policies, and observable sync state.
@MainActor
public final class CloudKitContainer {
    public static let shared = CloudKitContainer()

    /// The model container, or `nil` when both persistent and in-memory creation failed.
    public let state: ModelContainer?

    /// Non-nil when container creation failed entirely.
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
            return createInMemoryContainer(schema: schema)
        }

        do {
            let container = try ModelContainer(for: schema)
            return (container, nil)
        } catch {
            logger.error("Persistent ModelContainer failed: \(error, privacy: .public). Falling back to in-memory.")
            return createInMemoryContainer(schema: schema)
        }
    }

    private static func createInMemoryContainer(
        schema: Schema
    ) -> (ModelContainer?, (any Error)?) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            return (container, nil)
        } catch {
            logger.fault("In-memory ModelContainer also failed: \(error, privacy: .public). Storage is non-functional.")
            return (nil, error)
        }
    }
}
