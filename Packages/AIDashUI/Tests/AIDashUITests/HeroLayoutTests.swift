import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("HeroLayout Tests")
struct HeroLayoutTests {
    @Test("initializes with cards and style")
    func initializesWithCardsAndStyle() {
        let cards: [CardModel] = [
            CardModel(id: "hero-1", type: .metric, size: .hero, style: .accent, payloadJSON: Data()),
            CardModel(id: "card-2", type: .metric, size: .medium, style: .neutral, payloadJSON: Data()),
            CardModel(id: "card-3", type: .metric, size: .medium, style: .success, payloadJSON: Data()),
        ]

        let layout = HeroLayout(cards: cards, style: .accent)

        #expect(layout.cards.count == 3)
        #expect(layout.style == .accent)
    }

    @Test("accepts empty cards array")
    func acceptsEmptyCards() {
        let layout = HeroLayout(cards: [], style: .neutral)

        #expect(layout.cards.isEmpty)
        #expect(layout.style == .neutral)
    }

    @Test("single card treated as hero")
    func singleCardIsHero() {
        let cards: [CardModel] = [
            CardModel(id: "only-hero", type: .insight, size: .hero, style: .accent, payloadJSON: Data()),
        ]

        let layout = HeroLayout(cards: cards, style: .accent)

        #expect(layout.cards.count == 1)
        #expect(layout.cards.first?.id == "only-hero")
    }
}
