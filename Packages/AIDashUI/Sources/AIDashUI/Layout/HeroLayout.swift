import SwiftUI
import AIDashCore

/// Hero layout. Cards declare their own spans via `AIDashSize.gridSpan`
/// (a `hero` or `wide` card spans the full row, while small/medium pack
/// into the remaining columns). The layout simply forwards the cards to
/// the shared TokenGrid — it does not invent its own chrome, padding, or
/// CardType branching.
public struct HeroLayout: View {
    let cards: [CardModel]
    let style: CardStyle

    public init(cards: [CardModel], style: CardStyle) {
        self.cards = cards
        self.style = style
    }

    public var body: some View {
        TokenGrid(cards: cards)
    }
}
