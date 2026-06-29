import SwiftUI
import AIDashCore

// MARK: - TokenGrid (shared)
//
// Single token-driven grid used by every container layout. Total column
// count comes from `AIDashSize.columnCount(forWidth:)` and each card's
// span comes from `AIDashSize.gridSpan(_:)`. The grid does NOT branch on
// `CardType`; per the constitution (§Per-Type Visual Recipes,
// §Size = Geometry Only) layout responsibilities end at placement.
//
// `collapseToList` is the only per-layout override: ListLayout sets it
// to `true` so every card spans the full row regardless of its declared
// size. Auto / grid / hero use the token-driven column count untouched.

@MainActor
struct TokenGrid: View {
    let cards: [CardModel]
    let collapseToList: Bool

    init(cards: [CardModel], collapseToList: Bool = false) {
        self.cards = cards
        self.collapseToList = collapseToList
    }

    var body: some View {
        GeometryReader { proxy in
            PackedRowsView(
                cards: cards,
                width: proxy.size.width,
                collapseToList: collapseToList
            )
        }
    }

    /// Greedy left-to-right row packing. Pure function — no SwiftUI.
    /// Each card's span is clamped to `[1, totalColumns]`. Returns rows of
    /// `(card, span)` pairs in input order.
    static func packRows<C>(
        _ items: [C],
        totalColumns: Int,
        spanForItem: (C) -> Int
    ) -> [[(item: C, span: Int)]] {
        guard totalColumns > 0 else { return [] }
        var rows: [[(item: C, span: Int)]] = []
        var current: [(item: C, span: Int)] = []
        var used = 0
        for item in items {
            let clamped = max(1, min(spanForItem(item), totalColumns))
            if used + clamped > totalColumns, !current.isEmpty {
                rows.append(current)
                current = []
                used = 0
            }
            current.append((item, clamped))
            used += clamped
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}

@MainActor
private struct PackedRowsView: View {
    let cards: [CardModel]
    let width: CGFloat
    let collapseToList: Bool

    var body: some View {
        let totalColumns = collapseToList
            ? 1
            : max(1, AIDashSize.columnCount(forWidth: width))
        let gap = AIDashSpacing.gridGap
        let totalGap = CGFloat(max(0, totalColumns - 1)) * gap
        let cellWidth = max(0, (width - totalGap) / CGFloat(totalColumns))

        let rows = TokenGrid.packRows(
            cards,
            totalColumns: totalColumns,
            spanForItem: { AIDashSize.gridSpan($0.size) }
        )

        VStack(spacing: AIDashSpacing.cardVertical) {
            ForEach(rows.indices, id: \.self) { rowIdx in
                let row = rows[rowIdx]
                HStack(alignment: .top, spacing: gap) {
                    ForEach(row.indices, id: \.self) { colIdx in
                        let entry = row[colIdx]
                        let widthForSpan = cellWidth * CGFloat(entry.span)
                            + gap * CGFloat(max(0, entry.span - 1))
                        CardRouter(card: entry.item)
                            .frame(width: widthForSpan, alignment: .topLeading)
                    }
                    if row.reduce(0, { $0 + $1.span }) < totalColumns {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

// MARK: - AutoLayout

public struct AutoLayout: View {
    let cards: [CardModel]
    let style: CardStyle

    public init(cards: [CardModel], style: CardStyle) {
        self.cards = cards
        self.style = style
    }

    public var body: some View {
        TokenGrid(cards: cards)
    }
}
