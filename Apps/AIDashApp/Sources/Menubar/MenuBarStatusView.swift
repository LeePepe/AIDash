#if os(macOS)
import AppKit
import Charts
import SwiftUI

private enum Copy {
    static let updating = localized("menubar.status.updating", "Updating status…")
    static let emptyTitle = localized("menubar.status.empty_title", "No Telemetry Available")
    static let errorTitle = localized("menubar.status.error_title", "Status Unavailable")
    static let refresh = localized("menubar.status.refresh", "Refresh Status")
    static let refreshAction = localized("menubar.status.refresh_action", "Refresh")
    static let openBriefing = localized("menubar.status.open_briefing_action", "Open Briefing")
    static let about = localized("menubar.status.about_action", "About")
    static let quit = localized("menubar.status.quit_action", "Quit")
    static let actions = localized("menubar.status.actions", "Actions")

    internal static func resolveLocalized(_ key: String, _ value: String) -> String {
        let resolved = Bundle.main.localizedString(forKey: key, value: value, table: nil)
        return (resolved.isEmpty || resolved == key || resolved.hasPrefix("menubar.")) ? value : resolved
    }

    private static func localized(_ key: String, _ value: String) -> String {
        resolveLocalized(key, value)
    }
}

@MainActor
public struct MenuBarStatusView: View {
    public let state: MenuBarStatusViewState
    public let onRefresh: () -> Void
    public let onOpenBriefing: () -> Void
    public let onShowAbout: () -> Void
    public let onQuit: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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

