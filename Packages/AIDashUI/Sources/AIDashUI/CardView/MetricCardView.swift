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
        let isEmpty = payload.items.isEmpty
        // Collapse the card to a compact height when empty so the "no data"
        // caption reads as intentional, not a broken tall box (review P1).
        let emptyHeight: CGFloat? = isEmpty ? AIDashSize.emptyMinHeight : nil
        return HStack(alignment: isEmpty ? .center : .top, spacing: 12) {
            CardTypeBadge(type: .metric)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome(size: size, style: style, minHeight: emptyHeight)
    }

    @ViewBuilder
    private var content: some View {
        if payload.items.isEmpty {
            // Valid payload, no metrics to plot — render the sanctioned empty
            // state so the card reads as "nothing to report" rather than a
            // broken bare-badge box (the failure on sparse real data).
            CardEmptyState(message: Self.emptyMessage)
        } else {
            populatedContent
        }
    }

    @ViewBuilder
    private var populatedContent: some View {
        switch size {
        case .small:
            if let item = payload.items.first {
                kpiCell(item)
            }
        case .medium:
            // Up to 3 KPIs so a 2-up medium card reads as a dense mini-table
            // (e.g. a breakdown) rather than two numbers floating in a wide box
            // (product register: density is earned, not avoided).
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(payload.items.prefix(3).enumerated()), id: \.offset) { _, item in
                    kpiCell(item)
                }
            }
        case .wide:
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: AIDashSpace.s16),
                    count: AIDashSize.kpiColumnCount(forItems: payload.items.count)
                ),
                spacing: AIDashSpace.s16
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

    nonisolated private static let vizBandHeight: CGFloat = 52

    /// Reserved height for the trend-pill row so cells with and without a pill
    /// keep their viz bands on the same baseline across a KPI grid.
    nonisolated private static let pillRowHeight: CGFloat = 20

    private func kpiCell(_ item: MetricPayload.Item) -> some View {
        let recipe = AIDashTypography.detail(for: .metric)
        let viz = vizKind(item)
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

            // Reserve the pill row ONLY for a cell that draws a viz band — that
            // cell needs its band baseline-aligned with a pilled sibling's band
            // (which sits below a pill). A chart-less flat cell (no pill, no
            // band) reserves nothing and stays compact; top-alignment keeps the
            // grid row tidy without the empty 20pt strip.
            valueRow(item, recipe: recipe, showsPillRow: showsAnyPill && viz != .none)

            // Only draw the viz band when it carries signal. A flat or near-
            // constant series (e.g. real [100,100,…]) renders as a meaningless
            // uniform strip, so `vizKind` collapses it to `.none` and the band
            // (and its 52pt) simply isn't emitted — the cell shrinks to content
            // instead of pooling grid slack into a dead zone (the "too much
            // whitespace" failure on real agent data).
            if viz != .none {
                vizBand(item, kind: viz)
                    .frame(height: viz.height)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What data-viz a KPI cell should draw, if any.
    private enum VizKind {
        case gauge     // a ratio → SegmentedGauge
        case sparkbars // a series that actually varies
        case none      // flat / too-short series, or no viz data → draw nothing

        /// Height the band reserves. A gauge reads fine shorter than a spark.
        var height: CGFloat {
            switch self {
            case .gauge:    return 44
            case .sparkbars: return MetricCardView.vizBandHeight
            case .none:     return 0
            }
        }
    }

    /// Decide the viz for a KPI: a ratio always gauges; a series only draws
    /// bars when it carries signal (≥3 points AND not flat); otherwise nothing.
    private func vizKind(_ item: MetricPayload.Item) -> VizKind {
        if item.ratio != nil { return .gauge }
        if let series = item.series, series.count >= 3, !Self.isFlat(series) {
            return .sparkbars
        }
        return .none
    }

    /// A series is "flat" when its peak-to-trough range is a negligible
    /// fraction (<2%) of its own average magnitude — e.g. [100,100,…] or
    /// [59,59,…]. Such a series carries no trend, so a bar-spark of it is
    /// noise. A genuinely rising series like [42,84,…,250] is NOT flat and
    /// keeps its chart.
    static func isFlat(_ series: [Double]) -> Bool {
        guard let lo = series.min(), let hi = series.max() else { return true }
        let mean = series.reduce(0, +) / Double(series.count)
        let denom = max(abs(mean), 1)
        return (hi - lo) / denom < 0.02
    }

    /// True when ANY item in the payload draws a trend pill, so the whole grid
    /// reserves the pill row and cells stay baseline-aligned. When no item has
    /// a trend (e.g. an all-flat throughput card), the row isn't reserved at
    /// all — reclaiming ~20pt/cell of dead space.
    private var showsAnyPill: Bool {
        payload.items.contains { item in
            guard let trend = item.trend else { return false }
            return trendLabel(item, trend: trend) != nil
        }
    }

    /// The bottom viz band for the resolved `kind`.
    @ViewBuilder
    private func vizBand(_ item: MetricPayload.Item, kind: VizKind) -> some View {
        switch kind {
        case .gauge:
            ringGauge(item)
                .frame(maxWidth: .infinity, alignment: .center)
        case .sparkbars:
            sparkline(item)
                .frame(maxWidth: .infinity)
        case .none:
            EmptyView()
        }
    }

    /// Value line + a trend-delta pill on its own row beneath it.
    ///
    /// The number and unit share a baseline; the trend pill sits on a SEPARATE
    /// line so a wide delta (e.g. "▼ 293.7M") never competes with the big
    /// tabular value for horizontal space and wrap-folds inside a narrow KPI
    /// cell — the failure seen on real 9-item metric grids.
    ///
    /// `showsPillRow` reserves the pill row's fixed height so cells stay
    /// baseline-aligned across a grid — but ONLY when some item in the payload
    /// actually has a pill. An all-flat card (no trends anywhere) passes
    /// `false` and reclaims the row entirely.
    private func valueRow(
        _ item: MetricPayload.Item,
        recipe: AIDashTypography.DetailRecipe,
        showsPillRow: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: AIDashSpace.s4) {
            HStack(alignment: .firstTextBaseline, spacing: AIDashSpace.s4) {
                Text(formattedValue(item.value))
                    .font(recipe.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = item.unit {
                    // Unit reads as a proper suffix, not floating-point cruft:
                    // a monospaced medium glyph on the value's baseline via the
                    // `metricUnit` token (kept out of the renderer as a literal
                    // so the P1.1 no-hardcoded-font guard stays satisfied).
                    Text(unit)
                        .font(AIDashTypography.metricUnit)
                        .foregroundStyle(recipe.secondaryColor)
                        .lineLimit(1)
                }
            }
            // Reserve the pill row's height only when the grid draws pills at
            // all, so cells with and without a pill share a baseline — but an
            // all-flat card drops the row entirely rather than padding dead air.
            if showsPillRow {
                ZStack(alignment: .leading) {
                    Color.clear.frame(height: Self.pillRowHeight)
                    if let trend = item.trend, let label = trendLabel(item, trend: trend) {
                        StatusPill(label, tone: outcomeTone(item))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
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
    /// the ring matches the sparklines' outcome coloring. A ratio that DOES
    /// declare `higherIsBetter` but is flat makes no good/bad claim → neutral
    /// gray, consistent with the sparkbar neutral (never the seed olive).
    private func ratioColor(_ item: MetricPayload.Item) -> Color {
        switch outcome(item) {
        case .good: return theme.success
        case .bad:  return theme.danger
        case .neutral: return item.higherIsBetter == nil ? theme.success : theme.neutrals.text2
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
    /// makes no good/bad claim and renders in a neutral gray.
    ///
    /// The neutral case MUST NOT reuse the seed primary: with a lime seed its
    /// olive derivative sits at nearly the same hue as `theme.success`, so a
    /// grid mixing good/neutral bars reads as all-green and the three-state
    /// (good / bad / neutral) collapses — worst in dark. Neutral bars use
    /// `theme.neutrals.text2` so green stays reserved for a genuine good
    /// outcome, matching the neutral pill's gray.
    private func vizColor(_ item: MetricPayload.Item) -> Color {
        switch outcome(item) {
        case .good:    return theme.success
        case .bad:     return theme.danger
        case .neutral: return theme.neutrals.text2
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

    /// Caption for the empty state when a metric payload carries no items.
    /// Localized per constitution §F.1 so it renders in the reader's language.
    private static let emptyMessage = String(
        localized: "metric.empty",
        defaultValue: "No metric data",
        bundle: .module,
        comment: "Shown inside a metric card when its payload decoded successfully but has no items to plot."
    )

    /// Formats a metric value for a compact instrument readout.
    ///
    /// Large magnitudes are abbreviated (K/M/B/T) so a real value like
    /// `217_836_228` reads as `217.8M` instead of overflowing the tabular
    /// display digit onto a second line. Small values render as plain
    /// integers (no trailing `.0`) or with up to one decimal. This is the
    /// single formatter for both the KPI value and the trend-delta pill, so
    /// both stay short on real agent data.
    func formattedValue(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        let m = abs(value)

        // Below 10K: literal integer (4-digit counts like 1301 stay exact) or
        // one decimal for fractional values (keep the .0 so 1.04 → "1.0").
        if m < 10_000 {
            if m == m.rounded() { return sign + String(format: "%.0f", m) }
            return sign + String(format: "%.1f", m)
        }

        // Abbreviate on a 1000× ladder starting at K (1e3). Advance to the
        // largest unit whose mantissa stays under 1000.
        let suffixes = ["K", "M", "B", "T"]
        var magnitude = 1_000.0
        var index = 0
        while index < suffixes.count - 1, m / (magnitude * 1_000) >= 1 {
            magnitude *= 1_000
            index += 1
        }

        // Rounding the mantissa to one decimal can tip a boundary value up to
        // 1000.0 (e.g. 999_999 / 1e3 = 999.999 → "1000.0K"). When it does, and
        // a larger unit exists, promote so it reads "1M" instead of "1000K".
        var scaled = m / magnitude
        if roundedToTenth(scaled) >= 1_000, index < suffixes.count - 1 {
            magnitude *= 1_000
            index += 1
            scaled = m / magnitude
        }
        return sign + trimDecimal(scaled) + suffixes[index]
    }

    /// Rounds to one decimal place (matches what `%.1f` displays), used to
    /// detect the 999.95→1000.0 boundary before formatting.
    private func roundedToTenth(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// One-decimal string with a trailing `.0` trimmed (e.g. `218.0`→`218`,
    /// `1.01`→`1.0`), keeping abbreviations tight.
    private func trimDecimal(_ value: Double) -> String {
        let s = String(format: "%.1f", value)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
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
