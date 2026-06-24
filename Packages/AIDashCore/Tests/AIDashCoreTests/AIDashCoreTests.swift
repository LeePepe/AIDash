import Testing
import Foundation
@testable import AIDashCore

@Test func placeholder() async throws {
    #expect(true)
}

@Test func cardModelInit() throws {
    let payload = try JSONEncoder().encode(["key": "value"])
    let card = CardModel(
        id: "test-uuid",
        type: .metric,
        size: .medium,
        style: .neutral,
        payloadJSON: payload
    )

    #expect(card.id == "test-uuid")
    #expect(card.typeRaw == "metric")
    #expect(card.sizeRaw == "medium")
    #expect(card.styleRaw == "neutral")
    #expect(card.payloadJSON == payload)
    #expect(card.container == nil)
}

@Test func cardModelComputedProperties() throws {
    let payload = Data()
    let card = CardModel(
        id: "test-uuid-2",
        type: .insight,
        size: .wide,
        style: .success,
        payloadJSON: payload
    )

    #expect(card.type == .insight)
    #expect(card.size == .wide)
    #expect(card.style == .success)
}

@Test func cardModelAllCardTypes() throws {
    let payload = Data()
    for cardType in CardType.allCases {
        let card = CardModel(
            id: "test-\(cardType.rawValue)",
            type: cardType,
            size: .small,
            style: .neutral,
            payloadJSON: payload
        )
        #expect(card.type == cardType)
        #expect(card.typeRaw == cardType.rawValue)
    }
}
