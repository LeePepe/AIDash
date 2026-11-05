import Testing
import Foundation
@testable import AIDashCore

@Suite("HourlyTimelinePayload")
struct HourlyTimelinePayloadTests {
    private func payload(active: Set<Int> = [0, 1, 2, 3]) -> HourlyTimelinePayload {
        HourlyTimelinePayload(
            title: "Timeline",
            overview: "Overview",
            hours: (0..<24).map { hour in
                .init(hour: hour, summary: active.contains(hour) ? "Observed" : HourlyTimelinePayload.emptyBucketSummary, evidenceIds: active.contains(hour) ? ["e\(hour)"] : [])
            }
        )
    }

    @Test func roundTripAndValidation() throws {
        let value = payload()
        try value.validateInvariants()
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(HourlyTimelinePayload.self, from: data)
        #expect(decoded.hours.count == 24)
    }

    @Test func invalidEvidenceCombinationsAreRejected() {
        let emptyWithEvidence = HourlyTimelinePayload(
            title: "Timeline", overview: "Overview",
            hours: (0..<24).map { .init(hour: $0, summary: HourlyTimelinePayload.emptyBucketSummary, evidenceIds: $0 == 0 ? ["e"] : []) }
        )
        #expect(throws: XPCError.self) { try emptyWithEvidence.validateInvariants() }
    }

    @Test func effectiveSizeDowngradesByActiveHours() throws {
        let data = try JSONEncoder().encode(payload(active: [0]))
        #expect(EffectiveCardSize.resolve(type: .hourlyTimeline, authored: .hero, payloadJSON: data) == .medium)
    }

    @Test func todoMetadataRoundTrips() throws {
        let item = TodoListPayload.Item(title: "Task", category: "blocked", waitingOn: "Lee", ageText: "2d", commandHint: "approve")
        let value = TodoListPayload(items: [item], title: "Needs a Person")
        let decoded = try JSONDecoder().decode(TodoListPayload.self, from: JSONEncoder().encode(value))
        #expect(decoded.title == "Needs a Person")
        #expect(decoded.items[0].commandHint == "approve")
    }
}
