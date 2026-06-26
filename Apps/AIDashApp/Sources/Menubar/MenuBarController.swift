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

        let openItem = NSMenuItem(title: Self.openBriefingTitle,
                                   action: #selector(openBriefing),
                                   keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: Self.aboutTitle,
                                    action: #selector(showAbout),
                                    keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Quit: target NSApp directly so NSApplication.terminate(_:) dispatches correctly.
        let quitItem = NSMenuItem(title: Self.quitTitle,
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

    // MARK: - Localized titles
    // Resolved through the app's String Catalog (`Localizable.xcstrings`)
    // so translations can be added without code changes (Constitution §F.1).

    internal static var openBriefingTitle: String {
        String(
            localized: "menubar.openBriefing",
            defaultValue: "Open Briefing",
            bundle: .main,
            comment: "Menu bar item that opens the briefing window."
        )
    }

    internal static var aboutTitle: String {
        String(
            localized: "menubar.aboutAIDash",
            defaultValue: "About AIDash",
            bundle: .main,
            comment: "Menu bar item that opens the standard About panel."
        )
    }

    internal static var quitTitle: String {
        String(
            localized: "menubar.quitAIDash",
            defaultValue: "Quit AIDash",
            bundle: .main,
            comment: "Menu bar item that terminates the application."
        )
    }
}

public extension Notification.Name {
    static let openBriefingWindow = Notification.Name("openBriefingWindow")
}
#endif
