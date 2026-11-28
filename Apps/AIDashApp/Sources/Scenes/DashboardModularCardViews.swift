#if os(macOS)
// swiftlint:disable file_length
import AppKit
import Charts
import DesignKit
import SwiftUI
import AIDashUI

public struct SolidModularCardContainer<HeaderAccessory: View, Content: View>: View {
    public let title: String
    public let subtitle: String?
    public let symbolName: String
    private let accessory: HeaderAccessory
    private let content: Content

    @Environment(\.colorSchemeContrast) private var contrast
    private let theme = Theme.system

    public init(
        title: String, subtitle: String? = nil, symbolName: String,
        @ViewBuilder accessory: () -> HeaderAccessory, @ViewBuilder content: () -> Content
    ) {
        self.title = title; self.subtitle = subtitle; self.symbolName = symbolName
        self.accessory = accessory(); self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: symbolName).font(.headline).foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                accessory
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.neutrals.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(contrast == .increased ? Color.primary.opacity(0.28) : theme.neutrals.border, lineWidth: contrast == .increased ? 1.5 : 1)
        }
    }
}

extension SolidModularCardContainer where HeaderAccessory == EmptyView {
    public init(title: String, subtitle: String? = nil, symbolName: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, symbolName: symbolName, accessory: { EmptyView() }, content: content)
    }
}

public enum DashboardSemanticColorPalette {
    public static func color(for health: DashboardSemanticHealth) -> Color {
        let theme = Theme.system
        switch health {
        case .healthy: return theme.neutrals.text2
        case .warning: return theme.warning
        case .critical: return theme.danger
        case .neutral: return theme.neutrals.text2
        }
    }
}

public struct SystemTelemetryStripView: View {
    public let snapshot: MenuBarSystemSnapshot
    private let theme = Theme.system

    public init(snapshot: MenuBarSystemSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.telemetry.title", "Real-Time Machine Telemetry"),
            subtitle: DashboardL10n.format("dashboard.telemetry.subtitle_format", "%@ · %lld Cores", snapshot.machine.chipName, snapshot.machine.totalCores),
            symbolName: "cpu"
        ) {
            Text(snapshot.capturedAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } content: {
            Grid(horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    telemetryGaugeTile(
                        title: DashboardL10n.tr("dashboard.telemetry.cpu_load", "CPU Load"),
                        symbol: "cpu",
                        valueText: "\(Int((snapshot.cpu.usage * 100).rounded()))%",
                        detailText: DashboardL10n.format(
                            "dashboard.telemetry.load_avg_format",
                            "Load %.1f / %.1f / %.1f",
                            snapshot.cpu.loadOneMinute,
                            snapshot.cpu.loadFiveMinutes,
                            snapshot.cpu.loadFifteenMinutes
                        ),
                        fraction: snapshot.cpu.usage,
                        health: snapshot.cpu.usage >= 0.90 ? .critical : (snapshot.cpu.usage >= 0.70 ? .warning : .healthy)
                    )
                    telemetryGaugeTile(
                        title: DashboardL10n.tr("dashboard.telemetry.memory", "Memory"),
                        symbol: "memorychip",
                        valueText: MenuBarStatusView.compactMemoryPair(
                            used: snapshot.memory.usedBytes,
                            total: snapshot.memory.totalBytes
                        ),
                        detailText: DashboardL10n.format(
                            "dashboard.telemetry.pressure_format",
                            "Pressure: %@",
                            MenuBarController.pressureTitle(snapshot.memory.pressure)
                        ),
                        fraction: snapshot.memory.usageFraction,
                        health: snapshot.memory.pressure == .critical ? .critical : (snapshot.memory.pressure == .warning ? .warning : .healthy)
                    )
                    telemetryGaugeTile(
                        title: DashboardL10n.tr("dashboard.telemetry.storage", "System Storage"),
                        symbol: "internaldrive",
                        valueText: DashboardL10n.format(
                            "dashboard.telemetry.storage_free_format",
                            "%@ free",
                            ByteCountFormatter.string(fromByteCount: Int64(snapshot.storage.systemVolume.availableBytes), countStyle: .binary)
                        ),
                        detailText: DashboardL10n.format(
                            "dashboard.telemetry.storage_used_format",
                            "%lld%% used on %@",
                            Int((snapshot.storage.systemVolume.usageFraction * 100).rounded()),
                            snapshot.storage.systemVolume.name
                        ),
                        fraction: snapshot.storage.systemVolume.usageFraction,
                        health: snapshot.storage.systemVolume.usageFraction >= 0.90 ? .critical : (snapshot.storage.systemVolume.usageFraction >= 0.78 ? .warning : .healthy)
                    )
                }
            }
        }
    }

    private func telemetryGaugeTile(
        title: String, symbol: String, valueText: String,
        detailText: String, fraction: Double, health: DashboardSemanticHealth
    ) -> some View {
        let clamped = min(max(fraction, 0), 1)
        let tint = DashboardSemanticColorPalette.color(for: health)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Image(systemName: health.symbolName).foregroundStyle(tint).accessibilityHidden(true)
                Text(valueText).font(.subheadline.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
            }
            Gauge(value: clamped, in: 0...1) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity).labelsHidden().tint(tint)
            Text(detailText).font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.neutrals.inner))
        .accessibilityElement(children: .combine)
    }
}

public struct KPISummaryCardView: View {
    public let metrics: [KPIMetricItem]
    public var onSelectMetric: ((String) -> Void)?
    private let theme = Theme.system

