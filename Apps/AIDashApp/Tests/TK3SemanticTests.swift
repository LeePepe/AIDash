#if os(macOS)
import Foundation
import SwiftData
import Testing
import AIDashCore
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@MainActor
enum TK3Fixtures {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static func canonical() throws -> Data { try Data(contentsOf: root.appendingPathComponent("aidata/tests/fixtures/skills_roi_report.json")) }
    static func data(_ name: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent("Apps/AIDashApp/Tests/Fixtures/\(name)")) }
    static func actionLines() throws -> [Data] { try String(decoding: data("producer-learning-actions.jsonl"), as: UTF8.self).split(whereSeparator: \.isNewline).map { Data($0.utf8) } }
    static func home() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("tk3-hermetic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }
}

@MainActor
@Suite("TK3 R2 semantic regressions")
struct TK3SemanticTests {
    @Test("Exact tracked canonical report decodes all populations without stringifying rows or nulls")
    func canonicalReport() throws {
        let report = try JSONDecoder().decode(SkillsRoiReport.self, from: TK3Fixtures.canonical())
        #expect(report.diagnostics.pins?.behind.value == 0)
        #expect(report.diagnostics.pins?.metadata.sample == 1)
        #expect(report.diagnostics.gates?.catchRate.value == 0.5)
        #expect(report.diagnostics.audit?.evals.value == 8)
        #expect(report.diagnostics.usage?.active.value == 1)
        #expect(report.diagnostics.scripts.first?.touch.value == 0.5)
        #expect(report.diagnostics.disclosure.first?.l0.value == 0.5)
        #expect(report.diagnostics.churn.isEmpty)
        #expect(report.diagnostics.escapes.isEmpty)
        #expect(report.diagnostics.ranking.first?.r1Pass.value == nil)
        #expect(report.diagnostics.ranking.first?.roi.value == nil)
        #expect(report.diagnostics.context?.cacheHitPercent.value == 75)
        #expect(report.diagnostics.context?.savedTokens.value == nil)
        #expect(report.diagnostics.tools.first?.p95.value == 12000)
        #expect(report.diagnostics.tools.first?.metadata.estimated == true)
        #expect(report.metadata.asOf == "2026-11-11T14:00:00+08:00")
    }

    @Test("Wrapped metrics preserve their own observations, and daily populations are never merged")
    func wrappedObservations() throws {
        var root = try #require(JSONSerialization.jsonObject(with: TK3Fixtures.data("skills-roi-dense.json")) as? [String: Any])
        var diagnostics = try #require(root["diagnostics"] as? [String: Any])
        var gates = try #require(diagnostics["S2_gate_catch"] as? [String: Any])
        gates["gate_catch_rate"] = ["value": NSNull(), "sample_size": 0, "coverage_status": "unknown", "source_as_of": "2026-11-10"]
        diagnostics["S2_gate_catch"] = gates
        diagnostics["S1_pin_drift"] = ["value": ["outdated_pin_count": 2, "all_up_to_date": false], "sample_size": 3, "coverage_status": "partial", "source_as_of": "2026-11-09", "window_cst": "snapshot"]
        root["diagnostics"] = diagnostics
        let report = try JSONDecoder().decode(SkillsRoiReport.self, from: JSONSerialization.data(withJSONObject: root))
        #expect(report.diagnostics.gates?.catchRate.value == nil)
        #expect(report.diagnostics.gates?.catchRate.metadata.sample == 0)
        #expect(report.diagnostics.gates?.catchRate.metadata.asOf == "2026-11-10")
        #expect(report.diagnostics.pins?.behind.value == 2)
        #expect(report.diagnostics.pins?.behind.metadata.sample == 3)
        #expect(report.diagnostics.context?.slices.count == 5)
        #expect(report.diagnostics.churn.first?.edits.value == 4)
        #expect(report.diagnostics.escapes.first?.implementation.value == 2)
        #expect(report.skillsDaily.map(\.source) == ["copilot-attribution", "copilot-tool", "claude-slash"])
        #expect(report.skillsDaily.map(\.count) == [4, 4, 4])
    }

