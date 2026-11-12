#if os(macOS)
import AppKit
import Foundation
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
