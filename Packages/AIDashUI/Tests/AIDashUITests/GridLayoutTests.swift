import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("GridLayout Tests")
struct GridLayoutTests {
    @Test("initializes with cards and style")
    func initializesWithCardsAndStyle() {
        let cards: [CardModel] = [
            CardModel(id: "card-1", type: .metric, size: .medium, style: .neutral, payloadJSON: Data()),
            CardModel(id: "card-2", type: .insight, size: .wide, style: .success, payloadJSON: Data()),
        ]

        let layout = GridLayout(cards: cards, style: .neutral)

        #expect(layout.cards.count == 2)
        #expect(layout.style == .neutral)
    }

    @Test("accepts empty cards array")
    func acceptsEmptyCards() {
        let layout = GridLayout(cards: [], style: .accent)

        #expect(layout.cards.isEmpty)
        #expect(layout.style == .accent)
    }

    @Test("compact size class produces 2 columns")
    func compactSizeClassProduces2Columns() {
        let count = GridLayout.columnCount(for: .compact)
        #expect(count == 2)
    }

    @Test("regular size class produces 4 columns")
    func regularSizeClassProduces4Columns() {
        let count = GridLayout.columnCount(for: .regular)
        #expect(count == 4)
    }

    @Test("nil size class falls back to 2 columns")
    func nilSizeClassFallsBackTo2Columns() {
        let count = GridLayout.columnCount(for: nil)
        #expect(count == 2)
    }
}