    public init(metrics: [KPIMetricItem], onSelectMetric: ((String) -> Void)? = nil) {
        self.metrics = metrics
        self.onSelectMetric = onSelectMetric
    }

    public var body: some View {
        SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.card.kpi.title", "Daily Agent Summary"),
            subtitle: DashboardL10n.tr("dashboard.card.kpi.subtitle", "Key invocations, efficiency, cost, and action status"),
            symbolName: "gauge.with.dots.needle.33percent"
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185, maximum: 300), spacing: 12)], spacing: 12) {
                ForEach(metrics) { metric in metricTile(metric) }
            }
        }
    }

    private func metricTile(_ metric: KPIMetricItem) -> some View {
        let semanticColor = DashboardSemanticColorPalette.color(for: metric.health)
        return Button {
            onSelectMetric?(metric.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(metric.label).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: metric.symbolName).foregroundStyle(semanticColor).accessibilityHidden(true)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(metric.formattedValue).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit().contentTransition(.numericText())
                    if let unit = metric.unit { Text(unit).font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                }
                HStack(spacing: 4) {
                    Image(systemName: metric.direction.symbolName).font(.caption2.weight(.bold)).foregroundStyle(semanticColor)
                    Text(metric.deltaText).font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.neutrals.inner))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

public struct TrendChartCardView: View {
    public let points: [TrendDataPoint]
    public let selectedCategory: String?
    public let onSelectCategory: (String) -> Void
    public let onClearSelection: () -> Void
    public var showInlineCrossFilterPills: Bool
    @State private var timeGranularity: DashboardChartTimeGranularity = MenuBarDisplayPreferences.shared.defaultChartGranularity

    public init(
        points: [TrendDataPoint], selectedCategory: String?,
        onSelectCategory: @escaping (String) -> Void, onClearSelection: @escaping () -> Void,
        showInlineCrossFilterPills: Bool = true
    ) {
        self.points = points; self.selectedCategory = selectedCategory
        self.onSelectCategory = onSelectCategory; self.onClearSelection = onClearSelection
        self.showInlineCrossFilterPills = showInlineCrossFilterPills
    }

    public var body: some View {
        let activePoints = TrendDataPoint.points(from: points, granularity: timeGranularity)
        let dailySegments = TrendDataPoint.dailyKindBarSegments(from: points)
        return SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.card.trend.title", "Agent Invocations & Spend by CLI"),
            subtitle: DashboardL10n.tr("dashboard.card.trend.subtitle", "Hover bars for exact breakdown; click below to cross-filter"),
            symbolName: "chart.bar.xaxis"
        ) {
            HStack(spacing: 8) {
                Picker(DashboardL10n.tr("dashboard.chart_time.picker_label", "Time Granularity"), selection: $timeGranularity) {
                    ForEach(DashboardChartTimeGranularity.allCases) { gran in Text(gran.displayTitle).tag(gran) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                .onChange(of: timeGranularity) { _, newValue in
                    if MenuBarDisplayPreferences.shared.defaultChartGranularity != newValue {
                        MenuBarDisplayPreferences.shared.defaultChartGranularity = newValue
                    }
                }

                if let selectedCategory {
                    Button { onClearSelection() } label: {
                        Label(DashboardL10n.format("dashboard.chart.clear_filter_format", "Filter: %@ ×", selectedCategory), systemImage: "line.3.horizontal.decrease.circle.fill")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered).controlSize(.small).frame(minHeight: 28)
                }
            }
        } content: {
            let categoryTotals = Self.groupedCategoryTotals(from: activePoints, kind: .all)
            VStack(alignment: .leading, spacing: 10) {
                TrendChartInteractiveCanvas(
                    rawPoints: points, activePoints: activePoints,
                    dailySegments: dailySegments, selectedCategory: selectedCategory, timeGranularity: timeGranularity
                )
                if showInlineCrossFilterPills {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Text(DashboardL10n.tr("dashboard.chart.quick_filter", "Quick Cross-Filter:")).font(.caption).foregroundStyle(.secondary)
                            ForEach(categoryTotals, id: \.category) { item in
                                let active = selectedCategory == item.category
                                Button { onSelectCategory(item.category) } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                        Text(item.category)
                                        Text("\(DashboardTokenFormatter.compact(item.tokens)) tok").monospacedDigit()
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered).tint(active ? .accentColor : .secondary).controlSize(.small).frame(minHeight: 28)
                            }
                        }
                    }
                }
            }
        }
    }

    private static func groupedCategoryTotals(
        from points: [TrendDataPoint],
        kind: DashboardTokenKindFilter
    ) -> [(category: String, tokens: UInt64)] {
        var order: [String] = []
        var sums: [String: UInt64] = [:]
        for p in points {
            if sums[p.category] == nil {
                order.append(p.category)
            }
            sums[p.category, default: 0] += p.tokens(for: kind)
        }
        return order.map { ($0, sums[$0] ?? 0) }
    }
}

@MainActor
private struct TrendChartInteractiveCanvas: View {
    let rawPoints: [TrendDataPoint]
    let activePoints: [TrendDataPoint]
    let dailySegments: [DailyKindBarSegment]
    let selectedCategory: String?
    let timeGranularity: DashboardChartTimeGranularity
    @State private var hoveredBucketLabel: String?
    private let theme = Theme.system

    var body: some View {
        let hoverSummary = hoveredBucketLabel.flatMap {
            TrendDataPoint.hoverSummary(forBucket: $0, in: rawPoints, granularity: timeGranularity)
        }
        VStack(alignment: .leading, spacing: 8) {
            scrubReadoutSlot(summary: hoverSummary)
            if timeGranularity == .threeDayHourly, activePoints.contains(where: { $0.bucketDate != nil }) {
                hourlyTrendChart
            } else {
                dailyBarChart
            }
        }
    }

