import Testing
import SwiftUI
import AIDashCore
import DesignKit
@testable import AIDashUI

@MainActor
@Suite("MetricCardView Tests")
struct MetricCardViewTests {
    private func view(
        items: [MetricPayload.Item] = [.init(label: "Test", value: 1)],
        size: CardSize = .small,
        style: CardStyle = .neutral
    ) -> MetricCardView {
        MetricCardView(payload: MetricPayload(items: items), size: size, style: style)
    }

    // MARK: - formattedValue behavior

    @Test("formattedValue renders whole numbers without decimals")
    func formattedValueWholeNumber() {
        let v = view()
        #expect(v.formattedValue(3) == "3")
        #expect(v.formattedValue(0) == "0")
        #expect(v.formattedValue(124) == "124")
    }

    @Test("formattedValue keeps one decimal for fractional values")
    func formattedValueFractional() {
        let v = view()
        #expect(v.formattedValue(87.5) == "87.5")
        #expect(v.formattedValue(0.42) == "0.4")
        #expect(v.formattedValue(1.04) == "1.0") // rounds down to 1 decimal
    }

    @Test("formattedValue abbreviates large magnitudes on a K/M/B/T ladder")
    func formattedValueLargeNumbers() {
        let v = view()
        // 4-digit counts stay literal (no abbreviation below 10K).
        #expect(v.formattedValue(1301) == "1301")
        #expect(v.formattedValue(9999) == "9999")
        // 5-digit+ compress to K; trailing .0 trimmed.
        #expect(v.formattedValue(10_000) == "10K")
        #expect(v.formattedValue(12_657) == "12.7K")
        // Millions / billions / trillions.
        #expect(v.formattedValue(217_836_228) == "217.8M")
        #expect(v.formattedValue(1_000_000) == "1M")
        #expect(v.formattedValue(2_500_000_000) == "2.5B")
        #expect(v.formattedValue(3_000_000_000_000) == "3T")
        // Boundary: rounding tips the mantissa to 1000 → promote to next unit
        // ("1M", not "1000K"; "1B", not "1000M").
        #expect(v.formattedValue(999_999) == "1M")
        #expect(v.formattedValue(999_999_999) == "1B")
        // Negatives keep their sign.
        #expect(v.formattedValue(-42_000) == "-42K")
    }

    // MARK: - isFlat behavior (flat-series viz gate)

    @Test("isFlat treats constant / near-constant series as flat, varying series as not")
    func isFlatDetection() {
        // Real flat agent series — range is 0% of the mean → flat, no chart.
        #expect(MetricCardView.isFlat([100, 100, 100, 100, 100, 100]))
        #expect(MetricCardView.isFlat([59, 59, 59, 59, 59, 59]))
        #expect(MetricCardView.isFlat([41, 41, 41, 41, 41, 41]))
        // A genuinely rising series (42→250, range ≈ 136% of mean) is NOT flat.
        #expect(!MetricCardView.isFlat([42, 84, 125, 167, 208, 250]))
        // A gentle but real downslope (range ≈ 30% of mean) is NOT flat.
        #expect(!MetricCardView.isFlat([180, 170, 165, 150, 140, 132]))
        // Sub-2% jitter counts as flat (noise, not signal).
        #expect(MetricCardView.isFlat([1000, 1001, 1000, 999, 1000]))
        // 3% range clears the 2% threshold → not flat.
        #expect(!MetricCardView.isFlat([100, 103, 100, 101]))
        // Degenerate inputs never crash; empty is flat.
        #expect(MetricCardView.isFlat([]))
        #expect(MetricCardView.isFlat([7]))
    }

    // MARK: - trendGlyph behavior (arrow glyph mapping)
    @Test("trendGlyph maps each trend to the correct arrow glyph")
    func trendGlyphs() {
        let v = view()
        // Cockpit instrument glyphs: filled triangles for direction, bar for flat.
        #expect(v.trendGlyph(.up) == "▲")
        #expect(v.trendGlyph(.down) == "▼")
        #expect(v.trendGlyph(.flat) == "▬")
    }

    // MARK: - pillLabel: a trend pill is never suppressed by a missing chart
    //
    // Regression: the flat-series viz gate must NOT drop a trend pill. A KPI
    // with a flat series (draws no chart) but a real period-over-period trend
    // still has to show its pill — pill rendering is decoupled from the viz
    // band's presence.

    @Test("pillLabel keeps the pill for a flat series that still carries a trend")
    func pillSurvivesFlatSeries() {
        let v = view()
        // A series flat by MAGNITUDE (isFlat true → no chart) but whose last
        // step still moved: [1000,1000,1000,1001]. isFlat looks at the whole
        // range vs mean (<2% → flat, no chart), while trendLabel looks at the
        // last delta (1 → non-zero → a pill). The pill must survive the missing
        // chart — this is the regression the flat-gate could have introduced.
        let flatMagnitudeMovedLast = MetricPayload.Item(
            label: "Tokens", value: 1001, trend: .up,
            series: [1000, 1000, 1000, 1001], higherIsBetter: true
        )
        #expect(MetricCardView.isFlat([1000, 1000, 1000, 1001])) // <2% range → no chart
        #expect(v.pillLabel(for: flatMagnitudeMovedLast) != nil) // …but pill stays

        // A trend with NO series at all → bare directional glyph pill, and
        // certainly no chart. Must still produce a pill.
        let trendNoSeries = MetricPayload.Item(
            label: "PRs", value: 12, trend: .up, higherIsBetter: true
        )
        #expect(v.pillLabel(for: trendNoSeries) != nil)
    }

