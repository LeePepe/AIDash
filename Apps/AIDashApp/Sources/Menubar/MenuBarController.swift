#if os(macOS)
import AppKit
import SwiftUI

@MainActor
public final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?

    public override init() {
        super.init()
        installStatusItem()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "chart.bar.doc.horizontal",
                                      accessibilityDescription: "AIDash")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Briefing",
                                 action: #selector(openBriefing),
                                 keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "About AIDash",
                                 action: #selector(showAbout),
                                 keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit AIDash",
                                 action: #selector(NSApplication.terminate(_:)),
                                 keyEquivalent: "q"))
        for it in menu.items { it.target = self }
        item.menu = menu
        self.statusItem = item
    }

    @objc private func openBriefing() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title.contains("AIDash") }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NotificationCenter.default.post(name: .openBriefingWindow, object: nil)
        }
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

public extension Notification.Name {
    static let openBriefingWindow = Notification.Name("openBriefingWindow")
}
#endif