    private func scrubReadoutSlot(summary: TrendBucketHoverSummary?) -> some View {
        let totalTok = activePoints.reduce(UInt64(0)) { $0 + $1.totalTokens }
        let totalIn = activePoints.reduce(UInt64(0)) { $0 + $1.inputTokens }
        let totalOut = activePoints.reduce(UInt64(0)) { $0 + $1.outputTokens }
        let totalCache = activePoints.reduce(UInt64(0)) { $0 + $1.cacheTokens }
        let totalCalls = activePoints.reduce(0) { $0 + $1.invocations }

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: summary == nil ? "chart.bar.xaxis" : "chart.bar.doc.horizontal.fill")
                    .font(.caption).foregroundStyle(summary == nil ? Color.secondary : Color.accentColor)
                Text(summary?.bucketLabel ?? timeGranularity.displayTitle).font(.caption.weight(.bold)).monospacedDigit()
                Text(DashboardL10n.format("dashboard.chart.hover_total_calls_format", "Total %@ · %lld calls", DashboardTokenFormatter.compact(summary?.totalTokens ?? totalTok), summary?.invocations ?? totalCalls))
                    .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Color.accentColor)
                Spacer(minLength: 4)
                Text(DashboardL10n.format("dashboard.chart.hover_io_cache_format", "In %@ · Out %@ · Cache %@", DashboardTokenFormatter.compact(summary?.inputTokens ?? totalIn), DashboardTokenFormatter.compact(summary?.outputTokens ?? totalOut), DashboardTokenFormatter.compact(summary?.cacheTokens ?? totalCache)))
                    .font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(.primary).lineLimit(1)
            }
            if let summary, !summary.cliShares.isEmpty {
                Text(summary.cliShares.map { "\($0.cli.shortLabel) \(DashboardTokenFormatter.compact($0.tokens))" }.joined(separator: " · "))
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(periodCLISummaryText).font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.neutrals.inner))
    }

    private var periodCLISummaryText: String {
        var byCLI: [DashboardCLIFilter: UInt64] = [:]
        for pt in activePoints { byCLI[pt.cliFilter, default: 0] += pt.totalTokens }
        return byCLI.sorted { $0.value > $1.value }.map { "\($0.key.shortLabel) \(DashboardTokenFormatter.compact($0.value))" }.joined(separator: " · ")
    }

    private var hourlyTrendChart: some View {
        Chart {
            ForEach(activePoints) { point in
                if let date = point.bucketDate {
                    let isSelected = selectedCategory == nil || selectedCategory == point.category
                    let tokenMillions = Double(point.totalTokens) / 1_000_000.0
                    AreaMark(x: .value("Time", date), y: .value(DashboardL10n.tr("dashboard.chart.axis_invocations", "Total Tokens (M)"), tokenMillions))
                        .foregroundStyle(by: .value("CLI", point.category)).opacity(isSelected ? 0.25 : 0.08).interpolationMethod(.monotone)
                    LineMark(x: .value("Time", date), y: .value(DashboardL10n.tr("dashboard.chart.axis_invocations", "Total Tokens (M)"), tokenMillions))
                        .foregroundStyle(by: .value("CLI", point.category)).lineStyle(StrokeStyle(lineWidth: 2.0)).opacity(isSelected ? 1.0 : 0.30).interpolationMethod(.monotone)
                }
            }
            if let hoveredBucketLabel, let hoveredDate = activePoints.first(where: { $0.bucketLabel == hoveredBucketLabel })?.bucketDate {
                RuleMark(x: .value("Time", hoveredDate)).foregroundStyle(Color.accentColor.opacity(0.55)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .frame(height: 210).chartLegend(position: .bottom, alignment: .leading)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                    guard case let .active(location) = phase, let plotFrame = proxy.plotFrame else {
                        if hoveredBucketLabel != nil { hoveredBucketLabel = nil }
                        return
                    }
                    let xPos = location.x - geo[plotFrame].origin.x
                    guard xPos >= 0, xPos <= geo[plotFrame].width, let date: Date = proxy.value(atX: xPos) else {
                        if hoveredBucketLabel != nil { hoveredBucketLabel = nil }
                        return
                    }
                    let next = TrendDataPoint.nearestHourlyBucketLabel(to: date, in: activePoints)
                    if hoveredBucketLabel != next { hoveredBucketLabel = next }
                }
            }
        }
        .accessibilityLabel(DashboardL10n.tr("dashboard.chart.accessibility_label", "Agent invocations by CLI chart"))
    }

    private var dailyBarChart: some View {
        Chart {
            ForEach(dailySegments) { seg in
                let isSelected = selectedCategory == nil || selectedCategory == seg.category
                let isHovered = hoveredBucketLabel == nil || hoveredBucketLabel == seg.bucketLabel
                BarMark(x: .value("Date", seg.bucketLabel), y: .value(DashboardL10n.tr("dashboard.chart.axis_invocations", "Total Tokens (M)"), seg.tokenMillions))
                    .position(by: .value("Kind", seg.kindTitle))
                    .foregroundStyle(by: .value("CLI", seg.category))
                    .opacity((isSelected && isHovered) ? 1.0 : 0.32)
            }
            if let hoveredBucketLabel {
                RuleMark(x: .value("Date", hoveredBucketLabel))
                    .foregroundStyle(Color.accentColor.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .chartYScale(type: .symmetricLog(slopeAtZero: 0.1))
        .frame(height: 210)
        .chartLegend(position: .bottom, alignment: .leading)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                    guard case let .active(location) = phase, let plotFrame = proxy.plotFrame else {
                        if hoveredBucketLabel != nil { hoveredBucketLabel = nil }
                        return
                    }
                    let xPos = location.x - geo[plotFrame].origin.x
                    guard xPos >= 0, xPos <= geo[plotFrame].width, let bucket: String = proxy.value(atX: xPos) else {
                        if hoveredBucketLabel != nil { hoveredBucketLabel = nil }
                        return
                    }
                    if hoveredBucketLabel != bucket { hoveredBucketLabel = bucket }
                }
            }
        }
        .accessibilityLabel(DashboardL10n.tr("dashboard.chart.accessibility_label", "Agent invocations by CLI chart"))
    }
}

