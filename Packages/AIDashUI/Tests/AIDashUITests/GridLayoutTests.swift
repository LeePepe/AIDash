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

    // MARK: - Macro-tier breakpoints

    @Test("compact portrait stays single-column")
    func compactPortraitIsSingleColumn() {
        #expect(GridLayout.columnCount(for: .compact, width: 390) == 1)
    }

    @Test("wide touch uses two or three columns")
    func wideTouchUsesTwoOrThreeColumns() {
        #expect(GridLayout.columnCount(for: .regular, width: 768) == 3)
        #expect(GridLayout.columnCount(for: .regular, width: 1024) == 3)
    }

    @Test("desktop pointer caps at four columns")
    func desktopPointerCapsAtFourColumns() {
        #expect(GridLayout.columnCount(for: .regular, width: 1200) == 4)
        #expect(GridLayout.columnCount(for: nil, width: 2000) == 4)
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

private func readLayoutSource(_ filename: String) throws -> String {
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
