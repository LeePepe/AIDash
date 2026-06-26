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
        case .auto:
            AutoLayout(cards: cards, style: container.style)
        case .list:
            ListLayout(cards: cards, style: container.style)
        case .grid:
            GridLayout(cards: cards, style: container.style)
        case .hero:
            HeroLayout(cards: cards, style: container.style)
        }
    }
}
