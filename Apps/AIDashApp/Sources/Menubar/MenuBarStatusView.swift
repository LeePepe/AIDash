#if os(macOS)
// swiftlint:disable file_length
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
    public let onOpenScheduledPulse: () -> Void
    public let scheduledPulseSnapshot: ScheduledPulseSnapshot?
    public let scheduledJobFrameworkSnapshot: ScheduledJobFrameworkSnapshot?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var completedActionIDs: Set<String> = []
    @State private var copiedActionID: String?
    @State private var timeGranularity: DashboardChartTimeGranularity = MenuBarDisplayPreferences.shared.defaultChartGranularity

    public init(
        state: MenuBarStatusViewState,
        onRefresh: @escaping () -> Void = {},
        onOpenBriefing: @escaping () -> Void = {},
        onShowAbout: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {},
        onOpenScheduledPulse: @escaping () -> Void = {
            DashboardWorkspaceStore.shared.openDashboardWindow(section: .scheduledPulse)
        },
        scheduledPulseSnapshot: ScheduledPulseSnapshot? = nil,
        scheduledJobFrameworkSnapshot: ScheduledJobFrameworkSnapshot? = nil
    ) {
        self.state = state; self.onRefresh = onRefresh; self.onOpenBriefing = onOpenBriefing
        self.onShowAbout = onShowAbout; self.onQuit = onQuit
        self.onOpenScheduledPulse = onOpenScheduledPulse
        self.scheduledPulseSnapshot = scheduledPulseSnapshot
        self.scheduledJobFrameworkSnapshot = scheduledJobFrameworkSnapshot
    }

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
            VStack(alignment: .leading, spacing: 14) {
                switch state {
                case .loading: loadingView
                case let .empty(reason): diagnosticCard(title: Copy.emptyTitle, detail: reason, symbol: "chart.bar.xaxis", tint: .accentColor)
                case let .error(errorMessage): diagnosticCard(title: Copy.errorTitle, detail: errorMessage, symbol: "exclamationmark.triangle.fill", tint: .orange)
                case let .populated(snapshot): populatedView(snapshot)
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
        let frameworkSnapshot = scheduledJobFrameworkSnapshot
            ?? (LiveDashboardTelemetryReader.isLiveEnvironment
                ? DashboardWorkspaceStore.shared.scheduledJobFrameworkSnapshot
                : ScheduledJobFrameworkSnapshot(capturedAt: .now, entries: []))
        let prefs = MenuBarDisplayPreferences.shared
        return VStack(alignment: .leading, spacing: 12) {
            if prefs.showPopoverSystemTelemetry { telemetryGaugeStrip(snapshot) }
            cliTokenAndQuotaSection(entries: cliEntries, trendPoints: trendPoints, todayTotal: todayTotal, periodTotal: periodTotal)
            scheduledJobsSection(snapshot: frameworkSnapshot)
        }
    }

    private func telemetryGaugeStrip(_ snapshot: MenuBarSystemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DashboardL10n.tr("menubar.pulse.system_telemetry", "SYSTEM TELEMETRY"))
                .font(.system(.caption2, design: .rounded, weight: .semibold)).foregroundStyle(.secondary)
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
                        valueText: Self.compactStorageAvailable(snapshot.storage.systemVolume.availableBytes),
                        fraction: snapshot.storage.systemVolume.usageFraction,
                        health: snapshot.storage.systemVolume.usageFraction >= 0.90 ? .critical : .healthy
                    )
                }
            }
        }
    }

    private func compactGaugeCell(label: String, valueText: String, fraction: Double, health: DashboardSemanticHealth) -> some View {
        let tint = DashboardSemanticColorPalette.color(for: health)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 2)
                Text(valueText).font(.caption.weight(.semibold)).monospacedDigit().contentTransition(.numericText()).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            Gauge(value: min(max(fraction, 0), 1), in: 0...1) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity).labelsHidden().tint(tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(solidCardColor))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 1) }
    }
    private func cliTokenAndQuotaSection(
        entries: [CLICostQuotaEntry],
        trendPoints: [TrendDataPoint],
        todayTotal: UInt64,
        periodTotal: UInt64
    ) -> some View {
        let activePoints = TrendDataPoint.points(from: trendPoints, granularity: timeGranularity)
        let dailySegments = TrendDataPoint.dailyKindBarSegments(from: trendPoints)
        let pool = QuotaPoolSummary.summarize(entries: entries)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(DashboardL10n.tr("menubar.pulse.cli_cost_quota", "CLI TOKEN & QUOTA MONITOR"))
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
            VStack(alignment: .leading, spacing: 8) {
                Picker(DashboardL10n.tr("dashboard.chart_time.picker_label", "Time Granularity"), selection: $timeGranularity) {
                    ForEach(DashboardChartTimeGranularity.allCases) { gran in Text(gran.displayTitle).tag(gran) }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                .onChange(of: timeGranularity) { _, newValue in
                    if MenuBarDisplayPreferences.shared.defaultChartGranularity != newValue {
                        MenuBarDisplayPreferences.shared.defaultChartGranularity = newValue
                    }
                }

                MenuBarInteractiveTokenChart(
                    rawPoints: trendPoints,
                    activePoints: activePoints,
                    dailySegments: dailySegments,
                    timeGranularity: timeGranularity,
                    pool: pool
                )

                Divider()

                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(stride(from: 0, to: entries.count, by: 2)), id: \.self) { startIndex in
                        GridRow {
                            ForEach(entries[startIndex..<min(startIndex + 2, entries.count)]) { entry in
                                cliPopoverTile(entry)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(solidCardColor))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 1) }
        }
    }

    private func cliPopoverTile(_ entry: CLICostQuotaEntry) -> some View {
        let tint = DashboardSemanticColorPalette.color(for: entry.health)
        let usedPct = Int((entry.usedFraction * 100).rounded())
        let remainingPct = max(0, 100 - usedPct)
        let todayCompact = DashboardTokenFormatter.compact(entry.totalTokens)
        let periodCompact = DashboardTokenFormatter.compact(entry.periodTotalTokens)
        return Button {
            if let cmd = entry.authState.loginCommand {
                CLITerminalLoginLauncher.launchLoginInTerminal(command: cmd)
            } else {
                DashboardWorkspaceStore.shared.openDashboardWindow(section: .systemAndCosts, cliFilter: entry.cliFilter)
                perform(.openBriefing)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: entry.health.symbolName).font(.caption2).foregroundStyle(tint)
                    Text(entry.cliFilter.shortLabel).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 2)
                    if let badge = entry.authState.badgeTitle {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                    } else if entry.hasTrackedQuota {
                        Text(DashboardL10n.format("menubar.pulse.quota_remaining_format", "Left %lld%%", remainingPct))
                            .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
                    } else {
                        Text(todayCompact).font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if entry.authState.isAuthError {
                    Divider().padding(.vertical, 2)
                } else if entry.hasTrackedQuota {
                    Gauge(value: entry.usedFraction, in: 0...1) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity).labelsHidden().tint(tint)
                } else {
                    Divider().padding(.vertical, 2)
                }
                HStack(spacing: 4) {
                    if entry.authState.loginCommand != nil {
                        Image(systemName: "terminal.fill")
                            .foregroundStyle(tint)
                        Text(DashboardL10n.tr("dashboard.auth.login_terminal_button", "Login in Terminal"))
                            .fontWeight(.semibold)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                    } else if let hint = entry.authState.loginCommandHint, !entry.authState.isAuthenticated {
                        Text(hint)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                    } else {
                        Text("7d \(periodCompact)")
                        Spacer(minLength: 2)
                        if let secUsed = entry.secondaryQuotaUsed, let secLabel = entry.secondaryQuotaLabel {
                            Text("\(secLabel) \(Int((secUsed * 100).rounded()))%")
                        } else if entry.hasTrackedQuota {
                            Text("\(usedPct)%")
                        } else {
                            Text("\(entry.interactionCount) calls")
                        }
                    }
                }
                .font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(entry.displayName) · \(entry.authState.statusReasonText ?? "Today \(todayCompact)") · 7d \(periodCompact)")
    }
    private func scheduledJobsSection(snapshot: ScheduledJobFrameworkSnapshot) -> some View {
        MenuBarScheduledJobsCard(
            snapshot: snapshot,
            solidCardColor: solidCardColor,
            onOpenProblem: { entry in
                let store = DashboardWorkspaceStore.shared
                store.selectedFrameworkJobID = entry.id
                store.scheduledPulseTab = entry.actions.isEmpty ? .overview : .needActions
                onOpenScheduledPulse()
            }
        )
    }

    private func pulseExceptionsSection(rows: [ScheduledJobStatus]) -> some View {
        MenuBarPulseExceptionsCard(
            rows: rows,
            solidCardColor: solidCardColor,
            onOpenPulse: onOpenScheduledPulse
        )
    }

    private func topActionsSection(items: [DashboardActionItem]) -> some View {
        MenuBarTopActionsCard(
            items: items,
            solidCardColor: solidCardColor,
            completedActionIDs: $completedActionIDs,
            copiedActionID: $copiedActionID,
            onOpenBriefing: { perform(.openBriefing) }
        )
    }

    private var footerBar: some View {
        functionalGlassBar {
            Button { perform(.openBriefing) } label: {
                Label(Copy.openBriefing, systemImage: "macwindow").font(.caption.weight(.semibold))
            }
            .buttonStyle(.glassProminent).controlSize(.small).frame(minHeight: 28)

            Spacer(minLength: 4)

            Button {
                DashboardWorkspaceStore.shared.openDashboardWindow(section: .settings)
                perform(.openBriefing)
            } label: {
                Image(systemName: "gearshape").frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless).accessibilityLabel(DashboardL10n.tr("dashboard.section.settings", "Settings"))

            Button { perform(.showAbout) } label: {
                Image(systemName: "info.circle").frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless).accessibilityLabel(Copy.about)

            Button(role: .destructive) { perform(.quit) } label: {
                Image(systemName: "power").frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless).accessibilityLabel(Copy.quit)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.actions)
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([44.0, 68.0, 150.0, 84.0], id: \.self) { h in
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(solidCardColor).frame(height: h)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel(Copy.updating)
    }

    private func diagnosticCard(title: String, detail: String?, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Button(Copy.refresh, action: onRefresh).buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(solidCardColor))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 1) }
    }

    private func functionalGlassBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }

    private var solidCardColor: Color {
        reduceTransparency ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .controlBackgroundColor)
    }

    internal static func formatLoadAverages(one: Double, five: Double, fifteen: Double) -> String { String(format: "%.1f / %.1f / %.1f", one, five, fifteen) }

    internal static func compactMemoryPair(used: UInt64, total: UInt64) -> String {
        (used > 0 || total > 0) ? String(format: "%.1f / %.1f GB", Double(used) / 1_073_741_824.0, Double(total) / 1_073_741_824.0) : "0 / 0 GB"
    }

    private static func compactMemoryShort(used: UInt64, total: UInt64) -> String {
        total > 0 ? String(format: "%.0f/%.0fG", Double(used) / 1_073_741_824.0, Double(total) / 1_073_741_824.0) : "0G"
    }

    internal static func compactStorageAvailable(_ availableBytes: UInt64) -> String {
        let gib = Double(availableBytes) / 1_073_741_824.0
        return gib >= 100 ? String(format: "%.0fG", gib) : (gib >= 10 ? String(format: "%.1fG", gib) : String(format: "%.2fG", max(gib, 0)))
    }

    internal static func resolveLocalized(_ key: String, _ value: String) -> String { Copy.resolveLocalized(key, value) }
}

