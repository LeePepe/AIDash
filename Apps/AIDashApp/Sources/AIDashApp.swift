import SwiftUI
import SwiftData
import AIDashCore
import AIDashUI

@main
struct AIDashApp: App {
    @State private var containerState: CloudKitContainer.InitState = .failed("Loading…")

    #if os(macOS)
    private let menuBarController = MenuBarController()
    #endif

    init() {
        #if os(macOS)
        // TODO(T060): Start XPCListener once the listener lands on main so the CLI can reach us.
        // Register the LaunchAgent (T110). Idempotent — safe on every launch.
        LaunchdAgentInstaller.shared.registerIfNeeded()
        #endif
    }

    var body: some Scene {
        BriefingWindowScene(state: containerState)
    }
}
