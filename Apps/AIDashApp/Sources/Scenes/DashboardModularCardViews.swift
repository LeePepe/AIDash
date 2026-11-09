#if os(macOS)
// swiftlint:disable file_length
import AppKit
import Charts
import SwiftUI
import AIDashUI

public struct SolidModularCardContainer<HeaderAccessory: View, Content: View>: View {
    public let title: String
    public let subtitle: String?
    public let symbolName: String
    private let accessory: HeaderAccessory
    private let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

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
                .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(contrast == .increased ? Color.primary.opacity(0.28) : Color(nsColor: .separatorColor), lineWidth: contrast == .increased ? 1.5 : 1)
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
        switch health {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        case .neutral: return .secondary
        }
    }
}

public struct SystemTelemetryStripView: View {
    public let snapshot: MenuBarSystemSnapshot

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
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .accessibilityElement(children: .combine)
    }
}

public struct KPISummaryCardView: View {
    public let metrics: [KPIMetricItem]
    public var onSelectMetric: ((String) -> Void)?

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
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
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
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
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
                Text(entry.authState.statusReasonText ?? "")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
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
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(!entry.authState.isAuthenticated ? tint.opacity(0.45) : (isRecommended ? Color.accentColor.opacity(0.45) : Color.clear), lineWidth: 1.5)
        }
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

        return Button {
            onSelectCategory?(entry.displayName)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(entry.displayName).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 2)
                    if let badge = entry.authState.badgeTitle {
                        HStack(spacing: 3) {
                            Image(systemName: entry.health.symbolName)
                            Text(badge)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                    } else if isSelected {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill").font(.caption2).foregroundStyle(Color.accentColor)
                    } else if isTopVolume {
                        Image(systemName: "flame.fill").font(.caption2).foregroundStyle(Color.accentColor)
                    }
                }
                Text(todayCompact)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .foregroundStyle(isTopVolume || isSelected ? Color.accentColor : Color.primary).contentTransition(.numericText())
                Text(tailText)
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(entry.authState.isAuthenticated ? Color.secondary : tint)
                    .lineLimit(1)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(entry.displayName) (\(entry.modelTag)) — \(entry.authState.statusReasonText ?? "Today \(todayCompact) tok") · 7d \(periodCompact) tok")
        .accessibilityElement(children: .combine)
    }
}
#endif