    public enum Action: Sendable, Equatable {
        case refresh, openBriefing, showAbout, quit
    }

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
            VStack(alignment: .leading, spacing: 14) {
                switch state {
                case .loading:
                    loadingView
                case let .empty(reason):
                    diagnosticCard(title: Copy.emptyTitle, detail: reason, symbol: "chart.bar.xaxis", tint: .accentColor)
                case let .error(errorMessage):
                    diagnosticCard(title: Copy.errorTitle, detail: errorMessage, symbol: "exclamationmark.triangle.fill", tint: .orange)
                case let .populated(snapshot):
                    populatedView(snapshot)
                }
                footerBar
            }
            .padding(16)
        }
        .frame(width: 360)
    }
    private func populatedView(_ snapshot: MenuBarSystemSnapshot) -> some View {
        let today = DashboardWorkspaceStore.todayDateString()
        let liveDataset = LiveDashboardTelemetryReader.loadLiveDataset(forDate: today, fallbackUsage: snapshot.tokenUsage)
        let cliEntries = liveDataset?.entries ?? DashboardWorkspaceStore.deriveCLIEntries(from: snapshot.tokenUsage)
        let trendPoints = liveDataset?.trends ?? DashboardWorkspaceStore.deriveTrendPoints(from: cliEntries)
        let todayTotal = cliEntries.reduce(UInt64(0)) { $0 + $1.totalTokens }
        let periodTotal = cliEntries.reduce(UInt64(0)) { $0 + $1.periodTotalTokens }
        let pendingActions = Array(
            DashboardWorkspaceStore.deriveActionItems(from: snapshot, cliEntries: cliEntries)
                .filter { !$0.isCompleted }
                .prefix(3)
        )

        return VStack(alignment: .leading, spacing: 12) {
            pulseHeaderStrip(snapshot)
            telemetryGaugeStrip(snapshot)
            cliCostSection(entries: cliEntries)
            tokenVolumeChartSection(entries: cliEntries, trendPoints: trendPoints, todayTotal: todayTotal, periodTotal: periodTotal)
            topActionsSection(items: pendingActions)
        }
    }

    private func pulseHeaderStrip(_ snapshot: MenuBarSystemSnapshot) -> some View {
        functionalGlassBar {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(DashboardL10n.tr("menubar.pulse.title", "AIDash Pulse"))
                    .font(.headline)
                Text(DashboardL10n.format("menubar.pulse.machine_format", "%@ · %lldC", snapshot.machine.chipName, snapshot.machine.totalCores))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(snapshot.capturedAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func telemetryGaugeStrip(_ snapshot: MenuBarSystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DashboardL10n.tr("menubar.pulse.system_telemetry", "SYSTEM TELEMETRY"))
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    compactGaugeCell(
                        label: DashboardL10n.tr("menubar.status.cpu", "CPU"),
                        valueText: "\(Int((snapshot.cpu.usage * 100).rounded()))%",
                        fraction: snapshot.cpu.usage,
                        health: snapshot.cpu.usage >= 0.90 ? .critical : (snapshot.cpu.usage >= 0.70 ? .warning : .healthy)
                    )
                    compactGaugeCell(
                        label: DashboardL10n.tr("menubar.status.memory", "Memory"),
                        valueText: Self.compactMemoryShort(used: snapshot.memory.usedBytes, total: snapshot.memory.totalBytes),
                        fraction: snapshot.memory.usageFraction,
                        health: snapshot.memory.pressure == .critical ? .critical : (snapshot.memory.pressure == .warning ? .warning : .healthy)
                    )
                    compactGaugeCell(
                        label: DashboardL10n.tr("menubar.status.storage", "Storage"),
                        valueText: ByteCountFormatter.string(fromByteCount: Int64(snapshot.storage.systemVolume.availableBytes), countStyle: .binary),
                        fraction: snapshot.storage.systemVolume.usageFraction,
                        health: snapshot.storage.systemVolume.usageFraction >= 0.90 ? .critical : .healthy
                    )
                }
            }
        }
    }

    private func compactGaugeCell(
        label: String,
        valueText: String,
        fraction: Double,
        health: DashboardSemanticHealth
    ) -> some View {
        let tint = DashboardSemanticColorPalette.color(for: health)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(valueText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
            Gauge(value: min(max(fraction, 0), 1), in: 0...1) {
                Text(label)
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(solidCardColor)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
    private func cliCostSection(entries: [CLICostQuotaEntry]) -> some View {
        let quotaEntries = entries.filter { $0.cliFilter == .claude || $0.cliFilter == .codex }
        return VStack(alignment: .leading, spacing: 6) {
            Text(DashboardL10n.tr("menubar.pulse.cli_cost_quota", "CLI QUOTA MONITOR"))
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(quotaEntries) { entry in
                    cliPopoverRow(entry)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(solidCardColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private func cliPopoverRow(_ entry: CLICostQuotaEntry) -> some View {
        let tint = DashboardSemanticColorPalette.color(for: entry.health)
        let usedPct = Int((entry.usedFraction * 100).rounded())
        let remainingPct = max(0, 100 - usedPct)
        return Button {
            DashboardWorkspaceStore.shared.openDashboardWindow(
                section: .systemAndCosts,
                cliFilter: entry.cliFilter
            )
            perform(.openBriefing)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: entry.health.symbolName)
                        .foregroundStyle(tint)
                    Text(entry.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Text(DashboardL10n.format("menubar.pulse.quota_remaining_format", "Left %lld%%", remainingPct))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text("\(usedPct)%")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
                Gauge(value: entry.usedFraction, in: 0...1) {
                    Text(entry.displayName)
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tokenVolumeChartSection(
        entries: [CLICostQuotaEntry],
        trendPoints: [TrendDataPoint],
        todayTotal: UInt64,
        periodTotal: UInt64
    ) -> some View {
        let maxTokens = max(entries.map(\.totalTokens).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(DashboardL10n.tr("menubar.pulse.token_chart_title", "CLI TOKEN VOLUME"))
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(
                    DashboardL10n.format(
                        "menubar.pulse.today_tokens_format",
                        "Today %@ · 7d %@",
                        DashboardTokenFormatter.compact(todayTotal),
                        DashboardTokenFormatter.compact(periodTotal)
                    )
                )
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            }
            VStack(alignment: .leading, spacing: 10) {
                Chart(trendPoints) { point in
                    BarMark(
                        x: .value("Date", point.bucketLabel),
                        y: .value("Tokens (M)", Double(point.totalTokens) / 1_000_000.0)
                    )
                    .foregroundStyle(by: .value("CLI", point.category))
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 105)

                VStack(spacing: 6) {
                    ForEach(entries.filter { $0.totalTokens > 0 || $0.cliFilter != .kimi }) { entry in
                        HStack(spacing: 6) {
                            Text(entry.displayName)
                                .font(.caption.weight(.medium))
                                .frame(width: 78, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { geo in
                                let ratio = min(max(Double(entry.totalTokens) / Double(maxTokens), 0.04), 1.0)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.20))
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(Color.accentColor)
                                            .frame(width: entry.totalTokens > 0 ? geo.size.width * ratio : 0)
                                    }
                            }
                            .frame(height: 7)
                            Text("\(DashboardTokenFormatter.compact(entry.totalTokens))")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(solidCardColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }
    private func topActionsSection(items: [DashboardActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(DashboardL10n.tr("menubar.pulse.top_actions", "TOP ACTIONABLE ITEMS"))
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(DashboardL10n.format("menubar.pulse.pending_count_format", "%lld pending", items.count))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Text(item.priority.label)
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                DashboardSemanticColorPalette.color(for: item.priority.health).opacity(0.16),
                                in: Capsule()
                            )
                            .foregroundStyle(DashboardSemanticColorPalette.color(for: item.priority.health))
                        Text(item.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let command = item.command {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(command, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy CLI Command")
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(solidCardColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var footerBar: some View {
        functionalGlassBar {
            Button {
                perform(.openBriefing)
            } label: {
                Label(Copy.openBriefing, systemImage: "macwindow")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .frame(minHeight: 28)

            Spacer(minLength: 4)

            Button {
                perform(.refresh)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Copy.refreshAction)

            Button {
                perform(.showAbout)
            } label: {
                Image(systemName: "info.circle")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Copy.about)

            Button(role: .destructive) {
                perform(.quit)
            } label: {
                Image(systemName: "power")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Copy.quit)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.actions)
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(solidCardColor)
                .frame(height: 44)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(solidCardColor)
                .frame(height: 68)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(solidCardColor)
                .frame(height: 150)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(solidCardColor)
                .frame(height: 84)
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel(Copy.updating)
    }

    private func diagnosticCard(title: String, detail: String?, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button(Copy.refresh, action: onRefresh)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(solidCardColor)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private func functionalGlassBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }

    private var solidCardColor: Color {
        reduceTransparency
            ? Color(nsColor: .windowBackgroundColor)
            : Color(nsColor: .controlBackgroundColor)
    }
    internal static func formatLoadAverages(one: Double, five: Double, fifteen: Double) -> String {
        String(format: "%.1f / %.1f / %.1f", one, five, fifteen)
    }

    internal static func compactMemoryPair(used: UInt64, total: UInt64) -> String {
        guard used > 0 || total > 0 else { return "0 / 0 GB" }
        return String(
            format: "%.1f / %.1f GB",
            Double(used) / 1_073_741_824.0,
            Double(total) / 1_073_741_824.0
        )
    }

    private static func compactMemoryShort(used: UInt64, total: UInt64) -> String {
        guard total > 0 else { return "0GB" }
        return String(format: "%.0f/%.0fG", Double(used) / 1_073_741_824.0, Double(total) / 1_073_741_824.0)
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
