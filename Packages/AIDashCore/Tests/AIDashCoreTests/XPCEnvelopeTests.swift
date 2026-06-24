import Testing
import Foundation
@testable import AIDashCore

@Suite("XPC envelope")
struct XPCEnvelopeTests {

    @Test func requestRoundtrip() throws {
        let params = try JSONEncoder().encode(BriefingPutParams(
            date: "2026-06-23", generatedBy: "agent", published: false
        ))
        let req = XPCRequest(
            requestId: UUID().uuidString,
            cliVersion: "1.0.0",
            command: "briefing.put",
            params: params
        )
        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(XPCRequest.self, from: data)
        #expect(decoded.command == "briefing.put")
        #expect(decoded.cliVersion == "1.0.0")
    }

    @Test func responseSuccessRoundtrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let result = try encoder.encode(BriefingPutResult(
            date: "2026-06-23", generatedAt: .now, publishedAt: nil
        ))
        let resp = XPCResponse(
            requestId: UUID().uuidString, appVersion: "1.0.0",
            ok: true, data: result, error: nil
        )
        let data = try encoder.encode(resp)
        let decoded = try decoder.decode(XPCResponse.self, from: data)
        #expect(decoded.ok == true)
        #expect(decoded.data != nil)
        #expect(decoded.error == nil)
    }

    @Test func responseErrorRoundtrip() throws {
        let err = XPCError(
            code: "schema.unknown_card_type",
            message: "test",
            field: "type",
            got: "unicorn",
            allowed: ["metric", "insight"]
        )
        let resp = XPCResponse(
            requestId: UUID().uuidString, appVersion: "1.0.0",
            ok: false, data: nil, error: err
        )
        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(XPCResponse.self, from: data)
        #expect(decoded.ok == false)
        #expect(decoded.error?.code == "schema.unknown_card_type")
        #expect(decoded.error?.allowed?.count == 2)
    }

    @Test func cardPutParamsRoundtrip() throws {
        let p = CardPutParams(
            containerId: UUID().uuidString, id: UUID().uuidString,
            type: .digest, size: .hero, style: .neutral,
            payload: Data("{}".utf8)
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(CardPutParams.self, from: data)
        #expect(decoded.type == .digest)
        #expect(decoded.size == .hero)
    }

    @Test func eventsPullResultRoundtrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let events = [
            UserEvent(id: UUID().uuidString, timestamp: .now,
                      device: "iPhone [X]", cardId: UUID().uuidString, action: .done),
            UserEvent(id: UUID().uuidString, timestamp: .now,
                      device: "iPad [Y]", cardId: UUID().uuidString, action: .star),
        ]
        let r = EventsPullResult(events: events, count: 2)
        let data = try encoder.encode(r)
        let decoded = try decoder.decode(EventsPullResult.self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded.events[1].action == .star)
    }
}
