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

        // Register LaunchAgent (T110)
        LaunchdAgentInstaller.shared.registerIfNeeded()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if let state = container.state {
                Text("AIDash") // TODO(T090): Replace with BriefingView
                    .modelContainer(state)
            } else {
                Text("AIDash could not initialize storage.\nPlease restart the app.")
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .appInfo) { /* TODO: About menu */ }
        }
        #endif
    }
}
