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

    /// Resolve macro-tier columns from available width. Size class is retained
    /// for source compatibility, but width is the sole geometry authority.
    static func columnCount(for sizeClass: UserInterfaceSizeClass?, width: CGFloat) -> Int {
        _ = sizeClass
        return AIDashSize.columnCount(forWidth: width)
    }

    public var body: some View {
        TokenGrid(cards: cards)
    }
}
