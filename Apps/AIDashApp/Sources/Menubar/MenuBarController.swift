#if os(macOS)
import AppKit
import SwiftUI

@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    public static let computerRefreshInterval: TimeInterval = 5
    public static let tokenRefreshInterval: TimeInterval = 60
    private var statusItem: NSStatusItem?
    private let statusProvider: any MenuBarSystemStatusProviding
    private var statusState: MenuBarStatusViewState = .loading
    private weak var panelItem: NSMenuItem?
    private var statusHostingView: NSHostingView<AnyView>?
    private var computerRefreshTimer: Timer?
    private var tokenRefreshTimer: Timer?

    internal var statusItemForTesting: NSStatusItem? { statusItem }
    internal var statusStateForTesting: MenuBarStatusViewState { statusState }

    public convenience override init() {
        self.init(statusProvider: LiveMenuBarSystemStatusProvider())
    }

    public init(statusProvider: any MenuBarSystemStatusProviding) {
        self.statusProvider = statusProvider
        super.init()
        installStatusItem()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = NSImage(
            systemSymbolName: "chart.bar.doc.horizontal",
            accessibilityDescription: Self.appName
        ) {
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            item.button?.image = icon
        }

        let menu = NSMenu()
        menu.delegate = self
        refreshStatus()

        let panel = NSMenuItem()
        panel.view = sizedHostedStatusView()
        menu.addItem(panel)
        panelItem = panel

        menu.addItem(summaryMenuItem(title: Self.cpuStatusTitle, tag: 1001))
        menu.addItem(summaryMenuItem(title: Self.memoryStatusTitle, tag: 1002))
        menu.addItem(summaryMenuItem(title: Self.storageStatusTitle, tag: 1003))
        menu.addItem(summaryMenuItem(title: Self.tokenStatusTitle, tag: 1004))
        var tag = 1005
        for cli in AgentCLIKind.allCases {
            menu.addItem(summaryMenuItem(title: Self.cliTokenSummary(cli: cli, usage: nil), tag: tag))
            tag += 1
        }
        menu.addItem(summaryMenuItem(title: Self.networkStatusTitle, tag: 1008))

        let refreshItem = NSMenuItem(
            title: Self.refreshTitle,
            action: #selector(refreshStatusAction),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let openItem = NSMenuItem(
            title: Self.openBriefingTitle,
            action: #selector(openBriefing),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: Self.aboutTitle,
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: Self.quitTitle,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        updateMenuPresentation()
        startPeriodicRefresh()
    }

    private func hostedStatusView() -> NSHostingView<AnyView> {
        let rootView = AnyView(MenuBarStatusView(state: statusState, onRefresh: { [weak self] in
            self?.refreshStatus()
        }))
        if let statusHostingView {
            statusHostingView.rootView = rootView
            return statusHostingView
        }
        let statusHostingView = NSHostingView(rootView: rootView)
        self.statusHostingView = statusHostingView
        return statusHostingView
    }

    private func sizedHostedStatusView() -> NSView {
        let view = hostedStatusView()
        view.layoutSubtreeIfNeeded()
        let fitting = view.fittingSize
        view.frame.size = NSSize(width: 380, height: max(fitting.height, 1))
        return view
    }

    private func summaryMenuItem(title: String, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.tag = tag
        return item
    }

    public func menuWillOpen(_ menu: NSMenu) {
        refreshStatus()
    }

    public func refreshComputerSections() {
        guard case let .populated(snapshot) = statusState else {
            refreshStatus()
            return
        }
        let computer = statusProvider.captureComputerStatus()
        statusState = .populated(snapshot.updatingComputer(computer))
        updateMenuPresentation()
    }

    public func refreshTokenSection() {
        guard case let .populated(snapshot) = statusState else {
            refreshStatus()
            return
        }
        let token = statusProvider.captureTokenStatus()
        statusState = .populated(snapshot.updatingTokenUsage(token.usage, capturedAt: token.capturedAt))
        updateMenuPresentation()
    }

    public func stopPeriodicRefresh() {
        computerRefreshTimer?.invalidate()
        tokenRefreshTimer?.invalidate()
        computerRefreshTimer = nil
        tokenRefreshTimer = nil
    }

    private func startPeriodicRefresh() {
        stopPeriodicRefresh()
        computerRefreshTimer = Timer(timeInterval: Self.computerRefreshInterval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                self.refreshComputerSections()
            }
        }
        tokenRefreshTimer = Timer(timeInterval: Self.tokenRefreshInterval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated {
                self.refreshTokenSection()
            }
        }
        if let computerRefreshTimer {
            RunLoop.main.add(computerRefreshTimer, forMode: .common)
        }
        if let tokenRefreshTimer {
            RunLoop.main.add(tokenRefreshTimer, forMode: .common)
        }
    }

    @objc private func refreshStatusAction() {
        refreshStatus()
    }

    private func refreshStatus() {
        statusState = statusProvider.captureStatusState()
        updateMenuPresentation()
    }

    private func updateMenuPresentation() {
        guard let item = statusItem else { return }
        panelItem?.view = sizedHostedStatusView()
        item.button?.toolTip = summaryText
        for (tag, title) in zip(1001...1008, summaryTitles) {
            item.menu?.item(withTag: tag)?.title = title
        }
    }

    private var summaryText: String {
        guard case let .populated(snapshot) = statusState else {
            return Self.unavailableSummary
        }
        return [
            Self.cpuSummary(snapshot.cpu),
            Self.memorySummary(snapshot.memory),
            Self.storageSummary(snapshot.storage),
            Self.tokenSummary(snapshot.tokenUsage),
            Self.cliTokenSummary(cli: .claude, usage: snapshot.tokenUsage),
            Self.cliTokenSummary(cli: .codex, usage: snapshot.tokenUsage),
            Self.cliTokenSummary(cli: .copilot, usage: snapshot.tokenUsage),
            Self.networkSummary(snapshot.network)
        ].joined(separator: ", ")
    }

    private var summaryTitles: [String] {
        guard case let .populated(snapshot) = statusState else {
            return Array(repeating: Self.unavailableSummary, count: 8)
        }
        return [
            Self.cpuSummary(snapshot.cpu),
            Self.memorySummary(snapshot.memory),
            Self.storageSummary(snapshot.storage),
            Self.tokenSummary(snapshot.tokenUsage),
            Self.cliTokenSummary(cli: .claude, usage: snapshot.tokenUsage),
            Self.cliTokenSummary(cli: .codex, usage: snapshot.tokenUsage),
            Self.cliTokenSummary(cli: .copilot, usage: snapshot.tokenUsage),
            Self.networkSummary(snapshot.network)
        ]
    }

    @objc private func openBriefing() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openBriefingWindow, object: nil)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    static var appName: String {
        localized("menubar.app_name", "AIDash")
    }

    static var openBriefingTitle: String {
        localized("menubar.open_briefing", "Open Briefing")
    }

    static var aboutTitle: String {
        localized("menubar.about", "About AIDash")
    }

    static var quitTitle: String {
        localized("menubar.quit", "Quit AIDash")
    }

    static var refreshTitle: String {
        localized("menubar.status.refresh", "Refresh Status")
    }

    static var cpuStatusTitle: String {
        localized("menubar.status.cpu_status", "CPU status")
    }

    static var memoryStatusTitle: String {
        localized("menubar.status.memory_status", "Memory status")
    }

    static var storageStatusTitle: String {
        localized("menubar.status.storage_status", "Storage status")
    }

    static var networkStatusTitle: String {
        localized("menubar.status.network_status", "Network status")
    }

    static var tokenStatusTitle: String {
        localized("menubar.status.token_status", "Agent token status")
    }

    static var unavailableSummary: String {
        localized("menubar.status.unavailable_summary", "Status unavailable")
    }

    static func cpuSummary(_ cpu: CPUStatusSnapshot) -> String {
        String(
            format: localized("menubar.status.cpu_summary", "CPU %@ · %@ user · %@ system"),
            "\(Int(cpu.usage * 100))%",
            "\(Int(cpu.user * 100))%",
            "\(Int(cpu.system * 100))%"
        )
    }

    static func memorySummary(_ memory: MemoryStatusSnapshot) -> String {
        String(
            format: localized("menubar.status.memory_summary", "Memory %@ used · %@"),
            "\(Int(memory.usageFraction * 100))%",
            pressureTitle(memory.pressure)
        )
    }

    static func pressureTitle(_ pressure: MemoryPressureLevel) -> String {
        switch pressure {
        case .normal: return localized("menubar.status.pressure_normal", "Normal")
        case .warning: return localized("menubar.status.pressure_warning", "Warning")
        case .critical: return localized("menubar.status.pressure_critical", "Critical")
        }
    }

    static func storageSummary(_ storage: StorageStatusSnapshot) -> String {
        let ssd = storage.ssdVolume.isMounted
            ? "\(Int(storage.ssdVolume.usageFraction * 100))%"
            : localized("menubar.status.not_mounted", "Not Mounted")
        return String(
            format: localized("menubar.status.storage_summary", "Storage %@ · SSD %@"),
            "\(Int(storage.systemVolume.usageFraction * 100))%",
            ssd
        )
    }

    static func networkSummary(_ network: NetworkStatusSnapshot) -> String {
        String(
            format: localized("menubar.status.network_summary", "Network %@ · ↓ %@/s · ↑ %@/s"),
            network.interfaceName,
            ByteCountFormatter.string(fromByteCount: Int64(max(network.downloadBytesPerSecond, 0)), countStyle: .binary),
            ByteCountFormatter.string(fromByteCount: Int64(max(network.uploadBytesPerSecond, 0)), countStyle: .binary)
        )
    }

    static func tokenSummary(_ usage: CLITokenUsageSnapshot) -> String {
        String(
            format: localized("menubar.status.token_summary", "Agent tokens %@ active"),
            usage.totalActiveTokens.formatted(.number)
        )
    }

    static func cliTokenSummary(cli: AgentCLIKind, usage: CLITokenUsageSnapshot?) -> String {
        guard let usage, let item = usage.items.first(where: { $0.cli == cli }) else {
            return localized("menubar.status.unavailable_summary", "Status unavailable")
        }
        guard item.isAvailable else {
            return String(
                format: localized("menubar.status.cli_unavailable_summary", "%@ unavailable"),
                cli.rawValue
            )
        }
        return String(
            format: localized("menubar.status.cli_token_summary", "%@ %@ active · %@ cache"),
            cli.rawValue,
            item.activeTokens.formatted(.number),
            item.cacheTokens.formatted(.number)
        )
    }

    private static func localized(_ key: String, _ value: String) -> String {
        Bundle.main.localizedString(forKey: key, value: value, table: nil)
    }
}

public extension Notification.Name {
    static let openBriefingWindow = Notification.Name("openBriefingWindow")
}
#endif
