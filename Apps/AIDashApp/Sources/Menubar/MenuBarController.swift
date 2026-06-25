#if os(macOS)
import AppKit

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

        let openItem = NSMenuItem(title: "Open Briefing",
                                   action: #selector(openBriefing),
                                   keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About AIDash",
                                    action: #selector(showAbout),
                                    keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Quit: target NSApp directly so NSApplication.terminate(_:) dispatches correctly.
        let quitItem = NSMenuItem(title: "Quit AIDash",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
    }

    @objc private func openBriefing() {
        // Activate app and always post the briefing-open notification.
        // The scene/window owner (T082) is the source of truth for which
        // window represents the briefing; we do not guess by title.
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openBriefingWindow, object: nil)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

public extension Notification.Name {
    static let openBriefingWindow = Notification.Name("openBriefingWindow")
}
#endif
