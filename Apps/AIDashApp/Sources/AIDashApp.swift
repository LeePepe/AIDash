import SwiftUI
import SwiftData
import AIDashCore
import AIDashUI

@main
struct AIDashApp: App {
    private let containerState: CloudKitContainer.InitState

    #if os(macOS)
    private let menuBarController: MenuBarController
    #endif

    init() {
        self.containerState = CloudKitContainer.shared.state
        #if os(macOS)
        self.menuBarController = MenuBarController()
        // TODO(T060): Start XPCListener once the listener lands on main so the CLI can reach us.
        // Register the LaunchAgent (T110). Idempotent — safe on every launch.
        LaunchdAgentInstaller.shared.registerIfNeeded()
        #endif
    }

    var body: some Scene {
        BriefingWindowScene(state: containerState)
    }
}
