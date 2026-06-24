import Testing
import Foundation
import SwiftData
@testable import AIDashCore

@Test func cardModelInit() async throws {
    let payload = Data("{\"items\":[]}".utf8)
    let card = CardModel(
        id: "CARD-1",
        type: .metric,
        size: .medium,
        style: .neutral,
        payloadJSON: payload
    )

    #expect(card.id == "CARD-1")
    #expect(card.typeRaw == "metric")
    #expect(card.sizeRaw == "medium")
    #expect(card.styleRaw == "neutral")
    #expect(card.payloadJSON == payload)
    #expect(card.container == nil)
}

@Test func cardModelComputedProperties() async throws {
    let card = CardModel(
        id: "CARD-2",
        type: .insight,
        size: .wide,
        style: .accent,
        payloadJSON: Data()
    )

    #expect(card.type == .insight)
    #expect(card.size == .wide)
    #expect(card.style == .accent)
}

@Test func cardModelComputedSetters() async throws {
    let card = CardModel(
        id: "CARD-3",
        type: .metric,
        size: .small,
        style: .neutral,
        payloadJSON: Data()
    )

    card.type = .digest
    card.size = .hero
    card.style = .warning

    #expect(card.typeRaw == "digest")
    #expect(card.sizeRaw == "hero")
    #expect(card.styleRaw == "warning")
    #expect(card.type == .digest)
    #expect(card.size == .hero)
    #expect(card.style == .warning)
}

@Test(arguments: CardType.allCases)
func cardModelAllCardTypes(cardType: CardType) async throws {
    let card = CardModel(
        id: "CT-\(cardType.rawValue)",
        type: cardType,
        size: .medium,
        style: .neutral,
        payloadJSON: Data()
    )

    #expect(card.typeRaw == cardType.rawValue)
    #expect(card.type == cardType)
}

@Test(arguments: CardSize.allCases)
func cardModelAllCardSizes(cardSize: CardSize) async throws {
    let card = CardModel(
        id: "CS-\(cardSize.rawValue)",
        type: .metric,
        size: cardSize,
        style: .neutral,
        payloadJSON: Data()
    )

    #expect(card.sizeRaw == cardSize.rawValue)
    #expect(card.size == cardSize)
}

@Test(arguments: CardStyle.allCases)
func cardModelAllCardStyles(cardStyle: CardStyle) async throws {
    let card = CardModel(
        id: "CST-\(cardStyle.rawValue)",
        type: .metric,
        size: .medium,
        style: cardStyle,
        payloadJSON: Data()
    )

    #expect(card.styleRaw == cardStyle.rawValue)
    #expect(card.style == cardStyle)
}

@Test func cardModelPayloadPreservation() async throws {
    let json = """
    {"title":"Test Insight","body":"Details here","citations":null}
    """
    let payload = Data(json.utf8)
    let card = CardModel(
        id: "CARD-P",
        type: .insight,
        size: .wide,
        style: .success,
        payloadJSON: payload
    )

    #expect(card.payloadJSON == payload)
    #expect(String(data: card.payloadJSON, encoding: .utf8) == json)
}

@Test func cardModelUnknownRawValueFallback() async throws {
    let card = CardModel(
        id: "CARD-F",
        type: .metric,
        size: .medium,
        style: .neutral,
        payloadJSON: Data()
    )

    // Simulate corrupted raw values — computed properties should fall back gracefully
    card.typeRaw = "unknownType"
    card.sizeRaw = "unknownSize"
    card.styleRaw = "unknownStyle"

    #expect(card.type == .metric)
    #expect(card.size == .medium)
    #expect(card.style == .neutral)
}

// MARK: - ContainerModel.cards relationship tests

@Test func containerCardsInitializesEmpty() async throws {
    let container = ContainerModel(
        id: "REL-C1",
        title: "Test",
        subtitle: nil,
        order: 0,
        layout: .auto,
        style: .neutral
    )

    #expect(container.cards.isEmpty)
}

@Test func containerCardsRelationshipInMemory() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: BriefingModel.self, ContainerModel.self, CardModel.self,
        configurations: config
    )
    let context = ModelContext(container)

    let cont = ContainerModel(
        id: "REL-C2",
        title: "Metrics",
        subtitle: nil,
        order: 1,
        layout: .list,
        style: .neutral
    )
    context.insert(cont)

    let card = CardModel(
        id: "REL-CARD1",
        type: .metric,
        size: .medium,
        style: .neutral,
        payloadJSON: Data("{\"value\":42}".utf8)
    )
    card.container = cont
    context.insert(card)
    try context.save()

    // Verify inverse: container.cards contains the card
    #expect(cont.cards.count == 1)
    #expect(cont.cards.first?.id == "REL-CARD1")

    // Verify forward: card.container points back
    #expect(card.container?.id == "REL-C2")
}

@Test func containerCardsCascadeDelete() async throws {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: BriefingModel.self, ContainerModel.self, CardModel.self,
        configurations: config
    )
    let context = ModelContext(container)

    let cont = ContainerModel(
        id: "REL-C3",
        title: "Cascade",
        subtitle: nil,
        order: 0,
        layout: .grid,
        style: .accent
    )
    context.insert(cont)

    let card1 = CardModel(
        id: "REL-CARD2",
        type: .insight,
        size: .wide,
        style: .success,
        payloadJSON: Data()
    )
    card1.container = cont

    let card2 = CardModel(
        id: "REL-CARD3",
        type: .digest,
        size: .medium,
        style: .neutral,
        payloadJSON: Data()
    )
    card2.container = cont

    context.insert(card1)
    context.insert(card2)
    try context.save()

    #expect(cont.cards.count == 2)

    // Delete the container — cascade should remove its cards
    context.delete(cont)
    try context.save()

    let remainingCards = try context.fetch(FetchDescriptor<CardModel>())
    #expect(remainingCards.isEmpty)
}
