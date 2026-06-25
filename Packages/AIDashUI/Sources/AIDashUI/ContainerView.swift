import SwiftUI
import AIDashCore

@MainActor
public struct ContainerView: View {
    let container: ContainerModel

    public init(container: ContainerModel) {
        self.container = container
    }

    /// Cards sorted by id for stable ordering (until a sort key is added to data-model).
    var sortedCards: [CardModel] {
        container.cards.sorted { $0.id < $1.id }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            layoutContent
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(container.title)
                .font(.title2.bold())
            if let subtitle = container.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var layoutContent: some View {
        let cards = sortedCards
        switch container.layout {
        case .list:
            ListLayout(cards: cards, style: container.style)
        case .auto:
            // Inline fallback until AutoLayout (T092) ships
            LazyVStack(spacing: 12) {
                ForEach(cards) { card in
                    cardFallback(card)
                }
            }
        case .grid:
            // Inline fallback until GridLayout (T094) ships
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                spacing: 12
            ) {
                ForEach(cards) { card in
                    cardFallback(card)
                }
            }
        case .hero:
            // Inline fallback until HeroLayout (T095) ships
            VStack(spacing: 16) {
                ForEach(cards) { card in
                    cardFallback(card)
                }
            }
        }
    }

    /// Minimal card representation used by inline layout fallbacks.
    /// Will be replaced by CardRouter (T096) once the layout tasks ship.
    private func cardFallback(_ card: CardModel) -> some View {
        Text(card.id)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
