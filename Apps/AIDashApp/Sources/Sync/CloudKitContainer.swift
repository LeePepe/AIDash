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
            self.state = .failed(reason: "iCloud data sync is unavailable. Please check your iCloud account in Settings.")
        }
    }

    /// Returns the model container when state is `.ready`.
    /// Callers MUST inspect `state` first; calling this when `.failed` is a programming error.
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
