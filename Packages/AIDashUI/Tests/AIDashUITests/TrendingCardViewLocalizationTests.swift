import Testing
import SwiftUI
import AIDashCore
import DesignKit
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

    // MARK: - Radar redesign (clickable link + reason + delta)

    @Test("hero body materializes for radar items with reason + category + delta")
    func heroBodyWithRadarFields() {
        let payload = TrendingPayload(
            topic: "值得现在看",
            items: [
                .init(title: "owner/up", url: "https://github.com/owner/up",
                      score: 93459, delta: 412, category: "AI-agent",
                      reason: "多 Agent LLM 框架，与 Financial 项目直接相关"),
                .init(title: "owner/down", url: "https://github.com/owner/down",
                      score: 100, delta: -3, category: "工具",
                      reason: "白板工具，拓展工具库"),
                .init(title: "owner/day1", url: "https://github.com/owner/day1",
                      score: 50, delta: nil, category: "学习", reason: nil),
            ]
        )
        for style in CardStyle.allCases {
            let view = TrendingCardView(payload: payload, size: .hero, style: style)
            _ = view.body
        }
    }

    @Test("row body materializes when url is unparseable (link falls back to text)")
    func rowFallsBackWhenURLInvalid() {
        let payload = TrendingPayload(
            topic: "t",
            items: [.init(title: "no url", url: "", score: 1, reason: "still renders")]
        )
        let view = TrendingCardView(payload: payload, size: .hero, style: .neutral)
        _ = view.body
    }

    @Test("renderer opens the item URL via a Link (clickable repo name)")
    func sourceUsesLinkForRepo() throws {
        let source = try loadRendererSource(named: "TrendingCardView")
        #expect(source.contains("Link(destination:"),
                "repo name must be a Link so it opens GitHub")
    }

    @Test("renderer no longer draws the zero-information score sparkline")
    func sourceHasNoSparkline() throws {
        let source = try loadRendererSource(named: "TrendingCardView")
        #expect(!source.contains("ScoreSparkline"),
                "the monotonic score-distribution sparkline was removed (list is already sorted)")
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

    // MARK: - Token contract (MY-1054 / MY-1059)

    @Test("uses the shared trending typography recipe")
    func usesSharedTypographyRecipe() {
        let expected = AIDashTypography.detail(for: .trending)
        #expect(TrendingCardView.recipe.primary == expected.primary)
        #expect(TrendingCardView.recipe.secondary == expected.secondary)
        #expect(TrendingCardView.recipe.secondaryColor == expected.secondaryColor)
    }

    @Test("typography recipe is invariant across sizes (size = geometry only)")
    func typographyInvariantAcrossSizes() {
        for _ in CardSize.allCases {
            #expect(TrendingCardView.recipe.primary == AIDashTypography.detail(for: .trending).primary)
            #expect(TrendingCardView.recipe.secondary == AIDashTypography.detail(for: .trending).secondary)
        }
    }

    @Test("trending renders its required leading icon badge")
    func rendersTypeBadge() {
        #expect(CardType.trending.hasIconBadge)
        #expect(CardType.trending.iconSymbol == "chart.line.uptrend.xyaxis")
        #expect(CardType.trending.classification == .trending)
    }

    @Test("body materializes for every (size, style) combination")
    func bodyMaterializesEverywhere() {
        let payload = TrendingPayload(
            topic: "Test",
            items: (1...3).map { .init(title: "Item \($0)", url: "https://example.com/\($0)", score: Double($0)) }
        )
        for size in CardSize.allCases {
            for style in CardStyle.allCases {
                let view = TrendingCardView(payload: payload, size: size, style: style)
                _ = view.body
            }
        }
    }

    @Test("renderer source contains no local backgroundTint or RoundedRectangle chrome")
    func sourceHasNoLocalChrome() throws {
        let source = try loadRendererSource(named: "TrendingCardView")
        #expect(!source.contains("backgroundTint"), "TrendingCardView must not declare a local backgroundTint")
        #expect(!source.contains("RoundedRectangle(cornerRadius:"), "TrendingCardView must not draw its own rounded background")
        #expect(source.contains(".cardChrome(size: size, style: style)"), "TrendingCardView must consume the shared cardChrome modifier")
        #expect(source.contains("CardTypeBadge(type: .trending)"), "TrendingCardView must render the shared 32×32 type badge")
    }
}
