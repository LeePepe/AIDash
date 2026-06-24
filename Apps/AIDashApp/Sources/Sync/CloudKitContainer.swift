import Foundation
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
            self.state = .failed(reason: error.localizedDescription)
        }
    }

    /// Convenience accessor. Callers MUST inspect `state` first and show
    /// the error scene when `.failed`. This fallback exists solely to keep
    /// type signatures clean for code paths that only execute when `.ready`.
    public var modelContainer: ModelContainer {
        switch state {
        case .ready(let container):
            return container
        case .failed(let reason):
            assertionFailure("CloudKitContainer unavailable: \(reason). Caller must inspect .state first.")
            let inMemory = ModelConfiguration(isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            return try! ModelContainer(
                for: BriefingModel.self,
                ContainerModel.self,
                CardModel.self,
                UserEventModel.self,
                configurations: inMemory
            )
        }
    }
}
