import SwiftUI
import SwiftData
import AIDashCore

@main
struct AIDashApp: App {
    @State private var containerState: CloudKitContainer.InitState = .failed("Loading…")

    init() {
        #if os(macOS)
        LaunchdAgentInstaller.shared.registerIfNeeded()
        #endif
    }

    var body: some Scene {
        BriefingWindowScene(state: containerState)
    }
}
