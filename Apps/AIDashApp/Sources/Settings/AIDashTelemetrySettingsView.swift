import SwiftUI
#if os(macOS)
import AppKit
import Observation
#endif

struct AIDashTelemetrySettingsView: View {
    let coordinator: AIDashTelemetryCoordinator
    @State private var isEnabled: Bool

    init(coordinator: AIDashTelemetryCoordinator) {
        self.coordinator = coordinator
        _isEnabled = State(initialValue: coordinator.isConsentEnabled)
    }

    var body: some View {
        Toggle(
            String(
                localized: "telemetry.settings.send_usage_data",
                defaultValue: "Send usage data",
                bundle: .main,
                comment: "The sole opt-in control for anonymous product telemetry."
            ),
            isOn: $isEnabled
        )
        .onChange(of: isEnabled) { _, enabled in
            Task {
                await coordinator.setConsent(enabled)
                isEnabled = coordinator.isConsentEnabled
            }
        }
    }
}

#if os(macOS)
public enum MenuBarBadgeMetric: String, CaseIterable, Codable, Sendable, Equatable, Identifiable {
    case todayTokens = "today_tokens"
    case sevenDayTokens = "seven_day_tokens"
    case cpu = "cpu"
    case memory = "memory"
    case storage = "storage"
    case cpuAndMemory = "cpu_and_memory"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .todayTokens: return DashboardL10n.tr("settings.menubar.metric.today_tokens", "Today Token Total")
        case .sevenDayTokens: return DashboardL10n.tr("settings.menubar.metric.7d_tokens", "7-Day Token Total")
        case .cpu: return DashboardL10n.tr("settings.menubar.metric.cpu", "CPU Usage")
        case .memory: return DashboardL10n.tr("settings.menubar.metric.memory", "Memory Usage")
        case .storage: return DashboardL10n.tr("settings.menubar.metric.storage", "Available Disk Space")
        case .cpuAndMemory: return DashboardL10n.tr("settings.menubar.metric.cpu_memory", "CPU + Memory")
        }
    }

    public var subtitle: String {
        switch self {
        case .todayTokens: return DashboardL10n.tr("settings.menubar.metric.today_tokens_desc", "Today total tokens across all CLIs (Input + Output + Cache)")
        case .sevenDayTokens: return DashboardL10n.tr("settings.menubar.metric.7d_tokens_desc", "Rolling 7-day cumulative token volume")
        case .cpu: return DashboardL10n.tr("settings.menubar.metric.cpu_desc", "Real-time system CPU utilization percentage")
        case .memory: return DashboardL10n.tr("settings.menubar.metric.memory_desc", "Used / total physical memory in GB")
        case .storage: return DashboardL10n.tr("settings.menubar.metric.storage_desc", "Free space remaining on system volume")
        case .cpuAndMemory: return DashboardL10n.tr("settings.menubar.metric.cpu_memory_desc", "Combined CPU percentage and memory usage")
        }
    }

    public var symbolName: String {
        switch self {
        case .todayTokens: return "sparkles"
        case .sevenDayTokens: return "calendar.badge.clock"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .cpuAndMemory: return "gauge.with.dots.needle.67percent"
        }
    }

    public func formattedStatusBarTitle(snapshot: MenuBarSystemSnapshot, entries: [CLICostQuotaEntry]) -> String {
        switch self {
        case .todayTokens:
            let total = entries.reduce(UInt64(0)) { $0 + $1.totalTokens }
            return " \(DashboardTokenFormatter.compact(total)) tok"
        case .sevenDayTokens:
            let total7d = entries.reduce(UInt64(0)) { $0 + $1.periodTotalTokens }
            return " 7d \(DashboardTokenFormatter.compact(total7d))"
        case .cpu:
            return " CPU \(Int((snapshot.cpu.usage * 100).rounded()))%"
        case .memory:
            let usedG = Double(snapshot.memory.usedBytes) / 1_073_741_824.0
            let totG = Double(snapshot.memory.totalBytes) / 1_073_741_824.0
            return totG > 0 ? String(format: " Mem %.0f/%.0fG", usedG, totG) : " Mem 0G"
        case .storage:
            let freeStr = ByteCountFormatter.string(fromByteCount: Int64(snapshot.storage.systemVolume.availableBytes), countStyle: .binary)
            return " Disk \(freeStr)"
        case .cpuAndMemory:
            let cpuPct = Int((snapshot.cpu.usage * 100).rounded())
            let usedG = Double(snapshot.memory.usedBytes) / 1_073_741_824.0
            let totG = Double(snapshot.memory.totalBytes) / 1_073_741_824.0
            let memStr = totG > 0 ? String(format: "%.0f/%.0fG", usedG, totG) : "0G"
            return " CPU \(cpuPct)% · \(memStr)"
        }
    }
}

