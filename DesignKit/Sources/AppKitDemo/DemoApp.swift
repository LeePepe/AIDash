import AppKit
import DesignKit
import SwiftUI

// ============================================================================
//  AppKitDemo — a thin menu-bar shell hosting DesignKit's DashboardView.
//  This is the "menu-bar form" of the one design language. For an iOS/plain
//  macOS app, host DashboardView() in a WindowGroup instead — same DesignKit.
// ============================================================================

@main
struct DemoApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "square.grid.2x2", accessibilityDescription: "Dashboard")
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.action = #selector(toggle)
        statusItem?.button?.target = self

        let root = DashboardView().designTheme(seed: .appleBlue, neutral: .slate)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: 760, height: 620)
        popover.behavior = .transient
    }

    @objc private func toggle() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
