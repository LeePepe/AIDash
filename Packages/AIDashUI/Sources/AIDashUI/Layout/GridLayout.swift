import SwiftUI
import AIDashCore

@MainActor
public struct GridLayout: View {
    let cards: [CardModel]
    let style: CardStyle

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(cards: [CardModel], style: CardStyle) {
        self.cards = cards
        self.style = style
    }

    /// Column count driven by horizontal size class:
    /// - `.compact` → 2 columns (iPhone portrait, narrow iPad split)
    /// - `.regular` → 4 columns (iPad full-width, large iPhone landscape)
    /// - `nil` → 2 columns (fallback)
    static func columnCount(for sizeClass: UserInterfaceSizeClass?) -> Int {
        sizeClass == .regular ? 4 : 2
    }

    public var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 12),
                count: Self.columnCount(for: horizontalSizeClass)
            ),
            spacing: 12
        ) {
            ForEach(cards) { card in
                // TODO: Replace with CardRouter(card: card) when T096 merges
                Text(card.id)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
