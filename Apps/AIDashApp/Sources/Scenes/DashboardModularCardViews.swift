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
        title: String,
        subtitle: String? = nil,
        symbolName: String,
        @ViewBuilder accessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.accessory = accessory()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(title, systemImage: symbolName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                .fill(
                    reduceTransparency
                        ? Color(nsColor: .windowBackgroundColor)
                        : Color(nsColor: .controlBackgroundColor)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    contrast == .increased
                        ? Color.primary.opacity(0.28)
                        : Color(nsColor: .separatorColor),
                    lineWidth: contrast == .increased ? 1.5 : 1
                )
        }
    }
}

extension SolidModularCardContainer where HeaderAccessory == EmptyView {
    public init(
        title: String,
        subtitle: String? = nil,
        symbolName: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            accessory: { EmptyView() },
            content: content
        )
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
        title: String,
        symbol: String,
        valueText: String,
        detailText: String,
        fraction: Double,
        health: DashboardSemanticHealth
    ) -> some View {
        let clamped = min(max(fraction, 0), 1)
        let tint = DashboardSemanticColorPalette.color(for: health)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Image(systemName: health.symbolName)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(valueText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Gauge(value: clamped, in: 0...1) {
                Text(title)
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(tint)
            Text(detailText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
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
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 185, maximum: 300), spacing: 12)],
                spacing: 12
            ) {
                ForEach(metrics) { metric in
                    metricTile(metric)
                }
            }
        }
    }

    private func metricTile(_ metric: KPIMetricItem) -> some View {
        let semanticColor = DashboardSemanticColorPalette.color(for: metric.health)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(metric.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: metric.symbolName)
                    .foregroundStyle(semanticColor)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.formattedValue)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit = metric.unit {
                    Text(unit)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                Image(systemName: metric.direction.symbolName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(semanticColor)
                Text(metric.deltaText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .accessibilityElement(children: .combine)
    }
}

public struct TrendChartCardView: View {
    public let points: [TrendDataPoint]
    public let selectedCategory: String?
    public let onSelectCategory: (String) -> Void
    public let onClearSelection: () -> Void

    @State private var chartHoveredCategory: String?

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
        SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.card.trend.title", "Agent Invocations & Spend by CLI"),
            subtitle: DashboardL10n.tr("dashboard.card.trend.subtitle", "Click any bar to cross-filter tables and actionable items below"),
            symbolName: "chart.bar.xaxis"
        ) {
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
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Chart(points) { point in
                    let isSelected = selectedCategory == nil || selectedCategory == point.category
                    BarMark(
                        x: .value("CLI", point.category),
                        y: .value(DashboardL10n.tr("dashboard.chart.axis_invocations", "Invocations"), point.invocations)
                    )
                    .foregroundStyle(by: .value("CLI", point.category))
                    .opacity(isSelected ? 1.0 : 0.30)
                    .annotation(position: .top) {
                        Text("\(point.invocations)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 185)
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXSelection(value: $chartHoveredCategory)
                .onChange(of: chartHoveredCategory) { _, newValue in
                    if let newValue {
                        onSelectCategory(newValue)
                    }
                }
                .accessibilityLabel(DashboardL10n.tr("dashboard.chart.accessibility_label", "Agent invocations by CLI chart"))

                HStack(spacing: 8) {
                    Text(DashboardL10n.tr("dashboard.chart.quick_filter", "Quick Cross-Filter:"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(points) { point in
                        let active = selectedCategory == point.category
                        Button {
                            onSelectCategory(point.category)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                Text(point.bucketLabel)
                                Text("\(DashboardTokenFormatter.compact(point.totalTokens)) tok")
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
        let totalActive = entries.reduce(UInt64(0)) { $0 + $1.activeTokens }
        let totalCache = entries.reduce(UInt64(0)) { $0 + $1.cacheTokens }
        return SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.card.cli_cost.title", "Multi-CLI Token & Quota Monitor"),
            subtitle: DashboardL10n.tr("dashboard.card.cli_cost.subtitle", "Daily active tokens, cache tokens, and quota utilization"),
            symbolName: "sparkles"
        ) {
            HStack(spacing: 12) {
                LabeledContent(DashboardL10n.tr("dashboard.cli_cost.today", "Active")) {
                    Text(DashboardTokenFormatter.compact(totalActive))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                LabeledContent(DashboardL10n.tr("dashboard.cli_cost.cycle", "Cache")) {
                    Text(DashboardTokenFormatter.compact(totalCache))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        } content: {
            VStack(spacing: 10) {
                ForEach(entries) { entry in
                    cliQuotaRow(entry)
                }
            }
        }
    }

    private func cliQuotaRow(_ entry: CLICostQuotaEntry) -> some View {
        let tint = DashboardSemanticColorPalette.color(for: entry.health)
        let activeCompact = DashboardTokenFormatter.compact(entry.activeTokens)
        let totalCompact = DashboardTokenFormatter.compact(entry.activeTokens + entry.cacheTokens)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: entry.health.symbolName)
                    .foregroundStyle(tint)
                Text(entry.displayName)
                    .font(.body.weight(.medium))
                Text(entry.modelTag)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let quotaLabel = entry.quotaLabel {
                    Text(DashboardL10n.format("dashboard.cli_cost.tokens_and_quota_format", "%@ tok · %@", activeCompact, quotaLabel))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                } else {
                    Text("\(activeCompact) / \(totalCompact) tok")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text("\(Int((entry.usedFraction * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .frame(width: 40, alignment: .trailing)
            }
            Gauge(value: entry.usedFraction, in: 0...1) {
                Text(entry.displayName)
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(tint)
            HStack(spacing: 12) {
                Text(DashboardL10n.format("dashboard.cli_cost.active_tokens_format", "Active: %@ tok", entry.activeTokens.formatted(.number)))
                Text(DashboardL10n.format("dashboard.cli_cost.cache_tokens_format", "Cache: %@ tok", entry.cacheTokens.formatted(.number)))
                Text(DashboardL10n.format("dashboard.cli_cost.sessions_format", "Sessions/Turns: %@", entry.interactionCount.formatted(.number)))
                Spacer(minLength: 4)
                Text(DashboardL10n.format("dashboard.cli_cost.total_tokens_format", "Total: %@ tok", totalCompact))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .accessibilityElement(children: .combine)
    }
}
#endif