    @Test("Explicit stage states override stale exits, absent stages remain unknown, and receipts do not require launchd")
    func pulseStates() throws {
        for (status, exit, expected) in [("running", 1, ScheduledStageState.running), ("in_progress", 0, .running), ("failed", 0, .failed), ("warning", 0, .warning), ("passed", 1, .passed), ("unknown", 0, .unknown)] {
            let stage = ScheduledJobStageReceipt(id: "collect", title: "Collect", status: status, exitCode: exit)
            #expect(stage.semanticState == expected)
            #expect(stage.isSuccess == (expected == .passed))
        }
        let timestampOnly = ScheduledJobStageReceipt(id: "collect", title: "Collect", sourceAsOf: "2026-11-11")
        #expect(!timestampOnly.isKnown)
        #expect(ScheduledJobFrameworkLogic.semanticState(state: .init(id: .aidataDigest, lastResult: .succeeded), launchdStatus: nil) == .noState)
        let ids = ["collect", "normalize_merge", "retro_roi", "learning_topics", "digest_push"]
        let passed = ids.map { ScheduledJobStageReceipt(id: $0, title: $0, status: "passed", exitCode: 0) }
        #expect(ScheduledJobFrameworkLogic.semanticState(state: .init(id: .aidataDigest, lastResult: .succeeded, stages: passed), launchdStatus: nil) == .healthy)
        let running = ScheduledJobStageReceipt(id: "collect", title: "Collect", status: "running", exitCode: 1)
        #expect(ScheduledJobFrameworkLogic.semanticState(state: .init(id: .aidataDigest, lastResult: .failed, stages: [running]), launchdStatus: nil) == .running)
        let failed = ScheduledJobStageReceipt(id: "collect", title: "Collect", status: "failed", exitCode: 0)
        #expect(ScheduledJobFrameworkLogic.semanticState(state: .init(id: .aidataDigest, lastResult: .succeeded, stages: [failed]), launchdStatus: nil) == .failed)
    }

