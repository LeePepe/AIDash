import SwiftUI
import AIDashCore

/// Single-column list layout. Routes through the shared TokenGrid with
/// `collapseToList: true` so every card spans the full row regardless of
/// its declared size token (per the constitution: list collapse is the
/// only allowed deviation from the size→span ladder).
public struct ListLayout: View {
    let cards: [CardModel]
    let style: CardStyle

    public init(cards: [CardModel], style: CardStyle) {
        self.cards = cards
        self.style = style
    }

    public var body: some View {
        TokenGrid(cards: cards, collapseToList: true)
    }
}
