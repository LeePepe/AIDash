import SwiftUI
import AIDashCore

/// Stub — full implementation in T094.
struct GridLayout: View {
    let cards: [CardModel]
    let style: CardStyle

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(cards, id: \.id) { card in
                CardPlaceholder(card: card)
            }
        }
    }
}