@MainActor
private struct MenuBarInteractiveTokenChart: View {
    let rawPoints: [TrendDataPoint]
    let activePoints: [TrendDataPoint]
    let dailySegments: [DailyKindBarSegment]
    let timeGranularity: DashboardChartTimeGranularity
    let pool: QuotaPoolSummary
    @State private var hoveredBucketLabel: String?

    var body: some View {
        let summary = hoveredBucketLabel.flatMap {
            TrendDataPoint.hoverSummary(forBucket: $0, in: rawPoints, granularity: timeGranularity)
        }
        VStack(alignment: .leading, spacing: 6) {
            scrubHeaderSlot(summary: summary)
            if timeGranularity == .threeDayHourly, activePoints.contains(where: { $0.bucketDate != nil }) {
                hourlyChart
            } else {
                dailyChart
            }
        }
    }

    private func scrubHeaderSlot(summary: TrendBucketHoverSummary?) -> some View {
        let totalIn = activePoints.reduce(UInt64(0)) { $0 + $1.inputTokens }
        let totalOut = activePoints.reduce(UInt64(0)) { $0 + $1.outputTokens }
        let totalCache = activePoints.reduce(UInt64(0)) { $0 + $1.cacheTokens }
        let poolTint = DashboardSemanticColorPalette.color(for: pool.health)
        let remPct = max(0, 100 - Int((pool.averageUsedFraction * 100).rounded()))

        return VStack(alignment: .leading, spacing: 3) {
            if let summary {
                HStack(spacing: 6) {
                    Text(summary.bucketLabel).font(.caption2.weight(.bold)).monospacedDigit()
                    Spacer(minLength: 4)
                    Text(DashboardL10n.format("dashboard.chart.hover_total_calls_format", "Total %@ · %lld calls", DashboardTokenFormatter.compact(summary.totalTokens), summary.invocations))
                        .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(Color.accentColor)
                }
                Text(DashboardL10n.format("dashboard.chart.hover_io_cache_format", "In %@ · Out %@ · Cache %@", DashboardTokenFormatter.compact(summary.inputTokens), DashboardTokenFormatter.compact(summary.outputTokens), DashboardTokenFormatter.compact(summary.cacheTokens)))
                    .font(.caption2.weight(.medium)).monospacedDigit().foregroundStyle(.primary).lineLimit(1)
                Text(summary.cliShares.map { "\($0.cli.shortLabel) \(DashboardTokenFormatter.compact($0.tokens))" }.joined(separator: " · "))
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.caption2.weight(.semibold)).foregroundStyle(poolTint)
                    Text(DashboardL10n.format("menubar.pulse.pool_remaining_format", "Pool Left %lld%%", remPct))
                        .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(poolTint)
                    Spacer(minLength: 4)
                    if let rec = pool.recommendedEntry {
                        let recRem = Int((rec.remainingFraction * 100).rounded())
                        Text(DashboardL10n.format("menubar.pulse.route_recommend_format", "Route → %@ (%lld%% left)", rec.cliFilter.shortLabel, recRem))
                            .font(.caption2.weight(.medium)).monospacedDigit().foregroundStyle(.primary).lineLimit(1)
                    }
                }
                Text(DashboardL10n.format("dashboard.chart.hover_io_cache_format", "In %@ · Out %@ · Cache %@", DashboardTokenFormatter.compact(totalIn), DashboardTokenFormatter.compact(totalOut), DashboardTokenFormatter.compact(totalCache)))
                    .font(.caption2.weight(.medium)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                Text(periodCLISummaryText)
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
    }

    private var periodCLISummaryText: String {
        var byCLI: [DashboardCLIFilter: UInt64] = [:]
        for pt in activePoints { byCLI[pt.cliFilter, default: 0] += pt.totalTokens }
        return byCLI.sorted { $0.value > $1.value }.map { "\($0.key.shortLabel) \(DashboardTokenFormatter.compact($0.value))" }.joined(separator: " · ")
    }

    private var hourlyChart: some View {
        Chart {
            ForEach(activePoints) { point in
                if let date = point.bucketDate {
                    let valM = Double(point.totalTokens) / 1_000_000.0
                    AreaMark(x: .value("Time", date), y: .value("Tokens (M)", valM))
                        .foregroundStyle(by: .value("CLI", point.category)).opacity(0.24).interpolationMethod(.monotone)
                    LineMark(x: .value("Time", date), y: .value("Tokens (M)", valM))
                        .foregroundStyle(by: .value("CLI", point.category)).lineStyle(StrokeStyle(lineWidth: 1.5)).interpolationMethod(.monotone)
                }
            }
            if let hoveredBucketLabel, let hoveredDate = activePoints.first(where: { $0.bucketLabel == hoveredBucketLabel })?.bucketDate {
                RuleMark(x: .value("Time", hoveredDate)).foregroundStyle(Color.accentColor.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .chartLegend(position: .bottom, alignment: .leading).frame(height: 118)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                    guard case let .active(loc) = phase, let plotFrame = proxy.plotFrame else {
                        if hoveredBucketLabel != nil { hoveredBucketLabel = nil }
                        return
                    }
                    let xPos = loc.x - geo[plotFrame].origin.x
                    guard xPos >= 0, xPos <= geo[plotFrame].width, let date: Date = proxy.value(atX: xPos) else {
                        if hoveredBucketLabel != nil { hoveredBucketLabel = nil }
                        return
                    }
                    let next = TrendDataPoint.nearestHourlyBucketLabel(to: date, in: activePoints)
                    if hoveredBucketLabel != next { hoveredBucketLabel = next }
                }
            }
        }
    }

    private var dailyChart: some View {
        Chart {
            ForEach(dailySegments) { seg in
                let isHovered = hoveredBucketLabel == nil || hoveredBucketLabel == seg.bucketLabel
                BarMark(x: .value("Date", seg.bucketLabel), y: .value("Tokens (M)", seg.tokenMillions))
                    .position(by: .value("Kind", seg.kindTitle))
                    .foregroundStyle(by: .value("CLI", seg.category))
                    .opacity(isHovered ? 1.0 : 0.35)
            }
            if let hoveredBucketLabel {
                RuleMark(x: .value("Date", hoveredBucketLabel))
                    .foregroundStyle(Color.accentColor.opacity(0.50))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .chartYScale(type: .symmetricLog(slopeAtZero: 0.1))
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 118)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                    guard case let .active(loc) = phase, let plotFrame = proxy.plotFrame else {
                        if hoveredBucketLabel != nil { hoveredBucketLabel = nil }
                        return
                    }
                    let xPos = loc.x - geo[plotFrame].origin.x
                    guard xPos >= 0, xPos <= geo[plotFrame].width, let bucket: String = proxy.value(atX: xPos) else {
                        if hoveredBucketLabel != nil { hoveredBucketLabel = nil }
                        return
                    }
                    if hoveredBucketLabel != bucket { hoveredBucketLabel = bucket }
                }
            }
        }
    }
}

