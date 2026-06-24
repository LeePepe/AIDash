import Testing
@testable import AIDashCore

@Suite("DeviceIdentifier")
struct DeviceIdentifierTests {

    @Test("current() returns a non-empty string")
    func currentReturnsNonEmpty() {
        let result = DeviceIdentifier.current()
        #expect(!result.isEmpty)
    }

    @Test("current() matches expected format: <name> [<8-hex-chars>]")
    func currentMatchesFormat() {
        let result = DeviceIdentifier.current()
        // Format: "Some Name [3F2A4B1C]"
        let pattern = #/^.+ \[[0-9A-F]{8}\]$/#
        #expect(result.contains(pattern))
    }

    @Test("current() returns consistent results across calls")
    func currentIsConsistent() {
        let first = DeviceIdentifier.current()
        let second = DeviceIdentifier.current()
        #expect(first == second)
    }

    @Test("bracket suffix is exactly 8 uppercase hex characters")
    func bracketSuffixIsValid() {
        let result = DeviceIdentifier.current()
        guard let openBracket = result.lastIndex(of: "["),
              let closeBracket = result.lastIndex(of: "]") else {
            Issue.record("Missing brackets in result: \(result)")
            return
        }
        let suffix = String(result[result.index(after: openBracket)..<closeBracket])
        #expect(suffix.count == 8)
        let hexPattern = #/^[0-9A-F]{8}$/#
        #expect(suffix.contains(hexPattern))
    }

    @Test("name portion (before brackets) is non-empty")
    func namePortionIsNonEmpty() {
        let result = DeviceIdentifier.current()
        guard let openBracket = result.lastIndex(of: "[") else {
            Issue.record("Missing bracket in result: \(result)")
            return
        }
        let nameEnd = result.index(openBracket, offsetBy: -1)
        let name = String(result[result.startIndex..<nameEnd])
        #expect(!name.isEmpty)
    }
}
