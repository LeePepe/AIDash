import SwiftUI
import SwiftData
import AIDashCore

@main
struct AIDashApp: App {
    @State private var containerState: CloudKitContainer.InitState = .failed("Loading…")

    var body: some Scene {
        BriefingWindowScene(state: containerState)
    }
}