@MainActor
private struct MenuBarScheduledJobsCard: View {
    let snapshot: ScheduledJobFrameworkSnapshot
    let solidCardColor: Color
    let onOpenProblem: (ScheduledJobFrameworkEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(DashboardL10n.tr("menubar.scheduled_jobs.title", "定时任务"))
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(snapshot.entries) { entry in
                    if entry.isProblem || !entry.actions.isEmpty {
                        Button { onOpenProblem(entry) } label: {
                            row(entry)
                        }
                        .buttonStyle(.plain)
                    } else {
                        row(entry)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(solidCardColor))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 1) }
        }
    }

    private func row(_ entry: ScheduledJobFrameworkEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.semanticState.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(DashboardSemanticColorPalette.color(for: entry.semanticState.semanticHealth))
                .accessibilityHidden(true)
            Text(entry.definition.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(entry.statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DashboardSemanticColorPalette.color(for: entry.semanticState.semanticHealth))
                    .lineLimit(1)
                if let relative = ScheduledJobTimeFormatting.relativeText(from: entry.lastRunAt) {
                    Text(relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(minHeight: 28)
        .contentShape(Rectangle())
    }
}

@MainActor
private struct MenuBarPulseExceptionsCard: View {
    let rows: [ScheduledJobStatus]
    let solidCardColor: Color
    let onOpenPulse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(DashboardL10n.tr("menubar.pulse.exceptions", "SCHEDULED PULSE"))
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(DashboardL10n.format("menubar.pulse.exceptions_count_format", "%lld issues", rows.count))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows.prefix(3)) { row in
                    Button(action: onOpenPulse) {
                        HStack(spacing: 7) {
                            Image(systemName: row.health.semanticHealth.symbolName)
                                .foregroundStyle(DashboardSemanticColorPalette.color(for: row.health.semanticHealth))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.definition.displayName)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(row.health.exceptionSubtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(solidCardColor))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 1) }
        }
    }
}

