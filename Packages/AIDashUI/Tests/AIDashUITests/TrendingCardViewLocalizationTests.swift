import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

/// Tests for MY-1006: TrendingCardView user-visible strings must be sourced
/// from the package String Catalog (per constitution §F.1), not hardcoded.
///
/// These tests pin the contract that the helpers exposed for localized
/// text:
///   * resolve to non-empty strings via the package bundle, and
///   * carry the dynamic values they are called with.
@MainActor
@Suite("TrendingCardView Localization Tests")
struct TrendingCardViewLocalizationTests {
    @Test("more-items label includes the overflow count")
    func moreItemsLabelIncludesCount() {
        let label = TrendingCardView.moreItemsLabel(overflow: 7)

        #expect(!label.isEmpty)
        #expect(label.contains("7"))
    }

    @Test("more-items label varies by count")
    func moreItemsLabelVariesByCount() {
        let one = TrendingCardView.moreItemsLabel(overflow: 1)
        let many = TrendingCardView.moreItemsLabel(overflow: 42)

        #expect(one != many)
        #expect(one.contains("1"))
        #expect(many.contains("42"))
    }

    @Test("sparkline accessibility label is non-empty and stable")
    func sparklineAccessibilityLabelIsStable() {
        let label = TrendingCardView.sparklineAccessibilityLabel

        #expect(!label.isEmpty)
        // Same call site must return the same value — these are catalog-backed.
        #expect(TrendingCardView.sparklineAccessibilityLabel == label)
    }

    @Test("sparkline empty-value string is non-empty")
    func sparklineEmptyValueIsNonEmpty() {
        let value = TrendingCardView.sparklineEmptyValue

        #expect(!value.isEmpty)
    }

    @Test("sparkline range string includes min and max")
    func sparklineRangeIncludesBothBounds() {
        let value = TrendingCardView.sparklineRangeValue(min: 12, max: 487)

        #expect(!value.isEmpty)
        #expect(value.contains("12"))
        #expect(value.contains("487"))
    }

    @Test("sparkline range string varies with bounds")
    func sparklineRangeVariesWithBounds() {
        let a = TrendingCardView.sparklineRangeValue(min: 1, max: 10)
        let b = TrendingCardView.sparklineRangeValue(min: 50, max: 60)

        #expect(a != b)
    }

    @Test("hero body materializes for payloads with and without scores")
    func heroBodyMaterializes() {
        let withScores = TrendingPayload(
            topic: "Test",
            items: (1...10).map { i in
                .init(title: "Item \(i)", url: "https://example.com/\(i)", score: Double(i * 10))
            }
        )
        let withoutScores = TrendingPayload(
            topic: "Test",
            items: (1...10).map { i in
                .init(title: "Item \(i)", url: "https://example.com/\(i)")
            }
        )

        for payload in [withScores, withoutScores] {
            for style in CardStyle.allCases {
                let view = TrendingCardView(payload: payload, size: .hero, style: style)
                _ = view.body
            }
        }
    }

    @Test("medium body materializes when overflow line is shown")
    func mediumBodyWithOverflow() {
        let payload = TrendingPayload(
            topic: "Test",
            items: (1...5).map { i in
                .init(title: "Item \(i)", url: "https://example.com/\(i)")
            }
        )

        let view = TrendingCardView(payload: payload, size: .medium, style: .neutral)
        _ = view.body
    }
}
