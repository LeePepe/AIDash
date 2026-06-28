import SwiftUI
import AIDashCore

public struct AutoLayout: View {
    let cards: [CardModel]
    let style: CardStyle

    public init(cards: [CardModel], style: CardStyle) {
        self.cards = cards
        self.style = style
    }

    public var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(groupedRows, id: \.id) { row in
                switch row {
                case .fullWidth(let card):
                    CardRouter(card: card)
                        .frame(maxWidth: .infinity)
                case .grid(let gridCards):
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240, maximum: 360),
                                           spacing: 12, alignment: .topLeading)],
                        spacing: 12
                    ) {
                        ForEach(gridCards) { card in
                            CardRouter(card: card)
                        }
                    }
                }
            }
        }
    }

    private var groupedRows: [CardRow] {
        var rows: [CardRow] = []
        var pendingGrid: [CardModel] = []

        for card in cards {
            switch card.size {
            case .hero, .wide:
                if !pendingGrid.isEmpty {
                    rows.append(.grid(pendingGrid))
                    pendingGrid = []
                }
                rows.append(.fullWidth(card))
            case .small, .medium:
                pendingGrid.append(card)
            }
        }

        if !pendingGrid.isEmpty {
            rows.append(.grid(pendingGrid))
        }

        return rows
    }
}

private enum CardRow {
    case fullWidth(CardModel)
    case grid([CardModel])

    var id: String {
        switch self {
        case .fullWidth(let card):
            return "full-\(card.id)"
        case .grid(let cards):
            return "grid-\(cards.map(\.id).joined(separator: "-"))"
        }
    }
}