@MainActor
private struct MenuBarTopActionsCard: View {
    let items: [DashboardActionItem]
    let solidCardColor: Color
    @Binding var completedActionIDs: Set<String>
    @Binding var copiedActionID: String?
    let onOpenBriefing: () -> Void

    var body: some View {
        let pendingItems = items.filter { !completedActionIDs.contains($0.id) && !$0.isCompleted }
        if !pendingItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(DashboardL10n.tr("menubar.pulse.top_actions", "TOP ACTIONABLE ITEMS"))
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(DashboardL10n.format("menubar.pulse.pending_count_format", "%lld pending", pendingItems.count))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pendingItems.prefix(3)) { item in
                        actionRow(item)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(solidCardColor))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 1) }
            }
        }
    }

    private func actionRow(_ item: DashboardActionItem) -> some View {
        let isDone = completedActionIDs.contains(item.id) || item.isCompleted
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    if completedActionIDs.contains(item.id) { completedActionIDs.remove(item.id) } else { completedActionIDs.insert(item.id) }
                    DashboardWorkspaceStore.shared.toggleActionItem(id: item.id)
                } label: {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isDone ? Color.green : Color.secondary).frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)

                Button {
                    if let urlStr = item.externalURLString, let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }
                    DashboardWorkspaceStore.shared.openDashboardWindow(section: .actionItems)
                    onOpenBriefing()
                } label: {
                    HStack(spacing: 5) {
                        Text(item.priority.label)
                            .font(.caption2.weight(.bold)).monospacedDigit().padding(.horizontal, 5).padding(.vertical, 2)
                            .background(DashboardSemanticColorPalette.color(for: item.priority.health).opacity(0.16), in: Capsule())
                            .foregroundStyle(DashboardSemanticColorPalette.color(for: item.priority.health))
                        Text(item.title).font(.caption.weight(.medium)).strikethrough(isDone).foregroundStyle(isDone ? .secondary : .primary).lineLimit(1)
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let command = item.command {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        copiedActionID = item.id
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: copiedActionID == item.id ? "checkmark" : "doc.on.doc")
                            Text(copiedActionID == item.id ? DashboardL10n.tr("dashboard.actions.copied", "Copied") : DashboardL10n.tr("dashboard.actions.copy_command", "Copy Command"))
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(copiedActionID == item.id ? Color.green : Color.accentColor)
                    }
                    .buttonStyle(.bordered).controlSize(.mini)
                } else if let urlStr = item.externalURLString, let url = URL(string: urlStr) {
                    Button {
                        NSWorkspace.shared.open(url)
                        onOpenBriefing()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right.square")
                            Text(DashboardL10n.tr("dashboard.actions.open_link", "Open"))
                        }
                        .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.bordered).controlSize(.mini)
                }
            }
            if !isDone {
                Text(item.summary).font(.caption2).foregroundStyle(.secondary).padding(.leading, 26).lineLimit(2)
            }
        }
    }
}
#endif
