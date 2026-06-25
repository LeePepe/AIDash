import SwiftUI
import SwiftData
import AIDashCore
import AIDashUI

@main
struct AIDashApp: App {
    private let container = CloudKitContainer.shared

    #if os(macOS)
    private let menuBarController = MenuBarController()
    #endif

    init() {
        #if os(macOS)
        // Start XPC listener so the CLI can reach us
        XPCListener.shared.start()

        // Register login item (T110)
        LaunchdAgentInstaller.shared.registerIfNeeded()
        #endif
    }

    var body: some Scene {
        BriefingWindowScene(state: container.state)
    }
}
