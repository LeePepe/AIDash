import Testing
import SwiftUI
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

    // MARK: - Column count: nil size class (width-only fallback)

    @Test("nil size class with narrow width produces 2 columns")
    func nilNarrowProduces2Columns() {
        #expect(GridLayout.columnCount(for: nil, width: 400) == 2)
    }

    @Test("nil size class with medium width produces 3 columns")
    func nilMediumProduces3Columns() {
        #expect(GridLayout.columnCount(for: nil, width: 700) == 3)
    }

    @Test("nil size class with wide width produces 4 columns")
    func nilWideProduces4Columns() {
        #expect(GridLayout.columnCount(for: nil, width: 1200) == 4)
    }
}
