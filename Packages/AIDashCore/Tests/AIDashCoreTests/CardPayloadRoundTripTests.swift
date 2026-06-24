import Foundation
import Testing
@testable import AIDashCore

// MARK: - T031 Round-trip tests for all CardPayloadProtocol conforming types

@Suite("CardPayload Round-Trip Tests")
struct CardPayloadRoundTripTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func roundTrip<T: CardPayloadProtocol>(_ value: T) throws -> T {
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: MetricPayload

    @Test func metricPayloadRoundTrip() throws {
        let payload = MetricPayload(items: [
            MetricPayload.Item(label: "PRs merged", value: 3, unit: nil, trend: .up),
            MetricPayload.Item(label: "Build time", value: 124, unit: "s", trend: .down),
            MetricPayload.Item(label: "Coverage", value: 87.5, unit: "%", trend: .flat),
            MetricPayload.Item(label: "Issues", value: 12),
        ])
        let decoded = try roundTrip(payload)
        #expect(decoded.items.count == 4)
        #expect(decoded.items[0].label == "PRs merged")
        #expect(decoded.items[0].value == 3)
        #expect(decoded.items[0].trend == .up)
        #expect(decoded.items[1].unit == "s")
        #expect(decoded.items[3].trend == nil)
        #expect(decoded.items[3].unit == nil)

        // CardType.decode dispatch
        let data = try encoder.encode(payload)
        let dispatched = try CardType.metric.decode(data)
        #expect(dispatched is MetricPayload)
    }

    // MARK: InsightPayload

    @Test func insightPayloadRoundTrip() throws {
        let payload = InsightPayload(
            title: "Test insight",
            body: "Some analysis body",
            citations: [
                InsightPayload.Citation(label: "PR #1", url: "https://example.com/pr/1"),
            ]
        )
        let decoded = try roundTrip(payload)
        #expect(decoded.title == "Test insight")
        #expect(decoded.body == "Some analysis body")
        #expect(decoded.citations?.count == 1)
        #expect(decoded.citations?[0].label == "PR #1")
        #expect(decoded.citations?[0].url == "https://example.com/pr/1")

        // CardType.decode dispatch
        let data = try encoder.encode(payload)
        let dispatched = try CardType.insight.decode(data)
        #expect(dispatched is InsightPayload)
    }

    @Test func insightPayloadNoCitationsRoundTrip() throws {
        let payload = InsightPayload(title: "Title", body: "Body")
        let decoded = try roundTrip(payload)
        #expect(decoded.citations == nil)
    }

    // MARK: AgentSummaryPayload

    @Test func agentSummaryPayloadRoundTrip() throws {
        let payload = AgentSummaryPayload(
            agentName: "multica/sapphire",
            completed: [
                AgentSummaryPayload.Completed(title: "Fixed crash", ref: "https://example.com/pr/1"),
                AgentSummaryPayload.Completed(title: "Added telemetry"),
            ],
            stats: [
                AgentSummaryPayload.Stat(label: "PRs", value: 2),
                AgentSummaryPayload.Stat(label: "Hours", value: 4.5),
            ]
        )
        let decoded = try roundTrip(payload)
        #expect(decoded.agentName == "multica/sapphire")
        #expect(decoded.completed.count == 2)
        #expect(decoded.completed[0].ref == "https://example.com/pr/1")
        #expect(decoded.completed[1].ref == nil)
        #expect(decoded.stats?.count == 2)
        #expect(decoded.stats?[1].value == 4.5)

        // CardType.decode dispatch
        let data = try encoder.encode(payload)
        let dispatched = try CardType.agentSummary.decode(data)
        #expect(dispatched is AgentSummaryPayload)
    }

    @Test func agentSummaryPayloadNoStatsRoundTrip() throws {
        let payload = AgentSummaryPayload(
            agentName: "test-agent",
            completed: [AgentSummaryPayload.Completed(title: "Did thing")]
        )
        let decoded = try roundTrip(payload)
        #expect(decoded.stats == nil)
    }

    // MARK: TodoListPayload

