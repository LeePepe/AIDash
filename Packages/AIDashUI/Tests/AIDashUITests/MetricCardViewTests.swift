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

    // MARK: - trendIconName behavior (SF Symbol mapping)

    @Test("trendIconName maps each trend to the correct SF Symbol")
    func trendIconNames() {
        let v = view()
        #expect(v.trendIconName(.up) == "arrow.up")
        #expect(v.trendIconName(.down) == "arrow.down")
        #expect(v.trendIconName(.flat) == "arrow.right")
    }

    // MARK: - trendColor behavior (semantic token mapping)
    //
    // Trend arrow color is METRIC CONTENT (signal direction), not card chrome.
    // Per constitution §Style = Semantic Signal Only this is allowed to stay.
    // Colors resolve from the DesignKit theme tokens, not inline system colors.

    @Test("trendColor maps up to theme.success, down to theme.danger, flat to secondary")
    func trendColors() {
        let v = view()
        let theme = Theme(seed: .appleBlue, neutral: .slate, isDark: false)
        #expect(v.trendColor(.up) == theme.success)
        #expect(v.trendColor(.down) == theme.danger)
        #expect(v.trendColor(.flat) == .secondary)
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

    @Test("Metric primary font is 36pt rounded bold, secondary is .caption .secondary")
    func metricTypographyMatchesRecipe() {
        let recipe = AIDashTypography.detail(for: .metric)
        #expect(recipe.primary == .system(size: 36, weight: .bold, design: .rounded))
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
