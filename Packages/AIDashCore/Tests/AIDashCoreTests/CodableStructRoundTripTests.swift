import Foundation
import Testing
@testable import AIDashCore

@Suite("Top-Level Codable Struct Round-Trip Tests")
struct CodableStructRoundTripTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Card

    @Test func cardRoundTrip() throws {
        let payloadData = try encoder.encode(MetricPayload(items: [
            MetricPayload.Item(label: "LOC", value: 500, unit: nil, trend: .up),
        ]))
        let card = Card(
            id: "card-001",
            type: .metric,
            size: .medium,
            style: .accent,
            payload: payloadData
        )
        let data = try encoder.encode(card)
        let decoded = try decoder.decode(Card.self, from: data)
        #expect(decoded.id == "card-001")
        #expect(decoded.type == .metric)
        #expect(decoded.size == .medium)
        #expect(decoded.style == .accent)
        #expect(decoded.payload == payloadData)
    }

    // MARK: - Container

    @Test func containerRoundTrip() throws {
        let payloadData = try encoder.encode(
            InsightPayload(title: "t", body: "b", citations: nil)
        )
        let card = Card(
            id: "c-1",
            type: .insight,
            size: .wide,
            style: .neutral,
            payload: payloadData
        )
        let container = Container(
            id: "ctr-001",
            title: "Morning Highlights",
            subtitle: "Top items",
            order: 10,
            layout: .grid,
            style: .success,
            cards: [card]
        )
        let data = try encoder.encode(container)
        let decoded = try decoder.decode(Container.self, from: data)
        #expect(decoded.id == "ctr-001")
        #expect(decoded.title == "Morning Highlights")
        #expect(decoded.subtitle == "Top items")
        #expect(decoded.order == 10)
        #expect(decoded.layout == .grid)
        #expect(decoded.style == .success)
        #expect(decoded.cards.count == 1)
        #expect(decoded.cards[0].id == "c-1")
    }

    @Test func containerNilSubtitleRoundTrip() throws {
        let container = Container(
            id: "ctr-002",
            title: "Section",
            subtitle: nil,
            order: 20,
            layout: .list,
            style: .neutral,
            cards: []
        )
        let data = try encoder.encode(container)
        let decoded = try decoder.decode(Container.self, from: data)
        #expect(decoded.subtitle == nil)
        #expect(decoded.cards.isEmpty)
    }

    // MARK: - Briefing

    @Test func briefingRoundTrip() throws {
        let now = Date()
        let briefing = Briefing(
            date: "2026-06-24",
            generatedAt: now,
            generatedBy: "claude-code",
            containers: [
                Container(
                    id: "ctr-1",
                    title: "Overview",
                    subtitle: nil,
                    order: 10,
                    layout: .auto,
                    style: .neutral,
                    cards: []
                ),
            ]
        )
        let data = try encoder.encode(briefing)
        let decoded = try decoder.decode(Briefing.self, from: data)
        #expect(decoded.date == "2026-06-24")
        #expect(decoded.generatedBy == "claude-code")
        #expect(decoded.containers.count == 1)
        #expect(decoded.containers[0].id == "ctr-1")
    }

    // MARK: - UserEvent

    @Test func userEventRoundTrip() throws {
        let ts = Date()
        let event = UserEvent(
            id: "evt-001",
            timestamp: ts,
            device: "Test iPhone [AABB]",
            cardId: "card-001",
            action: .done
        )
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(UserEvent.self, from: data)
        #expect(decoded.id == "evt-001")
        #expect(decoded.device == "Test iPhone [AABB]")
        #expect(decoded.cardId == "card-001")
        #expect(decoded.action == .done)
    }

    @Test func userEventStarActionRoundTrip() throws {
        let event = UserEvent(
            id: "evt-002",
            timestamp: Date(),
            device: "iPad [1234]",
            cardId: "card-002",
            action: .star
        )
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(UserEvent.self, from: data)
        #expect(decoded.action == .star)
    }

    // MARK: - Memberwise init accessibility

    @Test func publicMemberwiseInitAccessible() throws {
        // Verify all public inits compile and are callable from outside the module
        _ = Card(id: "x", type: .metric, size: .small, style: .neutral, payload: Data())
        _ = Container(id: "x", title: "t", subtitle: nil, order: 0, layout: .auto, style: .neutral, cards: [])
        _ = Briefing(date: "2026-01-01", generatedAt: Date(), generatedBy: "test", containers: [])
        _ = UserEvent(id: "x", timestamp: Date(), device: "d", cardId: "c", action: .done)
    }
}