public struct CLICostQuotaCardView: View {
    public let entries: [CLICostQuotaEntry]
    public let todayTotalUSD: Double
    public let periodTotalUSD: Double
    public var selectedCategory: String?
    public var onSelectCategory: ((String) -> Void)?
    private let theme = Theme.system

    public init(
        entries: [CLICostQuotaEntry], todayTotalUSD: Double, periodTotalUSD: Double,
        selectedCategory: String? = nil, onSelectCategory: ((String) -> Void)? = nil
    ) {
        self.entries = entries; self.todayTotalUSD = todayTotalUSD; self.periodTotalUSD = periodTotalUSD
        self.selectedCategory = selectedCategory; self.onSelectCategory = onSelectCategory
    }

    public var body: some View {
        let pool = QuotaPoolSummary.summarize(entries: entries)
        let quotaEntries = entries.filter { $0.hasTrackedQuota || !$0.authState.isAuthenticated }
        let throughputEntries = entries.sorted { $0.totalTokens > $1.totalTokens }
        return SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.card.cli_cost.title", "Multi-CLI Token & Quota Monitor"),
            subtitle: DashboardL10n.tr("dashboard.card.cli_cost.subtitle_split", "Top: weekly quota headroom · Bottom: all-channel token throughput"),
            symbolName: "sparkles"
        ) {
            poolHeaderPill(pool: pool)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if !quotaEntries.isEmpty {
                    Text(DashboardL10n.tr("dashboard.quota.section_headroom", "1. QUOTA HEADROOM (CAPPED CHANNELS)"))
                        .font(.system(.caption2, design: .rounded, weight: .bold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 180), spacing: 10), count: min(max(quotaEntries.count, 1), 3)), spacing: 10) {
                        ForEach(quotaEntries) { entry in quotaHeadroomCard(entry, isRecommended: entry.id == pool.recommendedEntry?.id) }
                    }
                }
                Text(DashboardL10n.tr("dashboard.quota.section_throughput", "2. TOKEN THROUGHPUT (TODAY / 7D / CACHE)"))
                    .font(.system(.caption2, design: .rounded, weight: .bold)).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 140), spacing: 10), count: min(max(throughputEntries.count, 1), 4)), spacing: 10) {
                    ForEach(throughputEntries) { entry in
                        tokenThroughputCell(entry, isTopVolume: entry.id == throughputEntries.first?.id && entry.totalTokens > 0)
                    }
                }
            }
        }
    }

    private func poolHeaderPill(pool: QuotaPoolSummary) -> some View {
        let poolTint = DashboardSemanticColorPalette.color(for: pool.health)
        let avgRemPct = max(0, 100 - Int((pool.averageUsedFraction * 100).rounded()))
        let text: String = {
            if let rec = pool.recommendedEntry {
                return DashboardL10n.format("dashboard.quota.pool_pill_format", "Pool Left %lld%% · Route → %@", avgRemPct, rec.displayName)
            }
            return DashboardL10n.format("menubar.pulse.pool_remaining_format", "Pool Left %lld%%", avgRemPct)
        }()
        return HStack(spacing: 5) {
            Image(systemName: "bolt.horizontal.circle.fill").font(.caption2)
            Text(text).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(poolTint.opacity(0.14), in: Capsule())
        .foregroundStyle(poolTint)
    }

    private func quotaHeadroomCard(_ entry: CLICostQuotaEntry, isRecommended: Bool) -> some View {
        let tint = DashboardSemanticColorPalette.color(for: entry.health)
        let usedPct = Int((entry.usedFraction * 100).rounded())
        let remPct = max(0, 100 - usedPct)
        let badgeColor: Color = isRecommended ? .accentColor : tint
        let badgeText = entry.authState.badgeTitle
            ?? (isRecommended ? DashboardL10n.tr("dashboard.quota.recommended_badge", "⚡ Recommended") : entry.health.label)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(entry.displayName).font(.subheadline.weight(.bold)).lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    if !entry.authState.isAuthenticated {
                        Image(systemName: entry.health.symbolName).font(.caption2)
                    }
                    Text(badgeText)
                }
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(badgeColor.opacity(0.15), in: Capsule())
                .foregroundStyle(badgeColor)
            }
            if let authBadge = entry.authState.badgeTitle, entry.authState.isAuthError {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: entry.health.symbolName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(tint)
                    Text(authBadge)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(tint)
                    Spacer(minLength: 4)
                }
                Divider().padding(.vertical, 3)
                HStack(spacing: 8) {
                    Text(entry.authState.statusReasonText ?? "")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let cmd = entry.authState.loginCommand {
                        Button {
                            CLITerminalLoginLauncher.launchLoginInTerminal(command: cmd)
                        } label: {
                            Label(
                                DashboardL10n.tr("dashboard.auth.login_terminal_button", "Login in Terminal"),
                                systemImage: "terminal.fill"
                            )
                            .font(.caption2.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(tint)
                        .controlSize(.small)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(remPct)%")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                    Text(DashboardL10n.tr("dashboard.quota.remaining_short", "remaining"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                }
                Gauge(value: entry.usedFraction, in: 0...1) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity).labelsHidden().tint(tint)
                HStack(spacing: 6) {
                    if let secUsed = entry.secondaryQuotaUsed, let secLabel = entry.secondaryQuotaLabel {
                        Text("\(secLabel): \(Int((secUsed * 100).rounded()))%")
                    } else {
                        Text(DashboardL10n.format("dashboard.quota.used_short_format", "Used %lld%%", usedPct))
                    }
                    Spacer(minLength: 4)
                    Text(entry.authState.statusReasonText ?? entry.quotaResetText ?? entry.quotaLabel ?? "")
                }
                .font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(!entry.authState.isAuthenticated ? tint.opacity(0.10) : (isRecommended ? theme.primary.primary.opacity(0.10) : theme.neutrals.inner))
        )
        .accessibilityElement(children: .combine)
    }

    private func tokenThroughputCell(_ entry: CLICostQuotaEntry, isTopVolume: Bool) -> some View {
        let todayCompact = DashboardTokenFormatter.compact(entry.totalTokens)
        let periodCompact = DashboardTokenFormatter.compact(entry.periodTotalTokens)
        let cachePct = Int((entry.cacheHitFraction * 100).rounded())
        let isSelected = selectedCategory == entry.displayName || selectedCategory == entry.cliFilter.rawValue
        let tint = DashboardSemanticColorPalette.color(for: entry.health)
        let tailText: String = {
            if let hint = entry.authState.loginCommandHint, !entry.authState.isAuthenticated {
                return "7d \(periodCompact) · \(hint)"
            }
            return entry.cacheTokens > 0
                ? "7d \(periodCompact) · Cache \(cachePct)%"
                : "7d \(periodCompact) · \(entry.interactionCount) calls"
        }()
        let deviceText = entry.deviceContributions.prefix(2).map { "\($0.machineAlias) \($0.formattedShare)" }.joined(separator: " · ")
        let detailText = deviceText.isEmpty ? tailText : "\(tailText) · \(deviceText)"

        return Button {
            if let cmd = entry.authState.loginCommand {
                CLITerminalLoginLauncher.launchLoginInTerminal(command: cmd)
            } else {
                onSelectCategory?(entry.displayName)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(entry.displayName).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 2)
                    if let badge = entry.authState.badgeTitle {
                        HStack(spacing: 3) {
                            Image(systemName: entry.authState.loginCommand != nil ? "terminal.fill" : entry.health.symbolName)
                            Text(badge)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                    } else if isSelected {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill").font(.caption2).foregroundStyle(theme.primary.primary)
                    } else if isTopVolume {
                        Image(systemName: "flame.fill").font(.caption2).foregroundStyle(theme.neutrals.text2)
                    }
                }
                Text(todayCompact)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundStyle(theme.neutrals.text1).contentTransition(.numericText())
                HStack(spacing: 4) {
                    Text(detailText)
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(entry.authState.isAuthenticated ? Color.secondary : tint)
                        .lineLimit(1)
                    if entry.authState.loginCommand != nil {
                        Spacer(minLength: 2)
                        Image(systemName: "terminal.fill")
                            .font(.caption2)
                            .foregroundStyle(tint)
                    }
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? theme.primary.primary.opacity(0.12) : theme.neutrals.inner)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(entry.displayName) (\(entry.modelTag)) — \(entry.authState.statusReasonText ?? "Today \(todayCompact) tok") · 7d \(periodCompact) tok")
        .accessibilityElement(children: .combine)
    }
}

public enum AgentEfficiencyWorkloadMetric: String, CaseIterable, Identifiable {
    case runs
    case tokens

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .runs:
            return DashboardL10n.tr("dashboard.agent_efficiency.metric_runs", "Task Runs")
        case .tokens:
            return DashboardL10n.tr("dashboard.agent_efficiency.metric_tokens", "Token Share")
        }
    }
}