    @Test func todoListPayloadRoundTrip() throws {
        let dueDate = ISO8601DateFormatter().date(from: "2026-06-24T17:00:00Z")!
        let payload = TodoListPayload(items: [
            TodoListPayload.Item(title: "Review PRs", priority: .high),
            TodoListPayload.Item(title: "Reply to feedback", priority: .medium, due: dueDate),
            TodoListPayload.Item(title: "Update changelog", priority: .low, ref: "https://example.com"),
        ])
        let decoded = try roundTrip(payload)
        #expect(decoded.items.count == 3)
        #expect(decoded.items[0].priority == .high)
        #expect(decoded.items[0].due == nil)
        #expect(decoded.items[1].due == dueDate)
        #expect(decoded.items[2].ref == "https://example.com")

        // CardType.decode dispatch
        let data = try encoder.encode(payload)
        let dispatched = try CardType.todoList.decode(data)
        #expect(dispatched is TodoListPayload)
    }

    // MARK: TrendingPayload

    @Test func trendingPayloadRoundTrip() throws {
        let payload = TrendingPayload(
            topic: "Swift news",
            items: [
                TrendingPayload.Item(title: "Swift 6.1 macros", url: "https://swift.org", score: 487),
                TrendingPayload.Item(title: "SwiftData update", url: "https://example.com"),
            ]
        )
        let decoded = try roundTrip(payload)
        #expect(decoded.topic == "Swift news")
        #expect(decoded.items.count == 2)
        #expect(decoded.items[0].score == 487)
        #expect(decoded.items[1].score == nil)

        // CardType.decode dispatch
        let data = try encoder.encode(payload)
        let dispatched = try CardType.trending.decode(data)
        #expect(dispatched is TrendingPayload)
    }

    // MARK: DigestPayload

    @Test func digestPayloadRoundTrip() throws {
        let payload = DigestPayload(
            title: "Tuesday at a glance",
            body: "Brief overview of the day.",
            sections: [
                DigestPayload.Section(heading: "Shipped", paragraphs: ["PR merged.", "Crash fixed."]),
                DigestPayload.Section(heading: "Blockers", paragraphs: ["Review feedback due."]),
            ]
        )
        let decoded = try roundTrip(payload)
        #expect(decoded.title == "Tuesday at a glance")
        #expect(decoded.body == "Brief overview of the day.")
        #expect(decoded.sections?.count == 2)
        #expect(decoded.sections?[0].paragraphs.count == 2)

        // CardType.decode dispatch
        let data = try encoder.encode(payload)
        let dispatched = try CardType.digest.decode(data)
        #expect(dispatched is DigestPayload)
    }

    @Test func digestPayloadNoSectionsRoundTrip() throws {
        let payload = DigestPayload(title: "Title", body: "Body only")
        let decoded = try roundTrip(payload)
        #expect(decoded.sections == nil)
    }

    // MARK: SectionHeaderPayload

    @Test func sectionHeaderPayloadRoundTrip() throws {
        let payload = SectionHeaderPayload(title: "Engineering", subtitle: "Backend, infra")
        let decoded = try roundTrip(payload)
        #expect(decoded.title == "Engineering")
        #expect(decoded.subtitle == "Backend, infra")

        // CardType.decode dispatch
        let data = try encoder.encode(payload)
        let dispatched = try CardType.sectionHeader.decode(data)
        #expect(dispatched is SectionHeaderPayload)
    }

    @Test func sectionHeaderPayloadNoSubtitleRoundTrip() throws {
        let payload = SectionHeaderPayload(title: "Design")
        let decoded = try roundTrip(payload)
        #expect(decoded.subtitle == nil)
    }

    // MARK: Protocol conformance

    @Test func allTypesConformToCardPayloadProtocol() throws {
        // Verify each type can be used as CardPayloadProtocol
        let payloads: [any CardPayloadProtocol] = [
            MetricPayload(items: [MetricPayload.Item(label: "x", value: 1)]),
            InsightPayload(title: "t", body: "b"),
            AgentSummaryPayload(agentName: "a", completed: [AgentSummaryPayload.Completed(title: "c")]),
            TodoListPayload(items: [TodoListPayload.Item(title: "t")]),
            TrendingPayload(topic: "t", items: [TrendingPayload.Item(title: "t", url: "u")]),
            DigestPayload(title: "t", body: "b"),
            SectionHeaderPayload(title: "t"),
        ]
        #expect(payloads.count == 7)
    }

    // MARK: Dispatch mismatch

    @Test func dispatchFailsOnMismatchedPayload() throws {
        let metricPayload = MetricPayload(items: [
            MetricPayload.Item(label: "x", value: 1, unit: nil, trend: nil),
        ])
        let data = try encoder.encode(metricPayload)
        #expect(throws: DecodingError.self) {
            _ = try CardType.insight.decode(data)
        }
    }
}
