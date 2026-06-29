import Testing
import SwiftUI
import Foundation
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("GridLayout Tests")
struct GridLayoutTests {
    @Test("initializes with cards and style")
    func initializesWithCardsAndStyle() {
        let cards: [CardModel] = [
            CardModel(id: "card-1", type: .metric, size: .medium, style: .neutral, payloadJSON: Data()),
            CardModel(id: "card-2", type: .insight, size: .wide, style: .success, payloadJSON: Data()),
        ]

        let layout = GridLayout(cards: cards, style: .neutral)

        #expect(layout.cards.count == 2)
        #expect(layout.style == .neutral)
    }

    @Test("accepts empty cards array")
    func acceptsEmptyCards() {
        let layout = GridLayout(cards: [], style: .accent)

        #expect(layout.cards.isEmpty)
        #expect(layout.style == .accent)
    }

    // MARK: - Column count: compact size class

    @Test("compact size class produces 2 columns (narrow width)")
    func compactNarrowProduces2Columns() {
        #expect(GridLayout.columnCount(for: .compact, width: 320) == 2)
    }

    @Test("compact size class produces 2 columns even at wider width")
    func compactWideProduces2Columns() {
        #expect(GridLayout.columnCount(for: .compact, width: 1024) == 2)
    }

    // MARK: - Column count: regular size class (3- and 4-column tiers)

    @Test("regular size class with narrow width produces 3 columns")
    func regularNarrowProduces3Columns() {
        #expect(GridLayout.columnCount(for: .regular, width: 768) == 3)
    }

    @Test("regular size class just under threshold produces 3 columns")
    func regularJustUnderThresholdProduces3Columns() {
        #expect(GridLayout.columnCount(for: .regular, width: 899) == 3)
    }

    @Test("regular size class at threshold produces 4 columns")
    func regularAtThresholdProduces4Columns() {
        #expect(GridLayout.columnCount(for: .regular, width: 900) == 4)
    }

    @Test("regular size class at full width produces 4 columns")
    func regularFullWidthProduces4Columns() {
        #expect(GridLayout.columnCount(for: .regular, width: 1366) == 4)
    }

    // MARK: - Column count: nil size class (width-only fallback uses AIDashSize tokens)

    @Test("nil size class with very narrow width produces 1 column")
    func nilVeryNarrowProduces1Column() {
        // AIDashSize.columnCount: width < 480 → 1 column
        #expect(GridLayout.columnCount(for: nil, width: 320) == 1)
    }

    @Test("nil size class with narrow width produces 2 columns")
    func nilNarrowProduces2Columns() {
        // AIDashSize.columnCount: 480 ≤ width < 768 → 2 columns
        #expect(GridLayout.columnCount(for: nil, width: 600) == 2)
    }

    @Test("nil size class with medium width produces 3 columns")
    func nilMediumProduces3Columns() {
        // AIDashSize.columnCount: 768 ≤ width < 1100 → 3 columns
        #expect(GridLayout.columnCount(for: nil, width: 900) == 3)
    }

    @Test("nil size class with wide width produces 4 columns")
    func nilWideProduces4Columns() {
        // AIDashSize.columnCount: width ≥ 1100 → 4 columns
        #expect(GridLayout.columnCount(for: nil, width: 1200) == 4)
    }

    // MARK: - TokenGrid wiring

    @Test("GridLayout delegates to TokenGrid and never branches on CardType")
    func delegatesToTokenGridAndAvoidsCardTypeBranching() throws {
        let source = try readLayoutSource("GridLayout.swift")

        #expect(source.contains("TokenGrid("),
                "GridLayout must delegate placement to TokenGrid")
        #expect(!source.contains("switch card.type"),
                "GridLayout must not branch on CardType")
        #expect(!source.contains("CardType."),
                "GridLayout must not reference any CardType cases")
        #expect(!source.contains(".cardChrome"),
                "GridLayout must not apply card chrome")
        #expect(!source.contains(".background("),
                "GridLayout must not paint its own background")
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
