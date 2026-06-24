import Testing
import Foundation
@testable import AIDashCore

@Suite("XPC envelope")
struct XPCEnvelopeTests {

    @Test func requestRoundtrip() throws {
        let originalParams = BriefingPutParams(
            date: "2026-06-23", generatedBy: "agent", published: false
        )
        let params = try JSONEncoder().encode(originalParams)
        let requestId = UUID().uuidString
        let req = XPCRequest(
            requestId: requestId,
            cliVersion: "1.0.0",
            command: "briefing.put",
            params: params
        )
        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(XPCRequest.self, from: data)
        #expect(decoded.requestId == requestId)
        #expect(decoded.command == "briefing.put")
        #expect(decoded.cliVersion == "1.0.0")
        #expect(decoded.params == params)

        // Verify the payload decodes back to BriefingPutParams
        let decodedParams = try JSONDecoder().decode(BriefingPutParams.self, from: decoded.params)
        #expect(decodedParams.date == "2026-06-23")
        #expect(decodedParams.generatedBy == "agent")
        #expect(decodedParams.published == false)
    }

    @Test func responseSuccessRoundtrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let generatedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let originalResult = BriefingPutResult(
            date: "2026-06-23", generatedAt: generatedAt, publishedAt: nil
        )
        let result = try encoder.encode(originalResult)
        let requestId = UUID().uuidString
        let resp = XPCResponse(
            requestId: requestId, appVersion: "1.0.0",
            ok: true, data: result, error: nil
        )
        let data = try encoder.encode(resp)
        let decoded = try decoder.decode(XPCResponse.self, from: data)
        #expect(decoded.requestId == requestId)
        #expect(decoded.appVersion == "1.0.0")
        #expect(decoded.ok == true)
        #expect(decoded.data != nil)
        #expect(decoded.error == nil)

        // Verify the result payload decodes back correctly
        let decodedResult = try decoder.decode(BriefingPutResult.self, from: decoded.data!)
        #expect(decodedResult.date == "2026-06-23")
        #expect(decodedResult.generatedAt == generatedAt)
        #expect(decodedResult.publishedAt == nil)
    }

    @Test func responseErrorRoundtrip() throws {
        let err = XPCError(
            code: "schema.unknown_card_type",
            message: "Unknown card type provided",
            field: "type",
            got: "unicorn",
            allowed: ["metric", "insight"],
            cause: "validation failed"
        )
        let requestId = UUID().uuidString
        let resp = XPCResponse(
            requestId: requestId, appVersion: "2.1.0",
            ok: false, data: nil, error: err
        )
        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(XPCResponse.self, from: data)
        #expect(decoded.requestId == requestId)
        #expect(decoded.appVersion == "2.1.0")
        #expect(decoded.ok == false)
        #expect(decoded.data == nil)
        #expect(decoded.error?.code == "schema.unknown_card_type")
        #expect(decoded.error?.message == "Unknown card type provided")
        #expect(decoded.error?.field == "type")
        #expect(decoded.error?.got == "unicorn")
        #expect(decoded.error?.allowed == ["metric", "insight"])
        #expect(decoded.error?.cause == "validation failed")
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
