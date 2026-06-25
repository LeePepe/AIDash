#if os(macOS)
import AppKit
import os

private let logger = Logger(subsystem: "com.tianpli.aidash", category: "MenuBarController")

/// Controls the macOS menu bar status item for AIDash.
/// Provides the minimal menu surface so the LSUIElement app is visible and quittable.
/// TODO(T081): Full menu bar implementation with "Open Briefing", "About", popover.
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?

    init() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "doc.text.magnifyingglass",
                accessibilityDescription: String(localized: "menubar.app_name", defaultValue: "AIDash")
            )
        }

        let menu = NSMenu()
        // TODO(T081): Add "Open Briefing" and "About AIDash" items
        menu.addItem(
            NSMenuItem(
                title: String(localized: "menubar.quit", defaultValue: "Quit AIDash"),
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        item.menu = menu
        statusItem = item

        logger.info("Menu bar status item created.")
    }
}
#endif