public enum TodoSyncProviderMode: String, CaseIterable, Codable, Sendable, Equatable, Identifiable {
    case auto = "auto"
    case localOnly = "local"
    case linear = "linear"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto:
            return DashboardL10n.tr("settings.todo_sync.mode.auto", "Auto (Linear when configured, else Local)")
        case .localOnly:
            return DashboardL10n.tr("settings.todo_sync.mode.local", "Standalone Local-Only Mode")
        case .linear:
            return DashboardL10n.tr("settings.todo_sync.mode.linear", "Linear SSOT Sync Mode")
        }
    }

    public var subtitle: String {
        switch self {
        case .auto:
            return DashboardL10n.tr("settings.todo_sync.mode.auto_desc", "Uses Linear SSOT when linear-sync.py is installed and falls back to standalone local todos otherwise")
        case .localOnly:
            return DashboardL10n.tr("settings.todo_sync.mode.local_desc", "100% standalone mode with zero external Linear dependency; promoted proposals and todos stay on this Mac")
        case .linear:
            return DashboardL10n.tr("settings.todo_sync.mode.linear_desc", "Promotes starred proposals to Linear and bidirectionally syncs Done / Todo status with your Linear team")
        }
    }

    public var symbolName: String {
        switch self {
        case .auto: return "sparkles.rectangle.stack"
        case .localOnly: return "internaldrive.fill"
        case .linear: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }
}

public extension Notification.Name {
    static let menuBarDisplayPreferencesDidChange = Notification.Name("menuBarDisplayPreferencesDidChange")
}

@MainActor
@Observable
public final class MenuBarDisplayPreferences {
    public static let shared = MenuBarDisplayPreferences()

    private enum Keys {
        static let badgeMetric = "aidash.menubar.badge_metric"
        static let showSystemTelemetry = "aidash.menubar.show_system_telemetry"
        static let showActionItems = "aidash.menubar.show_action_items"
        static let defaultChartGranularity = "aidash.menubar.default_chart_granularity"
        static let todoSyncProviderMode = "aidash.todo_sync.provider_mode"
        static let todoSyncTeamKey = "aidash.todo_sync.team_key"
    }

    private let persistToDefaults: Bool
    private let todoSyncConfigFileURL: URL?

    public var badgeMetric: MenuBarBadgeMetric {
        didSet {
            if persistToDefaults { UserDefaults.standard.set(badgeMetric.rawValue, forKey: Keys.badgeMetric) }
            NotificationCenter.default.post(name: .menuBarDisplayPreferencesDidChange, object: nil)
        }
    }

    public var showPopoverSystemTelemetry: Bool {
        didSet {
            if persistToDefaults { UserDefaults.standard.set(showPopoverSystemTelemetry, forKey: Keys.showSystemTelemetry) }
            NotificationCenter.default.post(name: .menuBarDisplayPreferencesDidChange, object: nil)
        }
    }

    public var showPopoverActionItems: Bool {
        didSet {
            if persistToDefaults { UserDefaults.standard.set(showPopoverActionItems, forKey: Keys.showActionItems) }
            NotificationCenter.default.post(name: .menuBarDisplayPreferencesDidChange, object: nil)
        }
    }

    public var defaultChartGranularity: DashboardChartTimeGranularity {
        didSet {
            if persistToDefaults { UserDefaults.standard.set(defaultChartGranularity.rawValue, forKey: Keys.defaultChartGranularity) }
            NotificationCenter.default.post(name: .menuBarDisplayPreferencesDidChange, object: nil)
        }
    }

    public var todoSyncProviderMode: TodoSyncProviderMode {
        didSet {
            if persistToDefaults { UserDefaults.standard.set(todoSyncProviderMode.rawValue, forKey: Keys.todoSyncProviderMode) }
            writeTodoSyncConfigIfNeeded()
            NotificationCenter.default.post(name: .menuBarDisplayPreferencesDidChange, object: nil)
        }
    }

