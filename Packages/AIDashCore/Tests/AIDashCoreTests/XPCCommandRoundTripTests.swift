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
    let legacyJSON = """
    {
      "since": "2026-01-01T00:00:00Z",
      "until": null,
      "cardId": null,
      "action": null
    }
    """.data(using: .utf8)!

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

// MARK: - Error envelope round-trip

@Test func errorEnvelopeRoundTrip() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let error = XPCError(
        code: "schema.unknown_card_type",
        message: "Unknown card type 'foo'",
        field: "type",
        got: "foo",
        allowed: ["metric", "insight", "digest"]
    )
    let response = XPCResponse(
        requestId: "req-err",
        appVersion: "1.0.0",
        ok: false,
        data: nil,
        error: error
    )
    let responseData = try encoder.encode(response)
    let decoded = try decoder.decode(XPCResponse.self, from: responseData)

    #expect(decoded.ok == false)
    #expect(decoded.data == nil)
    #expect(decoded.error?.code == "schema.unknown_card_type")
    #expect(decoded.error?.message == "Unknown card type 'foo'")
    #expect(decoded.error?.field == "type")
    #expect(decoded.error?.got == "foo")
    #expect(decoded.error?.allowed == ["metric", "insight", "digest"])
}

// MARK: - Remaining command envelope tests

@Test func briefingGetEnvelopeRoundTrip() throws {
    let params = BriefingGetParams(date: "2026-06-24")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let paramsData = try encoder.encode(params)
    let request = XPCRequest(
        requestId: "req-bg",
        cliVersion: "1.0.0",
        command: "briefing.get",
        params: paramsData
    )
    let requestData = try encoder.encode(request)
    let decodedRequest = try decoder.decode(XPCRequest.self, from: requestData)
    let decodedParams = try decoder.decode(BriefingGetParams.self, from: decodedRequest.params)

    #expect(decodedRequest.command == "briefing.get")
    #expect(decodedParams.date == "2026-06-24")

    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let briefing = Briefing(
        date: "2026-06-24",
        generatedAt: now,
        generatedBy: "claude-code",
        containers: []
    )
    let result = BriefingGetResult(briefing: briefing)
    let resultData = try encoder.encode(result)
    let response = XPCResponse(
        requestId: "req-bg",
        appVersion: "1.0.0",
        ok: true,
        data: resultData,
        error: nil
    )
    let responseData = try encoder.encode(response)
    let decodedResponse = try decoder.decode(XPCResponse.self, from: responseData)
    let decodedResult = try decoder.decode(BriefingGetResult.self, from: decodedResponse.data!)

    #expect(decodedResponse.ok == true)
    #expect(decodedResult.briefing.date == "2026-06-24")
    #expect(decodedResult.briefing.generatedBy == "claude-code")
}

@Test func briefingPublishEnvelopeRoundTrip() throws {
    let params = BriefingPublishParams(date: "2026-06-24")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let paramsData = try encoder.encode(params)
    let request = XPCRequest(
        requestId: "req-bp",
        cliVersion: "1.0.0",
        command: "briefing.publish",
        params: paramsData
    )
    let requestData = try encoder.encode(request)
    let decodedRequest = try decoder.decode(XPCRequest.self, from: requestData)
    let decodedParams = try decoder.decode(BriefingPublishParams.self, from: decodedRequest.params)

    #expect(decodedRequest.command == "briefing.publish")
    #expect(decodedParams.date == "2026-06-24")

    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let result = BriefingPublishResult(date: "2026-06-24", publishedAt: now)
    let resultData = try encoder.encode(result)
    let response = XPCResponse(
        requestId: "req-bp",
        appVersion: "1.0.0",
        ok: true,
        data: resultData,
        error: nil
    )
    let responseData = try encoder.encode(response)
    let decodedResponse = try decoder.decode(XPCResponse.self, from: responseData)
    let decodedResult = try decoder.decode(BriefingPublishResult.self, from: decodedResponse.data!)

    #expect(decodedResponse.ok == true)
    #expect(decodedResult.date == "2026-06-24")
    #expect(decodedResult.publishedAt == now)
}

