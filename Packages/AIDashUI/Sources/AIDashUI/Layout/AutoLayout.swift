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
//
// Implementation note: TokenGrid is a custom SwiftUI `Layout` rather
// than a `GeometryReader`-wrapped VStack. `GeometryReader` is a flexible
// container that does not report an intrinsic height up the layout
// tree, so when a parent `ScrollView` / `VStack` asks the grid for its
// preferred size it would collapse to the placeholder height while the
// cards rendered outside the allocated rectangle. The `Layout`
// implementation packs rows during `sizeThatFits` and reports the real
// total height so container spacing is preserved.

@MainActor
struct TokenGrid: View {
    let cards: [CardModel]
    let collapseToList: Bool

    init(cards: [CardModel], collapseToList: Bool = false) {
        self.cards = cards
        self.collapseToList = collapseToList
    }

    var body: some View {
        // Resolve each card's content-derived effective size ONCE, then feed
        // the same value to both the grid span and the card render — so a
        // downgraded card (e.g. a thin digest tagged `hero`) shrinks its column
        // span AND its geometry coherently. `collapseToList` disables the
        // downgrade (list forces full-row). Pass-through types (metric etc.)
        // resolve back to their authored size, so their layout is unchanged.
        let resolved: [(card: CardModel, size: CardSize)] = cards.map { card in
            (card, EffectiveCardSize.resolve(
                type: card.type,
                authored: card.size,
                payloadJSON: card.payloadJSON,
                collapseToList: collapseToList
            ))
        }
        return TokenGridLayout(
            spans: resolved.map { AIDashSize.gridSpan($0.size) },
            collapseToList: collapseToList,
            columnGap: AIDashSpacing.gridGap,
            rowGap: AIDashSpacing.cardVertical
        ) {
            ForEach(resolved, id: \.card.id) { entry in
                CardRouter(card: entry.card, effectiveSize: entry.size)
            }
        }
    }

    /// Greedy left-to-right row packing. Pure function — no SwiftUI.
    /// Each item's span is clamped to `[1, totalColumns]`. Returns rows of
    /// `(item, span)` pairs in input order.
    nonisolated static func packRows<C>(
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

/// Custom `Layout` that packs cards into rows using a token-driven
/// column count and a per-card span. Reports the packed rows' total
/// height in `sizeThatFits` so a parent `ScrollView` / `VStack` allocates
/// the correct vertical space (otherwise cards would draw outside the
/// allocated rectangle and container spacing would collapse).
struct TokenGridLayout: Layout {
    let spans: [Int]
    let collapseToList: Bool
    let columnGap: CGFloat
    let rowGap: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .zero
        guard width > 0, !subviews.isEmpty else { return .zero }
        let rows = packedRows(width: width, subviewCount: subviews.count)
        let totalColumns = resolvedColumnCount(for: width)
        let colWidth = columnWidth(totalWidth: width, columns: totalColumns)

        var totalHeight: CGFloat = 0
        for (rowIdx, row) in rows.enumerated() {
            var rowHeight: CGFloat = 0
            for entry in row {
                let cellWidth = widthForSpan(entry.span, columnWidth: colWidth)
                let size = subviews[entry.index].sizeThatFits(
                    ProposedViewSize(width: cellWidth, height: nil)
                )
                rowHeight = max(rowHeight, size.height)
            }
            totalHeight += rowHeight
            if rowIdx < rows.count - 1 {
                totalHeight += rowGap
            }
        }
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard bounds.width > 0, !subviews.isEmpty else { return }
        let rows = packedRows(width: bounds.width, subviewCount: subviews.count)
        let totalColumns = resolvedColumnCount(for: bounds.width)
        let colWidth = columnWidth(totalWidth: bounds.width, columns: totalColumns)

        var y = bounds.minY
        for row in rows {
            var rowHeight: CGFloat = 0
            for entry in row {
                let cellWidth = widthForSpan(entry.span, columnWidth: colWidth)
                let size = subviews[entry.index].sizeThatFits(
                    ProposedViewSize(width: cellWidth, height: nil)
                )
                rowHeight = max(rowHeight, size.height)
            }
            var x = bounds.minX
            for entry in row {
                let cellWidth = widthForSpan(entry.span, columnWidth: colWidth)
                subviews[entry.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: cellWidth, height: rowHeight)
                )
                x += cellWidth + columnGap
            }
            y += rowHeight + rowGap
        }
    }

    private struct PackedEntry {
        let index: Int
        let span: Int
    }

    private func packedRows(width: CGFloat, subviewCount: Int) -> [[PackedEntry]] {
        let totalColumns = resolvedColumnCount(for: width)
        let indexed = (0..<subviewCount).map { $0 }
        let rows = TokenGrid.packRows(indexed, totalColumns: totalColumns) { idx in
            spans[safe: idx] ?? 1
        }
        return rows.map { row in row.map { PackedEntry(index: $0.item, span: $0.span) } }
    }

    private func resolvedColumnCount(for width: CGFloat) -> Int {
        collapseToList ? 1 : max(1, AIDashSize.columnCount(forWidth: width))
    }

    private func columnWidth(totalWidth: CGFloat, columns: Int) -> CGFloat {
        guard columns > 0 else { return 0 }
        let gaps = CGFloat(max(0, columns - 1)) * columnGap
        return max(0, (totalWidth - gaps) / CGFloat(columns))
    }

    private func widthForSpan(_ span: Int, columnWidth: CGFloat) -> CGFloat {
        let s = max(1, span)
        return columnWidth * CGFloat(s) + columnGap * CGFloat(max(0, s - 1))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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