    public var todoSyncTeamKey: String {
        didSet {
            let normalized = Self.normalizedTeamKey(todoSyncTeamKey)
            if todoSyncTeamKey != normalized {
                todoSyncTeamKey = normalized
                return
            }
            if persistToDefaults { UserDefaults.standard.set(todoSyncTeamKey, forKey: Keys.todoSyncTeamKey) }
            writeTodoSyncConfigIfNeeded()
            NotificationCenter.default.post(name: .menuBarDisplayPreferencesDidChange, object: nil)
        }
    }

    public init(
        persistToDefaults: Bool = LiveDashboardTelemetryReader.isLiveEnvironment,
        todoSyncConfigFileURL: URL? = nil
    ) {
        self.persistToDefaults = persistToDefaults
        if let todoSyncConfigFileURL {
            self.todoSyncConfigFileURL = todoSyncConfigFileURL
        } else if persistToDefaults {
            self.todoSyncConfigFileURL = LiveMenuBarSystemStatusProvider.realUserHomeDirectoryURL()
                .appendingPathComponent(".config/aidash/todo-sync.json")
        } else {
            self.todoSyncConfigFileURL = nil
        }

        if persistToDefaults {
            let defaults = UserDefaults.standard
            let rawMetric = defaults.string(forKey: Keys.badgeMetric) ?? ""
            self.badgeMetric = MenuBarBadgeMetric(rawValue: rawMetric) ?? .todayTokens
            self.showPopoverSystemTelemetry = defaults.object(forKey: Keys.showSystemTelemetry) as? Bool ?? true
            self.showPopoverActionItems = defaults.object(forKey: Keys.showActionItems) as? Bool ?? true
            let rawGran = defaults.string(forKey: Keys.defaultChartGranularity) ?? ""
            self.defaultChartGranularity = DashboardChartTimeGranularity(rawValue: rawGran) ?? .sevenDayDaily
            let rawSyncMode = defaults.string(forKey: Keys.todoSyncProviderMode) ?? ""
            self.todoSyncProviderMode = TodoSyncProviderMode(rawValue: rawSyncMode) ?? .auto
            let rawTeam = defaults.string(forKey: Keys.todoSyncTeamKey) ?? "TIA"
            self.todoSyncTeamKey = Self.normalizedTeamKey(rawTeam)
        } else {
            self.badgeMetric = .todayTokens
            self.showPopoverSystemTelemetry = true
            self.showPopoverActionItems = true
            self.defaultChartGranularity = .sevenDayDaily
            self.todoSyncProviderMode = .auto
            self.todoSyncTeamKey = "TIA"
        }
    }

    private static func normalizedTeamKey(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "TIA" : trimmed
    }

    public func writeTodoSyncConfigIfNeeded() {
        guard let url = todoSyncConfigFileURL else { return }
        let payload: [String: String] = [
            "provider": todoSyncProviderMode.rawValue,
            "teamKey": Self.normalizedTeamKey(todoSyncTeamKey)
        ]
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            // Best-effort bridge config write; never crash UI on sandbox/disk error.
        }
    }
}

@MainActor
public struct DashboardSettingsPageView: View {
    @Bindable public var store: DashboardWorkspaceStore
    @Bindable public var prefs: MenuBarDisplayPreferences
    @State private var sendUsageData: Bool = {
        if case .establishedEnabled = AIDashTelemetryPreferences().state {
            return true
        }
        return false
    }()

