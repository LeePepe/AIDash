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
    // Uniform three-band skeleton so a grid of KPI cards aligns (north-star §6):
    //   1. label (caption, uppercase) + optional context sub-label
    //   2. value + unit + trend pill row
    //   3. a FIXED-height viz band directly under the value (12pt gap) — a
    //      sparkline (full width) or a ring gauge. Both占同高, so a ratio card
    //      and a series card end up the same height. A trailing zero-min
    //      Spacer absorbs any extra grid-row height at the card BOTTOM, so
    //      the value→viz band never stretches into a dead zone.

    private static let vizBandHeight: CGFloat = 52

    private func kpiCell(_ item: MetricPayload.Item) -> some View {
        let recipe = AIDashTypography.detail(for: .metric)
        return VStack(alignment: .leading, spacing: AIDashSpace.s12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(recipe.secondary)
                    .foregroundStyle(recipe.secondaryColor)
                    .textCase(.uppercase)
                    .lineLimit(1)
                if let context = item.context, !context.isEmpty {
                    Text(context)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            valueRow(item, recipe: recipe)

            // Value → sparkline stay tight (12pt). Any height the grid row
            // grants beyond the natural content pools BELOW the viz band, so
            // the number-to-chart band never voids into a "sparse" dead zone
            // (north-star §0 病一). The trailing spacer keeps the card bottom-
            // padded rather than mid-stretched.
            vizBand(item)
                .frame(height: Self.vizBandHeight)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The bottom viz band — same height whether it draws a ring, a sparkline,
    /// or nothing, so cards in a grid stay flush.
    @ViewBuilder
    private func vizBand(_ item: MetricPayload.Item) -> some View {
        if item.ratio != nil {
            ringGauge(item)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            sparkline(item)
                .frame(maxWidth: .infinity)
        }
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
            if let trend = item.trend, let label = trendLabel(item, trend: trend) {
                StatusPill(label, tone: outcomeTone(item))
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
            SegmentedGauge(value: ratio, color: ratioColor(item))
        }
    }

    /// Ring color: use good/bad semantics when declared; a plain ratio with no
    /// `higherIsBetter` reads as achievement → success (not primary blue), so
    /// the ring matches the sparklines' outcome coloring.
    private func ratioColor(_ item: MetricPayload.Item) -> Color {
        switch outcome(item) {
        case .good: return theme.success
        case .bad:  return theme.danger
        case .neutral: return item.higherIsBetter == nil ? theme.success : theme.primary.primary
        }
    }

    @ViewBuilder
    private func sparkline(_ item: MetricPayload.Item) -> some View {
        if let series = item.series, series.count > 1 {
            Sparkbars(
                data: series,
                color: vizColor(item),
                height: Self.vizBandHeight,
                baseline: theme.neutrals.border
            )
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

    /// Pill text: an arrow + the last-step delta from `series` (e.g. "↑ 2").
    /// Returns nil when a series is present but the delta is zero (a lone arrow
    /// carries no information — hide the pill entirely). With no series, shows
    /// the bare directional arrow.
    func trendLabel(_ item: MetricPayload.Item, trend: MetricPayload.Item.Trend) -> String? {
        let glyph = trendGlyph(trend)
        if let series = item.series, series.count >= 2 {
            let delta = abs(series[series.count - 1] - series[series.count - 2])
            return delta > 0 ? "\(glyph) \(formattedValue(delta))" : nil
        }
        return glyph
    }

    /// Unicode arrow glyph for the trend, rendered as pill text. Filled
    /// triangles (▲ ▼) plus a bar (▬) for flat give the cockpit its
    /// instrument-panel read; direction is the glyph, good/bad is the tone.
    func trendGlyph(_ trend: MetricPayload.Item.Trend) -> String {
        switch trend {
        case .up: return "▲"
        case .down: return "▼"
        case .flat: return "▬"
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
