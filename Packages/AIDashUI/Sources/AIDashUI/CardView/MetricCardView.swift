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
                kpiCell(item)
            }
        case .medium:
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(payload.items.prefix(2).enumerated()), id: \.offset) { _, item in
                    kpiCell(item)
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
                    kpiCell(item)
                }
            }
        case .hero:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(payload.items.enumerated()), id: \.offset) { _, item in
                    kpiCell(item)
                }
            }
        }
    }

    // MARK: - KPI cell
    //
    // Layout (north-star §6): label (caption) → value + trend pill row (ring
    // gauge inline trailing when the metric is a ratio) → Spacer pushing the
    // sparkline to a common baseline at the card bottom. This keeps a grid of
    // KPI cards visually aligned instead of stranding the chart in mid-card.

    private func kpiCell(_ item: MetricPayload.Item) -> some View {
        let recipe = AIDashTypography.detail(for: .metric)
        return VStack(alignment: .leading, spacing: AIDashSpace.s8) {
            Text(item.label)
                .font(recipe.secondary)
                .foregroundStyle(recipe.secondaryColor)
                .textCase(.uppercase)

            HStack(alignment: .center, spacing: AIDashSpace.s8) {
                valueRow(item, recipe: recipe)
                if item.ratio != nil {
                    Spacer(minLength: AIDashSpace.s8)
                    ringGauge(item)
                }
            }

            if item.ratio == nil {
                Spacer(minLength: AIDashSpace.s12)
                sparkline(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func valueRow(
        _ item: MetricPayload.Item,
        recipe: AIDashTypography.DetailRecipe
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AIDashSpace.s4) {
            Text(formattedValue(item.value))
                .font(recipe.primary)
            if let unit = item.unit {
                Text(unit)
                    .font(.title3)
                    .foregroundStyle(recipe.secondaryColor)
            }
            if let trend = item.trend {
                trendPill(item, trend: trend)
            }
        }
    }

    // MARK: - Data-viz (north-star §6/§7)
    //
    // Render size is fixed — it does NOT branch on the card's `size` dimension
    // (§Metric Data-Viz). A ratio renders a ring gauge; a series a sparkline.

    @ViewBuilder
    private func ringGauge(_ item: MetricPayload.Item) -> some View {
        if let ratio = item.ratio {
            RingGauge(value: ratio, size: 56, color: vizColor(item))
        }
    }

    @ViewBuilder
    private func sparkline(_ item: MetricPayload.Item) -> some View {
        if let series = item.series, series.count > 1 {
            Sparkline(data: series, color: vizColor(item))
                .frame(height: 40)
        }
    }

    /// Semantic color for the metric's viz + trend pill. Colored by OUTCOME
    /// (good = success, bad = danger), not by raw direction, using the
    /// payload's `higherIsBetter`. When `higherIsBetter` is absent the metric
    /// makes no good/bad claim and renders in the neutral seed primary.
    private func vizColor(_ item: MetricPayload.Item) -> Color {
        switch outcome(item) {
        case .good:    return theme.success
        case .bad:     return theme.danger
        case .neutral: return theme.primary.primary
        }
    }

    private enum Outcome { case good, bad, neutral }

    /// Maps (trend direction × higherIsBetter) to a good/bad/neutral outcome.
    /// `flat`, a missing trend, or a missing `higherIsBetter` → neutral.
    private func outcome(_ item: MetricPayload.Item) -> Outcome {
        guard let trend = item.trend, let higherIsBetter = item.higherIsBetter else {
            return .neutral
        }
        switch trend {
        case .up:   return higherIsBetter ? .good : .bad
        case .down: return higherIsBetter ? .bad : .good
        case .flat: return .neutral
        }
    }

    /// Trend as a content-level status pill (§Content-Level Status Pills):
    /// an arrow glyph colored by OUTCOME, not direction, driven by the payload.
    private func trendPill(_ item: MetricPayload.Item, trend: MetricPayload.Item.Trend) -> some View {
        StatusPill(trendGlyph(trend), tone: outcomeTone(item))
    }

    /// Unicode arrow glyph for the trend, rendered as pill text.
    func trendGlyph(_ trend: MetricPayload.Item.Trend) -> String {
        switch trend {
        case .up: return "↑"
        case .down: return "↓"
        case .flat: return "→"
        }
    }

    /// Pill tone by outcome (good/bad/neutral), consistent with the viz color.
    func outcomeTone(_ item: MetricPayload.Item) -> PillTone {
        switch outcome(item) {
        case .good:    return .success
        case .bad:     return .danger
        case .neutral: return .neutral
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
