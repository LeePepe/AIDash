import SwiftUI
import AIDashCore

public struct GridLayout: View {
    let cards: [CardModel]
    let style: CardStyle

    public init(cards: [CardModel], style: CardStyle) {
        self.cards = cards
        self.style = style
    }

    public var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12)],
            spacing: 12
        ) {
            ForEach(cards, id: \.id) { card in
                // TODO: Replace with CardRouter(card: card) when T096 merges
                Text(card.id)
            }
        }
    }
}
