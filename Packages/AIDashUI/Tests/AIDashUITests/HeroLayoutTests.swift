import Testing
import SwiftUI
import Foundation
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("HeroLayout Tests")
struct HeroLayoutTests {
    @Test("initializes with cards and style")
    func initializesWithCardsAndStyle() {
        let cards: [CardModel] = [
            CardModel(id: "hero-1", type: .metric, size: .hero, style: .accent, payloadJSON: Data()),
            CardModel(id: "card-2", type: .metric, size: .medium, style: .neutral, payloadJSON: Data()),
            CardModel(id: "card-3", type: .metric, size: .medium, style: .success, payloadJSON: Data()),
        ]

        let layout = HeroLayout(cards: cards, style: .accent)

        #expect(layout.cards.count == 3)
        #expect(layout.style == .accent)
    }

    @Test("accepts empty cards array")
    func acceptsEmptyCards() {
        let layout = HeroLayout(cards: [], style: .neutral)

        #expect(layout.cards.isEmpty)
        #expect(layout.style == .neutral)
    }

    @Test("single card treated as hero")
    func singleCardIsHero() {
        let cards: [CardModel] = [
            CardModel(id: "only-hero", type: .insight, size: .hero, style: .accent, payloadJSON: Data()),
        ]

        let layout = HeroLayout(cards: cards, style: .accent)

        #expect(layout.cards.count == 1)
        #expect(layout.cards.first?.id == "only-hero")
    }

    // MARK: - TokenGrid wiring
    //
    // Hero placement is driven by AIDashSize.gridSpan(.hero) == max,
    // which the shared TokenGrid packs as a full-row card. HeroLayout
    // adds no chrome, no padding, no CardType branching.

    @Test("HeroLayout delegates to TokenGrid and never branches on CardType")
    func delegatesToTokenGrid() throws {
        let source = try readLayoutSource("HeroLayout.swift")

        #expect(source.contains("TokenGrid("),
                "HeroLayout must delegate placement to TokenGrid")
        #expect(!source.contains("switch card.type"),
                "HeroLayout must not branch on CardType")
        #expect(!source.contains("CardType."),
                "HeroLayout must not reference any CardType cases")
        #expect(!source.contains(".cardChrome"),
                "HeroLayout must not apply card chrome")
        #expect(!source.contains(".background("),
                "HeroLayout must not paint its own background")
    }
}

@MainActor
@Suite("TokenGrid packing")
struct TokenGridPackingTests {

    /// Cards declare spans via `AIDashSize.gridSpan(size)`. The grid
    /// must clamp each span into the available column count and pack
    /// rows greedily left-to-right.
    @Test("small cards (span 1) fill a 3-column grid one row at a time")
    func smallCardsPackOneRow() {
        let items = ["a", "b", "c", "d", "e"]
        let rows = TokenGrid.packRows(items, totalColumns: 3) { _ in 1 }
        #expect(rows.count == 2)
        #expect(rows[0].map(\.item) == ["a", "b", "c"])
        #expect(rows[0].allSatisfy { $0.span == 1 })
        #expect(rows[1].map(\.item) == ["d", "e"])
    }

    @Test("medium card (span 2) plus small card (span 1) fits one 3-col row")
    func mediumPlusSmallShareRow() {
        let rows = TokenGrid.packRows([("m", 2), ("s", 1)], totalColumns: 3) { $0.1 }
        #expect(rows.count == 1)
        #expect(rows[0].map(\.item.0) == ["m", "s"])
    }

    @Test("two mediums (span 2 each) in a 3-col grid wrap rather than overflow")
    func mediumsWrapWhenSumExceedsColumns() {
        let rows = TokenGrid.packRows([("m1", 2), ("m2", 2)], totalColumns: 3) { $0.1 }
        #expect(rows.count == 2)
        #expect(rows[0].map(\.item.0) == ["m1"])
        #expect(rows[1].map(\.item.0) == ["m2"])
    }

    @Test("hero/wide span (Int.max) is clamped to totalColumns and gets its own row")
    func heroClampsToFullRow() {
        let rows = TokenGrid.packRows(
            [("a", 1), ("hero", .max), ("b", 1)],
            totalColumns: 4
        ) { $0.1 }
        #expect(rows.count == 3)
        #expect(rows[0].map(\.item.0) == ["a"])
        #expect(rows[1].map(\.item.0) == ["hero"])
        #expect(rows[1].first?.span == 4)
        #expect(rows[2].map(\.item.0) == ["b"])
    }

    @Test("hero card span comes from AIDashSize.gridSpan, not a CardType branch")
    func heroSpanComesFromSizeToken() {
        // Verify the token contract that TokenGrid relies on.
        #expect(AIDashSize.gridSpan(.small) == 1)
        #expect(AIDashSize.gridSpan(.medium) == 2)
        #expect(AIDashSize.gridSpan(.wide) == .max)
        #expect(AIDashSize.gridSpan(.hero) == .max)
    }

    @Test("collapseToList path forces every card to one column regardless of declared size")
    func collapseToListForcesSingleColumn() {
        // packRows itself is column-agnostic; collapse is enforced by
        // the View body picking totalColumns = 1. Simulate that here.
        let mixed: [(String, Int)] = [
            ("small", 1), ("medium", 2), ("hero", .max),
        ]
        let rows = TokenGrid.packRows(mixed, totalColumns: 1) { $0.1 }
        #expect(rows.count == 3, "every card should land on its own row when collapsed to a list")
        #expect(rows.allSatisfy { $0.first?.span == 1 })
    }

    @Test("zero column count produces no rows (defensive)")
    func zeroColumnsProducesEmpty() {
        let rows = TokenGrid.packRows(["a", "b"], totalColumns: 0) { _ in 1 }
        #expect(rows.isEmpty)
    }
}

fileprivate func readLayoutSource(_ filename: String) throws -> String {
    var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0..<8 {
        let candidate = dir
            .appendingPathComponent("Sources/AIDashUI/Layout")
            .appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return try String(contentsOf: candidate, encoding: .utf8)
        }
        dir = dir.deletingLastPathComponent()
    }
    struct NotFound: Error { let filename: String }
    throw NotFound(filename: filename)
}
