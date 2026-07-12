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

    @Test("formattedValue switches to decimal form at one million even for whole values")
    func formattedValueLargeNumbers() {
        let v = view()
        // 999_999 is whole and below threshold → "%.0f"
        #expect(v.formattedValue(999_999) == "999999")
        // 1_000_000 is whole but at threshold → falls through to "%.1f"
        #expect(v.formattedValue(1_000_000) == "1000000.0")
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
}
