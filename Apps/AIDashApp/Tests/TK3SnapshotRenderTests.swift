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
    @Test("renders Actionable, Pulse, and Skills production views across states and appearances")
    func rendersProductionViews() throws {
        let output = URL(fileURLWithPath: "/Users/lee/Development/handoff/aidash-four-domains-pulse-roi/receipts/TK3-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let states = ["populated", "loading", "empty", "error"]
        for state in states {
            let store = makeStore(populated: state == "populated")
            for width in [1000.0, 700.0] {
                for (appearance, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                    try render(ActionItemsCardView(store: store), name: "actionable-\(state)-\(Int(width))-\(appearance)", width: width, scheme: scheme, output: output)
                    try render(ScheduledPulsePageView(store: store), name: "pulse-\(state)-\(Int(width))-\(appearance)", width: width, scheme: scheme, output: output)
                    try render(SkillsRoiDiagnosticsCardView(summary: state == "populated" ? store.liveEfficiencySummary : nil), name: "skills-\(state)-\(Int(width))-\(appearance)", width: width, scheme: scheme, output: output)
                }
            }
        }
    }

    private func makeStore(populated: Bool) -> DashboardWorkspaceStore {
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
        let item = DashboardActionItem(id: "learning-1", title: "字体回退与禁则", summary: "为什么现在学习", sourceTag: "Learning", priority: .p1, backingItemRef: "learning-topic://font-fallback", whyNow: "新缺口", sourceURI: "https://example.invalid", coverageRefs: ["vault://coverage"])
        let store = DashboardWorkspaceStore(snapshot: snapshot, actionItems: populated ? [item] : [])
        store.updateScheduledJobFrameworkSnapshot(ScheduledJobFrameworkSnapshot(capturedAt: .now, entries: []))
        return store
    }

    private func render<V: View>(_ view: V, name: String, width: CGFloat, scheme: ColorScheme, output: URL) throws {
        let host = view.frame(width: width, alignment: .topLeading).padding(20).fixedSize(horizontal: false, vertical: true).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: host)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
        #expect(rep.pixelsWide == Int((width + 40) * 2))
        #expect(rep.pixelsHigh > 0)
    }
}
#endif