    @Test("Producer numeric then string revision survives real file loading, append-only receipt, refresh and Done/Dismiss")
    func producerRevisionToUserEvent() throws {
        let lines = try TK3Fixtures.actionLines()
        for decision in ["Done", "Dismiss"] {
            let home = try TK3Fixtures.home()
            defer { try? FileManager.default.removeItem(at: home) }
            let directory = home.appendingPathComponent("Library/Application Support/AIDash/jobs/aidata-digest")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let actions = directory.appendingPathComponent("actions.jsonl")
            let proposals = home.appendingPathComponent("proposals.jsonl")
            let original = Data("fixture proposal must never be mutated\n".utf8)
            try original.write(to: proposals)
            try lines[0].write(to: actions)
            let initial = try #require(LiveDashboardTelemetryReader.parseUnifiedActionItems(fromURL: actions).first)
            #expect(initial.revision == "7")
            let container = try ModelContainer(for: UserEventModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            let writer = UserEventWriter(container: container)
            let store = DashboardWorkspaceStore(deferInitialRefresh: true, scheduledJobExecution: { _ in Issue.record("Unexpected execution"); return false }, topicCatalog: [], sessionBindings: [:])
            store.scheduledActionWriter = { action, responses in writer.acknowledgeScheduledJobAction(action: action, responses: responses, device: "fixture") }
            store.submitActionItemDecision(initial, decision: "Approve")
            let context = ModelContext(container)
            let receipt = try #require(context.fetch(FetchDescriptor<UserEventModel>()).first)
            let key = try #require(ScheduledJobAction.receiptKey(itemRef: receipt.itemRef, cardID: receipt.cardId))
            #expect(key.hasSuffix("revision=7"))
            #expect(receipt.itemRef?.contains("\"value\":\"7\"") == true)
            try lines[1].write(to: actions)
            let refreshed = try #require(LiveDashboardTelemetryReader.loadLiveImprovementActionItems(homeURL: home, acknowledgedActionIDs: [key]).first)
            #expect(refreshed.revision == "8")
            #expect(refreshed.status == .inProgress)
            #expect(!refreshed.isCompleted)
            #expect(refreshed.decisionOptions.contains(decision))
            store.submitActionItemDecision(refreshed, decision: decision)
            let events = try ModelContext(container).fetch(FetchDescriptor<UserEventModel>())
            #expect(events.count == 2)
            #expect(events.allSatisfy { $0.action == .acknowledgeJobAction })
            #expect(events.contains { $0.itemRef?.contains("\"value\":\"8\"") == true && $0.itemRef?.contains(decision) == true })
            #expect(try Data(contentsOf: proposals) == original)
            // Native bridge uses the same revision-scoped writer seam, not a forever job/action dedup.
            let native = UserEventWriter(container: try ModelContainer(for: UserEventModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
            let firstAction = try #require(JobActionsSources.decode(lines[0], jobID: "aidata-digest").first)
            let nextAction = try #require(JobActionsSources.decode(lines[1], jobID: "aidata-digest").first)
            let firstEvent = try native.recordReviewedJobAction(action: firstAction, responses: [.init(controlID: "decision", value: "Approve"), .init(controlID: "note", value: "")], device: "fixture")
            let nextEvent = try native.recordReviewedJobAction(action: nextAction, responses: [.init(controlID: "decision", value: decision), .init(controlID: "note", value: "")], device: "fixture")
            #expect(firstEvent.id != nextEvent.id)
        }
    }

    @Test("Work exclusions precede quota and preserve personal word substrings and empty canonical sources")
    func personalFilterAndQuota() throws {
        let home = try TK3Fixtures.home()
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent("Library/Application Support/AIDash/jobs/aidata-digest")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("actions.jsonl")
        let base = try #require(JSONSerialization.jsonObject(with: TK3Fixtures.actionLines()[0]) as? [String: Any])
        var objects: [[String: Any]] = (0..<520).map { index in var a = base; a["id"] = "work-\(index)"; a["scope"] = "work"; return a }
        let titles = ["probing", "describing", "combining", "plumbing", "shadow"]
        for (index, title) in titles.enumerated() { var a = base; a["id"] = "personal-\(index)"; a["title"] = title; objects.append(a) }
        for (index, marker) in ["[Bing]", "[FlightBook]", "ADO", "Teams", "mail_inbox", "work_teams_bridge"].enumerated() { var a = base; a["id"] = "excluded-\(index)"; a["title"] = marker; objects.append(a) }
        var urlWork = base; urlWork["id"] = "ghe"; urlWork["url"] = "https://msft.ghe.com/x/y"; objects.append(urlWork)
        var tagged = base; tagged["id"] = "tagged"; tagged["labels"] = ["work-business"]; objects.append(tagged)
        try objects.map { try JSONSerialization.data(withJSONObject: $0) }.reduce(into: Data()) { $0.append($1); $0.append(10) }.write(to: url)
        let loaded = LiveDashboardTelemetryReader.parseUnifiedActionItems(fromURL: url)
        #expect(Set(loaded.map(\.title)) == Set(titles))
        #expect(loaded.count == 5)
        try Data().write(to: url)
        #expect(LiveDashboardTelemetryReader.loadLiveImprovementActionItems(homeURL: home).isEmpty)
        let legacy = home.appendingPathComponent("Development/AIDash/aidata/L5_apps/digest/state/proposals.jsonl")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"id":"legacy-work","status":"pending","title":"Local work proposal","agent":"retro-loop","scope":"work"}"#.utf8).write(to: legacy)
        try FileManager.default.removeItem(at: url)
        #expect(LiveDashboardTelemetryReader.loadLiveImprovementActionItems(homeURL: home).isEmpty)
    }
}
#endif