    public init(store: DashboardWorkspaceStore, prefs: MenuBarDisplayPreferences? = nil) {
        self.store = store
        self.prefs = prefs ?? MenuBarDisplayPreferences.shared
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            menuBarBadgeCard
            popoverModulesCard
            todoSyncIntegrationCard
            telemetryPrivacyCard
        }
    }

    private var menuBarBadgeCard: some View {
        SolidModularCardContainer(
            title: DashboardL10n.tr("settings.menubar.card_title", "MenuBar Status Bar Display"),
            subtitle: DashboardL10n.tr("settings.menubar.card_subtitle", "Choose the live metric shown next to the AIDash icon in the macOS top menu bar"),
            symbolName: "menubar.rectangle"
        ) {
            if case let .populated(snapshot) = store.systemState {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.caption.weight(.semibold))
                    Text(prefs.badgeMetric.formattedStatusBarTitle(snapshot: snapshot, entries: store.cliEntries).trimmingCharacters(in: .whitespaces))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .windowBackgroundColor), in: Capsule())
            }
        } content: {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 240), spacing: 10),
                    GridItem(.flexible(minimum: 240), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(MenuBarBadgeMetric.allCases) { metric in
                    metricOptionTile(metric)
                }
            }
        }
    }

    private func metricOptionTile(_ metric: MenuBarBadgeMetric) -> some View {
        let isSelected = prefs.badgeMetric == metric
        let previewText: String = {
            if case let .populated(snapshot) = store.systemState {
                return metric.formattedStatusBarTitle(snapshot: snapshot, entries: store.cliEntries).trimmingCharacters(in: .whitespaces)
            }
            return metric.title
        }()
        return Button {
            prefs.badgeMetric = metric
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Image(systemName: metric.symbolName)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    Text(metric.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Text(previewText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(isSelected ? 0.16 : 0.08), in: Capsule())
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                Text(metric.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var popoverModulesCard: some View {
        SolidModularCardContainer(
            title: DashboardL10n.tr("settings.popover.card_title", "MenuBar Popover Layout & Defaults"),
            subtitle: DashboardL10n.tr("settings.popover.card_subtitle", "Configure which sections appear inside the 360pt menu bar popover"),
            symbolName: "slider.horizontal.3"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $prefs.showPopoverSystemTelemetry) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DashboardL10n.tr("settings.popover.show_telemetry", "Show System Telemetry Strip (CPU / Memory / Storage)"))
                            .font(.subheadline.weight(.medium))
                        Text(DashboardL10n.tr("settings.popover.show_telemetry_desc", "Display the three real-time hardware capacity gauges at the top of the popover"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                Toggle(isOn: $prefs.showPopoverActionItems) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DashboardL10n.tr("settings.popover.show_actions", "Show Top Actionable Items Section"))
                            .font(.subheadline.weight(.medium))
                        Text(DashboardL10n.tr("settings.popover.show_actions_desc", "Display pending workflow blockers and improvement proposals at the bottom of the popover"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        }
    }

    private var todoSyncIntegrationCard: some View {
        SolidModularCardContainer(
            title: DashboardL10n.tr("settings.todo_sync.card_title", "Todo & Issue Sync Integration"),
            subtitle: DashboardL10n.tr("settings.todo_sync.card_subtitle", "Run AIDash 100% standalone with local todos or connect to Linear as a cross-app Single Source of Truth"),
            symbolName: "arrow.triangle.2.circlepath"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(TodoSyncProviderMode.allCases) { mode in
                    todoSyncModeTile(mode)
                }

                if prefs.todoSyncProviderMode != .localOnly {
                    HStack(spacing: 10) {
                        Text(DashboardL10n.tr("settings.todo_sync.team_key_label", "Linear Team Key"))
                            .font(.subheadline.weight(.medium))
                        TextField("TIA", text: $prefs.todoSyncTeamKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 96)
                        Text(DashboardL10n.tr("settings.todo_sync.team_key_hint", "Used for linear://<TEAM>-xx canonical sync refs"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func todoSyncModeTile(_ mode: TodoSyncProviderMode) -> some View {
        let isSelected = prefs.todoSyncProviderMode == mode
        return Button {
            prefs.todoSyncProviderMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Image(systemName: mode.symbolName)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                Text(mode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.5), lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var telemetryPrivacyCard: some View {
        SolidModularCardContainer(
            title: DashboardL10n.tr("settings.telemetry.card_title", "Privacy & Anonymous Telemetry"),
            subtitle: DashboardL10n.tr("settings.telemetry.card_subtitle", "Manage optional anonymous product telemetry and startup performance metrics"),
            symbolName: "hand.raised.fill"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $sendUsageData) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DashboardL10n.tr("telemetry.settings.send_usage_data", "Send usage data"))
                            .font(.subheadline.weight(.medium))
                        Text(DashboardL10n.tr("settings.telemetry.send_usage_desc", "Only anonymous GUI launch duration and briefing view events are recorded; no briefing content or prompts are ever collected."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: sendUsageData) { _, enabled in
                    let updatedState = AIDashTelemetryPreferences().setConsent(enabled)
                    if case .establishedEnabled = updatedState {
                        sendUsageData = true
                    } else {
                        sendUsageData = false
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        }
    }
}
#endif
