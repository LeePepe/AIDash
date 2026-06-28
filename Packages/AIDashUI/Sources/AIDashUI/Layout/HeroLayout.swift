import SwiftUI
import AIDashCore

public struct HeroLayout: View {
    let cards: [CardModel]
    let style: CardStyle

    public init(cards: [CardModel], style: CardStyle) {
        self.cards = cards
        self.style = style
    }

    public var body: some View {
        VStack(spacing: 12) {
            if let hero = cards.first {
                cardView(for: hero)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
                    .padding(.bottom, 4)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12)],
                spacing: 12
            ) {
                ForEach(cards.dropFirst()) { card in
                    cardView(for: card)
                }
            }
        }
    }

    // Routes each card through CardRouter for content rendering.
    @ViewBuilder
    private func cardView(for card: CardModel) -> some View {
        CardRouter(card: card)
    }
}
