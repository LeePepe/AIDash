import Testing
import SwiftUI
import AIDashCore
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

    // MARK: - trendColor behavior (semantic color mapping)

    @Test("trendColor maps up to green, down to red, flat to secondary")
    func trendColors() {
        let v = view()
        #expect(v.trendColor(.up) == .green)
        #expect(v.trendColor(.down) == .red)
        #expect(v.trendColor(.flat) == .secondary)
    }

    // MARK: - backgroundTint behavior (style → tint mapping)

    @Test("backgroundTint resolves each CardStyle to the expected tinted color")
    func backgroundTintForEachStyle() {
        #expect(view(style: .neutral).backgroundTint == Color.clear)
        #expect(view(style: .success).backgroundTint == Color.green.opacity(0.08))
        #expect(view(style: .warning).backgroundTint == Color.orange.opacity(0.08))
        #expect(view(style: .accent).backgroundTint == Color.accentColor.opacity(0.10))
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
