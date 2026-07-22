import Foundation
import Testing
import AIDashCore

/// Tests for `aidash events pull` (spec 002 T002 — star feedback loop read
/// path). Covers the Constitution §G.3 gate (success + validation-failure
/// paths) for the command's local helpers: bound parsing, action parsing,
/// card-id validation, and the contract's JSONL rendering.
@Suite("EventsPullCommand")
struct EventsPullCommandTests {

    // MARK: - Bound parsing (EventsPullCommand.parseBound)

    @Test("parseBound('yesterday') -> local midnight yesterday")
    func parsesYesterday() throws {
        let date = try EventsPullCommand.parseBound("yesterday", field: "--since")
        #expect(Calendar.current.isDateInYesterday(date))
        #expect(Calendar.current.component(.hour, from: date) == 0)
        #expect(Calendar.current.component(.minute, from: date) == 0)
    }

    @Test("parseBound is case-insensitive for sugar values")
    func parsesSugarCaseInsensitive() throws {
        let date = try EventsPullCommand.parseBound("Yesterday", field: "--since")
        #expect(Calendar.current.isDateInYesterday(date))
    }

    @Test("parseBound('YYYY-MM-DD') -> local midnight of that day")
    func parsesDateOnly() throws {
        let date = try EventsPullCommand.parseBound("2026-07-20", field: "--since")
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 20)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
    }

    @Test("parseBound accepts full ISO-8601 timestamps")
    func parsesISO8601() throws {
        let plain = try EventsPullCommand.parseBound("2026-07-20T04:00:00Z", field: "--since")
        let fractional = try EventsPullCommand.parseBound("2026-07-20T04:00:00.000Z", field: "--since")
        #expect(plain == fractional)
        #expect(plain.timeIntervalSince1970 == 1_784_520_000)
    }

    @Test("parseBound rejects garbage with schema.invalid_argument")
    func rejectsInvalidBound() {
        do {
            _ = try EventsPullCommand.parseBound("last-week-ish", field: "--since")
            Issue.record("expected parseBound to throw")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_argument")
            #expect(error.field == "--since")
        } catch {
            Issue.record("expected XPCError, got \(error)")
        }
    }

    @Test("parseBound rejects impossible calendar dates")
    func rejectsImpossibleDate() {
        #expect(throws: (any Error).self) {
            _ = try EventsPullCommand.parseBound("2026-13-40", field: "--until")
        }
    }

    // MARK: - Action parsing (EventsPullCommand.parseAction)

    @Test("parseAction accepts done and star (case-insensitive)")
    func parsesActions() throws {
        #expect(try EventsPullCommand.parseAction("done") == .done)
        #expect(try EventsPullCommand.parseAction("star") == .star)
        #expect(try EventsPullCommand.parseAction("Star") == .star)
    }

    @Test("parseAction rejects unknown actions and lists the allowed set")
    func rejectsUnknownAction() {
        do {
            _ = try EventsPullCommand.parseAction("hide")
            Issue.record("expected parseAction to throw")
        } catch let error as XPCError {
            #expect(error.code == "schema.invalid_argument")
            #expect(error.allowed == ["done", "star"])
        } catch {
            Issue.record("expected XPCError, got \(error)")
        }
    }

    // MARK: - Card id validation (EventsPullCommand.validateCardId)

    @Test("validateCardId accepts a canonical UUID")
    func acceptsValidCardId() throws {
        try EventsPullCommand.validateCardId("123E4567-E89B-12D3-A456-426614174000")
    }

    @Test("validateCardId rejects non-UUID input")
    func rejectsInvalidCardId() {
        #expect(throws: (any Error).self) {
            try EventsPullCommand.validateCardId("not-a-uuid")
        }
    }

    // MARK: - JSONL rendering (EventsPullCommand.renderJSONL)

    @Test("renderJSONL emits one JSON object per line, ISO-8601 timestamps")
    func rendersJSONL() throws {
        let events = [
            UserEvent(
                id: "id-1",
                timestamp: Date(timeIntervalSince1970: 1_784_520_000),
                device: "mac",
                cardId: "card-1",
                action: .star,
                itemRef: "https://github.com/a/b"
            ),
            UserEvent(
                id: "id-2",
                timestamp: Date(timeIntervalSince1970: 1_784_520_001),
                device: "mac",
                cardId: "card-2",
                action: .done,
                itemRef: nil
            ),
        ]

        let jsonl = try EventsPullCommand.renderJSONL(events)
        let lines = jsonl.split(separator: "\n")
        #expect(lines.count == 2)

        let first = try #require(
            try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any]
        )
        #expect(first["id"] as? String == "id-1")
        #expect(first["action"] as? String == "star")
        #expect(first["itemRef"] as? String == "https://github.com/a/b")
        #expect(first["timestamp"] as? String == "2026-07-20T04:00:00Z")

        // Absent itemRef is omitted, not null — keeps JSONL flat for jq.
        let second = try #require(
            try JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any]
        )
        #expect(second["itemRef"] == nil)
    }

    @Test("renderJSONL of an empty result is an empty string (no trailing newline)")
    func rendersEmpty() throws {
        #expect(try EventsPullCommand.renderJSONL([]) == "")
    }
}
