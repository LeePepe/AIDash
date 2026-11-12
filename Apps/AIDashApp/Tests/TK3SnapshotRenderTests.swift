#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
import AIDashCore
@testable import AIDashApp

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
        #expect(roi.diagnostics.count == 11)
        #expect(roi.diagnostics["S1_pin_drift"]?["sample_size"] == "1")
        #expect(roi.diagnostics["S12_tool_context_burn"] != nil)
        #expect(roi.skillsDaily.count >= 0)
    }

    @Test("renders Actionable, Pulse, and Skills production views across states and appearances")
    func rendersProductionViews() throws {
        let output = URL(fileURLWithPath: "/Users/lee/Development/handoff/aidash-four-domains-pulse-roi/receipts/TK3-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let states = ["populated", "loading", "empty", "error"]
        var geometrySamples: [DashboardGeometrySample] = []
        for state in states {
            let skillsSummary = try makeSkillsSummary(state: state)
            let store = makeStore(state: state, skillsSummary: skillsSummary)
            for width in [1000.0, 700.0] {
                for (appearance, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                    try render(ActionItemsCardView(store: store), name: "actionable-\(state)-\(Int(width))-\(appearance)", width: width, scheme: scheme, output: output, geometrySamples: &geometrySamples)
                    try render(ScheduledPulsePageView(store: store), name: "pulse-\(state)-\(Int(width))-\(appearance)", width: width, scheme: scheme, output: output, geometrySamples: &geometrySamples)
                    try render(SkillsRoiDiagnosticsCardView(summary: store.liveEfficiencySummary), name: "skills-\(state)-\(Int(width))-\(appearance)", width: width, scheme: scheme, output: output, geometrySamples: &geometrySamples)
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
        try Data(contentsOf: URL(fileURLWithPath: "/Users/lee/Development/worktrees/aidash-4dom-data-review-fix/aidata/tests/fixtures/skills_roi_report.json"))
    }

    private func makeSkillsSummary(state: String) throws -> LiveDashboardTelemetryReader.LiveEfficiencySummary {
        let base = try makeCanonicalSummary()
        guard let roi = base.skillsROI else { return base }
        switch state {
        case "empty":
            return LiveDashboardTelemetryReader.LiveEfficiencySummary(skillsROI: .init(window: roi.window, windowStart: roi.windowStart, windowEnd: roi.windowEnd, sourceAsOf: roi.sourceAsOf, sampleSize: 0, coverageStatus: "missing"))
        case "loading":
            return LiveDashboardTelemetryReader.LiveEfficiencySummary(skillsROI: .init(window: roi.window, windowStart: roi.windowStart, windowEnd: nil, sourceAsOf: nil, sampleSize: nil, coverageStatus: "partial", diagnostics: roi.diagnostics, skillsDaily: roi.skillsDaily))
        case "error":
            return LiveDashboardTelemetryReader.LiveEfficiencySummary(skillsROI: .init(window: roi.window, windowStart: roi.windowStart, windowEnd: roi.windowEnd, sourceAsOf: roi.sourceAsOf, sampleSize: roi.sampleSize, coverageStatus: "error", diagnostics: roi.diagnostics, skillsDaily: roi.skillsDaily))
        default:
            return base
        }
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
        let item = DashboardActionItem(id: "learning-1", title: state == "error" ? "Blocked learning decision" : "字体回退与禁则", summary: "为什么现在学习", sourceTag: "Learning", priority: .p1, status: state == "error" ? .blocked : (state == "loading" ? .inProgress : .triage), backingItemRef: "learning-topic://font-fallback", whyNow: "新缺口", sourceURI: "https://example.invalid", coverageRefs: ["vault://coverage"])
        let jobs = ScheduledPulseRegistry.jobs(homeURL: URL(fileURLWithPath: "/tmp/tk3-render"), fileExists: { _ in true })
        let stages = (0..<5).map { index in ScheduledJobStageReceipt(id: "stage-\(index)", title: "Stage \(index)", status: state == "error" ? "failed" : (state == "loading" ? "running" : "ok"), exitCode: state == "error" ? 1 : (state == "loading" ? nil : 0), durationSec: state == "empty" ? nil : Double(index + 1), sourceAsOf: state == "empty" ? nil : "2026-11-12") }
        let stateReceipt = ScheduledJobState(id: .aidataDigest, lastResult: state == "error" ? .failed : (state == "populated" ? .succeeded : nil), lastRunAt: state == "empty" ? nil : .now, summary: state == "empty" ? nil : "Fixture \(state) receipt", stages: stages, sourceAsOf: state == "empty" ? nil : "2026-11-12")
        let framework = ScheduledJobFrameworkSnapshot(capturedAt: .now, entries: [ScheduledJobFrameworkEntry(definition: jobs[2], state: stateReceipt, actions: state == "error" ? [ScheduledJobAction(id: "action", jobID: .aidataDigest, title: "Resolve failure", descriptionMd: "Failure evidence", controls: [])] : [])])
        let store = DashboardWorkspaceStore(snapshot: snapshot, cliEntries: [], actionItems: state == "empty" ? [] : [item], rankingRows: [], liveEfficiencySummary: skillsSummary)
        store.updateScheduledJobFrameworkSnapshot(framework)
        return store
    }

    private func render<V: View>(_ view: V, name: String, width: CGFloat, scheme: ColorScheme, output: URL, geometrySamples: inout [DashboardGeometrySample]) throws {
        let recorder = DashboardGeometryRecorder()
        let host = view.frame(width: width, alignment: .topLeading).padding(20).fixedSize(horizontal: false, vertical: true).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme).environment(\.dashboardGeometryRecorder, recorder).coordinateSpace(name: "tk3-geometry")
        let renderer = ImageRenderer(content: host)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
        geometrySamples.append(contentsOf: recorder.samples.map { DashboardGeometrySample(id: "\(name)/\($0.id)", role: $0.role, frame: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)) })
        #expect(rep.pixelsWide == Int((width + 40) * 2))
        #expect(rep.pixelsHigh > 0)
    }
}
#endif
