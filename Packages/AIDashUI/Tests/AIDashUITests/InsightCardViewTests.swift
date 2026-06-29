import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("InsightCardView Tests")
struct InsightCardViewTests {
    private let samplePayload = InsightPayload(
        title: "Test Insight",
        body: "This is a test body that provides insight information."
    )

    private let payloadWithCitations = InsightPayload(
        title: "Test Insight",
        body: "This is a test body.",
        citations: [
            .init(label: "Source 1", url: "https://example.com/1"),
            .init(label: "Source 2", url: "https://example.com/2"),
        ]
    )

    @Test("initializes with payload, size, and style")
    func initializesCorrectly() {
        let view = InsightCardView(
            payload: samplePayload,
            size: .medium,
            style: .neutral
        )

        #expect(view.payload.title == "Test Insight")
        #expect(view.size == .medium)
        #expect(view.style == .neutral)
    }

    @Test("accepts all card sizes", arguments: CardSize.allCases)
    func acceptsAllSizes(size: CardSize) {
        let view = InsightCardView(
            payload: samplePayload,
            size: size,
            style: .neutral
        )

        #expect(view.size == size)
    }

    @Test("accepts all card styles", arguments: [CardStyle.neutral, .success, .warning, .accent])
    func acceptsAllStyles(style: CardStyle) {
        let view = InsightCardView(
            payload: samplePayload,
            size: .medium,
            style: style
        )

        #expect(view.style == style)
    }

    @Test("safeCitations enforces URLPolicy (https-only, non-empty host)")
    func filtersCitationSchemes() {
        let citations: [InsightPayload.Citation] = [
            .init(label: "Good HTTPS", url: "https://example.com"),
            .init(label: "Bad HTTP", url: "http://example.com"),
            .init(label: "Bad file", url: "file:///etc/passwd"),
            .init(label: "Bad custom", url: "myapp://deeplink"),
            .init(label: "Bad javascript", url: "javascript:alert(1)"),
            .init(label: "Bad empty host", url: "https:///foo"),
            .init(label: "Invalid URL", url: ""),
        ]

        let view = InsightCardView(
            payload: samplePayload,
            size: .hero,
            style: .neutral
        )
        let safe = view.safeCitations(from: citations)

        #expect(safe.count == 1)
        #expect(safe[0].label == "Good HTTPS")
    }

    @Test("truncatedBody truncates at 150 chars with ellipsis")
    func truncatesLongBody() {
        let longBody = String(repeating: "A", count: 200)
        let payload = InsightPayload(title: "T", body: longBody)
        let view = InsightCardView(payload: payload, size: .medium, style: .neutral)

        let truncated = view.truncatedBody
        #expect(truncated.count == 151) // 150 chars + ellipsis character
        #expect(truncated.hasSuffix("\u{2026}"))
    }

    @Test("truncatedBody does not truncate short body")
    func doesNotTruncateShortBody() {
        let shortBody = "Short body"
        let payload = InsightPayload(title: "T", body: shortBody)
        let view = InsightCardView(payload: payload, size: .medium, style: .neutral)

        #expect(view.truncatedBody == shortBody)
    }

    // MARK: - Token contract assertions
    //
    // Per MY-1057 / constitution §Per-Type Visual Recipes: Insight MUST consume
    // AIDashTypography.detail(for: .insight) and must NOT carry its own
    // backgroundTint / corner radius / padding tokens.

    @Test("Insight type carries the Per-Type icon badge contract")
    func insightBadgeContract() {
        #expect(CardType.insight.iconSymbol == "sparkles")
        #expect(CardType.insight.iconTint == .purple)
        #expect(CardType.insight.hasIconBadge)
    }

    @Test("Insight primary font is title3 semibold, secondary is .body .primary")
    func insightTypographyMatchesRecipe() {
        let recipe = AIDashTypography.detail(for: .insight)
        #expect(recipe.primary == .title3.weight(.semibold))
        #expect(recipe.secondary == .body)
        #expect(recipe.secondaryColor == .primary)
    }

    @Test(
        "body renders without crashing for every size × style combination",
        arguments: CardSize.allCases, CardStyle.allCases
    )
    func bodyRendersForAllSizeStyleCombinations(size: CardSize, style: CardStyle) {
        let view = InsightCardView(
            payload: payloadWithCitations,
            size: size,
            style: style
        )
        _ = view.body
    }
}
