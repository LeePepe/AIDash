import Testing
import Foundation
@testable import AIDashCore

@Suite("CardModel Tests")
struct CardModelTests {
    private func samplePayload() throws -> Data {
        let payload = MetricPayload(items: [
            MetricPayload.Item(label: "Tasks", value: 42, unit: nil, trend: .up)
        ])
        return try JSONEncoder().encode(payload)
    }

    @Test func initStoresRawValues() throws {
        let data = try samplePayload()
        let card = CardModel(
            id: "test-id",
            type: .metric,
            size: .medium,
            style: .neutral,
            payloadJSON: data
        )

        #expect(card.id == "test-id")
        #expect(card.typeRaw == "metric")
        #expect(card.sizeRaw == "medium")
        #expect(card.styleRaw == "neutral")
        #expect(card.payloadJSON == data)
    }

    @Test func computedPropertiesReturnTypedEnums() throws {
        let data = try samplePayload()
        let card = CardModel(
            id: "test-id",
            type: .insight,
            size: .wide,
            style: .success,
            payloadJSON: data
        )

        #expect(card.type == .insight)
        #expect(card.size == .wide)
        #expect(card.style == .success)
    }

    @Test(arguments: CardType.allCases)
    func allCardTypesRoundTrip(cardType: CardType) throws {
        let data = try samplePayload()
        let card = CardModel(
            id: "card-\(cardType.rawValue)",
            type: cardType,
            size: .small,
            style: .accent,
            payloadJSON: data
        )

        #expect(card.typeRaw == cardType.rawValue)
        #expect(card.type == cardType)
    }

    @Test(arguments: CardSize.allCases)
    func allCardSizesRoundTrip(cardSize: CardSize) throws {
        let data = try samplePayload()
        let card = CardModel(
            id: "card-\(cardSize.rawValue)",
            type: .metric,
            size: cardSize,
            style: .neutral,
            payloadJSON: data
        )

        #expect(card.sizeRaw == cardSize.rawValue)
        #expect(card.size == cardSize)
    }

    @Test(arguments: CardStyle.allCases)
    func allCardStylesRoundTrip(cardStyle: CardStyle) throws {
        let data = try samplePayload()
        let card = CardModel(
            id: "card-\(cardStyle.rawValue)",
            type: .metric,
            size: .medium,
            style: cardStyle,
            payloadJSON: data
        )

        #expect(card.styleRaw == cardStyle.rawValue)
        #expect(card.style == cardStyle)
    }

    @Test func payloadDataPreservedExactly() throws {
        let data = try samplePayload()
        let card = CardModel(
            id: "payload-test",
            type: .metric,
            size: .medium,
            style: .neutral,
            payloadJSON: data
        )

        let decoded = try JSONDecoder().decode(MetricPayload.self, from: card.payloadJSON)
        #expect(decoded.items.count == 1)
        #expect(decoded.items[0].label == "Tasks")
        #expect(decoded.items[0].value == 42)
        #expect(decoded.items[0].trend == .up)
    }
}
