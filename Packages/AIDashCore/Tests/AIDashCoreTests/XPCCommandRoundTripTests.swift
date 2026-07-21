import Foundation
import Testing
@testable import AIDashCore

// MARK: - T033: XPC Command Params/Result round-trip tests

// MARK: - briefing.put

@Test func briefingPutParamsRoundTrip() throws {
    let original = BriefingPutParams(
        date: "2026-06-24",
        generatedBy: "claude-code",
        published: true
    )

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BriefingPutParams.self, from: data)

    #expect(decoded.date == "2026-06-24")
    #expect(decoded.generatedBy == "claude-code")
    #expect(decoded.published == true)
}

@Test func briefingPutResultRoundTrip() throws {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let original = BriefingPutResult(
        date: "2026-06-24",
        generatedAt: now,
        publishedAt: now
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BriefingPutResult.self, from: data)

    #expect(decoded.date == "2026-06-24")
    #expect(decoded.generatedAt == now)
    #expect(decoded.publishedAt == now)
}

@Test func briefingPutResultNilPublishedAt() throws {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let original = BriefingPutResult(
        date: "2026-06-24",
        generatedAt: now,
        publishedAt: nil
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(BriefingPutResult.self, from: data)

    #expect(decoded.publishedAt == nil)
}

// MARK: - card.put

@Test func cardPutParamsRoundTrip() throws {
    let payload = Data("{\"items\":[]}".utf8)
    let original = CardPutParams(
        containerId: "container-1",
        id: "card-1",
        type: .metric,
        size: .medium,
        style: .accent,
        payload: payload
    )

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(CardPutParams.self, from: data)

    #expect(decoded.containerId == "container-1")
    #expect(decoded.id == "card-1")
    #expect(decoded.type == .metric)
    #expect(decoded.size == .medium)
    #expect(decoded.style == .accent)
    #expect(decoded.payload == payload)
}

@Test func cardPutResultRoundTrip() throws {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let original = CardPutResult(
        id: "card-1",
        updatedAt: now,
        wasCreated: true
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(CardPutResult.self, from: data)

    #expect(decoded.id == "card-1")
    #expect(decoded.updatedAt == now)
    #expect(decoded.wasCreated == true)
}

// MARK: - events.pull

@Test func eventsPullParamsRoundTrip() throws {
    let since = Date(timeIntervalSince1970: 1_000_000)
    let until = Date(timeIntervalSince1970: 2_000_000)
    let original = EventsPullParams(
        since: since,
        until: until,
        cardId: "card-42",
        action: .done
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(EventsPullParams.self, from: data)

    #expect(decoded.since == since)
    #expect(decoded.until == until)
    #expect(decoded.cardId == "card-42")
    #expect(decoded.action == .done)
}

@Test func eventsPullParamsMinimalRoundTrip() throws {
    let since = Date(timeIntervalSince1970: 1_000_000)
    let original = EventsPullParams(
        since: since,
        until: nil,
        cardId: nil,
        action: nil
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(EventsPullParams.self, from: data)

    #expect(decoded.since == since)
    #expect(decoded.until == nil)
    #expect(decoded.cardId == nil)
    #expect(decoded.action == nil)
}

@Test func eventsPullResultRoundTrip() throws {
    let event = UserEvent(
        id: "evt-1",
        timestamp: Date(timeIntervalSince1970: 1_500_000),
        device: "iPhone",
        cardId: "card-42",
        action: .star
    )
    let original = EventsPullResult(events: [event], count: 1)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(EventsPullResult.self, from: data)

    #expect(decoded.count == 1)
    #expect(decoded.events.count == 1)
    #expect(decoded.events[0].id == "evt-1")
    #expect(decoded.events[0].action == .star)
}

// MARK: - events.pull itemRef filter (spec 002 D1 / T001)

@Test func eventsPullParamsWithItemRefFilterRoundTrip() throws {
    let since = Date(timeIntervalSince1970: 1_000_000)
    let original = EventsPullParams(
        since: since,
        until: nil,
        cardId: "radar-1",
        action: .star,
        itemRef: "https://github.com/vapor/vapor"
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(EventsPullParams.self, from: data)

    #expect(decoded.itemRef == "https://github.com/vapor/vapor")
    #expect(decoded.cardId == "radar-1")
    #expect(decoded.action == .star)
}

@Test func eventsPullParamsLegacyJSONWithoutItemRefDecodesAsNil() throws {
    // Simulates a payload from a pre-itemRef CLI. Forward-compat: itemRef
    // must decode as nil, filter is inactive.
    let legacyJSON = Data("""
    {
      "since": "2026-01-01T00:00:00Z",
      "until": null,
      "cardId": null,
      "action": null
    }
    """.utf8)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(EventsPullParams.self, from: legacyJSON)
    #expect(decoded.itemRef == nil)
    #expect(decoded.cardId == nil)
    #expect(decoded.action == nil)
}

@Test func eventsPullResultRoundTripPreservesItemRef() throws {
    let event = UserEvent(
        id: "evt-item",
        timestamp: Date(timeIntervalSince1970: 1_600_000),
        device: "Mac",
        cardId: "radar-1",
        action: .star,
        itemRef: "https://github.com/apple/swift"
    )
    let original = EventsPullResult(events: [event], count: 1)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(EventsPullResult.self, from: data)

    #expect(decoded.events[0].itemRef == "https://github.com/apple/swift")
}

// MARK: - schema.list

@Test func schemaListParamsRoundTrip() throws {
    let original = SchemaListParams()

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(SchemaListParams.self, from: data)

    #expect(decoded.type == nil)
}

@Test func schemaListParamsWithTypeRoundTrip() throws {
    let original = SchemaListParams(type: "metric")

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(SchemaListParams.self, from: data)

    #expect(decoded.type == "metric")

    // Verify the encoded JSON actually carries the field so a non-Swift
    // peer (the macOS app's XPC handler) would observe the filter.
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"type\""))
    #expect(json.contains("\"metric\""))
}

@Test func schemaListResultRoundTrip() throws {
    let payloads = [
        "metric": #"{"type":"object","properties":{"items":{"type":"array"}},"required":["items"]}"#,
        "insight": #"{"type":"object","properties":{"title":{"type":"string"},"body":{"type":"string"}},"required":["title","body"]}"#
    ]
    let original = SchemaListResult(
        cliVersion: "1.0.0",
        schemaVersion: "1",
        cardTypes: ["metric", "insight", "digest"],
        cardSizes: ["small", "medium", "wide", "hero"],
        cardStyles: ["neutral", "success", "warning", "accent"],
        containerLayouts: ["auto", "list", "grid", "hero"],
        userEventActions: ["done", "star"],
        payloads: payloads
    )

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(SchemaListResult.self, from: data)

    #expect(decoded.cliVersion == "1.0.0")
    #expect(decoded.schemaVersion == "1")
    #expect(decoded.cardTypes == ["metric", "insight", "digest"])
    #expect(decoded.cardSizes == ["small", "medium", "wide", "hero"])
    #expect(decoded.cardStyles == ["neutral", "success", "warning", "accent"])
    #expect(decoded.containerLayouts == ["auto", "list", "grid", "hero"])
    #expect(decoded.userEventActions == ["done", "star"])
    #expect(decoded.payloads["metric"] == payloads["metric"])
    #expect(decoded.payloads["insight"] == payloads["insight"])
}
