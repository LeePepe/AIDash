#if os(macOS)
// swiftlint:disable file_length
import DesignKit
import SwiftUI
private enum Copy {
    static let updating = localized("menubar.status.updating", "Updating status…")
    static let emptyTitle = localized("menubar.status.empty_title", "No Telemetry Available")
    static let errorTitle = localized("menubar.status.error_title", "Status Unavailable")
    static let refresh = localized("menubar.status.refresh", "Refresh Status")
    static let refreshAction = localized("menubar.status.refresh_action", "Refresh")
    static let notMounted = localized("menubar.status.not_mounted", "Not Mounted")
    static let unavailable = localized("menubar.status.unavailable", "Unavailable")
    static let available = localized("menubar.status.available", "Available")
    static let connectedShort = localized("menubar.status.connected_short", "UP")
    static let disconnectedShort = localized("menubar.status.disconnected_short", "OFF")
    static let computerGroup = localized("menubar.status.computer_group", "Computer Info")
    static let every5s = localized("menubar.status.every_5s", "Every 5s")
    static let tokens = localized("menubar.status.tokens", "Agent Token Usage")
    static let every1m = localized("menubar.status.every_1m", "Every 1m")
    static let cpu = localized("menubar.status.cpu", "CPU")
    static let memory = localized("menubar.status.memory", "Memory")
    static let network = localized("menubar.status.network", "Network")
    static let storage = localized("menubar.status.storage", "Storage")
    static let user = localized("menubar.status.user", "User")
    static let system = localized("menubar.status.system", "System")
    static let idle = localized("menubar.status.idle", "Idle")
    static let wired = localized("menubar.status.wired", "Wired")
    static let compressed = localized("menubar.status.compressed", "Compressed")
    static let free = localized("menubar.status.free", "Free")
    static let swap = localized("menubar.status.swap", "Swap")
    static let active = localized("menubar.status.active", "Active")
    static let totalLabel = localized("menubar.status.total_label", "Total")
    static let cache = localized("menubar.status.cache", "Cache")
    static let interactions = localized("menubar.status.interactions", "Interactions")
    static let activeFormat = localized("menubar.status.active_format", "Active %@")
    static let turnsReqsFormat = localized("menubar.status.turns_reqs", "%@ turns/reqs")
    static let interactionFormat = localized("menubar.status.interaction", "%@ %@")
    static let turns = localized("menubar.status.turns", "turns")
    static let reqs = localized("menubar.status.reqs", "reqs")
    static let inOutFormat = localized("menubar.status.in_out_format", "In+Out %@")
    static let cacheFormat = localized("menubar.status.cache_format", "Cache %@")
    static let uptimeFormat = localized("menubar.status.uptime", "Up %@ · %@")
    static let loadShort = localized("menubar.status.load_short", "Load")
    static let claudeQuotaFormat = localized("menubar.status.claude_quota", "Claude %lld%%")
    static let nominal = localized("menubar.status.thermal_nominal", "Nominal")
    static let fair = localized("menubar.status.thermal_fair", "Fair")
    static let serious = localized("menubar.status.thermal_serious", "Serious")
    static let critical = localized("menubar.status.thermal_critical", "Critical")
    static let normal = localized("menubar.status.pressure_normal", "Normal")
    static let warning = localized("menubar.status.pressure_warning", "Warning")
    static let openBriefing = localized("menubar.status.open_briefing_action", "Open Briefing")
    static let about = localized("menubar.status.about_action", "About")
    static let quit = localized("menubar.status.quit_action", "Quit")
    static let actions = localized("menubar.status.actions", "Actions")
    static let needsPerson = localized("menubar.status.needs_person", "Needs a Person")
    static let blocking = localized("menubar.status.blocking", "%lld blocking")
    static let top = localized("menubar.status.top", "Top")
    static let gpu = localized("menubar.status.gpu", "GPU")
    static let power = localized("menubar.status.power", "Power")
    static let gateway = localized("menubar.status.gateway", "Local Gateway")
    static func uptime(_ value: TimeInterval) -> String {
        "\(Int(value / 3600))h \(Int(value.truncatingRemainder(dividingBy: 3600) / 60))m"
    }
    static func cliName(_ cli: AgentCLIKind) -> String {
        switch cli {
        case .claude: return localized("menubar.status.cli_claude", "Claude Code")
        case .codex: return localized("menubar.status.cli_codex", "Codex CLI")
        case .copilot: return localized("menubar.status.cli_copilot", "Copilot CLI")
        }
    }
    internal static func resolveLocalized(_ key: String, _ value: String) -> String {
        let resolved = Bundle.main.localizedString(forKey: key, value: value, table: nil)
        return (resolved.isEmpty || resolved == key || resolved.hasPrefix("menubar.")) ? value : resolved
    }
    private static func localized(_ key: String, _ value: String) -> String {
        resolveLocalized(key, value)
    }
}
@MainActor
public struct MenuBarStatusView: View { // swiftlint:disable:this type_body_length
    public let state: MenuBarStatusViewState
    public let onRefresh: () -> Void
    public let onOpenBriefing: () -> Void
    public let onShowAbout: () -> Void
    public let onQuit: () -> Void
    public init(
        state: MenuBarStatusViewState,
        onRefresh: @escaping () -> Void = {},
        onOpenBriefing: @escaping () -> Void = {},
        onShowAbout: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) {
        self.state = state
        self.onRefresh = onRefresh
        self.onOpenBriefing = onOpenBriefing
        self.onShowAbout = onShowAbout
        self.onQuit = onQuit
    }
    @Environment(\.colorScheme) private var colorScheme
    private var theme: Theme { Theme(seed: .lime, neutral: .slate, isDark: colorScheme == .dark) }
    public enum Action: Sendable, Equatable { case refresh, openBriefing, showAbout, quit }
    public func perform(_ action: Action) {
        switch action {
        case .refresh: onRefresh()
        case .openBriefing: onOpenBriefing()
        case .showAbout: onShowAbout()
        case .quit: onQuit()
        }
    }
    public var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    switch state {
                    case .loading: loadingView
                    case let .empty(reason):
                        message(title: Copy.emptyTitle, detail: reason, symbol: "chart.bar.xaxis", symbolColor: theme.primary.primary)
                    case let .error(errorMessage):
                        message(title: Copy.errorTitle, detail: errorMessage, symbol: "exclamationmark.triangle", symbolColor: theme.warning)
                    case let .populated(snapshot): populated(snapshot)
                    }
                }
                actionFooter
            }
            .padding(16)
        }
        .frame(width: 380)
        .environment(\.theme, theme)
        .foregroundStyle(theme.neutrals.text1)
    }
    private var actionFooter: some View {
        glassStrip {
            HStack(spacing: 6) {
                actionButton(Copy.refreshAction, symbol: "arrow.clockwise", action: .refresh)
                actionButton(Copy.openBriefing, symbol: "newspaper", action: .openBriefing, primary: true)
                actionButton(Copy.about, symbol: "info.circle", action: .showAbout)
                actionButton(Copy.quit, symbol: "power", action: .quit, destructive: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.actions)
    }
    @ViewBuilder
    private func actionButton(
        _ title: String,
        symbol: String,
        action: Action,
        primary: Bool = false,
        destructive: Bool = false
    ) -> some View {
        baseActionButton(title, symbol: symbol, action: action, role: destructive ? .destructive : nil)
            .foregroundStyle(destructive ? theme.danger : primary ? theme.primary.primary : theme.neutrals.text1)
            .glassEffect(
                destructive
                    ? .regular.tint(theme.danger.opacity(0.15)).interactive()
                    : primary
                        ? .regular.tint(theme.primary.primary.opacity(0.18)).interactive()
                        : .regular.interactive(),
                in: .capsule
            )
    }
    private func baseActionButton(_ title: String, symbol: String, action: Action, role: ButtonRole? = nil) -> some View {
        Button(role: role) { perform(action) } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 11, weight: .medium)).lineLimit(1)
            .fixedSize(horizontal: true, vertical: false).padding(.horizontal, 7)
            .frame(height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
    private func populated(_ snapshot: MenuBarSystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(snapshot)
            attentionStrip(snapshot.attention)
            sectionHeader(Copy.computerGroup, icon: "gauge.with.dots.needle.33percent", cadence: Copy.every5s, date: snapshot.computerCapturedAt)
            HStack(alignment: .top, spacing: 12) {
                glassCard {
                    cpuCard(snapshot.cpu)
                        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220, alignment: .top)
                }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Copy.cpu)
                glassCard {
                    memoryCard(snapshot.memory)
                        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220, alignment: .top)
                }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Copy.memory)
            }
            HStack(alignment: .top, spacing: 12) {
                glassCard {
                    networkCard(snapshot.network)
                        .frame(maxWidth: .infinity, minHeight: 188, maxHeight: 188, alignment: .top)
                }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Copy.network)
                glassCard {
                    storageCard(snapshot.storage)
                        .frame(maxWidth: .infinity, minHeight: 188, maxHeight: 188, alignment: .top)
                }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Copy.storage)
            }
            sectionHeader(Copy.tokens, icon: "sparkles", cadence: Copy.every1m, date: snapshot.tokenCapturedAt)
            glassCard {
                tokenCard(snapshot.tokenUsage)
                gatewayCard(snapshot.gateway)
            }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Copy.tokens)
        }
    }
    @ViewBuilder
    private func attentionStrip(_ attention: AttentionStatusSnapshot) -> some View {
        glassStrip {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(attention.needsPersonCount > 0 ? theme.warning : theme.success)
                    Text(Copy.needsPerson)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 4)
                    StatusPill(String(format: Copy.blocking, attention.needsPersonCount), tone: attention.needsPersonCount > 0 ? .warning : .success)
                }
                if attention.needsPersonCount > 0 {
                    ForEach(Array(attention.items.prefix(2))) { item in
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.turn.down.right")
                                .foregroundStyle(theme.warning)
                            Text(item.title)
                                .lineLimit(1)
                            if let waitingOn = item.waitingOn, !waitingOn.isEmpty {
                                Text("· \(waitingOn)")
                                    .foregroundStyle(theme.neutrals.text2)
                                    .lineLimit(1)
                            }
                        }
                        .font(.system(size: 11))
                        .contentShape(Rectangle())
                    }
                }
            }
        }
    }
    private func gatewayCard(_ gateway: GatewayStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Copy.gateway).font(.system(size: 12, weight: .semibold))
            HStack(spacing: 6) {
                StatusPill("Magpie \(gateway.magpieUp ? Copy.connectedShort : Copy.disconnectedShort)", tone: gateway.magpieUp ? .success : .danger)
                StatusPill("Raven \(gateway.ravenUp ? Copy.connectedShort : Copy.disconnectedShort)", tone: gateway.ravenUp ? .success : .danger)
                StatusPill("Falcon \(gateway.falconUp ? Copy.connectedShort : Copy.disconnectedShort)", tone: gateway.falconUp ? .success : .danger)
            }
            Text("\(gateway.jevRequests24h) req · \(gateway.jevStarredCount) starred")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.neutrals.text2)
        }
    }
    private func header(_ snapshot: MenuBarSystemSnapshot) -> some View {
        glassStrip {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.primary.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.machine.chipName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                let cores = snapshot.machine.efficiencyCores > 0
                    ? "\(snapshot.machine.totalCores)C (\(snapshot.machine.performanceCores)P+\(snapshot.machine.efficiencyCores)E)"
                    : "\(snapshot.machine.totalCores)C · \(snapshot.machine.performanceCores)P"
                Text("\(cores) · \(Copy.uptime(snapshot.machine.uptimeSeconds))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.neutrals.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                StatusPill(thermal(snapshot.machine.thermalState), tone: thermalTone(snapshot.machine.thermalState))
                    .fixedSize(horizontal: true, vertical: false)
                if let power = snapshot.machine.powerSummary {
                    Text("\(Copy.power) \(power)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.neutrals.text2)
                }
            }
        }
    }
    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            skeleton(height: 72)
            skeleton(height: 18)
            HStack(alignment: .top, spacing: 12) {
                skeleton(height: 228)
                skeleton(height: 228)
            }
            HStack(alignment: .top, spacing: 12) {
                skeleton(height: 165)
                skeleton(height: 165)
            }
            skeleton(height: 18)
            skeleton(height: 248)
        }
        .frame(minHeight: 780, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.updating)
    }
    private func skeleton(height: CGFloat) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.neutrals.border.opacity(colorScheme == .dark ? 0.18 : 0.24), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
    private func sectionHeader(_ title: String, icon: String, cadence: String, date: Date) -> some View {
        HStack(spacing: 8) {
            SectionHeader(title, icon: icon)
            Spacer(minLength: 4)
            StatusPill(cadence, tone: .primary)
                .fixedSize(horizontal: true, vertical: false)
            Text(time(date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.neutrals.text2)
                .lineLimit(1)
        }
        .frame(height: 24)
    }
    private func cpuCard(_ cpu: CPUStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            cardTitle(Copy.cpu, badge: "\(cpu.coreCount)C")
            HStack(spacing: 8) {
                RingGauge(value: cpu.usage, size: 42, stroke: 5, color: theme.primary.primary, showLabel: true)
                Text(Copy.loadShort)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.neutrals.text2)
            }
            Text(Self.formatLoadAverages(one: cpu.loadOneMinute, five: cpu.loadFiveMinutes, fifteen: cpu.loadFifteenMinutes))
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .layoutPriority(1)
            if let name = cpu.topProcessName {
                Text("\(Copy.top): \(name)\(cpu.topProcessValueText.map { " · \($0)" } ?? "")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.neutrals.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if cpu.gpu.deviceUtilization > 0 || cpu.gpu.inUseMemoryBytes > 0 {
                Text("\(Copy.gpu) \(percent(cpu.gpu.deviceUtilization)) · \(formatBytes(cpu.gpu.inUseMemoryBytes))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.neutrals.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Sparkline(data: cpu.history.isEmpty ? [cpu.usage, cpu.usage] : cpu.history, color: theme.primary.primary)
                .frame(height: 20)
            metricLines([
                (Copy.user, percent(cpu.user)),
                (Copy.system, percent(cpu.system)),
                (Copy.idle, percent(cpu.idle))
            ])
        }
    }
    private func memoryCard(_ memory: MemoryStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle(Copy.memory, badge: pressure(memory.pressure), tone: pressureTone(memory.pressure))
            Text(Self.compactMemoryPair(used: memory.usedBytes, total: memory.totalBytes))
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
            SegmentedGauge(value: memory.usageFraction, segments: 16, color: pressureColor(memory.pressure), height: 18)
            if let name = memory.topProcessName {
                Text("\(Copy.top): \(name)\(memory.topProcessValueText.map { " · \($0)" } ?? "")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.neutrals.text2)
                    .lineLimit(1)
            }
            metricLines([
                (Copy.wired, formatBytes(memory.wiredBytes)),
                (Copy.compressed, formatBytes(memory.compressedBytes)),
                (Copy.free, formatBytes(memory.freeBytes)),
                (Copy.swap, Self.compactMemoryPair(used: memory.swapUsedBytes, total: memory.swapTotalBytes))
            ])
            Spacer(minLength: 0)
        }
    }
    private func networkCard(_ network: NetworkStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "network")
                    .foregroundStyle(theme.primary.primary)
                    .accessibilityHidden(true)
                Text(Copy.network)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                StatusPill(network.isConnected ? Copy.connectedShort : Copy.disconnectedShort, tone: network.isConnected ? .success : .warning)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text("\(network.interfaceName) · \(network.ipAddress ?? "—")")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.neutrals.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            VStack(alignment: .leading, spacing: 2) {
                Text("↓ \(rate(network.downloadBytesPerSecond))")
                Text("↑ \(rate(network.uploadBytesPerSecond))")
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .lineLimit(1)
            Sparkline(data: network.throughputHistory.isEmpty ? [0, 0] : network.throughputHistory, color: theme.primary.primary)
                .frame(height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("↓ \(formatBytes(network.totalReceivedBytes))")
                Text("↑ \(formatBytes(network.totalSentBytes))")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(theme.neutrals.text2)
            .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
    private func storageCard(_ storage: StorageStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            cardTitle(Copy.storage)
            ForEach(storage.volumes) { volume in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: volume.isExternalSSD ? "externaldrive" : "internaldrive")
                            .foregroundStyle(volume.isMounted ? theme.success : theme.warning)
                            .accessibilityHidden(true)
                        Text(volume.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 2)
                        if volume.isMounted {
                            Text(percent(volume.usageFraction))
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                    if volume.isMounted {
                        SegmentedGauge(value: volume.usageFraction, segments: 16, color: theme.primary.primary, height: 14)
                        Text("\(formatBytes(volume.usedBytes)) / \(formatBytes(volume.totalBytes))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.neutrals.text2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("\(formatBytes(volume.availableBytes)) \(Copy.available.lowercased())")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.neutrals.text2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    } else {
                        StatusPill(Copy.notMounted, tone: .warning)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
    private func tokenCard(_ usage: CLITokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let quota = usage.claudeWeeklyRemainingPercent {
                HStack {
                    Spacer(minLength: 0)
                    StatusPill(String(format: Copy.claudeQuotaFormat, quota), tone: quota > 60 ? .success : quota > 25 ? .warning : .danger)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            HStack(spacing: 8) {
                tokenMetric(Copy.active, value: compactCount(usage.totalActiveTokens))
                tokenMetric(Copy.totalLabel, value: compactCount(usage.grandTotalTokens))
                tokenMetric(Copy.cache, value: compactCount(usage.totalCacheTokens))
                tokenMetric(Copy.interactions, value: compactCount(usage.totalInteractions))
            }
            ForEach(Array(usage.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(theme.neutrals.border).frame(height: 1)
                }
                cliRow(item, usage: usage)
            }
        }
    }
    private func tokenMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.neutrals.text2)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
        }
    }
    private func cliRow(_ item: CLITokenUsageItem, usage: CLITokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(Copy.cliName(item.cli))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                StatusPill(item.isAvailable ? Copy.available : Copy.unavailable, tone: item.isAvailable ? .success : .danger)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 4)
                Text(item.isAvailable ? compactCount(item.totalTokens) : "—")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)
            }
            if item.isAvailable {
                progress(value: usage.shareFraction(for: item.cli), label: Copy.cliName(item.cli))
                HStack {
                    Text(String(format: Copy.inOutFormat, compactCount(item.activeTokens)))
                    Spacer(minLength: 4)
                    Text(String(format: Copy.cacheFormat, compactCount(item.cacheTokens)))
                    Text(String(format: Copy.interactionFormat, compactCount(item.interactionCount), item.cli == .codex ? Copy.reqs : Copy.turns))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.neutrals.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
        }
    }
    private func cardTitle(_ title: String, badge: String? = nil, tone: PillTone = .neutral) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if let badge {
                StatusPill(badge, tone: tone)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 2)
        }
        .frame(height: 22)
    }
    private func metricLines(_ values: [(String, String)]) -> some View {
        VStack(spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                HStack {
                    Text(value.0)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.neutrals.text2)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(value.1)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)
                }
                .frame(height: 15)
            }
        }
    }
    private func progress(value: Double, label: String) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(theme.neutrals.border)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(theme.primary.primary)
                        .frame(width: proxy.size.width * min(max(value, 0), 1))
                }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(percent(value))
    }
    private func message(title: String, detail: String? = nil, symbol: String, symbolColor: Color) -> some View {
        glassCard {
            VStack(alignment: .leading, spacing: 12) {
                glassStrip {
                    Image(systemName: symbol)
                        .foregroundStyle(symbolColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 15, weight: .semibold))
                        if let detail {
                            Text(detail)
                                .font(.system(size: 11))
                                .foregroundStyle(theme.neutrals.text2)
                        }
                    }
                }
                Button(Copy.refresh, action: onRefresh)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.primary.primary)
                    .controlSize(.small)
                    .accessibilityLabel(Copy.refresh)
            }
        }
    }
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.neutrals.border.opacity(colorScheme == .dark ? 0.22 : 0.28), lineWidth: 1) }
    }
    private func glassStrip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.neutrals.border.opacity(colorScheme == .dark ? 0.18 : 0.24), lineWidth: 1) }
    }
    private func thermal(_ value: SystemThermalLevel) -> String {
        switch value {
        case .nominal: return Copy.nominal
        case .fair: return Copy.fair
        case .serious: return Copy.serious
        case .critical: return Copy.critical
        }
    }
    private func thermalTone(_ value: SystemThermalLevel) -> PillTone {
        value == .nominal ? .success : value == .fair ? .warning : .danger
    }
    private func pressure(_ value: MemoryPressureLevel) -> String {
        switch value {
        case .normal: return Copy.normal
        case .warning: return Copy.warning
        case .critical: return Copy.critical
        }
    }
    private func pressureTone(_ value: MemoryPressureLevel) -> PillTone {
        value == .normal ? .success : value == .warning ? .warning : .danger
    }
    private func pressureColor(_ value: MemoryPressureLevel) -> Color {
        value == .normal ? theme.success : value == .warning ? theme.warning : theme.danger
    }
    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    internal static func formatLoadAverages(one: Double, five: Double, fifteen: Double) -> String {
        "\(loadDecimal(one)) / \(loadDecimal(five)) / \(loadDecimal(fifteen))"
    }
    private static func loadDecimal(_ value: Double) -> String { String(format: "%.1f", value) }
    internal static func compactMemoryPair(used: UInt64, total: UInt64) -> String {
        guard used > 0 || total > 0 else { return "0 / 0 GB" }
        return String(format: "%.1f / %.1f GB",
            Double(used) / 1_073_741_824.0, Double(total) / 1_073_741_824.0)
    }
    private func compactCount(_ value: UInt64) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.2fB", Double(value) / 1_000_000_000.0)
        } else if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        } else if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        return value.formatted(.number)
    }
    private func formatBytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) }
    private func rate(_ value: Double) -> String { "\(ByteCountFormatter.string(fromByteCount: Int64(max(value, 0)), countStyle: .binary))/s" }
    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
    internal static func resolveLocalized(_ key: String, _ value: String) -> String {
        Copy.resolveLocalized(key, value)
    }
}
#endif
