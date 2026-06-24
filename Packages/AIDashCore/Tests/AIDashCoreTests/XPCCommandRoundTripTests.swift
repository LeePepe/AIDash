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

// MARK: - schema.list

@Test func schemaListParamsRoundTrip() throws {
    let original = SchemaListParams()

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(original)
    let decoded = try decoder.decode(SchemaListParams.self, from: data)

    // Empty struct — just verify it round-trips without error
    _ = decoded
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

// MARK: - XPC Envelope round-trip tests

@Test func briefingPutEnvelopeRoundTrip() throws {
    let params = BriefingPutParams(
        date: "2026-06-24",
        generatedBy: "claude-code",
        published: false
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    // Encode params into XPCRequest.params
    let paramsData = try encoder.encode(params)
    let request = XPCRequest(
        requestId: "req-001",
        cliVersion: "1.0.0",
        command: "briefing.put",
        params: paramsData
    )
    let requestData = try encoder.encode(request)
    let decodedRequest = try decoder.decode(XPCRequest.self, from: requestData)
    let decodedParams = try decoder.decode(BriefingPutParams.self, from: decodedRequest.params)

    #expect(decodedRequest.command == "briefing.put")
    #expect(decodedParams.date == "2026-06-24")
    #expect(decodedParams.generatedBy == "claude-code")
    #expect(decodedParams.published == false)

    // Encode result into XPCResponse.data
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let result = BriefingPutResult(date: "2026-06-24", generatedAt: now, publishedAt: nil)
    let resultData = try encoder.encode(result)
    let response = XPCResponse(
        requestId: "req-001",
        appVersion: "1.0.0",
        ok: true,
        data: resultData,
        error: nil
    )
    let responseData = try encoder.encode(response)
    let decodedResponse = try decoder.decode(XPCResponse.self, from: responseData)
    let decodedResult = try decoder.decode(BriefingPutResult.self, from: decodedResponse.data!)

    #expect(decodedResponse.ok == true)
    #expect(decodedResult.date == "2026-06-24")
    #expect(decodedResult.generatedAt == now)
    #expect(decodedResult.publishedAt == nil)
}

@Test func cardPutEnvelopeRoundTrip() throws {
    let payload = Data("{\"items\":[]}".utf8)
    let params = CardPutParams(
        containerId: "container-1",
        id: "card-1",
        type: .metric,
        size: .medium,
        style: .accent,
        payload: payload
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let paramsData = try encoder.encode(params)
    let request = XPCRequest(
        requestId: "req-002",
        cliVersion: "1.0.0",
        command: "card.put",
        params: paramsData
    )
    let requestData = try encoder.encode(request)
    let decodedRequest = try decoder.decode(XPCRequest.self, from: requestData)
    let decodedParams = try decoder.decode(CardPutParams.self, from: decodedRequest.params)

    #expect(decodedRequest.command == "card.put")
    #expect(decodedParams.type == .metric)
    #expect(decodedParams.size == .medium)
    #expect(decodedParams.payload == payload)

    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let result = CardPutResult(id: "card-1", updatedAt: now, wasCreated: true)
    let resultData = try encoder.encode(result)
    let response = XPCResponse(
        requestId: "req-002",
        appVersion: "1.0.0",
        ok: true,
        data: resultData,
        error: nil
    )
    let responseData = try encoder.encode(response)
    let decodedResponse = try decoder.decode(XPCResponse.self, from: responseData)
    let decodedResult = try decoder.decode(CardPutResult.self, from: decodedResponse.data!)

    #expect(decodedResponse.ok == true)
    #expect(decodedResult.id == "card-1")
    #expect(decodedResult.wasCreated == true)
}

@Test func eventsPullEnvelopeRoundTrip() throws {
    let since = Date(timeIntervalSince1970: 1_000_000)
    let params = EventsPullParams(since: since, until: nil, cardId: nil, action: nil)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let paramsData = try encoder.encode(params)
    let request = XPCRequest(
        requestId: "req-003",
        cliVersion: "1.0.0",
        command: "events.pull",
        params: paramsData
    )
    let requestData = try encoder.encode(request)
    let decodedRequest = try decoder.decode(XPCRequest.self, from: requestData)
    let decodedParams = try decoder.decode(EventsPullParams.self, from: decodedRequest.params)

    #expect(decodedRequest.command == "events.pull")
    #expect(decodedParams.since == since)

    let event = UserEvent(
        id: "evt-1",
        timestamp: Date(timeIntervalSince1970: 1_500_000),
        device: "iPhone",
        cardId: "card-42",
        action: .star
    )
    let result = EventsPullResult(events: [event], count: 1)
    let resultData = try encoder.encode(result)
    let response = XPCResponse(
        requestId: "req-003",
        appVersion: "1.0.0",
        ok: true,
        data: resultData,
        error: nil
    )
    let responseData = try encoder.encode(response)
    let decodedResponse = try decoder.decode(XPCResponse.self, from: responseData)
    let decodedResult = try decoder.decode(EventsPullResult.self, from: decodedResponse.data!)

    #expect(decodedResponse.ok == true)
    #expect(decodedResult.count == 1)
    #expect(decodedResult.events[0].action == .star)
}

@Test func schemaListEnvelopeRoundTrip() throws {
    let params = SchemaListParams()
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let paramsData = try encoder.encode(params)
    let request = XPCRequest(
        requestId: "req-004",
        cliVersion: "1.0.0",
        command: "schema.list",
        params: paramsData
    )
    let requestData = try encoder.encode(request)
    let decodedRequest = try decoder.decode(XPCRequest.self, from: requestData)

    #expect(decodedRequest.command == "schema.list")

    let result = SchemaListResult(
        cliVersion: "1.0.0",
        schemaVersion: "1",
        cardTypes: ["metric"],
        cardSizes: ["small"],
        cardStyles: ["neutral"],
        containerLayouts: ["auto"],
        userEventActions: ["done"],
        payloads: ["metric": #"{"type":"object"}"#]
    )
    let resultData = try encoder.encode(result)
    let response = XPCResponse(
        requestId: "req-004",
        appVersion: "1.0.0",
        ok: true,
        data: resultData,
        error: nil
    )
    let responseData = try encoder.encode(response)
    let decodedResponse = try decoder.decode(XPCResponse.self, from: responseData)
    let decodedResult = try decoder.decode(SchemaListResult.self, from: decodedResponse.data!)

    #expect(decodedResponse.ok == true)
    #expect(decodedResult.cardTypes == ["metric"])
    #expect(decodedResult.payloads["metric"] == #"{"type":"object"}"#)
}
