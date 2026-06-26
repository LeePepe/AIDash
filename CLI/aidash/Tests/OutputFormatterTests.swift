import Foundation
import Testing
import AIDashCore

@Suite("OutputFormatter Tests")
struct OutputFormatterTests {

    // MARK: - AnyEncodable

    @Test("AnyEncodable encodes String")
    func anyEncodableString() throws {
        let wrapper = AnyEncodable("hello")
        let data = try JSONEncoder().encode(wrapper)
        let decoded = try JSONDecoder().decode(String.self, from: data)
        #expect(decoded == "hello")
    }

    @Test("AnyEncodable encodes struct")
    func anyEncodableStruct() throws {
        let sample = SamplePayload(name: "test", count: 7)
        let wrapper = AnyEncodable(sample)
        let data = try JSONEncoder().encode(wrapper)
        let decoded = try JSONDecoder().decode(SamplePayload.self, from: data)
        #expect(decoded.name == "test")
        #expect(decoded.count == 7)
    }

    // MARK: - OutputMode

    @Test("OutputMode.json returns JSONOutput")
    func outputModeJson() {
        let formatter = OutputMode.json.formatter()
        #expect(formatter is JSONOutput)
    }

    @Test("OutputMode.human returns HumanOutput")
    func outputModeHuman() {
        let formatter = OutputMode.human.formatter()
        #expect(formatter is HumanOutput)
    }

    // MARK: - JSONOutput encoder config

    @Test("JSONOutput encoder uses sortedKeys")
    func jsonOutputSortedKeys() throws {
        let payload: [String: Int] = ["zebra": 1, "apple": 2]
        let data = try JSONOutput.encoder.encode(payload)
        let json = String(data: data, encoding: .utf8)!
        // sortedKeys means "apple" appears before "zebra"
        let appleIndex = json.range(of: "apple")!.lowerBound
        let zebraIndex = json.range(of: "zebra")!.lowerBound
        #expect(appleIndex < zebraIndex)
    }

    @Test("JSONOutput encoder uses ISO8601 dates")
    func jsonOutputISO8601() throws {
        let date = Date(timeIntervalSince1970: 0) // 1970-01-01T00:00:00Z
        let wrapper = DateWrapper(date: date)
        let data = try JSONOutput.encoder.encode(wrapper)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("1970-01-01T00:00:00Z"))
    }

    // MARK: - Success envelope (cli-surface.md contract)

    @Test("CLISuccessEnvelope wraps payload in {ok, data, requestId}")
    func successEnvelopeShape() throws {
        let payload = SamplePayload(name: "ok", count: 1)
        let envelope = CLISuccessEnvelope(data: payload, requestId: "req-1")
        let data = try JSONOutput.encoder.encode(envelope)
        let obj = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(obj["ok"] as? Bool == true)
        #expect(obj["requestId"] as? String == "req-1")
        let body = try #require(obj["data"] as? [String: Any])
        #expect(body["name"] as? String == "ok")
        #expect(body["count"] as? Int == 1)
    }

    @Test("CLISuccessEnvelope always emits requestId (constitution §B.1)")
    func successEnvelopeRequestIdRequired() throws {
        // The type system enforces requestId: String (not optional);
        // confirm it's always serialised regardless of value.
        let payload = SamplePayload(name: "x", count: 0)
        let envelope = CLISuccessEnvelope(data: payload, requestId: "req-42")
        let data = try JSONOutput.encoder.encode(envelope)
        let obj = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(obj["requestId"] as? String == "req-42")
    }

    @Test("CLISuccessEnvelope keys sorted: data, ok, requestId")
    func successEnvelopeSortedKeys() throws {
        let payload = SamplePayload(name: "x", count: 0)
        let envelope = CLISuccessEnvelope(data: payload, requestId: "abc")
        let data = try JSONOutput.encoder.encode(envelope)
        let json = String(data: data, encoding: .utf8)!
        // sortedKeys = alphabetical: data < ok < requestId
        let dataIdx = json.range(of: "\"data\"")!.lowerBound
        let okIdx = json.range(of: "\"ok\"")!.lowerBound
        let ridIdx = json.range(of: "\"requestId\"")!.lowerBound
        #expect(dataIdx < okIdx)
        #expect(okIdx < ridIdx)
    }

    // MARK: - Error envelope (cli-surface.md contract)

    @Test("CLIErrorEnvelope wraps XPCError in ok:false envelope; excludes cause")
    func errorEnvelopeAllFields() throws {
        let error = XPCError(
            code: "test.error",
            message: "Something broke",
            field: "name",
            got: "bad",
            allowed: ["good", "better"],
            cause: "internal transport detail"
        )
        let envelope = CLIErrorEnvelope(from: error)
        let data = try JSONOutput.encoder.encode(envelope)
        let obj = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(obj["ok"] as? Bool == false)
        let body = try #require(obj["error"] as? [String: Any])
        #expect(body["code"] as? String == "test.error")
        #expect(body["message"] as? String == "Something broke")
        #expect(body["field"] as? String == "name")
        #expect(body["got"] as? String == "bad")
        #expect((body["allowed"] as? [String])?.contains("good") == true)
        // cause must NOT leak to CLI output
        #expect(body["cause"] == nil)
        let raw = String(data: data, encoding: .utf8)!
        #expect(!raw.contains("internal transport detail"))
    }

    @Test("CLIErrorEnvelope omits nil optional fields")
    func errorEnvelopeMinimal() throws {
        let error = XPCError(code: "minimal.error", message: "Minimal")
        let envelope = CLIErrorEnvelope(from: error)
        let data = try JSONOutput.encoder.encode(envelope)
        let obj = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let body = try #require(obj["error"] as? [String: Any])
        #expect(body["code"] as? String == "minimal.error")
        #expect(body["message"] as? String == "Minimal")
        #expect(body["got"] == nil)
        #expect(body["field"] == nil)
        #expect(body["allowed"] == nil)
        #expect(body["requestId"] == nil)
    }

    @Test("CLIErrorEnvelope nests requestId inside error object")
    func errorEnvelopeRequestIdNested() throws {
        let error = XPCError(code: "test.error", message: "Test")
        let envelope = CLIErrorEnvelope(from: error, requestId: "abc-123")
        let data = try JSONOutput.encoder.encode(envelope)
        let obj = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        // requestId must be inside `error`, not a sibling at the root.
        let body = try #require(obj["error"] as? [String: Any])
        #expect(body["requestId"] as? String == "abc-123")
        #expect(obj["requestId"] == nil)
    }
}

// MARK: - Test helpers

private struct SamplePayload: Codable, Sendable {
    let name: String
    let count: Int
}

private struct DateWrapper: Codable, Sendable {
    let date: Date
}
