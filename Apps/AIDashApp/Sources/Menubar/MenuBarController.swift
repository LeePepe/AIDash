#if os(macOS)
import AppKit

@MainActor
public final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?

    /// Test-only accessor: lets `MenuBarControllerTests` inspect the
    /// installed `NSStatusItem` to assert layout-recursion guarantees
    /// (fixed length, sized template image). Not part of the public API
    /// surface used by production code.
    internal var statusItemForTesting: NSStatusItem? { statusItem }

    public override init() {
        super.init()
        installStatusItem()
    }

    private func installStatusItem() {
        // Use a fixed square length and a sized template image. On macOS 26
        // a variable-length NSStatusItem combined with an SF Symbol image
        // whose `size` is the symbol's intrinsic size triggers an AppKit
        // `_NSDetectedLayoutRecursion` warning during the initial layout
        // pass: the status-item host view runs `-layoutSubtreeIfNeeded` to
        // measure the icon while it is already inside its own layout pass.
        // Pinning `length` and giving the image a stable size + template
        // flag breaks that recursion before AppKit ever enters it.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = NSImage(systemSymbolName: "chart.bar.doc.horizontal",
                              accessibilityDescription: Self.appName) {
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            item.button?.image = icon
        }

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

    // MARK: - Localized strings
    //
    // All user-visible strings are resolved through the app's String Catalog
    // (`Apps/AIDashApp/Resources/Localizable.xcstrings`) per Constitution §F.1.
    // The `defaultValue` keeps the English string available even before a
    // translator fills in the catalog entry.

    static var appName: String {
        String(
            localized: "menubar.app_name",
            defaultValue: "AIDash",
            bundle: .main,
            comment: "Accessibility label for the AIDash menu bar status item icon."
        )
    }

    static var openBriefingTitle: String {
        String(
            localized: "menubar.open_briefing",
            defaultValue: "Open Briefing",
            bundle: .main,
            comment: "Menu bar item that opens the briefing window."
        )
    }

    static var aboutTitle: String {
        String(
            localized: "menubar.about",
            defaultValue: "About AIDash",
            bundle: .main,
            comment: "Menu bar item that opens the standard About panel."
        )
    }

    static var quitTitle: String {
        String(
            localized: "menubar.quit",
            defaultValue: "Quit AIDash",
            bundle: .main,
            comment: "Menu bar item that quits the AIDash app."
        )
    }
}

public extension Notification.Name {
    static let openBriefingWindow = Notification.Name("openBriefingWindow")
}
#endif
