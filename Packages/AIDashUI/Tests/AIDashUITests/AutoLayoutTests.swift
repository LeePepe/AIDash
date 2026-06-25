import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("AutoLayout Tests")
struct AutoLayoutTests {
    @Test("initializes with cards and style")
    func initializesWithCardsAndStyle() {
        let cards: [CardModel] = [
            CardModel(id: "card-1", type: .metric, size: .small, style: .neutral, payloadJSON: Data()),
            CardModel(id: "card-2", type: .metric, size: .hero, style: .success, payloadJSON: Data()),
        ]

        let layout = AutoLayout(cards: cards, style: .neutral)

        #expect(layout.cards.count == 2)
        #expect(layout.style == .neutral)
    }

    @Test("accepts empty cards array")
    func acceptsEmptyCards() {
        let layout = AutoLayout(cards: [], style: .accent)

        #expect(layout.cards.isEmpty)
        #expect(layout.style == .accent)
    }

    @Test("public init signature matches other layouts")
    func publicInitSignature() {
        let cards: [CardModel] = []
        let style: CardStyle = .neutral
        // Verifies the same public init(cards:style:) signature as ListLayout
        let _: AutoLayout = AutoLayout(cards: cards, style: style)
    }
}
