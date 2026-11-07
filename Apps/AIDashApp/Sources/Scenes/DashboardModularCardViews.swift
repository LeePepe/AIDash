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
            title: "Real-Time Machine Telemetry",
            subtitle: "\(snapshot.machine.chipName) · \(snapshot.machine.totalCores) Cores",
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
                        title: "CPU Load",
                        symbol: "cpu",
                        valueText: "\(Int((snapshot.cpu.usage * 100).rounded()))%",
                        detailText: String(
                            format: "Load %.1f / %.1f / %.1f",
                            snapshot.cpu.loadOneMinute,
                            snapshot.cpu.loadFiveMinutes,
                            snapshot.cpu.loadFifteenMinutes
                        ),
                        fraction: snapshot.cpu.usage,
                        health: snapshot.cpu.usage >= 0.90 ? .critical : (snapshot.cpu.usage >= 0.70 ? .warning : .healthy)
                    )
                    telemetryGaugeTile(
                        title: "Memory",
                        symbol: "memorychip",
                        valueText: MenuBarStatusView.compactMemoryPair(
                            used: snapshot.memory.usedBytes,
                            total: snapshot.memory.totalBytes
                        ),
                        detailText: "Pressure: \(snapshot.memory.pressure.rawValue.capitalized)",
                        fraction: snapshot.memory.usageFraction,
                        health: snapshot.memory.pressure == .critical ? .critical : (snapshot.memory.pressure == .warning ? .warning : .healthy)
                    )
                    telemetryGaugeTile(
                        title: "System Storage",
                        symbol: "internaldrive",
                        valueText: "\(ByteCountFormatter.string(fromByteCount: Int64(snapshot.storage.systemVolume.availableBytes), countStyle: .binary)) free",
                        detailText: "\(Int((snapshot.storage.systemVolume.usageFraction * 100).rounded()))% used on \(snapshot.storage.systemVolume.name)",
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
            title: "Daily Agent Summary",
            subtitle: "Key invocations, efficiency, cost, and action status",
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
            title: "Agent Invocations & Spend by CLI",
            subtitle: "Click any bar to cross-filter tables and actionable items below (IP-001)",
            symbolName: "chart.bar.xaxis"
        ) {
            if let selectedCategory {
                Button {
                    onClearSelection()
                } label: {
                    Label("Filter: \(selectedCategory) ×", systemImage: "line.3.horizontal.decrease.circle.fill")
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
                        y: .value("Invocations", point.invocations)
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
                .accessibilityLabel("Agent invocations by CLI chart")

                HStack(spacing: 8) {
                    Text("Quick Cross-Filter:")
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
                                Text(String(format: "$%.2f", point.costUSD))
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
        SolidModularCardContainer(
            title: "Multi-CLI Cost & Quota Monitor",
            subtitle: "Daily spend, cycle cumulative cost, and quota utilization",
            symbolName: "creditcard.and.123"
        ) {
            HStack(spacing: 12) {
                LabeledContent("Today") {
                    Text(String(format: "$%.2f", todayTotalUSD))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                LabeledContent("Cycle") {
                    Text(String(format: "$%.2f", periodTotalUSD))
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
                Text(String(format: "$%.2f / $%.2f", entry.todayCostUSD, entry.quotaLimitUSD))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
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
                Text("Active: \(entry.activeTokens.formatted(.number)) tok")
                Text("Cache: \(entry.cacheTokens.formatted(.number)) tok")
                Text("Sessions/Turns: \(entry.interactionCount.formatted(.number))")
                Spacer(minLength: 4)
                Text("Cycle: \(String(format: "$%.2f", entry.periodCostUSD))")
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
