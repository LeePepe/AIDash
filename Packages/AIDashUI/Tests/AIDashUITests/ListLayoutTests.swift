import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("ListLayout Tests")
struct ListLayoutTests {
    @Test("initializes with cards and style")
    func initializesWithCardsAndStyle() {
        let cards: [CardModel] = [
            CardModel(id: "card-1", type: .metric, size: .medium, style: .neutral, payloadJSON: Data()),
            CardModel(id: "card-2", type: .metric, size: .wide, style: .success, payloadJSON: Data()),
        ]

        let layout = ListLayout(cards: cards, style: .neutral)

        #expect(layout.cards.count == 2)
        #expect(layout.style == .neutral)
    }

    @Test("accepts empty cards array")
    func acceptsEmptyCards() {
        let layout = ListLayout(cards: [], style: .accent)

        #expect(layout.cards.isEmpty)
        #expect(layout.style == .accent)
    }
}
