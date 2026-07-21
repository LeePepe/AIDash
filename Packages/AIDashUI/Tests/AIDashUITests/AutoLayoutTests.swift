import Testing
import SwiftUI
import Foundation
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("AutoLayout Tests")
struct AutoLayoutTests {
    private func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(value)) ?? Data()
    }

    @Test("initializes with cards and style")
    func initializesWithCardsAndStyle() {
        let cards: [CardModel] = [
            CardModel(id: "card-1", type: .metric, size: .small, style: .neutral, payloadJSON: Data()),
            CardModel(id: "card-2", type: .metric, size: .hero, style: .success, payloadJSON: Data()),
        ]

        let layout = AutoLayout(cards: cards, style: .neutral)

        #expect(layout.cards.count == 2)
        #expect(layout.style == .neutral)
    }

    @Test("accepts empty cards array")
    func acceptsEmptyCards() {
        let layout = AutoLayout(cards: [], style: .accent)

        #expect(layout.cards.isEmpty)
        #expect(layout.style == .accent)
    }

    @Test("public init signature matches other layouts")
    func publicInitSignature() {
        let cards: [CardModel] = []
        let style: CardStyle = .neutral
        let _: AutoLayout = AutoLayout(cards: cards, style: style)
    }

    @Test("body renders without crash when cards have valid payloads")
    func bodyRendersWithValidPayloads() {
        let metric = MetricPayload(items: [.init(label: "A", value: 1)])
        let digest = DigestPayload(title: "T", body: "B")
        let cards: [CardModel] = [
            CardModel(id: "c-hero", type: .metric, size: .hero, style: .neutral, payloadJSON: encode(metric)),
            CardModel(id: "c-small-1", type: .digest, size: .small, style: .neutral, payloadJSON: encode(digest)),
            CardModel(id: "c-small-2", type: .digest, size: .medium, style: .neutral, payloadJSON: encode(digest)),
        ]
        let layout = AutoLayout(cards: cards, style: .neutral)
        _ = layout.body
    }

    // MARK: - TokenGrid wiring
    //
    // Constitution §Size = Geometry Only — layout column span comes from
    // AIDashSize.gridSpan(size), NOT from CardType. AutoLayout must
    // delegate to the shared TokenGrid and must not branch on CardType
    // or invent its own card chrome.

    @Test("AutoLayout source delegates to TokenGrid and never switches on CardType")
    func autoLayoutDelegatesAndAvoidsCardTypeBranching() throws {
        let source = try readLayoutSource("AutoLayout.swift")

        #expect(source.contains("TokenGrid("),
                "AutoLayout must delegate placement to TokenGrid")
        #expect(!source.contains("switch card.type"),
                "AutoLayout must not branch on CardType")
        #expect(!source.contains("CardType."),
                "AutoLayout must not reference any CardType cases")
        #expect(!source.contains(".cardChrome"),
                "AutoLayout must not apply card chrome — that lives in CardView")
        #expect(!source.contains(".background("),
                "AutoLayout must not paint its own background")
    }

    // MARK: - Content-derived effective span
    //
    // A prose card authored larger than its content justifies (e.g. a one-line
    // digest tagged `hero`) must span as its DOWNGRADED size, so it no longer
    // hogs a full row half-empty.

    @Test("a thin hero digest spans as small, packing inline with KPIs")
    func thinHeroDigestDowngradesSpan() {
        // Same resolution the grid performs, then pack with metric KPIs.
        let thinDigest = CardModel(
            id: "d", type: .digest, size: .hero, style: .neutral,
            payloadJSON: encode(DigestPayload(title: "T", body: "one line"))
        )
        let kpi = { (i: Int) in
            CardModel(id: "k\(i)", type: .metric, size: .small, style: .neutral,
                      payloadJSON: encode(MetricPayload(items: [.init(label: "A", value: 1)])))
        }
        let cards = [thinDigest, kpi(1), kpi(2), kpi(3)]

        let spans = cards.map { card in
            AIDashSize.gridSpan(EffectiveCardSize.resolve(
                type: card.type, authored: card.size, payloadJSON: card.payloadJSON))
        }
        // Thin hero digest resolved to small → span 1 (not .max/full-row).
        #expect(spans[0] == 1)

        // With a 4-column grid, all four now fit on ONE row (1+1+1+1), instead
        // of the digest forcing its own full-row and stranding the KPIs.
        let rows = TokenGrid.packRows(Array(cards.enumerated()), totalColumns: 4) { spans[$0.offset] }
        #expect(rows.count == 1)
        #expect(rows[0].count == 4)
    }

    @Test("a rich multi-section wide digest keeps its full-row span")
    func richDigestKeepsSpan() {
        let rich = CardModel(
            id: "d", type: .digest, size: .wide, style: .neutral,
            payloadJSON: encode(DigestPayload(
                title: "T", body: String(repeating: "x", count: 500),
                sections: [.init(heading: "a", paragraphs: ["p"]),
                           .init(heading: "b", paragraphs: ["p"])]))
        )
        let span = AIDashSize.gridSpan(EffectiveCardSize.resolve(
            type: rich.type, authored: rich.size, payloadJSON: rich.payloadJSON))
        #expect(span == AIDashSize.gridSpan(.wide)) // unchanged — content justifies wide
    }
}

/// Reads a Swift source file from `Sources/AIDashUI/Layout/<filename>` by
/// walking up from this test file. Used by the source-level assertions
/// that verify layouts delegate to `TokenGrid` without branching on
/// `CardType` or painting their own chrome (SwiftUI's view graph does not
/// expose enough to assert this at runtime).
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
