import Testing
import Foundation
import SwiftData
@testable import AIDashCore

@Suite("CardModel Tests")
struct CardModelTests {

    // MARK: - Init & Stored Properties

    @Test("init stores correct raw values and payload")
    func cardModelInit() {
        let payload = Data("{\"value\":42}".utf8)
        let card = CardModel(
            id: "test-id",
            type: .metric,
            size: .medium,
            style: .neutral,
            payloadJSON: payload
        )

        #expect(card.id == "test-id")
        #expect(card.typeRaw == "metric")
        #expect(card.sizeRaw == "medium")
        #expect(card.styleRaw == "neutral")
        #expect(card.payloadJSON == payload)
        #expect(card.container == nil)
    }

    // MARK: - Computed Properties

    @Test("computed type/size/style return typed enums")
    func computedProperties() {
        let card = CardModel(
            id: "cp-1",
            type: .insight,
            size: .wide,
            style: .success,
            payloadJSON: Data()
        )

        #expect(card.type == .insight)
        #expect(card.size == .wide)
        #expect(card.style == .success)
    }

    @Test("computed setters update raw values")
    func computedSetters() {
        let card = CardModel(
            id: "cs-1",
            type: .metric,
            size: .small,
            style: .neutral,
            payloadJSON: Data()
        )

        card.type = .trending
        card.size = .hero
        card.style = .warning

        #expect(card.typeRaw == "trending")
        #expect(card.sizeRaw == "hero")
        #expect(card.styleRaw == "warning")
    }

    // MARK: - Parametric Enum Coverage

    @Test("all CardType cases round-trip through rawValue", arguments: CardType.allCases)
    func allCardTypes(type: CardType) {
        let card = CardModel(id: "t-\(type.rawValue)", type: type, size: .medium, style: .neutral, payloadJSON: Data())
        #expect(card.type == type)
    }

    @Test("all CardSize cases round-trip through rawValue", arguments: CardSize.allCases)
    func allCardSizes(size: CardSize) {
        let card = CardModel(id: "s-\(size.rawValue)", type: .metric, size: size, style: .neutral, payloadJSON: Data())
        #expect(card.size == size)
    }

    @Test("all CardStyle cases round-trip through rawValue", arguments: CardStyle.allCases)
    func allCardStyles(style: CardStyle) {
        let card = CardModel(id: "st-\(style.rawValue)", type: .metric, size: .medium, style: style, payloadJSON: Data())
        #expect(card.style == style)
    }

    // MARK: - Payload Preservation

    @Test("payloadJSON preserves arbitrary data")
    func payloadPreservation() {
        let json = """
        {"title":"Hello","value":3.14,"items":["a","b","c"]}
        """
        let payload = Data(json.utf8)
        let card = CardModel(id: "pp-1", type: .digest, size: .wide, style: .accent, payloadJSON: payload)
        #expect(card.payloadJSON == payload)
    }

    // MARK: - Unknown Raw Value Fallback

    @Test("unknown typeRaw falls back to .metric")
    func unknownTypeFallback() {
        let card = CardModel(id: "uf-1", type: .metric, size: .medium, style: .neutral, payloadJSON: Data())
        card.typeRaw = "nonexistent"
        #expect(card.type == .metric)
    }

    @Test("unknown sizeRaw falls back to .medium")
    func unknownSizeFallback() {
        let card = CardModel(id: "uf-2", type: .metric, size: .medium, style: .neutral, payloadJSON: Data())
        card.sizeRaw = "nonexistent"
        #expect(card.size == .medium)
    }

    @Test("unknown styleRaw falls back to .neutral")
    func unknownStyleFallback() {
        let card = CardModel(id: "uf-3", type: .metric, size: .medium, style: .neutral, payloadJSON: Data())
        card.styleRaw = "nonexistent"
        #expect(card.style == .neutral)
    }

    // MARK: - ContainerModel.cards Relationship

    @Test("ContainerModel.cards initializes empty")
    func containerCardsInitializesEmpty() {
        let container = ContainerModel(
            id: "c-1", title: "Test", subtitle: nil, order: 0,
            layout: .auto, style: .neutral
        )
        #expect(container.cards.isEmpty)
    }

    @Test("ContainerModel.cards relationship in-memory assignment")
    func containerCardsRelationship() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(
            for: BriefingModel.self, ContainerModel.self, CardModel.self,
            configurations: config
        )
        let context = ModelContext(modelContainer)

        let container = ContainerModel(
            id: "rel-c1", title: "Section", subtitle: nil, order: 0,
            layout: .auto, style: .neutral
        )
        context.insert(container)

        let card = CardModel(
            id: "rel-card1", type: .metric, size: .small,
            style: .success, payloadJSON: Data("{\"v\":1}".utf8)
        )
        context.insert(card)
        card.container = container

        try context.save()

        #expect(container.cards.count == 1)
        #expect(container.cards.first?.id == "rel-card1")
        #expect(card.container?.id == "rel-c1")
    }

    @Test("ContainerModel cascade delete removes child cards")
    func containerCardsCascadeDelete() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(
            for: BriefingModel.self, ContainerModel.self, CardModel.self,
            configurations: config
        )
        let context = ModelContext(modelContainer)

        let container = ContainerModel(
            id: "cas-c1", title: "Cascade", subtitle: nil, order: 0,
            layout: .auto, style: .neutral
        )
        context.insert(container)

        let card1 = CardModel(id: "cas-1", type: .metric, size: .medium, style: .neutral, payloadJSON: Data())
        let card2 = CardModel(id: "cas-2", type: .insight, size: .wide, style: .accent, payloadJSON: Data())
        context.insert(card1)
        context.insert(card2)
        card1.container = container
        card2.container = container
        try context.save()

        #expect(container.cards.count == 2)

        context.delete(container)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<CardModel>())
        #expect(remaining.isEmpty)
    }
}