    @Test("pillLabel returns nil only when there is no trend signal")
    func pillNilWithoutTrend() {
        let v = view()
        // No trend at all → no pill.
        let noTrend = MetricPayload.Item(label: "Coverage", value: 87)
        #expect(v.pillLabel(for: noTrend) == nil)
        // Trend present but the series' last delta is zero → trendLabel nil →
        // no pill (a lone arrow with no movement carries no information).
        let flatDelta = MetricPayload.Item(
            label: "Open", value: 3, trend: .up, series: [3, 3]
        )
        #expect(v.pillLabel(for: flatDelta) == nil)
    }

    // MARK: - outcomeTone behavior (semantic good/bad coloring)
    //
    // Trend is METRIC CONTENT, rendered as a content-level StatusPill per
    // constitution §Content-Level Status Pills. Color is by OUTCOME (good =
    // success, bad = danger), driven by (trend × higherIsBetter), NOT by raw
    // direction. Absent higherIsBetter → neutral (no good/bad claim).

    @Test("outcomeTone colors by good/bad outcome, not raw direction")
    func outcomeTones() {
        let v = view()
        // higherIsBetter = true: up is good (success), down is bad (danger)
        let moreIsBetter = MetricPayload.Item(label: "PRs", value: 3, trend: .up, higherIsBetter: true)
        #expect(v.outcomeTone(moreIsBetter) == .success)
        let moreIsBetterDown = MetricPayload.Item(label: "PRs", value: 3, trend: .down, higherIsBetter: true)
        #expect(v.outcomeTone(moreIsBetterDown) == .danger)
        // higherIsBetter = false: down is good (build time falling), up is bad
        let lessIsBetter = MetricPayload.Item(label: "Build", value: 124, trend: .down, higherIsBetter: false)
        #expect(v.outcomeTone(lessIsBetter) == .success)
        let lessIsBetterUp = MetricPayload.Item(label: "Build", value: 124, trend: .up, higherIsBetter: false)
        #expect(v.outcomeTone(lessIsBetterUp) == .danger)
        // No higherIsBetter, or flat trend → neutral
        let noClaim = MetricPayload.Item(label: "X", value: 1, trend: .up)
        #expect(v.outcomeTone(noClaim) == .neutral)
        let flat = MetricPayload.Item(label: "X", value: 1, trend: .flat, higherIsBetter: true)
        #expect(v.outcomeTone(flat) == .neutral)
    }

    // MARK: - Token contract assertions
    //
    // Per MY-1057 / constitution §Per-Type Visual Recipes: Metric MUST consume
    // AIDashTypography.detail(for: .metric) and must NOT have its own
    // backgroundTint / corner radius / padding tokens.

    @Test("Metric type carries the Per-Type icon badge contract")
    func metricBadgeContract() {
        #expect(CardType.metric.iconSymbol == "chart.bar.fill")
        #expect(CardType.metric.classification == .metric)
        #expect(CardType.metric.hasIconBadge)
    }

    @Test("Metric primary font is 36pt monospaced bold tabular figures, secondary is .caption .secondary")
    func metricTypographyMatchesRecipe() {
        let recipe = AIDashTypography.detail(for: .metric)
        #expect(recipe.primary == .system(size: 36, weight: .bold, design: .monospaced).monospacedDigit())
        #expect(recipe.secondary == .caption)
        #expect(recipe.secondaryColor == .secondary)
    }

    // MARK: - body rendering smoke (covers every size × style combination)

    @Test(
        "body renders without crashing for every size × style combination",
        arguments: CardSize.allCases, CardStyle.allCases
    )
    func bodyRendersForAllSizeStyleCombinations(size: CardSize, style: CardStyle) {
        let payload = MetricPayload(items: [
            .init(label: "Primary", value: 100, unit: "%", trend: .up),
            .init(label: "Secondary", value: 5, trend: .down),
            .init(label: "Tertiary", value: 42, trend: .flat),
            .init(label: "Quaternary", value: 7),
        ])
        let v = MetricCardView(payload: payload, size: size, style: style)
        // Touching the body forces SwiftUI to evaluate the @ViewBuilder switch
        // and the per-cell formatters. If a layout branch crashes (e.g. empty
        // items, missing optional), this would surface here.
        _ = v.body
    }

    // MARK: - empty-items resilience for body

    @Test("body does not crash when payload has a single item across all sizes")
    func bodyHandlesSingleItem() {
        let payload = MetricPayload(items: [.init(label: "Solo", value: 1)])
        for size in CardSize.allCases {
            let v = MetricCardView(payload: payload, size: size, style: .neutral)
            _ = v.body
        }
    }

    @Test("body renders the empty state without crashing when items are empty")
    func bodyHandlesEmptyItems() {
        // A valid metric payload with no items (a quiet day on real agent
        // data) must render the CardEmptyState, not a bare-badge box. Exercise
        // every size so no size branch reintroduces a blank render.
        let payload = MetricPayload(items: [])
        for size in CardSize.allCases {
            let v = MetricCardView(payload: payload, size: size, style: .neutral)
            _ = v.body
        }
    }
}
