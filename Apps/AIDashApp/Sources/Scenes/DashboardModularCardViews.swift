#if os(macOS)
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
            Gauge(value: clamped, in: 0...1) { Text(title) }.gaugeStyle(.accessoryLinearCapacity).tint(tint)
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

    public init(metrics: [KPIMetricItem]) {
        self.metrics = metrics
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
        return VStack(alignment: .leading, spacing: 6) {
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
        .accessibilityElement(children: .combine)
    }
}

public struct TrendChartCardView: View {
    public let points: [TrendDataPoint]
    public let selectedCategory: String?
    public let onSelectCategory: (String) -> Void
    public let onClearSelection: () -> Void
    @State private var timeGranularity: DashboardChartTimeGranularity = .sevenDayDaily

    public init(
        points: [TrendDataPoint],
        selectedCategory: String?,
        onSelectCategory: @escaping (String) -> Void,
        onClearSelection: @escaping () -> Void
    ) {
        self.points = points
        self.selectedCategory = selectedCategory
        self.onSelectCategory = onSelectCategory
        self.onClearSelection = onClearSelection
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
                    ForEach(DashboardChartTimeGranularity.allCases) { gran in
                        Text(gran.displayTitle).tag(gran)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)

                if let selectedCategory {
                    Button {
                        onClearSelection()
                    } label: {
                        Label(
                            DashboardL10n.format("dashboard.chart.clear_filter_format", "Filter: %@ ×", selectedCategory),
                            systemImage: "line.3.horizontal.decrease.circle.fill"
                        )
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minHeight: 28)
                }
            }
        } content: {
            let categoryTotals = Self.groupedCategoryTotals(from: activePoints, kind: .all)
            VStack(alignment: .leading, spacing: 10) {
                TrendChartInteractiveCanvas(
                    rawPoints: points,
                    activePoints: activePoints,
                    dailySegments: dailySegments,
                    selectedCategory: selectedCategory,
                    timeGranularity: timeGranularity
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text(DashboardL10n.tr("dashboard.chart.quick_filter", "Quick Cross-Filter:"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(categoryTotals, id: \.category) { item in
                            let active = selectedCategory == item.category
                            Button {
                                onSelectCategory(item.category)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                    Text(item.category)
                                    Text("\(DashboardTokenFormatter.compact(item.tokens)) tok")
                                        .monospacedDigit()
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(active ? .accentColor : .secondary)
                            .controlSize(.small)
                            .frame(minHeight: 28)
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
        Group {
            if timeGranularity == .threeDayHourly, activePoints.contains(where: { $0.bucketDate != nil }) {
                hourlyTrendChart
            } else {
                dailyBarChart
            }
        }
        .overlay(alignment: .topLeading) {
            if let hoverSummary {
                hoverOverlayBadge(summary: hoverSummary)
                    .allowsHitTesting(false)
            }
        }
    }

    private func hoverOverlayBadge(summary: TrendBucketHoverSummary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            Text(summary.formattedReadout)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(DashboardL10n.format("dashboard.chart.hover_calls_format", "%lld calls", summary.invocations))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var hourlyTrendChart: some View {
        Chart {
            ForEach(activePoints) { point in
                if let date = point.bucketDate {
                    let isSelected = selectedCategory == nil || selectedCategory == point.category
                    let tokenMillions = Double(point.totalTokens) / 1_000_000.0
                    AreaMark(x: .value("Time", date), y: .value(DashboardL10n.tr("dashboard.chart.axis_invocations", "Total Tokens (M)"), tokenMillions))
                        .foregroundStyle(by: .value("CLI", point.category))
                        .opacity(isSelected ? 0.25 : 0.08)
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", date), y: .value(DashboardL10n.tr("dashboard.chart.axis_invocations", "Total Tokens (M)"), tokenMillions))
                        .foregroundStyle(by: .value("CLI", point.category))
                        .lineStyle(StrokeStyle(lineWidth: 2.0))
                        .opacity(isSelected ? 1.0 : 0.30)
                        .interpolationMethod(.monotone)
                }
            }
            if let hoveredBucketLabel,
               let hoveredDate = activePoints.first(where: { $0.bucketLabel == hoveredBucketLabel })?.bucketDate {
                RuleMark(x: .value("Time", hoveredDate))
                    .foregroundStyle(Color.accentColor.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
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

    public init(
        entries: [CLICostQuotaEntry],
        todayTotalUSD: Double,
        periodTotalUSD: Double
    ) {
        self.entries = entries
        self.todayTotalUSD = todayTotalUSD
        self.periodTotalUSD = periodTotalUSD
    }

    public var body: some View {
        let todayTotal = entries.reduce(UInt64(0)) { $0 + $1.totalTokens }
        let periodTotal = entries.reduce(UInt64(0)) { $0 + $1.periodTotalTokens }
        let pool = QuotaPoolSummary.summarize(entries: entries)
        return SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.card.cli_cost.title", "Multi-CLI Token & Quota Monitor"),
            subtitle: DashboardL10n.tr("dashboard.card.cli_cost.subtitle", "Overall quota pool balance, routing recommendation, and multi-window telemetry"),
            symbolName: "sparkles"
        ) {
            HStack(spacing: 12) {
                LabeledContent(DashboardL10n.tr("dashboard.cli_cost.today", "Today Total")) {
                    Text(DashboardTokenFormatter.compact(todayTotal))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                LabeledContent(DashboardL10n.tr("dashboard.cli_cost.cycle", "7d Total")) {
                    Text(DashboardTokenFormatter.compact(periodTotal))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                quotaPoolOverviewStrip(pool: pool)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 240), spacing: 10),
                        GridItem(.flexible(minimum: 240), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(entries) { entry in
                        cliQuotaTile(entry)
                    }
                }
            }
        }
    }

    private func quotaPoolOverviewStrip(pool: QuotaPoolSummary) -> some View {
        let poolTint = DashboardSemanticColorPalette.color(for: pool.health)
        let avgUsedPct = Int((pool.averageUsedFraction * 100).rounded())
        let avgRemPct = max(0, 100 - avgUsedPct)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.pie.fill").foregroundStyle(poolTint)
                    Text(DashboardL10n.tr("dashboard.quota.pool_title", "Overall Quota Pool")).font(.caption.weight(.semibold))
                    Text(DashboardL10n.format("dashboard.quota.pool_used_rem_format", "Used %lld%% · Left %lld%%", avgUsedPct, avgRemPct))
                        .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(poolTint)
                }
                Gauge(value: pool.averageUsedFraction, in: 0...1) {
                    Text(DashboardL10n.tr("dashboard.quota.pool_title", "Overall Quota Pool"))
                }
                .gaugeStyle(.accessoryLinearCapacity).tint(poolTint).frame(maxWidth: 220)
            }
            Divider().frame(height: 28)
            if let rec = pool.recommendedEntry {
                let recRemPct = Int((rec.remainingFraction * 100).rounded())
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DashboardL10n.format("dashboard.quota.recommend_route_format", "Recommended Route: %@ (%lld%% remaining)", rec.displayName, recRemPct))
                            .font(.caption.weight(.semibold)).foregroundStyle(.primary)
                        Text(DashboardL10n.format("dashboard.quota.balance_hint_format", "%lld idle channel(s) (<25%% used) · %lld high-load channel(s)", pool.idleChannelCount, pool.pressuredChannelCount))
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 4)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
    }

    private func cliQuotaTile(_ entry: CLICostQuotaEntry) -> some View {
        let tint = DashboardSemanticColorPalette.color(for: entry.health)
        let todayCompact = DashboardTokenFormatter.compact(entry.totalTokens)
        let periodCompact = DashboardTokenFormatter.compact(entry.periodTotalTokens)
        let usedPct = Int((entry.usedFraction * 100).rounded())
        let remPct = max(0, 100 - usedPct)
        let cachePct = Int((entry.cacheHitFraction * 100).rounded())

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: entry.health.symbolName).foregroundStyle(tint)
                Text(entry.displayName).font(.subheadline.weight(.semibold))
                Text(entry.modelTag).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 6)
                if let quotaLabel = entry.quotaLabel {
                    Text("\(quotaLabel) · \(DashboardL10n.format("menubar.pulse.quota_remaining_format", "Left %lld%%", remPct))")
                        .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
                } else {
                    Text(DashboardL10n.tr("dashboard.quota.token_metered", "Token Metered"))
                        .font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.14), in: Capsule()).foregroundStyle(Color.accentColor)
                }
            }
            if entry.quotaLabel != nil {
                Gauge(value: entry.usedFraction, in: 0...1) { Text(entry.displayName) }
                    .gaugeStyle(.accessoryLinearCapacity).tint(tint)
            } else {
                Divider().padding(.vertical, 2)
            }
            HStack(spacing: 8) {
                Text(DashboardL10n.format("dashboard.cli_cost.total_tokens_format", "Today: %@ tok", todayCompact))
                Text(DashboardL10n.format("dashboard.cli_cost.period_tokens_format", "7d: %@ tok", periodCompact))
                Text("Cache \(cachePct)%")
                Spacer(minLength: 4)
                if let secUsed = entry.secondaryQuotaUsed, let secLabel = entry.secondaryQuotaLabel {
                    Text("\(secLabel): \(Int((secUsed * 100).rounded()))%").foregroundStyle(.secondary)
                }
                if let resetText = entry.quotaResetText {
                    Text(resetText).foregroundStyle(.secondary)
                } else {
                    Text(DashboardL10n.format("dashboard.cli_cost.sessions_format", "Calls: %@", entry.interactionCount.formatted(.number)))
                }
            }
            .font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .help("\(entry.displayName) (\(entry.modelTag)) — Today \(todayCompact) tok (Active \(DashboardTokenFormatter.compact(entry.activeTokens)) · Cache \(DashboardTokenFormatter.compact(entry.cacheTokens))) · 7d \(periodCompact) tok · Calls \(entry.interactionCount)")
        .accessibilityElement(children: .combine)
    }
}
#endif
