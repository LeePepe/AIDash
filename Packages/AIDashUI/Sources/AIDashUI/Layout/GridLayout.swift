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

    /// Total column count for the given viewport width, sourced from
    /// `AIDashSize.columnCount(forWidth:)` per the constitution
    /// §Size = Geometry Only. The legacy `horizontalSizeClass`-aware
    /// matrix is preserved as a fallback for callers that still pass a
    /// size class; new code should rely on `AIDashSize.columnCount`.
    static func columnCount(for sizeClass: UserInterfaceSizeClass?, width: CGFloat) -> Int {
        switch sizeClass {
        case .compact:
            return 2
        case .regular:
            return width >= 900 ? 4 : 3
        case .none:
            return AIDashSize.columnCount(forWidth: width)
        case .some:
            return 2
        }
    }

    public var body: some View {
        TokenGrid(cards: cards)
    }
}
