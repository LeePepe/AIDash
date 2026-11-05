#if os(macOS)
import SwiftUI
import Testing
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@MainActor
@Suite("Menu bar status view")
struct MenuBarStatusViewTests {
    @Test("view renders with expanded attention items and hardware fields")
    func rendersExpandedState() {
        let snapshot = MenuBarSystemSnapshot(
            capturedAt: .now,
            machine: MachineStatusSnapshot(totalCores: 10, performanceCores: 6, efficiencyCores: 4, powerSummary: "AC"),
            cpu: CPUStatusSnapshot(
                usage: 0.25, user: 0.1, system: 0.15, idle: 0.75, coreCount: 10,
                loadOneMinute: 1, loadFiveMinutes: 1, loadFifteenMinutes: 1,
                gpu: GPUStatusSnapshot(deviceUtilization: 0.5),
                topProcessName: "worker",
                topProcessValueText: "10 ticks"
            ),
            memory: MemoryStatusSnapshot(
                usedBytes: 1, totalBytes: 2, freeBytes: 1, wiredBytes: 0, compressedBytes: 0,
                pressure: .normal, topProcessName: "worker", topProcessValueText: "1.0M"
            ),
            storage: StorageStatusSnapshot(
                systemVolume: StorageVolumeSnapshot(id: "root", name: "Root", mountPoint: "/", isMounted: true, isExternalSSD: false, usedBytes: 1, availableBytes: 1, totalBytes: 2),
                ssdVolume: StorageVolumeSnapshot(id: "ssd", name: "SSD", mountPoint: "/Volumes/SSD", isMounted: false, isExternalSSD: true, usedBytes: 0, availableBytes: 0, totalBytes: 0)
            ),
            tokenUsage: CLITokenUsageSnapshot(items: []),
            attention: AttentionStatusSnapshot(
                needsPersonCount: 1,
                items: [AttentionStatusItem(id: "1", title: "Approve proposal", waitingOn: "Lee")]
            )
        )
        _ = MenuBarStatusView(state: .populated(snapshot)).body
    }
}
#endif
