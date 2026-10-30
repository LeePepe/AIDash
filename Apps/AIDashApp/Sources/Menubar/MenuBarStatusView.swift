#if os(macOS)
import DesignKit
import SwiftUI

@MainActor
public struct MenuBarStatusView: View {
    public let state: MenuBarStatusViewState
    public let onRefresh: () -> Void
    public init(state: MenuBarStatusViewState, onRefresh: @escaping () -> Void = {}) { self.state = state; self.onRefresh = onRefresh }
    @Environment(\.colorScheme) private var colorScheme
    private var theme: Theme { Theme(seed: .lime, neutral: .slate, isDark: colorScheme == .dark) }
    public var body: some View {
        Group {
            switch state {
            case .loading: loadingView
            case let .empty(reason): message(title: Copy.emptyTitle, detail: reason, symbol: "chart.bar.xaxis")
            case let .error(error): message(title: Copy.errorTitle, detail: error, symbol: "exclamationmark.triangle")
            case let .populated(snapshot): populated(snapshot)
            }
        }
        .frame(width: 380)
        .padding(16)
        .background(theme.neutrals.bg)
        .designTheme(seed: .lime, neutral: .slate)
    }

    private func populated(_ snapshot: MenuBarSystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardInner {
                Image(systemName: "desktopcomputer").foregroundStyle(theme.primary.primary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snapshot.machine.chipName) · \(snapshot.machine.totalCores)C").font(.system(size: 13, weight: .semibold))
                    Text(String(format: Copy.uptimeFormat, uptime(snapshot.machine.uptimeSeconds), time(snapshot.computerCapturedAt))).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.neutrals.text2)
                }
                Spacer()
                StatusPill(thermal(snapshot.machine.thermalState), tone: thermalTone(snapshot.machine.thermalState))
                StatusPill(Copy.cadenceBadge, tone: .primary)
            }
            groupHeader(Copy.computerGroup, icon: "gauge.with.dots.needle.33percent", cadence: Copy.every5s, date: snapshot.computerCapturedAt)
            HStack(alignment: .top, spacing: 10) {
                Card { cpuCard(snapshot.cpu) }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Copy.cpu)
                Card { memoryCard(snapshot.memory) }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Copy.memory)
            }
            Card { networkCard(snapshot.network) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Copy.network)
            Card { storageCard(snapshot.storage) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Copy.storage)
            groupHeader(Copy.tokens, icon: "sparkles", cadence: Copy.every1m, date: snapshot.tokenCapturedAt, quota: snapshot.tokenUsage.claudeWeeklyRemainingPercent)
            Card { tokenCard(snapshot.tokenUsage) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Copy.tokens)
        }
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            skeleton(height: 42)
            skeleton(height: 18)
            HStack(alignment: .top, spacing: 10) {
                skeleton(height: 148)
                skeleton(height: 148)
            }
            skeleton(height: 82)
            skeleton(height: 112)
            skeleton(height: 18)
            skeleton(height: 144)
        }
        .frame(minHeight: 780, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.updating)
    }

    private func skeleton(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(theme.neutrals.border.opacity(0.55))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityHidden(true)
    }

    private func groupHeader(_ title: String, icon: String, cadence: String, date: Date, quota: Int? = nil) -> some View {
        HStack(spacing: 8) {
            SectionHeader(title, icon: icon); Spacer()
            if let quota { StatusPill(String(format: Copy.claudeQuotaFormat, quota), tone: quota > 60 ? .success : quota > 25 ? .warning : .danger) }
            StatusPill(cadence, tone: .primary)
            Text(time(date)).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.neutrals.text2)
        }
    }
    private func cpuCard(_ cpu: CPUStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle(Copy.cpu, badge: "\(cpu.coreCount)C")
            HStack(spacing: 10) {
                RingGauge(value: cpu.usage, size: 44, stroke: 5, color: theme.primary.primary, showLabel: true)
                Sparkbars(data: cpu.history.isEmpty ? [cpu.usage, cpu.usage] : cpu.history, color: theme.primary.primary, height: 32, baseline: theme.neutrals.border)
            }
            metricLines([(Copy.user, percent(cpu.user)), (Copy.system, percent(cpu.system)), (Copy.idle, percent(cpu.idle)), (Copy.loadCompact, "\(decimal(cpu.loadOneMinute)) · \(decimal(cpu.loadFiveMinutes)) · \(decimal(cpu.loadFifteenMinutes))")])
        }
    }
    private func memoryCard(_ memory: MemoryStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { cardTitle(Copy.memory); Spacer(); StatusPill(pressure(memory.pressure), tone: pressureTone(memory.pressure)) }
            HStack { Text("\(formatBytes(memory.usedBytes)) / \(formatBytes(memory.totalBytes))").font(.system(size: 15, weight: .semibold, design: .monospaced)); Spacer(); Text(percent(memory.usageFraction)).font(.system(size: 12, design: .monospaced)) }
            SegmentedGauge(value: memory.usageFraction, segments: 16, color: pressureColor(memory.pressure), height: 22)
            metricLines([(Copy.wired, formatBytes(memory.wiredBytes)), (Copy.compressed, formatBytes(memory.compressedBytes)), (Copy.free, formatBytes(memory.freeBytes)), (Copy.swap, "\(formatBytes(memory.swapUsedBytes)) / \(formatBytes(memory.swapTotalBytes))")])
        }
    }
    private func networkCard(_ network: NetworkStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "network").foregroundStyle(theme.primary.primary).accessibilityHidden(true)
                Text(Copy.network).font(.system(size: 13, weight: .semibold))
                Text("\(network.interfaceName) · \(network.ipAddress ?? "—")").font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.neutrals.text2)
                Spacer()
                Text("↓ \(rate(network.downloadBytesPerSecond)) · ↑ \(rate(network.uploadBytesPerSecond))").font(.system(size: 10, design: .monospaced))
            }
            Sparkline(data: network.throughputHistory.isEmpty ? [0, 0] : network.throughputHistory, color: theme.primary.primary).frame(height: 28)
            Text("↓ \(formatBytes(network.totalReceivedBytes)) · ↑ \(formatBytes(network.totalSentBytes))").font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.neutrals.text2)
        }
    }
    private func storageCard(_ storage: StorageStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) { cardTitle(Copy.storage); ForEach(storage.volumes) { volume in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: volume.isExternalSSD ? "externaldrive" : "internaldrive")
                        .foregroundStyle(volume.isMounted ? theme.success : theme.warning)
                        .accessibilityHidden(true)
                    Text(volume.name).font(.system(size: 12, weight: .semibold))
                    Text(volume.mountPoint)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.neutrals.text2)
                    Spacer()
                    if volume.isMounted {
                        Text(percent(volume.usageFraction)).font(.system(size: 11, design: .monospaced))
                    } else {
                        StatusPill(Copy.notMounted, tone: .warning)
                    }
                }
                if volume.isMounted { SegmentedGauge(value: volume.usageFraction, segments: 20, color: theme.primary.primary, height: 18); Text(String(format: Copy.storageDetailFormat, formatBytes(volume.usedBytes), formatBytes(volume.totalBytes), formatBytes(volume.availableBytes), Copy.available)).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.neutrals.text2) }
            }
        } }
    }
    private func tokenCard(_ usage: CLITokenUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(String(format: Copy.activeFormat, formatCount(usage.totalActiveTokens))).font(.system(size: 13, weight: .semibold, design: .monospaced)); Spacer(); Text(String(format: Copy.totalFormat, formatCount(usage.grandTotalTokens))).font(.system(size: 11, design: .monospaced)); Text(String(format: Copy.turnsReqsFormat, formatCount(usage.totalInteractions))).font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.neutrals.text2) }
            ForEach(usage.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Copy.cliName(item.cli)).font(.system(size: 12, weight: .semibold))
                        if item.isAvailable {
                            Text(String(format: Copy.interactionFormat, formatCount(item.interactionCount), item.cli == .codex ? Copy.reqs : Copy.turns))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(theme.neutrals.text2)
                        }
                        Spacer()
                        if item.isAvailable {
                            Text(formatCount(item.totalTokens)).font(.system(size: 11, design: .monospaced))
                        } else {
                            StatusPill(Copy.unavailable, tone: .danger)
                        }
                    }
                    if item.isAvailable {
                        progress(value: usage.shareFraction(for: item.cli), label: Copy.cliName(item.cli))
                        HStack {
                            Text(String(format: Copy.inOutFormat, formatCount(item.activeTokens))).lineLimit(1)
                            Spacer()
                            Text(String(format: Copy.cacheFormat, formatCount(item.cacheTokens))).lineLimit(1)
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.neutrals.text2)
                    }
                }
            }
        }
    }
    private func cardTitle(_ title: String, badge: String? = nil) -> some View { HStack { Text(title).font(.system(size: 13, weight: .semibold)); if let badge { StatusPill(badge, tone: .neutral) }; Spacer() } }
    private func metricLines(_ values: [(String, String)]) -> some View { VStack(spacing: 4) { ForEach(Array(values.enumerated()), id: \.offset) { _, value in HStack { Text(value.0).font(.system(size: 10)).foregroundStyle(theme.neutrals.text2).lineLimit(1).minimumScaleFactor(0.85); Spacer(); Text(value.1).font(.system(size: 10, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.85) } } } }
    private func progress(value: Double, label: String) -> some View {
        GeometryReader { proxy in
            Capsule().fill(theme.neutrals.border).overlay(alignment: .leading) {
                Capsule().fill(theme.primary.primary).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(percent(value))
    }
    private func message(title: String, detail: String? = nil, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardInner {
                Image(systemName: symbol).foregroundStyle(theme.primary.primary).accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(theme.neutrals.text2) }
                }
            }
            Button(Copy.refresh, action: onRefresh)
                .buttonStyle(.borderedProminent)
                .tint(theme.primary.primary)
                .frame(minHeight: 28)
                .accessibilityLabel(Copy.refresh)
        }
    }
    private func thermal(_ value: SystemThermalLevel) -> String {
        switch value {
        case .nominal: return Copy.nominal
        case .fair: return Copy.fair
        case .serious: return Copy.serious
        case .critical: return Copy.critical
        }
    }
    private func thermalTone(_ value: SystemThermalLevel) -> PillTone { value == .nominal ? .success : value == .fair ? .warning : .danger }
    private func pressure(_ value: MemoryPressureLevel) -> String {
        switch value {
        case .normal: return Copy.normal
        case .warning: return Copy.warning
        case .critical: return Copy.critical
        }
    }
    private func pressureTone(_ value: MemoryPressureLevel) -> PillTone { value == .normal ? .success : value == .warning ? .warning : .danger }
    private func pressureColor(_ value: MemoryPressureLevel) -> Color { value == .normal ? theme.success : value == .warning ? theme.warning : theme.danger }
    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private func decimal(_ value: Double) -> String { String(format: "%.2f", value) }
    private func formatCount(_ value: UInt64) -> String { value.formatted(.number) }
    private func formatBytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) }
    private func rate(_ value: Double) -> String { "\(ByteCountFormatter.string(fromByteCount: Int64(max(value, 0)), countStyle: .binary))/s" }
    private func uptime(_ value: TimeInterval) -> String { "\(Int(value / 3600))h \(Int(value.truncatingRemainder(dividingBy: 3600) / 60))m" }
    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
    private enum Copy {
        static let updating = localized("menubar.status.updating", "Updating status…")
        static let emptyTitle = localized("menubar.status.empty_title", "No Telemetry Available")
        static let errorTitle = localized("menubar.status.error_title", "Status Unavailable")
        static let refresh = localized("menubar.status.refresh", "Refresh Status")
        static let notMounted = localized("menubar.status.not_mounted", "Not Mounted")
        static let unavailable = localized("menubar.status.unavailable", "Unavailable")
        static let computerGroup = localized("menubar.status.computer_group", "Computer Info")
        static let every5s = localized("menubar.status.every_5s", "Every 5s")
        static let tokens = localized("menubar.status.tokens", "Agent Token Usage")
        static let every1m = localized("menubar.status.every_1m", "Every 1m")
        static let cadenceBadge = localized("menubar.status.cadence_badge", "5s / 1m")
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
        static let available = localized("menubar.status.available", "available")
        static let activeFormat = localized("menubar.status.active_format", "Active %@")
        static let totalFormat = localized("menubar.status.total", "Total %@")
        static let turnsReqsFormat = localized("menubar.status.turns_reqs", "%@ turns/reqs")
        static let interactionFormat = localized("menubar.status.interaction", "%@ %@")
        static let turns = localized("menubar.status.turns", "turns")
        static let reqs = localized("menubar.status.reqs", "reqs")
        static let inOutFormat = localized("menubar.status.in_out_format", "In+Out %@")
        static let cacheFormat = localized("menubar.status.cache_format", "Cache %@")
        static let storageDetailFormat = localized("menubar.status.storage_detail", "%@ / %@ · %@ %@")
        static let uptimeFormat = localized("menubar.status.uptime", "Up %@ · %@")
        static let loadCompact = localized("menubar.status.load_compact", "Load 1/5/15m")
        static let claudeQuotaFormat = localized("menubar.status.claude_quota", "Claude %lld%%")
        static let nominal = localized("menubar.status.thermal_nominal", "Nominal")
        static let fair = localized("menubar.status.thermal_fair", "Fair")
        static let serious = localized("menubar.status.thermal_serious", "Serious")
        static let critical = localized("menubar.status.thermal_critical", "Critical")
        static let normal = localized("menubar.status.pressure_normal", "Normal")
        static let warning = localized("menubar.status.pressure_warning", "Warning")
        static func cliName(_ cli: AgentCLIKind) -> String {
            switch cli {
            case .claude: return localized("menubar.status.cli_claude", "Claude Code")
            case .codex: return localized("menubar.status.cli_codex", "Codex CLI")
            case .copilot: return localized("menubar.status.cli_copilot", "Copilot CLI")
            }
        }
        private static func localized(_ key: String, _ value: String) -> String { Bundle.main.localizedString(forKey: key, value: value, table: nil) }
    }
}
#endif
