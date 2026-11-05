import Foundation
import Testing
@testable import AIDashCore

@Suite("Widget Snapshot Tests")
struct WidgetSnapshotTests {
    @Test("decodes aidata camelCase string actions")
    func decodesExportedSnapshot() throws {
        let data = Data(#"""
        {
          "date": "2026-11-05",
          "needsPersonCount": 2,
          "topActions": ["Review TIA-93", "Approve widget copy"],
          "completedGoalsCount": 3,
          "ciPassRate": 98.5,
          "dailySpendUSD": 12.34,
          "cacheHitPct": 81.2
        }
        """#.utf8)

        let snapshot = try JSONDecoder().decode(WidgetBriefingSnapshot.self, from: data)
        #expect(snapshot.needsPersonCount == 2)
        #expect(snapshot.topActions.map(\.title) == ["Review TIA-93", "Approve widget copy"])
        #expect(snapshot.completedGoalsCount == 3)
        #expect(snapshot.ciPassRate == 98.5)
    }

    @Test("decodes snake_case object actions and defaults missing fields")
    func decodesLegacyShape() throws {
        let data = Data(#"""
        {
          "needs_person_count": 1,
          "top_actions": [
            {"id": "a1", "title": "Unblock build", "priority": "high", "waiting_on": "Owner"}
          ],
          "time_breakdown": {
            "lead_time_minutes_p50": 42,
            "agent_minutes": 10,
            "model_minutes": 8,
            "ci_minutes": 12,
            "wait_minutes": 12
          }
        }
        """#.utf8)

        let snapshot = try JSONDecoder().decode(WidgetBriefingSnapshot.self, from: data)
        #expect(snapshot.needsPersonCount == 1)
        #expect(snapshot.topActions[0].waitingOn == "Owner")
        #expect(snapshot.timeBreakdown?.leadTimeMinutesP50 == 42)
        #expect(snapshot.quotas.isEmpty)
    }

    @Test("round trips and atomically stores briefing snapshots")
    func roundTripsAndAtomicallyStoresBriefingSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-widget-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("widget.json")
        let original = WidgetBriefingSnapshot(date: "2026-11-05", needsPersonCount: 4)
        try WidgetSnapshotStore.saveBriefingSnapshot(original, to: url)
        let loaded = try WidgetSnapshotStore.loadBriefingSnapshot(from: url)
        #expect(loaded == original)
    }
}
