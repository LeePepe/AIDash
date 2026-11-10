#if os(macOS)
import Foundation
import SQLite3
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

    @Test("provider reads merged device token rows from the warehouse")
    @MainActor
    func providerReadsDeviceTokenWarehouse() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("aidash-menubar-device-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let warehouse = tempDir.appendingPathComponent("warehouse.db")
        var db: OpaquePointer?
        #expect(sqlite3_open(warehouse.path, &db) == SQLITE_OK)
        guard let db else { return }
        let sql = """
        CREATE TABLE fact_device_token_daily (device_id TEXT, input_tokens INTEGER, output_tokens INTEGER, cache_read INTEGER, cache_write INTEGER, invocations INTEGER, cli TEXT);
        INSERT INTO fact_device_token_daily VALUES ('local',100,50,20,5,2,'codex-tui');
        INSERT INTO fact_device_token_daily VALUES ('remote',300,50,0,10,3,'codex-tui');
        INSERT INTO fact_device_token_daily VALUES ('__all__',400,100,20,15,5,'codex-tui');
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let provider = LiveMenuBarSystemStatusProvider(tokenDatabasePaths: CLITokenDatabasePaths(codex: [warehouse]))
        let usage = provider.captureTokenStatus().usage
        let codex = try #require(usage.items.first(where: { $0.cli == .codex }))
        #expect(codex.inputTokens == 400)
        #expect(codex.outputTokens == 100)
        #expect(codex.cacheTokens == 35)
        #expect(codex.interactionCount == 5)
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
