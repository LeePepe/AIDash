import SwiftUI
import SwiftData
import AIDashCore
import AIDashUI

@main
struct AIDashApp: App {
    private let containerState: CloudKitContainer.InitState

    #if os(macOS)
    private let menuBarController: MenuBarController
    private let xpcListener: XPCListener?
    #endif

    init() {
        let state = CloudKitContainer.shared.state
        self.containerState = state
        #if os(macOS)
        self.menuBarController = MenuBarController()
        // Register the LaunchAgent (T110). Idempotent — safe on every launch.
        LaunchdAgentInstaller.shared.registerIfNeeded()
        // T060: start the XPC listener once the ModelContainer is ready, so
        // the `aidash` CLI can reach us. If CloudKit init failed, skip the
        // listener — handlers need a real ModelContainer (Constitution §D.2
        // graceful degradation: surface failure in UI, do not crash).
        switch state {
        case .ready(let container):
            let listener = XPCListener(handlers: XPCHandlers(container: container))
            listener.start()
            self.xpcListener = listener
        case .failed:
            self.xpcListener = nil
        }
        #endif
    }

    var body: some Scene {
        BriefingWindowScene(state: containerState)
    }
}
