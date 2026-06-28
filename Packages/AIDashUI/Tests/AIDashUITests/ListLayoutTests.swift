import Testing
import SwiftUI
import Foundation
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("ListLayout Tests")
struct ListLayoutTests {
    private func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try! encoder.encode(value)
    }

    @Test("initializes with cards and style")
    func initializesWithCardsAndStyle() {
        let cards: [CardModel] = [
            CardModel(id: "card-1", type: .metric, size: .medium, style: .neutral, payloadJSON: Data()),
            CardModel(id: "card-2", type: .metric, size: .wide, style: .success, payloadJSON: Data()),
        ]

        let layout = ListLayout(cards: cards, style: .neutral)

        #expect(layout.cards.count == 2)
        #expect(layout.style == .neutral)
    }

    @Test("accepts empty cards array")
    func acceptsEmptyCards() {
        let layout = ListLayout(cards: [], style: .accent)

        #expect(layout.cards.isEmpty)
        #expect(layout.style == .accent)
    }

    @Test("body renders without crash when cards have valid payloads")
    func bodyRendersWithValidPayloads() {
        let todo = TodoListPayload(items: [.init(title: "Buy milk")])
        let insight = InsightPayload(title: "Hello", body: "World")
        let cards: [CardModel] = [
            CardModel(id: "c-todo", type: .todoList, size: .medium, style: .neutral, payloadJSON: encode(todo)),
            CardModel(id: "c-insight", type: .insight, size: .medium, style: .accent, payloadJSON: encode(insight)),
        ]
        let layout = ListLayout(cards: cards, style: .neutral)
        _ = layout.body
    }
}
