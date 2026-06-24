import SwiftUI
import SwiftData
import AIDashCore
import AIDashUI

@main
struct AIDashApp: App {
    @State private var cloudKitState = CloudKitContainer.shared.state

    #if os(macOS)
    private let menuBarController = MenuBarController()
    #endif

    init() {
        #if os(macOS)
        // Start XPC listener so the CLI can reach us
        XPCListener.shared.start()

        // Register LaunchAgent (T110)
        LaunchdAgentInstaller.shared.registerIfNeeded()
        #endif
    }

    var body: some Scene {
        BriefingWindowScene(state: cloudKitState)
        #if os(macOS)
            .commands {
                CommandGroup(replacing: .appInfo) { /* About menu later */ }
            }
        #endif
    }
}
