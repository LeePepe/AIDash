import SwiftUI
import SwiftData

/// The primary window scene displaying today's briefing.
/// TODO(T082): Full BriefingWindowScene with BriefingView and navigation.
public struct BriefingWindowScene: Scene {
    private let container: ModelContainer

    public init(state: ModelContainer) {
        self.container = state
    }

    public var body: some Scene {
        WindowGroup {
            // TODO(T082): Replace with BriefingView
            Text("AIDash")
        }
        .modelContainer(container)
    }
}
