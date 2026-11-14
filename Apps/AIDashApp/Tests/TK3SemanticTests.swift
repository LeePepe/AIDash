#if os(macOS)
import AppKit
import Foundation
import SwiftData
import SwiftUI
import Testing
import AIDashCore
import DesignKit
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@MainActor
enum TK3Fixtures {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static func canonical() throws -> Data { try Data(contentsOf: root.appendingPathComponent("aidata/tests/fixtures/skills_roi_report.json")) }
    static let producerLearningActionsJSONL = #"""
{"id": "learning-font-fallback", "jobID": "aidata-digest", "createdAt": "2026-11-11T16:00:00Z", "title": "字体回退与禁则如何共同避免断行错误？", "description": "未覆盖缺口 · 审批仅记录意图", "descriptionMd": "未覆盖缺口 · 审批仅记录意图", "status": "triage", "source": "Learning", "domain": "decisions", "bucket": "待决策", "priority": "P1", "ref": "learning-topic://font-fallback", "url": "https://example.invalid/font-fallback", "scope": "personal", "topic_key": "font-fallback", "origin_ref": "learning-topic://font-fallback", "revision": 7, "why_now": "New coverage gap", "source_uri": "https://example.invalid/font-fallback", "coverage_refs": ["vault://typography"], "external_id": null, "evidence": "Observed mixed-script line breaks", "freshness": "7d · 2026-11-11 · 4 · healthy", "window_cst": "7d", "source_as_of": "2026-11-11", "sample_size": 4, "coverage_status": "healthy", "controls": [{"id": "decision", "kind": "singleSelect", "title": "Action", "options": ["Approve", "Snooze 7d", "Done", "Dismiss"]}, {"id": "note", "kind": "textInput", "title": "Note", "maxLength": 80}]}
{"id": "learning-font-fallback", "jobID": "aidata-digest", "createdAt": "2026-11-11T16:00:00Z", "title": "字体回退与禁则如何共同避免断行错误？", "description": "未覆盖缺口 · 审批仅记录意图", "descriptionMd": "未覆盖缺口 · 审批仅记录意图", "status": "in_progress", "source": "Learning", "domain": "decisions", "bucket": "待决策", "priority": "P1", "ref": "learning-topic://font-fallback", "url": "https://example.invalid/font-fallback", "scope": "personal", "topic_key": "font-fallback", "origin_ref": "learning-topic://font-fallback", "revision": "8", "why_now": "New coverage gap", "source_uri": "https://example.invalid/font-fallback", "coverage_refs": ["vault://typography"], "external_id": null, "evidence": "Observed mixed-script line breaks", "freshness": "7d · 2026-11-11 · 4 · healthy", "window_cst": "7d", "source_as_of": "2026-11-11", "sample_size": 4, "coverage_status": "healthy", "controls": [{"id": "decision", "kind": "singleSelect", "title": "Action", "options": ["Approve", "Snooze 7d", "Done", "Dismiss"]}, {"id": "note", "kind": "textInput", "title": "Note", "maxLength": 80}]}
"""#
    static let skillsRoiDenseJSON = #"""
{
  "schema_version": 1,
  "window_cst": "7d",
  "window_start": "2026-11-05T00:00:00+08:00",
  "window_end": "2026-11-11T23:59:59+08:00",
  "source_as_of": "2026-11-11T14:00:00+08:00",
  "sample_size": 4,
  "coverage_status": "healthy",
  "diagnostics": {
    "ok": true,
    "window_cst": "7d",
    "window_start": "2026-11-05T00:00:00+08:00",
    "window_end": "2026-11-11T23:59:59+08:00",
    "source_as_of": "2026-11-11T14:00:00+08:00",
    "sample_size": 4,
    "coverage_status": "healthy",
    "S1_pin_drift": {
      "window_cst": "snapshot",
      "window_start": "2026-11-10T12:00:00+08:00",
      "window_end": "2026-11-10T12:00:00+08:00",
      "source_as_of": "2026-11-10T12:00:00+08:00",
      "sample_size": 1,
      "coverage_status": "healthy",
      "upstreams": {
        "shared-ci": "abc123"
      },
      "consumers": [],
      "outdated_pin_count": 0,
      "all_up_to_date": true
    },
    "S2_gate_catch": {
      "window_cst": "7d",
      "window_start": "2026-11-05T00:00:00+08:00",
      "window_end": "2026-11-11T23:59:59+08:00",
      "source_as_of": "2026-11-11T14:00:00+08:00",
      "sample_size": 4,
      "coverage_status": "healthy",
      "total_runs_7d": 4,
      "true_positive_catches_7d": 1,
      "config_or_rerun_noise_7d": 1,
      "gate_catch_rate": 0.5,
      "noise_rate": 0.25
    },
    "S3_skill_health": {
      "window_cst": "snapshot",
      "window_start": "2026-11-10T12:00:00+08:00",
      "window_end": "2026-11-10T12:00:00+08:00",
      "source_as_of": "2026-11-10T12:00:00+08:00",
      "sample_size": 2,
      "coverage_status": "healthy",
      "total_skills": 2,
      "audit_pass_count": 1,
      "audit_pass_rate": 0.5,
      "eval_case_total": 8,
      "eval_case_weekly_delta": 1,
      "top3_l0_watermarks": [],
      "top3_l1_watermarks": []
    },
    "S4_usage_and_r1": {
      "window_cst": "30d",
      "window_start": "2026-10-13T00:00:00+08:00",
      "window_end": "2026-11-11T23:59:59+08:00",
      "source_as_of": "2026-11-11T14:00:00+08:00",
      "sample_size": 2,
      "coverage_status": "healthy",
      "active_skills_count": 1,
      "idle_skills_30d": [],
      "top_used_skills": [
        {
          "window_cst": "7d",
          "window_start": "2026-11-05T00:00:00+08:00",
          "window_end": "2026-11-11T23:59:59+08:00",
          "source_as_of": "2026-11-11T14:00:00+08:00",
          "sample_size": 12,
          "coverage_status": "healthy",
          "estimated": true,
          "skill": "team-lead",
          "loads_7d": 12,
          "loads_30d": 38,
          "r1_total": 8,
          "r1_pass_rate": 0.75,
          "script_touch_rate": 0.5,
          "unpracticed_rate": 0.5,
          "roi_score": 1.4,
          "diagnosis": "Script practice gap",
          "script_execs": 19
        }
      ]
    },
    "S6_load_vs_script": [
      {
        "window_cst": "7d",
        "window_start": "2026-11-05T00:00:00+08:00",
        "window_end": "2026-11-11T23:59:59+08:00",
        "source_as_of": "2026-11-11T14:00:00+08:00",
        "sample_size": 12,
        "coverage_status": "healthy",
        "estimated": true,
        "skill": "team-lead",
        "loads_7d": 12,
        "loads_30d": 38,
        "r1_total": 8,
        "r1_pass_rate": 0.75,
        "script_touch_rate": 0.5,
        "unpracticed_rate": 0.5,
        "roi_score": 1.4,
        "diagnosis": "Script practice gap",
        "script_execs": 19
      }
    ],
    "S7_disclosure_funnel": [
      {
        "window_cst": "7d",
        "window_start": "2026-11-05T00:00:00+08:00",
        "window_end": "2026-11-11T23:59:59+08:00",
        "source_as_of": "2026-11-11T14:00:00+08:00",
        "sample_size": 4,
        "coverage_status": "healthy",
        "estimated": true,
        "skill": "team-lead",
        "l0_only_rate": 0.5,
        "l1_selective_rate": 0.35,
        "l1_greedy_violation_rate": 0.15,
        "avg_context_tokens": 22000
      }
    ],
    "S8_post_skill_churn": [
      {
        "window_cst": "7d",
        "window_start": "2026-11-05T00:00:00+08:00",
        "window_end": "2026-11-11T23:59:59+08:00",
        "source_as_of": "2026-11-11T14:00:00+08:00",
        "sample_size": 4,
        "coverage_status": "healthy",
        "skill": "team-lead",
        "edit_churn_count": 4,
        "retry_commands": 2
      }
    ],
    "S9_escape_attribution": [
      {
        "window_cst": "7d",
        "window_start": "2026-11-05T00:00:00+08:00",
        "window_end": "2026-11-11T23:59:59+08:00",
        "source_as_of": "2026-11-11T14:00:00+08:00",
        "sample_size": 4,
        "coverage_status": "healthy",
        "skill": "my-designer",
        "impl_bug_escapes": 2,
        "spec_gap_escapes": 1
      }
    ],
    "S10_skill_roi_ranking": [
      {
        "window_cst": "7d",
        "window_start": "2026-11-05T00:00:00+08:00",
        "window_end": "2026-11-11T23:59:59+08:00",
        "source_as_of": "2026-11-11T14:00:00+08:00",
        "sample_size": 12,
        "coverage_status": "healthy",
        "estimated": true,
        "skill": "team-lead",
        "loads_7d": 12,
        "loads_30d": 38,
        "r1_total": 8,
        "r1_pass_rate": 0.75,
        "script_touch_rate": 0.5,
        "unpracticed_rate": 0.5,
        "roi_score": 1.4,
        "diagnosis": "Script practice gap",
        "script_execs": 19
      },
      {
        "window_cst": "7d",
        "window_start": "2026-11-05T00:00:00+08:00",
        "window_end": "2026-11-11T23:59:59+08:00",
        "source_as_of": "2026-11-11T14:00:00+08:00",
        "sample_size": 12,
        "coverage_status": "healthy",
        "estimated": true,
        "skill": "my-designer",
        "loads_7d": 7,
        "loads_30d": 18,
        "r1_total": 0,
        "r1_pass_rate": null,
        "script_touch_rate": 0.5,
        "unpracticed_rate": 0.5,
        "roi_score": null,
        "diagnosis": "Insufficient review observations",
        "script_execs": 19
      }
    ],
    "S11_context_composition": {
      "window_cst": "7d",
      "window_start": "2026-11-05T00:00:00+08:00",
      "window_end": "2026-11-11T23:59:59+08:00",
      "source_as_of": "2026-11-11T14:00:00+08:00",
      "sample_size": 1,
      "coverage_status": "healthy",
      "estimated": true,
      "estimation_method": "fixed-share allocation of observed turn tokens; no measured compression saving",
      "slices": [
        {
          "window_cst": "7d",
          "window_start": "2026-11-05T00:00:00+08:00",
          "window_end": "2026-11-11T23:59:59+08:00",
          "source_as_of": "2026-11-11T14:00:00+08:00",
          "sample_size": 4,
          "coverage_status": "healthy",
          "estimated": true,
          "slice_key": "System & AGENTS.md 指令链",
          "tokens": 4000,
          "share_pct": 20.0
        },
        {
          "window_cst": "7d",
          "window_start": "2026-11-05T00:00:00+08:00",
          "window_end": "2026-11-11T23:59:59+08:00",
          "source_as_of": "2026-11-11T14:00:00+08:00",
          "sample_size": 4,
          "coverage_status": "healthy",
          "estimated": true,
          "slice_key": "Skills 目录与 SKILL.md",
          "tokens": 3000,
          "share_pct": 15.0
        },
        {
          "window_cst": "7d",
          "window_start": "2026-11-05T00:00:00+08:00",
          "window_end": "2026-11-11T23:59:59+08:00",
          "source_as_of": "2026-11-11T14:00:00+08:00",
          "sample_size": 4,
          "coverage_status": "healthy",
          "estimated": true,
          "slice_key": "Tools Schema 定义",
          "tokens": 2000,
          "share_pct": 10.0
        },
        {
          "window_cst": "7d",
          "window_start": "2026-11-05T00:00:00+08:00",
          "window_end": "2026-11-11T23:59:59+08:00",
          "source_as_of": "2026-11-11T14:00:00+08:00",
          "sample_size": 4,
          "coverage_status": "healthy",
          "estimated": true,
          "slice_key": "Tool Results 结果",
          "tokens": 6000,
          "share_pct": 30.0
        },
        {
          "window_cst": "7d",
          "window_start": "2026-11-05T00:00:00+08:00",
          "window_end": "2026-11-11T23:59:59+08:00",
          "source_as_of": "2026-11-11T14:00:00+08:00",
          "sample_size": 4,
          "coverage_status": "healthy",
          "estimated": true,
          "slice_key": "User/Assistant 对话与思考链",
          "tokens": 5000,
          "share_pct": 25.0
        }
      ],
      "total_context_tokens": 20000,
      "kv_cache_hit_pct": 75.0,
      "compressed_saved_tokens": null
    },
    "S12_tool_context_burn": [
      {
        "window_cst": "7d",
        "window_start": "2026-11-05T00:00:00+08:00",
        "window_end": "2026-11-11T23:59:59+08:00",
        "source_as_of": "2026-11-11T14:00:00+08:00",
        "sample_size": 1,
        "coverage_status": "healthy",
        "estimated": true,
        "estimation_method": "turn context * 0.36 / tool count, not measured tool result tokens",
        "tool_name": "view",
        "call_count": 1,
        "total_tokens": 12000,
        "p95_tokens": 12000,
        "bloated_call_count": 1,
        "share_pct": 100.0,
        "dominant_skill": "team-lead"
      }
    ],
    "low_roi_proposals": []
  },
  "skills_daily": [
    {
      "window_cst": "1d",
      "window_start": "2026-11-05T00:00:00+08:00",
      "window_end": "2026-11-11T23:59:59+08:00",
      "source_as_of": "2026-11-11T14:00:00+08:00",
      "sample_size": 4,
      "coverage_status": "healthy",
      "day": "2026-11-11",
      "source": "copilot-attribution",
      "skill": "team-lead",
      "n": 4,
      "sessions": 2
    },
    {
      "window_cst": "1d",
      "window_start": "2026-11-05T00:00:00+08:00",
      "window_end": "2026-11-11T23:59:59+08:00",
      "source_as_of": "2026-11-11T14:00:00+08:00",
      "sample_size": 4,
      "coverage_status": "healthy",
      "day": "2026-11-11",
      "source": "copilot-tool",
      "skill": "team-lead",
      "n": 4,
      "sessions": 2
    },
    {
      "window_cst": "1d",
      "window_start": "2026-11-05T00:00:00+08:00",
      "window_end": "2026-11-11T23:59:59+08:00",
      "source_as_of": "2026-11-11T14:00:00+08:00",
      "sample_size": 4,
      "coverage_status": "healthy",
      "day": "2026-11-11",
      "source": "claude-slash",
      "skill": "team-lead",
      "n": 4,
      "sessions": 2
    }
  ]
}
"""#
    static func data(_ name: String) throws -> Data {
        switch name {
        case "producer-learning-actions.jsonl": return Data(producerLearningActionsJSONL.utf8)
        case "skills-roi-dense.json": return Data(skillsRoiDenseJSON.utf8)
        default: return try Data(contentsOf: root.appendingPathComponent("Apps/AIDashApp/Tests/Fixtures/\(name)"))
        }
    }
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
        #expect(ScheduledJobFrameworkLogic.semanticState(state: .init(id: .dailyLearning, lastResult: .succeeded), launchdStatus: nil) == .healthy)
        let failedNonDigest = ScheduledJobStageReceipt(id: "run", title: "Run", status: "failed", exitCode: 1)
        #expect(ScheduledJobFrameworkLogic.semanticState(state: .init(id: .linearBotBridge, lastResult: .succeeded, stages: [failedNonDigest]), launchdStatus: nil) == .failed)
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
        var malformedWork = base
        malformedWork["scope"] = "work"
        malformedWork["revision"] = true
        let malformed = try JSONSerialization.data(withJSONObject: malformedWork)
        let registry = ScheduledPulseRegistry.jobs(homeURL: home, fileExists: { _ in true }).filter { $0.id == .aidataDigest }
        let framework = LiveDashboardTelemetryReader.loadScheduledJobFrameworkSnapshot(
            fileReader: { $0.lastPathComponent == "actions.jsonl" ? malformed : nil }, homeURL: home, registry: registry)
        #expect(framework.entries.flatMap(\.actions).isEmpty)

        var retroObj = base
        retroObj["id"] = "retro-agent-efficiency-m1"
        retroObj["ref"] = "retro://agent-efficiency-m1"
        retroObj["source"] = "Retro"
        retroObj["domain"] = "decisions"
        try JSONSerialization.data(withJSONObject: retroObj).write(to: url)
        let retroLoaded = try #require(LiveDashboardTelemetryReader.parseUnifiedActionItems(fromURL: url).first)
        #expect(retroLoaded.isProposal)
        #expect(retroLoaded.resolvedDomain == .decisions)
        #expect(retroLoaded.evidence != nil)
        #expect(retroLoaded.freshness != nil)
    }
}

@MainActor
@Suite("TK3 production view screenshots")
struct TK3SnapshotRenderTests {
    @Test("decodes the producer-shaped canonical skills-roi artifact")
    func decodesCanonicalSkillsRoiArtifact() throws {
        let artifact = try canonicalFixtureData()
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("tk3-skills-\(UUID().uuidString)", isDirectory: true)
        let output = home.appendingPathComponent("Library/Application Support/AIDash/jobs/aidata-digest", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try artifact.write(to: output.appendingPathComponent("skills-roi.json"))
        defer { try? FileManager.default.removeItem(at: home) }
        let summary = LiveDashboardTelemetryReader.loadLiveEfficiencySummary(homeURL: home)
        let roi = try #require(summary?.skillsROI)
        #expect(roi.diagnostics.pins?.metadata.sample == 1)
        #expect(roi.diagnostics.tools.first?.p95.value == 12000)
        #expect(roi.diagnostics.ranking.first?.roi.value == nil)
    }

    @Test("renders Actionable, Pulse, and Skills production views across states and appearances")
    func rendersProductionViews() throws {
        #expect(!JobActionsSources.isProductionEnvironment)
        #expect(!LiveDashboardTelemetryReader.isLiveEnvironment)
        let output: URL
        let temporary: URL?
        if let configured = ProcessInfo.processInfo.environment["AIDASH_TK3_SCREENSHOT_DIR"], !configured.isEmpty {
            output = URL(fileURLWithPath: configured, isDirectory: true)
            temporary = nil
        } else {
            let root = try TK3Fixtures.home()
            output = root.appendingPathComponent("screenshots")
            temporary = root
        }
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let states = ["populated", "loading", "empty", "error"]
        var geometrySamples: [DashboardGeometrySample] = []
        for state in states {
            let skillsSummary = try makeSkillsSummary(state: state)
            let store = makeStore(state: state, skillsSummary: skillsSummary)
            for width in [1000.0, 700.0] {
                for (appearance, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                    try render(ActionItemsCardView(store: store), name: "actionable-\(state)-\(Int(width))-\(appearance)", width: width, scheme: scheme, output: output, geometrySamples: &geometrySamples)
                    try render(ScheduledPulsePageView(store: store, registerJobs: {}), name: "pulse-\(state)-\(Int(width))-\(appearance)", width: width, scheme: scheme, output: output, geometrySamples: &geometrySamples)
                    try render(SkillsRoiDiagnosticsCardView(summary: store.liveEfficiencySummary), name: "skills-\(state)-\(Int(width))-\(appearance)", width: width, scheme: scheme, output: output, geometrySamples: &geometrySamples)
                    if state == "populated" {
                        for lens in [SkillsRoiLens.disclosure, .context] {
                            try render(SkillsRoiDiagnosticsCardView(summary: store.liveEfficiencySummary, initialLens: lens), name: "skills-\(lens.rawValue)-populated-\(Int(width))-\(appearance)", width: width, scheme: scheme, output: output, geometrySamples: &geometrySamples)
                        }
                        try render(SkillsRoiDiagnosticsCardView(summary: store.liveEfficiencySummary, showDailyPopulations: true), name: "skills-daily-populated-\(Int(width))-\(appearance)", width: width, scheme: scheme, output: output, geometrySamples: &geometrySamples)
                        let context = try #require(store.liveEfficiencySummary?.skillsROI?.diagnostics.context)
                        let evidence = [SkillsEvidence(title: "KV hit (%)", value: context.cacheHitPercent.value.map { String($0) } ?? "Unknown", metadata: context.cacheHitPercent.metadata),
                                        SkillsEvidence(title: "Saved tokens", value: context.savedTokens.value.map { String($0) } ?? "Unknown", metadata: context.savedTokens.metadata)]
                        try render(SkillsObservationDrawer(evidence: evidence), name: "skills-evidence-populated-\(Int(width))-\(appearance)", width: width, scheme: scheme, output: output, geometrySamples: &geometrySamples)
                    }
                }
            }
        }
        try #require(!geometrySamples.isEmpty)
        let rawNodes = geometrySamples.map { ["label": $0.id, "role": $0.role, "frame": ["x": $0.x, "y": $0.y, "width": $0.width, "height": $0.height]] }
        let rawDocument: [String: Any] = ["platform": "desktop", "viewportWidth": 1040, "children": rawNodes]
        let receipts = output.deletingLastPathComponent()
        try JSONSerialization.data(withJSONObject: rawDocument, options: [.prettyPrinted]).write(to: receipts.appendingPathComponent("TK3-geometry-raw.json"))
        let leafNodes = geometrySamples.filter { $0.role != "pulseStageGrid" && $0.role != "skillsHealthGrid" }
        let groups = Dictionary(grouping: leafNodes, by: { $0.id.split(separator: "/", maxSplits: 1).first.map(String.init) ?? $0.id }).map { key, values in
            ["label": key, "children": values.map { ["label": $0.id, "role": $0.role, "frame": ["x": $0.x, "y": $0.y, "width": $0.width, "height": $0.height]] }] as [String: Any]
        }
        let geometryDocument: [String: Any] = ["platform": "desktop", "viewportWidth": 1040, "children": groups]
        try JSONSerialization.data(withJSONObject: geometryDocument, options: [.prettyPrinted]).write(to: receipts.appendingPathComponent("TK3-geometry.json"))
    }

    private func canonicalFixtureData() throws -> Data {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // AIDashApp
            .deletingLastPathComponent() // Apps
            .deletingLastPathComponent()
        return try Data(contentsOf: repoRoot.appendingPathComponent("aidata/tests/fixtures/skills_roi_report.json"))
    }

    private func makeSkillsSummary(state: String) throws -> LiveDashboardTelemetryReader.LiveEfficiencySummary {
        if state == "populated" {
            return .init(skillsROI: try JSONDecoder().decode(SkillsRoiReport.self, from: TK3Fixtures.data("skills-roi-dense.json")))
        }
        let coverage = state == "empty" ? "missing" : (state == "error" ? "error" : "partial")
        let object: [String: Any] = ["schema_version": 1, "window_cst": "7d", "source_as_of": NSNull(), "sample_size": 0,
                                     "coverage_status": coverage, "diagnostics": [:], "skills_daily": [],
                                     "errors": state == "error" ? ["producer unavailable"] : []]
        return .init(skillsROI: try JSONDecoder().decode(SkillsRoiReport.self, from: JSONSerialization.data(withJSONObject: object)))
    }

    private func makeCanonicalSummary() throws -> LiveDashboardTelemetryReader.LiveEfficiencySummary {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("tk3-render-skills-\(UUID().uuidString)", isDirectory: true)
        let output = home.appendingPathComponent("Library/Application Support/AIDash/jobs/aidata-digest", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try canonicalFixtureData().write(to: output.appendingPathComponent("skills-roi.json"))
        defer { try? FileManager.default.removeItem(at: home) }
        return try #require(LiveDashboardTelemetryReader.loadLiveEfficiencySummary(homeURL: home))
    }

    private func makeStore(state: String, skillsSummary: LiveDashboardTelemetryReader.LiveEfficiencySummary?) -> DashboardWorkspaceStore {
        let snapshot = MenuBarSystemSnapshot(
            capturedAt: .now,
            cpu: CPUStatusSnapshot(usage: 0.2, user: 0.1, system: 0.1, idle: 0.8, coreCount: 8, loadOneMinute: 0.2, loadFiveMinutes: 0.2, loadFifteenMinutes: 0.2),
            memory: MemoryStatusSnapshot(usedBytes: 1, totalBytes: 2, freeBytes: 1, wiredBytes: 0, compressedBytes: 0, pressure: .normal),
            storage: StorageStatusSnapshot(
                systemVolume: StorageVolumeSnapshot(id: "system", name: "System", mountPoint: "/", isMounted: true, isExternalSSD: false, usedBytes: 1, availableBytes: 1, totalBytes: 2),
                ssdVolume: StorageVolumeSnapshot(id: "ssd", name: "SSD", mountPoint: "/Volumes/SSD", isMounted: true, isExternalSSD: true, usedBytes: 1, availableBytes: 1, totalBytes: 2)
            ),
            tokenUsage: CLITokenUsageSnapshot(items: []),
            attention: AttentionStatusSnapshot()
        )
        let controls = [ScheduledJobActionControl(id: "decision", kind: .singleSelect, title: "Action", options: ["Approve", "Snooze 7d", "Done", "Dismiss"])]
        let item = DashboardActionItem(id: "learning-1", title: state == "error" ? "学习探索被阻塞 · 等待来源恢复" : "字体回退与禁则如何共同避免断行错误？", summary: "新覆盖缺口 · 混排字体回退与断行证据", sourceTag: "Learning", priority: .p1, status: state == "error" ? .blocked : (state == "loading" ? .inProgress : .triage), backingItemRef: "learning-topic://font-fallback", jobID: .aidataDigest, controls: controls, revision: "7", whyNow: "新缺口", sourceURI: "https://example.invalid", coverageRefs: ["vault://coverage"])
        let domainItems = [item,
            DashboardActionItem(id: "blocker", title: "个人 CI 门禁等待修复", summary: "收集阶段待处理", sourceTag: "GTT Blocker", status: .blocked),
            DashboardActionItem(id: "finding", title: "Shared pins 需要同步", summary: "只读诊断 · 两个 consumer 落后", sourceTag: "CI Improve", domain: .findings),
            DashboardActionItem(id: "planned", title: "个人学习卡片在途", summary: "已批准 · 后台探索尚未完成", sourceTag: "Linear", status: .inProgress)]
        let jobs = ScheduledPulseRegistry.jobs(homeURL: URL(fileURLWithPath: "/tmp/tk3-render"), fileExists: { $0.hasSuffix("aidata_digest_run.sh") })
        let ids = ["collect", "normalize_merge", "retro_roi", "learning_topics", "digest_push"]
        let stages: [ScheduledJobStageReceipt] = state == "empty" ? [] : ids.enumerated().map { index, id in
            let status = state == "loading" ? (index < 2 ? "passed" : (index == 2 ? "running" : "unknown")) : (state == "error" && index == 2 ? "failed" : "passed")
            return ScheduledJobStageReceipt(id: id, title: id, status: status, exitCode: status == "unknown" ? nil : 0, durationSec: status == "passed" ? Double(index + 1) : nil, sourceAsOf: status == "passed" ? "2026-11-11" : nil)
        }
        let date = Date(timeIntervalSince1970: 1794412800)
        let stateReceipt: ScheduledJobState? = state == "empty" ? nil : .init(id: .aidataDigest, lastResult: state == "error" ? .failed : (state == "loading" ? .running : .succeeded), lastRunAt: date, summary: state == "loading" ? "诊断阶段正在运行；后续阶段尚无回执。" : (state == "error" ? "诊断阶段明确失败；旧 exit 0 不代表通过。" : "个人源入仓，Skills 诊断与每日新题已投递。"), stages: stages, sourceAsOf: state == "loading" ? nil : "2026-11-11")
        let framework = ScheduledJobFrameworkSnapshot(capturedAt: date, entries: [ScheduledJobFrameworkEntry(definition: jobs[2], state: stateReceipt, actions: state == "error" ? [ScheduledJobAction(id: "action", jobID: .aidataDigest, title: "Resolve failure", descriptionMd: "Failure evidence", controls: [])] : [])])
        let store = DashboardWorkspaceStore(snapshot: snapshot, cliEntries: [], actionItems: state == "empty" ? [] : (state == "populated" ? domainItems : [item]), rankingRows: [], scheduledPulseSnapshot: .init(capturedAt: date, jobs: []), liveEfficiencySummary: skillsSummary, scheduledJobExecution: { _ in Issue.record("Snapshot attempted execution"); return false }, topicCatalog: [], sessionBindings: [:], m2DispatchExecutor: { _, _, _ in Issue.record("Snapshot attempted dispatch"); return .init(succeeded: false, error: "fixture") })
        store.scheduledActionWriter = { _, _ in Issue.record("Snapshot attempted receipt write"); return false }
        store.updateScheduledJobFrameworkSnapshot(framework)
        return store
    }

    private func render<V: View>(_ view: V, name: String, width: CGFloat, scheme: ColorScheme, output: URL, geometrySamples: inout [DashboardGeometrySample]) throws {
        let recorder = DashboardGeometryRecorder()
        let host = view.frame(width: width, alignment: .topLeading).padding(20).fixedSize(horizontal: false, vertical: true).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme).environment(\.theme, Theme(isDark: scheme == .dark)).environment(\.dashboardGeometryRecorder, recorder).coordinateSpace(name: "tk3-geometry")
        let renderer = ImageRenderer(content: host)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
        let samples = recorder.samples
        if name.hasPrefix("actionable-") {
            let tiles = samples.filter { $0.role == "domainTile" }
            #expect(tiles.count == 4)
            #expect(Set(tiles.map { Int($0.y.rounded()) }).count == (width == 700 ? 2 : 1))
            #expect(Set(tiles.map { Int($0.x.rounded()) }).count == (width == 700 ? 2 : 4))
            #expect(samples.filter { $0.role == "domainSubtitle" }.allSatisfy { $0.width >= (width == 700 ? 200 : 100) && $0.height >= 14 })
        }
        if name.hasPrefix("pulse-") {
            #expect(samples.filter { $0.role == "pulseStageTile" }.count == 5)
            let footerIDs = ["pulse-run", "pulse-refresh", "pulse-service", "pulse-diagnostics"]
            #expect(samples.filter { $0.role == "button" && footerIDs.contains($0.id) }.count == 4)
            #expect(samples.filter { $0.role == "button" && $0.id.hasPrefix("pulse-tab-") }.count == 2)
        }
        if name.hasPrefix("skills-populated") {
            for column in ["skill", "loads", "roi", "r1", "touch", "unpracticed", "evidence"] {
                let header = try #require(samples.first { $0.id == "usage-header-\(column)" })
                let cell = try #require(samples.first { $0.id == "usage-team-lead-\(column)" })
                #expect(abs(header.x - cell.x) < 1)
                #expect(abs(header.width - cell.width) < 1)
            }
        }
        #expect(samples.filter { $0.role == "button" }.allSatisfy { $0.width >= 28 && $0.height >= 28 })
        geometrySamples.append(contentsOf: samples.map { DashboardGeometrySample(id: "\(name)/\($0.id)", role: $0.role, frame: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)) })
        #expect(rep.pixelsWide == Int((width + 40) * 2))
        #expect(rep.pixelsHigh > 0)
    }
}
#endif
