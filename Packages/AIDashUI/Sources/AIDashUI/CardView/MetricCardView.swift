import SwiftUI
import AIDashCore

public struct MetricCardView: View {
    let payload: MetricPayload
    let size: CardSize
    let style: CardStyle

    public init(payload: MetricPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundTint, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var content: some View {
        switch size {
        case .small:
            smallLayout
        case .medium:
            mediumLayout
        case .wide:
            wideLayout
        case .hero:
            heroLayout
        }
    }

    // MARK: - Size Layouts

    private var smallLayout: some View {
        VStack(alignment: .center, spacing: 4) {
            if let item = payload.items.first {
                metricValue(item, font: .largeTitle)
                Text(item.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            ForEach(Array(payload.items.prefix(2).enumerated()), id: \.offset) { _, item in
                metricCell(item)
            }
        }
    }

    private var wideLayout: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: min(payload.items.count, 4)),
            spacing: 12
        ) {
            ForEach(Array(payload.items.enumerated()), id: \.offset) { _, item in
                metricCell(item)
            }
        }
    }

    private var heroLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let primary = payload.items.first {
                metricValue(primary, font: .system(size: 48, weight: .bold))
                Text(primary.label)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if payload.items.count > 1 {
                Divider()
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.adaptive(minimum: 100), spacing: 12),
                        count: 1
                    ),
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(Array(payload.items.dropFirst().enumerated()), id: \.offset) { _, item in
                        metricCell(item, compact: true)
                    }
                }
            }
        }
    }

    // MARK: - Components

    private func metricCell(_ item: MetricPayload.Item, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            metricValue(item, font: compact ? .title3 : .title2)
            Text(item.label)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metricValue(_ item: MetricPayload.Item, font: Font) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(formattedValue(item.value))
                .font(font)
                .fontWeight(.semibold)

            if let unit = item.unit {
                Text(unit)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let trend = item.trend {
                trendArrow(trend)
            }
        }
    }

    private func trendArrow(_ trend: MetricPayload.Item.Trend) -> some View {
        Image(systemName: trendIconName(trend))
            .font(.caption)
            .foregroundStyle(trendColor(trend))
    }

    // MARK: - Helpers

    func formattedValue(_ value: Double) -> String {
        if value == value.rounded() && value < 1_000_000 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    func trendIconName(_ trend: MetricPayload.Item.Trend) -> String {
        switch trend {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .flat: return "arrow.right"
        }
    }

    func trendColor(_ trend: MetricPayload.Item.Trend) -> Color {
        switch trend {
        case .up: return .green
        case .down: return .red
        case .flat: return .secondary
        }
    }

    var backgroundTint: Color {
        switch style {
        case .neutral: return Color.clear
        case .success: return Color.green.opacity(0.08)
        case .warning: return Color.orange.opacity(0.08)
        case .accent: return Color.accentColor.opacity(0.10)
        }
    }
}

// MARK: - Previews

#Preview("Small") {
    MetricCardView(
        payload: MetricPayload(items: [
            .init(label: "PRs merged", value: 3, trend: .up),
        ]),
        size: .small,
        style: .success
    )
    .frame(width: 160, height: 120)
    .padding()
}

#Preview("Medium") {
    MetricCardView(
        payload: MetricPayload(items: [
            .init(label: "PRs merged", value: 3, trend: .up),
            .init(label: "Build time", value: 124, unit: "s", trend: .down),
        ]),
        size: .medium,
        style: .neutral
    )
    .frame(width: 320, height: 120)
    .padding()
}

#Preview("Wide") {
    MetricCardView(
        payload: MetricPayload(items: [
            .init(label: "PRs merged", value: 3, trend: .up),
            .init(label: "Build time", value: 124, unit: "s", trend: .down),
            .init(label: "Test coverage", value: 87.5, unit: "%", trend: .flat),
            .init(label: "Active issues", value: 12),
        ]),
        size: .wide,
        style: .accent
    )
    .frame(width: 500, height: 140)
    .padding()
}

#Preview("Hero") {
    MetricCardView(
        payload: MetricPayload(items: [
            .init(label: "Test coverage", value: 87.5, unit: "%", trend: .flat),
            .init(label: "PRs merged", value: 3, trend: .up),
            .init(label: "Build time", value: 124, unit: "s", trend: .down),
            .init(label: "Active issues", value: 12),
        ]),
        size: .hero,
        style: .warning
    )
    .frame(width: 500, height: 220)
    .padding()
}
