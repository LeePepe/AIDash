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
        return try! encoder.encode(value)
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
}
