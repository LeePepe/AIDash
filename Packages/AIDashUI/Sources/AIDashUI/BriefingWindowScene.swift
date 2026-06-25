import SwiftUI
import SwiftData

/// The primary window scene displaying today's briefing.
/// TODO(T082): Full BriefingWindowScene with BriefingView and navigation.
public struct BriefingWindowScene: Scene {
    private let container: ModelContainer?

    public init(state: ModelContainer?) {
        self.container = state
    }

    public var body: some Scene {
        WindowGroup {
            if let container {
                // TODO(T082/T090): Replace with BriefingView
                Text(String(localized: "briefing.app_name", defaultValue: "AIDash"))
                    .modelContainer(container)
            } else {
                ContentUnavailableView {
                    Label {
                        Text(String(localized: "briefing.storage_unavailable.title", defaultValue: "Storage Unavailable"))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                } description: {
                    Text(String(localized: "briefing.storage_unavailable.description", defaultValue: "AIDash could not initialize storage.\nPlease restart the app or check iCloud settings."))
                }
            }
        }
    }
}