public struct AgentEfficiencyChartsCardView: View {
    public let summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?
    @State private var workloadMetric: AgentEfficiencyWorkloadMetric = .runs
    @Environment(\.locale) private var locale
    private let theme = Theme.system

    public init(summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?) {
        self.summary = summary
    }

    private var workbench: AgentEfficiencyWorkbenchSnapshot? {
        summary?.agentEfficiency
    }

    public var body: some View {
        SolidModularCardContainer(
            title: DashboardL10n.tr(
                "dashboard.agent_efficiency.title",
                "Agent Role Division & Multi-Round Collaboration"
            ),
            subtitle: subtitleText,
            symbolName: "chart.xyaxis.line"
        ) {
            coverageBadge
        } content: {
            if let snapshot = workbench, snapshot.sampleSize > 0 {
                VStack(alignment: .leading, spacing: 14) {
                    kpiSummaryStrip(snapshot)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            roleDivisionPanel(snapshot)
                            reviewRoundPanel(snapshot)
                        }
                        .frame(minWidth: 760)
                        VStack(alignment: .leading, spacing: 14) {
                            roleDivisionPanel(snapshot)
                            reviewRoundPanel(snapshot)
                        }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            stageDurationPanel(snapshot)
                            dailyThroughputPanel(snapshot)
                        }
                        .frame(minWidth: 760)
                        VStack(alignment: .leading, spacing: 14) {
                            stageDurationPanel(snapshot)
                            dailyThroughputPanel(snapshot)
                        }
                    }
                    if let retro = snapshot.agentRetro {
                        AgentRetroTrajectoryPanelsView(retro: retro)
                    }
                }
            } else {
                emptyStatePanel
            }
        }
        .accessibilityIdentifier("dashboard.agentEfficiencyChartsCard")
    }

    private var subtitleText: String {
        guard let snapshot = workbench, snapshot.sampleSize > 0 else {
            return DashboardL10n.tr(
                "dashboard.agent_efficiency.subtitle_empty",
                "Read-only personal workflow telemetry · awaiting observed receipts"
            )
        }
        let asOf = snapshot.sourceAsOf ?? snapshot.windowEnd ?? "—"
        return DashboardL10n.format(
            "dashboard.agent_efficiency.subtitle_format",
            "Window %@ · Updated %@ · %lld observed runs",
            snapshot.windowCST,
            asOf,
            snapshot.sampleSize
        )
    }

    @ViewBuilder
    private var coverageBadge: some View {
        let status = workbench?.coverageStatus ?? "missing"
        let health: DashboardSemanticHealth = {
            switch status {
            case "healthy": return .healthy
            case "partial": return .warning
            case "error": return .critical
            default: return .neutral
            }
        }()
        let tint = DashboardSemanticColorPalette.color(for: health)
        HStack(spacing: 5) {
            Image(systemName: health.symbolName)
                .font(.caption2)
            Text(coverageLabel(for: status))
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
        .foregroundStyle(tint)
    }

    private func coverageLabel(for status: String) -> String {
        switch status {
        case "healthy":
            return DashboardL10n.tr("dashboard.agent_efficiency.coverage_healthy", "Observed")
        case "partial":
            return DashboardL10n.tr("dashboard.agent_efficiency.coverage_partial", "Partial")
        case "error":
            return DashboardL10n.tr("dashboard.agent_efficiency.coverage_error", "Degraded")
        default:
            return DashboardL10n.tr("dashboard.agent_efficiency.coverage_unknown", "No Sample")
        }
    }

    private var emptyStatePanel: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(DashboardL10n.tr(
                    "dashboard.agent_efficiency.empty_title",
                    "No Agent Collaboration Observations Yet"
                ))
                .font(.subheadline.weight(.semibold))
                Text(DashboardL10n.tr(
                    "dashboard.agent_efficiency.empty_desc",
                    "Run the daily aidata digest pipeline to populate role division, review rounds, stage duration, and daily throughput."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.neutrals.inner)
        )
    }

    private func kpiSummaryStrip(_ snapshot: AgentEfficiencyWorkbenchSnapshot) -> some View {
        let round = snapshot.roundSummary
        let passRateText = round.r1PassRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
        let passHealth: DashboardSemanticHealth = {
            guard let rate = round.r1PassRate else { return .neutral }
            if rate >= 0.70 { return .healthy }
            if rate >= 0.50 { return .warning }
            return .critical
        }()
        let multiRoundTotal = round.r2Count + round.r3PlusCount
        let multiHealth: DashboardSemanticHealth = round.r3PlusCount > 10 ? .warning : .healthy
        let medText = formatDuration(round.medianDurationSec)
        let p90Text = formatDuration(round.p90DurationSec)
        let steeringPct = round.steeringTokenShare.map { Int(($0 * 100).rounded()) }
        let execPct = steeringPct.map { max(0, 100 - $0) }
        let tokenSplitValue = steeringPct.map { "\($0)% / \(execPct ?? 0)%" } ?? "—"

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 195), spacing: 10), count: 4),
            spacing: 10
        ) {
            kpiTile(
                title: DashboardL10n.tr("dashboard.agent_efficiency.kpi_first_pass", "First-Pass Review Rate"),
                value: passRateText,
                detail: DashboardL10n.format(
                    "dashboard.agent_efficiency.kpi_first_pass_detail_format",
                    "%lld of %lld evaluated tasks",
                    round.r1Count,
                    round.evaluatedTasks
                ),
                symbol: "checkmark.seal.fill",
                health: passHealth
            )
            kpiTile(
                title: DashboardL10n.tr("dashboard.agent_efficiency.kpi_multi_round", "Multi-Round Rework Tasks"),
                value: "\(multiRoundTotal)",
                detail: DashboardL10n.format(
                    "dashboard.agent_efficiency.kpi_multi_round_detail_format",
                    "r2: %lld · r3+: %lld",
                    round.r2Count,
                    round.r3PlusCount
                ),
                symbol: "arrow.triangle.2.circlepath",
                health: multiHealth
            )
            kpiTile(
                title: DashboardL10n.tr("dashboard.agent_efficiency.kpi_stage_duration", "Stage Duration (Median / P90)"),
                value: "\(medText) / \(p90Text)",
                detail: round.ttftP90Sec.map {
                    DashboardL10n.format(
                        "dashboard.agent_efficiency.kpi_ttft_detail_format",
                        "Gateway P90 TTFT %.1fs",
                        $0
                    )
                } ?? DashboardL10n.tr(
                    "dashboard.agent_efficiency.kpi_duration_detail_default",
                    "Dispatch to completion span"
                ),
                symbol: "timer",
                health: .neutral
            )
            kpiTile(
                title: DashboardL10n.tr("dashboard.agent_efficiency.kpi_token_split", "Coordination vs Execution"),
                value: tokenSplitValue,
                detail: round.cacheHitRate.map {
                    DashboardL10n.format(
                        "dashboard.agent_efficiency.kpi_cache_detail_format",
                        "KV Cache Hit %lld%%",
                        Int(($0 * 100).rounded())
                    )
                } ?? DashboardL10n.tr(
                    "dashboard.agent_efficiency.kpi_token_split_detail_default",
                    "Lead vs implementation token share"
                ),
                symbol: "chart.pie.fill",
                health: .healthy
            )
        }
    }

    private func kpiTile(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        health: DashboardSemanticHealth
    ) -> some View {
        let tint = DashboardSemanticColorPalette.color(for: health)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(detail)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.neutrals.inner)
        )
    }

    private func roleDivisionPanel(_ snapshot: AgentEfficiencyWorkbenchSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(DashboardL10n.tr(
                        "dashboard.agent_efficiency.chart_role_title",
                        "Role Division & Workload Split"
                    ))
                    .font(.subheadline.weight(.bold))
                    Spacer(minLength: 4)
                    Picker(
                        DashboardL10n.tr("dashboard.agent_efficiency.metric_picker", "Metric"),
                        selection: $workloadMetric
                    ) {
                        ForEach(AgentEfficiencyWorkloadMetric.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize(horizontal: true, vertical: false)
                }
                Text(DashboardL10n.tr(
                    "dashboard.agent_efficiency.chart_role_subtitle",
                    "Task executions and token share across coordination and leaf roles"
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            Chart(snapshot.roles) { role in
                let label = localizedRoleTitle(role)
                let val: Double = workloadMetric == .runs
                    ? Double(role.runsCount)
                    : role.tokenSharePct
                BarMark(
                    x: .value(workloadMetric.title, val),
                    y: .value("Role", label)
                )
                .foregroundStyle(roleTint(for: role.roleKey))
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(
                        workloadMetric == .runs
                            ? "\(role.runsCount)"
                            : String(format: "%.1f%%", role.tokenSharePct)
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 210)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.neutrals.inner)
        )
    }

    private struct RoundBarSegment: Identifiable {
        let id: String
        let roleLabel: String
        let tierTitle: String
        let count: Int
        let color: Color
    }

    private func reviewRoundPanel(_ snapshot: AgentEfficiencyWorkbenchSnapshot) -> some View {
        let r1Title = DashboardL10n.tr("dashboard.agent_efficiency.round_r1", "r1 First-Pass")
        let r2Title = DashboardL10n.tr("dashboard.agent_efficiency.round_r2", "r2 Second-Round")
        let r3Title = DashboardL10n.tr("dashboard.agent_efficiency.round_r3_plus", "r3+ Multi-Round")
        let activeRoles = snapshot.roles.filter { ($0.r1Count + $0.r2Count + $0.r3PlusCount) > 0 }
        let segments: [RoundBarSegment] = activeRoles.flatMap { role in
            let label = localizedRoleTitle(role)
            return [
                RoundBarSegment(id: "\(role.roleKey)-r1", roleLabel: label, tierTitle: r1Title, count: role.r1Count, color: .green),
                RoundBarSegment(id: "\(role.roleKey)-r2", roleLabel: label, tierTitle: r2Title, count: role.r2Count, color: .orange),
                RoundBarSegment(id: "\(role.roleKey)-r3", roleLabel: label, tierTitle: r3Title, count: role.r3PlusCount, color: .red),
            ]
        }

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DashboardL10n.tr(
                    "dashboard.agent_efficiency.chart_rounds_title",
                    "Review Convergence & Round Distribution"
                ))
                .font(.subheadline.weight(.bold))
                Text(DashboardL10n.tr(
                    "dashboard.agent_efficiency.chart_rounds_subtitle",
                    "First-pass completion (r1) vs second-round (r2) and multi-round rework (r3+)"
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            Chart(segments) { seg in
                BarMark(
                    x: .value("Tasks", seg.count),
                    y: .value("Role", seg.roleLabel)
                )
                .foregroundStyle(by: .value("Round", seg.tierTitle))
            }
            .chartForegroundStyleScale([
                r1Title: Color.green,
                r2Title: Color.orange,
                r3Title: Color.red,
            ])
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(minHeight: 210)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.neutrals.inner)
        )
    }

    private struct DurationBarItem: Identifiable {
        let id: String
        let roleLabel: String
        let percentileTitle: String
        let minutes: Double
    }

    private func stageDurationPanel(_ snapshot: AgentEfficiencyWorkbenchSnapshot) -> some View {
        let medTitle = DashboardL10n.tr("dashboard.agent_efficiency.duration_median", "Median (min)")
        let p90Title = DashboardL10n.tr("dashboard.agent_efficiency.duration_p90", "P90 Tail (min)")
        let rolesWithDur = snapshot.roles.filter { ($0.medianDurationSec ?? 0) > 0 || ($0.p90DurationSec ?? 0) > 0 }
        let items: [DurationBarItem] = rolesWithDur.flatMap { role in
            let label = localizedRoleTitle(role)
            let medMin = max((role.medianDurationSec ?? 0) / 60.0, 0.05)
            let p90Min = max((role.p90DurationSec ?? 0) / 60.0, medMin)
            return [
                DurationBarItem(id: "\(role.roleKey)-med", roleLabel: label, percentileTitle: medTitle, minutes: medMin),
                DurationBarItem(id: "\(role.roleKey)-p90", roleLabel: label, percentileTitle: p90Title, minutes: p90Min),
            ]
        }

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DashboardL10n.tr(
                    "dashboard.agent_efficiency.chart_duration_title",
                    "Stage Duration Median vs P90"
                ))
                .font(.subheadline.weight(.bold))
                Text(DashboardL10n.tr(
                    "dashboard.agent_efficiency.chart_duration_subtitle",
                    "Stage turnaround time in minutes exposing long-tail bottlenecks"
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            if items.isEmpty {
                Text(DashboardL10n.tr(
                    "dashboard.agent_efficiency.duration_empty",
                    "No paired task dispatch-to-completion timestamps in current window."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 190, alignment: .center)
            } else {
                Chart(items) { item in
                    BarMark(
                        x: .value("Minutes", item.minutes),
                        y: .value("Role", item.roleLabel)
                    )
                    .position(by: .value("Percentile", item.percentileTitle))
                    .foregroundStyle(by: .value("Percentile", item.percentileTitle))
                    .cornerRadius(3)
                }
                .chartXScale(type: .symmetricLog(slopeAtZero: 0.5))
                .chartForegroundStyleScale([
                    medTitle: Color.accentColor,
                    p90Title: Color.orange,
                ])
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(minHeight: 210)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.neutrals.inner)
        )
    }

    private func dailyThroughputPanel(_ snapshot: AgentEfficiencyWorkbenchSnapshot) -> some View {
        let tasksTitle = DashboardL10n.tr("dashboard.agent_efficiency.daily_tasks", "Completed Tasks")
        let goalsTitle = DashboardL10n.tr("dashboard.agent_efficiency.daily_goals", "Completed Goals")

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(DashboardL10n.tr(
                        "dashboard.agent_efficiency.chart_daily_title",
                        "Daily Goal Throughput & Token Trend"
                    ))
                    .font(.subheadline.weight(.bold))
                    Spacer(minLength: 4)
                    let totalTok = snapshot.dailySeries.reduce(UInt64(0)) { $0 + $1.totalTokens }
                    if totalTok > 0 {
                        Text("14d \(DashboardTokenFormatter.compact(totalTok)) tok")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(DashboardL10n.tr(
                    "dashboard.agent_efficiency.chart_daily_subtitle",
                    "14-day completed tasks, goals, and daily token volume"
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            if snapshot.dailySeries.isEmpty {
                Text(DashboardL10n.tr(
                    "dashboard.agent_efficiency.daily_empty",
                    "No daily series recorded yet."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 190, alignment: .center)
            } else {
                Chart {
                    ForEach(snapshot.dailySeries) { pt in
                        BarMark(
                            x: .value("Day", pt.shortDayLabel),
                            y: .value(tasksTitle, pt.tasksCompleted)
                        )
                        .foregroundStyle(by: .value("Metric", tasksTitle))
                        .cornerRadius(3)

                        LineMark(
                            x: .value("Day", pt.shortDayLabel),
                            y: .value(goalsTitle, pt.goalsCompleted)
                        )
                        .foregroundStyle(by: .value("Metric", goalsTitle))
                        .lineStyle(StrokeStyle(lineWidth: 2.0))
                        .symbol(Circle())
                    }
                }
                .chartForegroundStyleScale([
                    tasksTitle: Color.accentColor.opacity(0.78),
                    goalsTitle: Color.green,
                ])
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(minHeight: 210)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.neutrals.inner)
        )
    }

    private func localizedRoleTitle(_ role: AgentRoleEfficiencyRow) -> String {
        AgentEfficiencyFormatting.localizedRoleTitle(role, locale: locale)
    }

    private func roleTint(for key: String) -> Color {
        AgentEfficiencyFormatting.roleTint(for: key)
    }

    private func formatDuration(_ seconds: Double?) -> String {
        AgentEfficiencyFormatting.formatDuration(seconds)
    }
}

private enum AgentEfficiencyFormatting {
    static func localizedRoleTitle(_ role: AgentRoleEfficiencyRow, locale: Locale) -> String {
        switch role.roleKey {
        case "m3": return DashboardL10n.tr("dashboard.agent_efficiency.role.top_coordinator", "Top-Level Coordinator")
        case "m2": return DashboardL10n.tr("dashboard.agent_efficiency.role.topic_dispatcher", "Topic Dispatcher")
        case "m1": return DashboardL10n.tr("dashboard.agent_efficiency.role.goal_lead", "Goal Lead (TL)")
        case "designer": return DashboardL10n.tr("dashboard.agent_efficiency.role.designer", "Visual Design (Designer)")
        case "writer": return DashboardL10n.tr("dashboard.agent_efficiency.role.writer", "Code Implementation (Writer)")
        case "reviewer": return DashboardL10n.tr("dashboard.agent_efficiency.role.reviewer", "Independent Review (Reviewer)")
        case "explorer": return DashboardL10n.tr("dashboard.agent_efficiency.role.explorer", "Code Exploration (Explorer)")
        case "pr_monitor": return DashboardL10n.tr("dashboard.agent_efficiency.role.pr_monitor", "Delivery Monitor (PR Monitor)")
        default:
            let isZh = locale.language.languageCode?.identifier.hasPrefix("zh") == true
            return isZh ? role.roleLabel : (role.roleLabelEn ?? role.roleLabel)
        }
    }

    static func roleTint(for key: String) -> Color {
        switch key {
        case "m3", "m2", "m1": return .indigo
        case "designer": return .purple
        case "writer": return .accentColor
        case "reviewer": return .teal
        case "explorer": return .cyan
        case "pr_monitor": return .orange
        default: return .secondary
        }
    }

    static func formatDuration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        if seconds < 3600 { return String(format: "%.1fm", seconds / 60.0) }
        return String(format: "%.1fh", seconds / 3600.0)
    }
}
#endif
