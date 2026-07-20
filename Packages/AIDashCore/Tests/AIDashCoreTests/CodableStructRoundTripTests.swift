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
        // Use a whole-second date so ISO8601 round-trip is lossless
        let now = Date(timeIntervalSince1970: Double(Int(Date().timeIntervalSince1970)))
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
        #expect(decoded.generatedAt == now)
        #expect(decoded.generatedBy == "claude-code")
        #expect(decoded.containers.count == 1)
        #expect(decoded.containers[0].id == "ctr-1")
        #expect(decoded.publishedAt == nil)
    }

    /// MY-1047: `briefing.get` must surface `publishedAt` so callers can
    /// verify a prior `briefing.publish` without inspecting the SwiftData
    /// store. The Briefing wire type carries the timestamp through encode
    /// and decode.
    @Test func briefingRoundTripWithPublishedAt() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let publishedAt = Date(timeIntervalSince1970: 1_750_000_500)
        let briefing = Briefing(
            date: "2026-06-28",
            generatedAt: generatedAt,
            generatedBy: "claude-code",
            publishedAt: publishedAt,
            containers: []
        )
        let data = try encoder.encode(briefing)
        let decoded = try decoder.decode(Briefing.self, from: data)
        #expect(decoded.publishedAt == publishedAt)

        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["publishedAt"] is String)
    }

    /// Backward compatibility: payloads written by an older app version that
    /// predates the `publishedAt` field must continue to decode. The missing
    /// key surfaces as `nil`, never a decoding failure.
    @Test func briefingDecodesLegacyPayloadWithoutPublishedAt() throws {
        let legacyJSON = #"""
        {
          "date": "2026-06-28",
          "generatedAt": "2026-06-28T11:00:00Z",
          "generatedBy": "legacy-agent",
          "containers": []
        }
        """#
        let data = Data(legacyJSON.utf8)
        let decoded = try decoder.decode(Briefing.self, from: data)
        #expect(decoded.date == "2026-06-28")
        #expect(decoded.generatedBy == "legacy-agent")
        #expect(decoded.publishedAt == nil)
    }

    // MARK: - UserEvent

    @Test func userEventRoundTrip() throws {
        // Use a whole-second date so ISO8601 round-trip is lossless
        let ts = Date(timeIntervalSince1970: Double(Int(Date().timeIntervalSince1970)))
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
        #expect(decoded.timestamp == ts)
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
        #expect(decoded.itemRef == nil)
    }

    // MARK: - UserEvent.itemRef (spec 002 D1 / T001)

    @Test func userEventWithItemRefRoundTrip() throws {
        let ts = Date(timeIntervalSince1970: Double(Int(Date().timeIntervalSince1970)))
        let event = UserEvent(
            id: "evt-item-1",
            timestamp: ts,
            device: "Mac [CAFEBABE]",
            cardId: "radar-card-42",
            action: .star,
            itemRef: "https://github.com/vapor/vapor"
        )
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(UserEvent.self, from: data)
        #expect(decoded.id == "evt-item-1")
        #expect(decoded.action == .star)
        #expect(decoded.itemRef == "https://github.com/vapor/vapor")
        #expect(decoded.cardId == "radar-card-42")
    }

    @Test func userEventLegacyJSONWithoutItemRefDecodesAsNil() throws {
        // Simulates a payload written by a pre-itemRef producer (older CloudKit
        // record, older CLI). The forward-compat contract requires it to decode
        // without error and expose itemRef == nil.
        let legacyJSON = """
        {
          "id": "evt-legacy-1",
          "timestamp": "2026-01-01T00:00:00Z",
          "device": "iPhone [DEADBEEF]",
          "cardId": "card-legacy",
          "action": "done"
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode(UserEvent.self, from: legacyJSON)
        #expect(decoded.id == "evt-legacy-1")
        #expect(decoded.action == .done)
        #expect(decoded.itemRef == nil)
    }

    @Test func userEventWithItemRefEmitsKey() throws {
        let event = UserEvent(
            id: "evt-emit",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            device: "Mac",
            cardId: "card-x",
            action: .star,
            itemRef: "https://github.com/apple/swift"
        )
        let data = try encoder.encode(event)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"itemRef\""))
        // JSONEncoder escapes forward slashes; check the host substring instead
        #expect(json.contains("github.com"))
        #expect(json.contains("apple"))
    }

}
