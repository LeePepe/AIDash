import SwiftUI
import AIDashCore

@MainActor
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
                // TODO: Replace with CardRouter(card: card) when T096 merges
                Text(card.id)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
