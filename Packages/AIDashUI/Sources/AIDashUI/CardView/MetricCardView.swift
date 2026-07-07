import SwiftUI
import AIDashCore
import DesignKit

public struct MetricCardView: View {
    let payload: MetricPayload
    let size: CardSize
    let style: CardStyle
    @Environment(\.theme) private var theme

    public init(payload: MetricPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CardTypeBadge(type: .metric)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome(size: size, style: style)
    }

    @ViewBuilder
    private var content: some View {
        switch size {
        case .small:
            if let item = payload.items.first {
                metricCell(item)
            }
        case .medium:
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(payload.items.prefix(2).enumerated()), id: \.offset) { _, item in
                    metricCell(item)
                }
            }
        case .wide:
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 12),
                    count: max(1, min(payload.items.count, 4))
                ),
                spacing: 12
            ) {
                ForEach(Array(payload.items.enumerated()), id: \.offset) { _, item in
                    metricCell(item)
                }
            }
        case .hero:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(payload.items.enumerated()), id: \.offset) { _, item in
                    metricCell(item)
                }
            }
        }
    }

    // MARK: - Components

    private func metricCell(_ item: MetricPayload.Item) -> some View {
        let recipe = AIDashTypography.detail(for: .metric)
        return VStack(alignment: .leading, spacing: AIDashSpace.s8) {
            metricValue(item, recipe: recipe)
            Text(item.label)
                .font(recipe.secondary)
                .foregroundStyle(recipe.secondaryColor)
            dataViz(item)
        }
    }

    /// Content-level data-viz beside the number (north-star §6/§7):
    /// a `ratio` renders a ring gauge (replacing the sparkline); otherwise a
    /// `series` renders a sparkline. Render size is fixed — it does NOT
    /// branch on the card's `size` dimension (§Metric Data-Viz).
    @ViewBuilder
    private func dataViz(_ item: MetricPayload.Item) -> some View {
        if let ratio = item.ratio {
            RingGauge(value: ratio, color: vizColor(item.trend))
        } else if let series = item.series, series.count > 1 {
            Sparkline(data: series, color: vizColor(item.trend))
                .frame(height: 40)
        }
    }

    /// Sparkline / gauge tint follows the item's trend semantics; a metric
    /// with no trend uses the seed primary (a chart token, never inlined).
    private func vizColor(_ trend: MetricPayload.Item.Trend?) -> Color {
        switch trend {
        case .up: return theme.success
        case .down: return theme.danger
        case .flat, nil: return theme.primary.primary
        }
    }

    private func metricValue(
        _ item: MetricPayload.Item,
        recipe: AIDashTypography.DetailRecipe
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AIDashSpace.s4) {
            Text(formattedValue(item.value))
                .font(recipe.primary)

            if let unit = item.unit {
                Text(unit)
                    .font(recipe.secondary)
                    .foregroundStyle(recipe.secondaryColor)
            }

            if let trend = item.trend {
                trendPill(trend)
            }
        }
    }

    /// Trend rendered as a content-level status pill (§Content-Level Status
    /// Pills) — a directional arrow glyph inside a colored capsule. This is a
    /// content signal driven by the payload's `trend`, not the card `style`.
    private func trendPill(_ trend: MetricPayload.Item.Trend) -> some View {
        StatusPill(trendGlyph(trend), tone: trendTone(trend))
    }

    /// Unicode arrow glyph for the trend, rendered as pill text.
    func trendGlyph(_ trend: MetricPayload.Item.Trend) -> String {
        switch trend {
        case .up: return "↑"
        case .down: return "↓"
        case .flat: return "→"
        }
    }

    func trendTone(_ trend: MetricPayload.Item.Trend) -> PillTone {
        switch trend {
        case .up: return .success
        case .down: return .danger
        case .flat: return .neutral
        }
    }

    // MARK: - Helpers

    func formattedValue(_ value: Double) -> String {
        if value == value.rounded() && value < 1_000_000 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
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
    .frame(width: 220, height: 140)
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
    .frame(width: 420, height: 160)
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
    .frame(width: 640, height: 180)
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
    .frame(width: 640, height: 320)
    .padding()
}
