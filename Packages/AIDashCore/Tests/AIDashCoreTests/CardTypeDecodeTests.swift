import Foundation
import Testing
@testable import AIDashCore

@Suite("CardType.decode / validate dispatch")
struct CardTypeDecodeTests {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: - decode returns correct dynamic type per case

    @Test func decodeMetric() throws {
        let payload = MetricPayload(items: [
            .init(label: "Steps", value: 8_200, unit: "steps", trend: .up)
        ])
        let data = try encoder.encode(payload)
        let result = try CardType.metric.decode(data)
        #expect(result is MetricPayload)
    }

    @Test func decodeInsight() throws {
        let payload = InsightPayload(title: "Sleep", body: "You slept 7h")
        let data = try encoder.encode(payload)
        let result = try CardType.insight.decode(data)
        #expect(result is InsightPayload)
    }

    @Test func decodeAgentSummary() throws {
        let payload = AgentSummaryPayload(
            agentName: "HealthBot",
            completed: [.init(title: "Sync steps")]
        )
        let data = try encoder.encode(payload)
        let result = try CardType.agentSummary.decode(data)
        #expect(result is AgentSummaryPayload)
    }

    @Test func decodeTodoList() throws {
        let payload = TodoListPayload(items: [
            .init(title: "Drink water", priority: .high, due: Date(timeIntervalSince1970: 1_782_338_400))
        ])
        let data = try encoder.encode(payload)
        let result = try CardType.todoList.decode(data)
        #expect(result is TodoListPayload)
        let decoded = try #require(result as? TodoListPayload)
        #expect(decoded.items[0].due != nil)
    }

    @Test func decodeTrending() throws {
        let payload = TrendingPayload(topic: "Fitness", items: [
            .init(title: "HIIT", url: "https://example.com", score: 9.5)
        ])
        let data = try encoder.encode(payload)
        let result = try CardType.trending.decode(data)
        #expect(result is TrendingPayload)
    }

    @Test func decodeDigest() throws {
        let payload = DigestPayload(title: "Daily", body: "Summary here")
        let data = try encoder.encode(payload)
        let result = try CardType.digest.decode(data)
        #expect(result is DigestPayload)
    }

    @Test func decodeSectionHeader() throws {
        let payload = SectionHeaderPayload(title: "Morning")
        let data = try encoder.encode(payload)
        let result = try CardType.sectionHeader.decode(data)
        #expect(result is SectionHeaderPayload)
    }

    @Test func decodeBarList() throws {
        let payload = BarListPayload(items: [
            .init(label: "runtime-offline", value: 39, valueText: "39%", semantic: "warning")
        ])
        let data = try encoder.encode(payload)
        let result = try CardType.barList.decode(data)
        #expect(result is BarListPayload)
    }

    @Test func decodeStackedBar() throws {
        let payload = StackedBarPayload(segments: [
            .init(label: "end_turn", value: 70, semantic: "success"),
            .init(label: "tool_use", value: 25),
            .init(label: "max_tokens", value: 5, semantic: "warning")
        ], title: "会话质量")
        let data = try encoder.encode(payload)
        let result = try CardType.stackedBar.decode(data)
        #expect(result is StackedBarPayload)
    }

    @Test func decodeTeamAudit() throws {
        let payload = TeamAuditPayload(
            snapshotID: "audit-snapshot-001",
            capturedAt: Date(),
            scope: .init(owner: "Owner", projectID: "project-ref", repository: "https://example.com/org/repo"),
            mode: .baseline,
            section: .overview,
            partIndex: 0,
            partCount: 1,
            contentSHA256: String(repeating: "a", count: 64),
            artifactSidecarID: "audit-snapshot-001:artifact-sidecar:v1",
            artifactSidecarSHA256: String(repeating: "b", count: 64),
            overview: .init(
                taskEffectiveness: .init(totalEvaluated: 1, effective: 1, ineffective: 0, regressed: 0, pending: 0, insufficientEvidence: 0),
                limitations: ["Redacted"]
            )
        )
        let data = try encoder.encode(payload)
        let result = try CardType.teamAudit.decode(data)
        #expect(result is TeamAuditPayload)
        try CardType.teamAudit.validate(data)
    }

    // MARK: - validate throws on invalid data

    @Test func validateThrowsOnInvalidJSON() {
        let badData = Data("not json".utf8)
        #expect(throws: (any Error).self) {
            try CardType.metric.validate(badData)
        }
    }

    // MARK: - validate succeeds on valid data

    @Test func validateSucceedsOnValidData() throws {
        let payload = MetricPayload(items: [.init(label: "HR", value: 72)])
        let data = try encoder.encode(payload)
        try CardType.metric.validate(data)
    }
}
