import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("DigestCardView Tests")
struct DigestCardViewTests {
    private let samplePayload = DigestPayload(
        title: "Tuesday at a glance",
        body: "Yesterday was a moderate-pace day. Multica handled three Sapphire PRs without intervention.",
        sections: [
            .init(heading: "What got shipped", paragraphs: [
                "Sapphire merged 3 PRs overnight.",
                "The crash that was blocking v9 is fixed.",
            ]),
            .init(heading: "What's blocking today", paragraphs: [
                "Performance review feedback (due 5pm).",
            ]),
        ]
    )

    @Test("initializes with payload, size, and style")
    func initializesCorrectly() {
        let view = DigestCardView(
            payload: samplePayload,
            size: .wide,
            style: .accent
        )

        #expect(view.payload.title == "Tuesday at a glance")
        #expect(view.size == .wide)
        #expect(view.style == .accent)
    }

    @Test("renders across all card sizes", arguments: CardSize.allCases)
    func acceptsAllSizes(size: CardSize) {
        let view = DigestCardView(
            payload: samplePayload,
            size: size,
            style: .neutral
        )
        _ = view.body
        #expect(view.size == size)
    }

    @Test("renders across all card styles", arguments: CardStyle.allCases)
    func acceptsAllStyles(style: CardStyle) {
        let view = DigestCardView(
            payload: samplePayload,
            size: .medium,
            style: style
        )
        _ = view.body
        #expect(view.style == style)
    }

    @Test("renders payload without sections")
    func rendersWithoutSections() {
        let payload = DigestPayload(
            title: "Quiet day",
            body: "Nothing much shipped."
        )
        let view = DigestCardView(payload: payload, size: .hero, style: .neutral)
        _ = view.body
        #expect(view.payload.sections == nil)
    }

    @Test("renders very long body across hero layout")
    func rendersLongBody() {
        let longBody = String(repeating: "Lorem ipsum dolor sit amet. ", count: 50)
        let payload = DigestPayload(
            title: "Verbose digest",
            body: longBody
        )
        let view = DigestCardView(payload: payload, size: .hero, style: .neutral)
        _ = view.body
        #expect(view.payload.body.count > 200)
    }

    // MARK: - Token compliance contract

    @Test("declares CardType.digest so it carries the constitution badge + tint")
    func badgeIsDigest() {
        #expect(CardType.digest.iconSymbol == "doc.text.fill")
        #expect(CardType.digest.iconTint == .teal)
        #expect(CardType.digest.hasIconBadge)
    }

    @Test("uses the Digest detail recipe (headline + body with 4pt line spacing) from DesignTokens")
    func consumesDetailRecipe() {
        let recipe = AIDashTypography.detail(for: .digest)
        #expect(recipe.primary == .headline)
        #expect(recipe.secondary == .body)
        #expect(recipe.secondaryLineSpacing == 4)
        #expect(recipe.secondaryColor == .primary)
    }
}