@Test func containerPutEnvelopeRoundTrip() throws {
    let params = ContainerPutParams(
        briefingDate: "2026-06-24",
        id: "c-1",
        title: "Summary",
        subtitle: nil,
        order: 0,
        layout: .auto,
        style: .neutral
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let paramsData = try encoder.encode(params)
    let request = XPCRequest(
        requestId: "req-cp",
        cliVersion: "1.0.0",
        command: "container.put",
        params: paramsData
    )
    let requestData = try encoder.encode(request)
    let decodedRequest = try decoder.decode(XPCRequest.self, from: requestData)
    let decodedParams = try decoder.decode(ContainerPutParams.self, from: decodedRequest.params)

    #expect(decodedRequest.command == "container.put")
    #expect(decodedParams.id == "c-1")
    #expect(decodedParams.layout == .auto)

    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let result = ContainerPutResult(id: "c-1", updatedAt: now, wasCreated: true)
    let resultData = try encoder.encode(result)
    let response = XPCResponse(
        requestId: "req-cp",
        appVersion: "1.0.0",
        ok: true,
        data: resultData,
        error: nil
    )
    let responseData = try encoder.encode(response)
    let decodedResponse = try decoder.decode(XPCResponse.self, from: responseData)
    let decodedResult = try decoder.decode(ContainerPutResult.self, from: decodedResponse.data!)

    #expect(decodedResponse.ok == true)
    #expect(decodedResult.id == "c-1")
    #expect(decodedResult.wasCreated == true)
}

@Test func containerDeleteEnvelopeRoundTrip() throws {
    let params = ContainerDeleteParams(id: "c-1")
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let paramsData = try encoder.encode(params)
    let request = XPCRequest(
        requestId: "req-cd",
        cliVersion: "1.0.0",
        command: "container.delete",
        params: paramsData
    )
    let requestData = try encoder.encode(request)
    let decodedRequest = try decoder.decode(XPCRequest.self, from: requestData)
    let decodedParams = try decoder.decode(ContainerDeleteParams.self, from: decodedRequest.params)

    #expect(decodedRequest.command == "container.delete")
    #expect(decodedParams.id == "c-1")

    let result = ContainerDeleteResult()
    let resultData = try encoder.encode(result)
    let response = XPCResponse(
        requestId: "req-cd",
        appVersion: "1.0.0",
        ok: true,
        data: resultData,
        error: nil
    )
    let responseData = try encoder.encode(response)
    let decodedResponse = try decoder.decode(XPCResponse.self, from: responseData)
    let decodedResult = try decoder.decode(ContainerDeleteResult.self, from: decodedResponse.data!)

    #expect(decodedResponse.ok == true)
    _ = decodedResult // Empty struct, just verify decode succeeds
}

@Test func cardDeleteEnvelopeRoundTrip() throws {
    let params = CardDeleteParams(id: "card-99")
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let paramsData = try encoder.encode(params)
    let request = XPCRequest(
        requestId: "req-crd",
        cliVersion: "1.0.0",
        command: "card.delete",
        params: paramsData
    )
    let requestData = try encoder.encode(request)
    let decodedRequest = try decoder.decode(XPCRequest.self, from: requestData)
    let decodedParams = try decoder.decode(CardDeleteParams.self, from: decodedRequest.params)

    #expect(decodedRequest.command == "card.delete")
    #expect(decodedParams.id == "card-99")

    let result = CardDeleteResult()
    let resultData = try encoder.encode(result)
    let response = XPCResponse(
        requestId: "req-crd",
        appVersion: "1.0.0",
        ok: true,
        data: resultData,
        error: nil
    )
    let responseData = try encoder.encode(response)
    let decodedResponse = try decoder.decode(XPCResponse.self, from: responseData)
    let decodedResult = try decoder.decode(CardDeleteResult.self, from: decodedResponse.data!)

    #expect(decodedResponse.ok == true)
    _ = decodedResult // Empty struct, just verify decode succeeds
}
