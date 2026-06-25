import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("MetricCardView Tests")
struct MetricCardViewTests {
    @Test("initializes with payload, size, and style")
    func initializesCorrectly() {
        let payload = MetricPayload(items: [
            .init(label: "PRs merged", value: 3, trend: .up),
        ])
        let view = MetricCardView(payload: payload, size: .small, style: .neutral)

        #expect(view.payload.items.count == 1)
        #expect(view.size == .small)
        #expect(view.style == .neutral)
    }

    @Test("small size uses only first item")
    func smallSizeUsesFirstItem() {
        let payload = MetricPayload(items: [
            .init(label: "Coverage", value: 87.5, unit: "%", trend: .up),
            .init(label: "Extra", value: 10),
        ])
        let view = MetricCardView(payload: payload, size: .small, style: .success)

        #expect(view.payload.items.first?.label == "Coverage")
        #expect(view.size == .small)
    }

    @Test("medium size limits to two items")
    func mediumSizeLimitsToTwo() {
        let payload = MetricPayload(items: [
            .init(label: "A", value: 1),
            .init(label: "B", value: 2),
            .init(label: "C", value: 3),
        ])
        let view = MetricCardView(payload: payload, size: .medium, style: .neutral)

        #expect(view.size == .medium)
        #expect(view.payload.items.count == 3)
    }

    @Test("wide size accepts up to four items in grid")
    func wideSizeGrid() {
        let payload = MetricPayload(items: [
            .init(label: "A", value: 1),
            .init(label: "B", value: 2),
            .init(label: "C", value: 3),
            .init(label: "D", value: 4),
        ])
        let view = MetricCardView(payload: payload, size: .wide, style: .accent)

        #expect(view.size == .wide)
        #expect(view.payload.items.count == 4)
    }

    @Test("hero size separates primary from secondary metrics")
    func heroSizeLayout() {
        let payload = MetricPayload(items: [
            .init(label: "Primary", value: 100, unit: "%", trend: .up),
            .init(label: "Secondary A", value: 5, trend: .down),
            .init(label: "Secondary B", value: 42, trend: .flat),
        ])
        let view = MetricCardView(payload: payload, size: .hero, style: .warning)

        #expect(view.size == .hero)
        #expect(view.payload.items.first?.label == "Primary")
        #expect(view.payload.items.dropFirst().count == 2)
    }

    @Test("all card styles produce valid views")
    func allStylesValid() {
        let payload = MetricPayload(items: [
            .init(label: "Test", value: 1),
        ])

        for cardStyle in CardStyle.allCases {
            let view = MetricCardView(payload: payload, size: .small, style: cardStyle)
            #expect(view.style == cardStyle)
        }
    }

    @Test("all card sizes produce valid views")
    func allSizesValid() {
        let payload = MetricPayload(items: [
            .init(label: "Test", value: 1),
        ])

        for cardSize in CardSize.allCases {
            let view = MetricCardView(payload: payload, size: cardSize, style: .neutral)
            #expect(view.size == cardSize)
        }
    }

    @Test("item without unit or trend is valid")
    func itemWithoutOptionals() {
        let payload = MetricPayload(items: [
            .init(label: "Count", value: 42),
        ])
        let view = MetricCardView(payload: payload, size: .small, style: .neutral)

        #expect(view.payload.items.first?.unit == nil)
        #expect(view.payload.items.first?.trend == nil)
    }
}
