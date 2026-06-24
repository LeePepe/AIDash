import SwiftData
import Foundation

/// Shared ModelContainer for AIDash persistent storage.
/// TODO(T070): Add CloudKit sync, migration policies, and observable sync state.
@MainActor
public final class CloudKitContainer {
    public static let shared = CloudKitContainer()

    public let state: ModelContainer

    private init() {
        let schema = Schema([
            BriefingModel.self,
            ContainerModel.self,
            CardModel.self,
            UserEventModel.self,
        ])
        do {
            state = try ModelContainer(for: schema)
        } catch {
            // Fallback: in-memory store if persistent storage fails (e.g. disk corruption)
            let fallbackConfig = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                state = try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                // Unreachable: in-memory containers do not fail under normal conditions.
                preconditionFailure("ModelContainer creation failed: \(error)")
            }
        }
    }
}
