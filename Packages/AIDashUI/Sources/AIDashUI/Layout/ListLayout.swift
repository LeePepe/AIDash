import SwiftUI
import AIDashCore

public struct ListLayout: View {
    let cards: [CardModel]
    let style: CardStyle

    public init(cards: [CardModel], style: CardStyle) {
        self.cards = cards
        self.style = style
    }

    public var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(cards) { card in
                CardRouter(card: card)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
