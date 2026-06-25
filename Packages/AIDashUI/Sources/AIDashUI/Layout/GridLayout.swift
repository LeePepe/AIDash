import SwiftUI
import AIDashCore

@MainActor
public struct GridLayout: View {
    let cards: [CardModel]
    let style: CardStyle

    public init(cards: [CardModel], style: CardStyle) {
        self.cards = cards
        self.style = style
    }

    /// Equal-width 2/3/4-column grid based on horizontal size class and available width.
    ///
    /// `horizontalSizeClass` alone is binary (compact/regular) and cannot
    /// distinguish the 3-column tier, so the width is used to disambiguate
    /// the regular and fallback tiers required by T094:
    /// - `.compact` → 2 columns (iPhone portrait, narrow split)
    /// - `.regular` + width < 900 → 3 columns (iPad portrait, large landscape iPhone)
    /// - `.regular` + width ≥ 900 → 4 columns (iPad landscape, full-width)
    /// - `nil` (no environment) → width-only fallback: 2 / 3 / 4
    static func columnCount(for sizeClass: UserInterfaceSizeClass?, width: CGFloat) -> Int {
        switch sizeClass {
        case .compact:
            return 2
        case .regular:
            return width >= 900 ? 4 : 3
        case .none:
            if width >= 900 { return 4 }
            if width >= 600 { return 3 }
            return 2
        case .some:
            return 2
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            ResponsiveGrid(cards: cards, width: proxy.size.width)
        }
    }
}

@MainActor
private struct ResponsiveGrid: View {
    let cards: [CardModel]
    let width: CGFloat

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let count = GridLayout.columnCount(for: horizontalSizeClass, width: width)
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 12),
                count: count
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
