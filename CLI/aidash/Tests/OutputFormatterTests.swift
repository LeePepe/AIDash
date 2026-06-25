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

    @Test("AnyEncodable encodes Int")
    func anyEncodableInt() throws {
        let wrapper = AnyEncodable(42)
        let data = try JSONEncoder().encode(wrapper)
        let decoded = try JSONDecoder().decode(Int.self, from: data)
        #expect(decoded == 42)
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

    // MARK: - XPCError encoding

    @Test("JSONOutput encodes XPCError with all fields")
    func jsonOutputXPCErrorFields() throws {
        let error = XPCError(
            code: "test.error",
            message: "Something broke",
            field: "name",
            got: "bad",
            allowed: ["good", "better"]
        )
        let data = try JSONOutput.encoder.encode(error)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"code\":\"test.error\""))
        #expect(json.contains("\"message\":\"Something broke\""))
        #expect(json.contains("\"field\":\"name\""))
        #expect(json.contains("\"got\":\"bad\""))
        #expect(json.contains("\"allowed\""))
    }

    @Test("JSONOutput encodes XPCError with nil optional fields")
    func jsonOutputXPCErrorMinimal() throws {
        let error = XPCError(code: "minimal.error", message: "Minimal")
        let data = try JSONOutput.encoder.encode(error)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"code\":\"minimal.error\""))
        // nil fields should not appear (or appear as null depending on Codable impl)
        #expect(!json.contains("\"got\""))
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
