#if os(macOS)
import Foundation
import Testing
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@Suite("Menu bar hardware snapshots")
struct MenuBarSystemStatusTests {
    @Test("new hardware fields preserve default initializer compatibility")
    func defaultsRemainStable() {
        let machine = MachineStatusSnapshot()
        let cpu = CPUStatusSnapshot(
            usage: 0,
            user: 0,
            system: 0,
            idle: 1,
            coreCount: 1,
            loadOneMinute: 0,
            loadFiveMinutes: 0,
            loadFifteenMinutes: 0
        )
        let memory = MemoryStatusSnapshot(
            usedBytes: 0,
            totalBytes: 1,
            freeBytes: 1,
            wiredBytes: 0,
            compressedBytes: 0,
            pressure: .normal
        )
        #expect(machine.efficiencyCores == 0)
        #expect(machine.powerSummary == nil)
        #expect(cpu.gpu == GPUStatusSnapshot())
        #expect(cpu.topProcessName == nil)
        #expect(memory.topProcessName == nil)
    }

    @Test("provider exposes hardware fields without requiring live home data")
    @MainActor
    func providerSnapshotMaterializes() {
        let provider = LiveMenuBarSystemStatusProvider(
            tokenDatabasePaths: CLITokenDatabasePaths(),
            ssdMountPath: "/"
        )
        let snapshot = provider.captureComputerStatus()
        #expect(snapshot.cpu.gpu.deviceUtilization >= 0)
        #expect(snapshot.cpu.gpu.deviceUtilization <= 1)
        #expect(snapshot.machine.efficiencyCores >= 0)
    }
}
#endif
