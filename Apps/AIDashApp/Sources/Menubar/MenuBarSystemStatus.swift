#if os(macOS)
import AppKit
import Darwin
import Foundation
import SQLite3

public enum AgentCLIKind: String, CaseIterable, Sendable, Equatable, Identifiable {
    case claude = "Claude Code"
    case codex = "Codex CLI"
    case copilot = "Copilot CLI"

    public var id: String { rawValue }
}

public struct CPUStatusSnapshot: Sendable, Equatable {
    public let usage: Double
    public let user: Double
    public let system: Double
    public let idle: Double
    public let coreCount: Int
    public let loadOneMinute: Double
    public let loadFiveMinutes: Double
    public let loadFifteenMinutes: Double

    public init(
        usage: Double,
        user: Double,
        system: Double,
        idle: Double,
        coreCount: Int,
        loadOneMinute: Double,
        loadFiveMinutes: Double,
        loadFifteenMinutes: Double
    ) {
        self.usage = usage
        self.user = user
        self.system = system
        self.idle = idle
        self.coreCount = coreCount
        self.loadOneMinute = loadOneMinute
        self.loadFiveMinutes = loadFiveMinutes
        self.loadFifteenMinutes = loadFifteenMinutes
    }
}

public enum MemoryPressureLevel: String, Sendable, Equatable {
    case normal
    case warning
    case critical
}

public struct MemoryStatusSnapshot: Sendable, Equatable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let pressure: MemoryPressureLevel

    public init(
        usedBytes: UInt64,
        totalBytes: UInt64,
        freeBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        pressure: MemoryPressureLevel
    ) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.pressure = pressure
    }

    public var usageFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }
}

public struct StorageVolumeSnapshot: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let mountPoint: String
    public let isMounted: Bool
    public let isExternalSSD: Bool
    public let usedBytes: UInt64
    public let availableBytes: UInt64
    public let totalBytes: UInt64

    public init(
        id: String,
        name: String,
        mountPoint: String,
        isMounted: Bool,
        isExternalSSD: Bool,
        usedBytes: UInt64,
        availableBytes: UInt64,
        totalBytes: UInt64
    ) {
        self.id = id
        self.name = name
        self.mountPoint = mountPoint
        self.isMounted = isMounted
        self.isExternalSSD = isExternalSSD
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
        self.totalBytes = totalBytes
    }

    public var usageFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }
}

public struct StorageStatusSnapshot: Sendable, Equatable {
    public let systemVolume: StorageVolumeSnapshot
    public let ssdVolume: StorageVolumeSnapshot

    public init(systemVolume: StorageVolumeSnapshot, ssdVolume: StorageVolumeSnapshot) {
        self.systemVolume = systemVolume
        self.ssdVolume = ssdVolume
    }

    public var volumes: [StorageVolumeSnapshot] { [systemVolume, ssdVolume] }
}

public struct CLITokenUsageItem: Sendable, Equatable, Identifiable {
    public var id: String { cli.rawValue }
    public let cli: AgentCLIKind
    public let inputTokens: UInt64
    public let outputTokens: UInt64
    public let cacheTokens: UInt64
    public let isAvailable: Bool

    public init(
        cli: AgentCLIKind,
        inputTokens: UInt64,
        outputTokens: UInt64,
        cacheTokens: UInt64,
        isAvailable: Bool
    ) {
        self.cli = cli
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheTokens = cacheTokens
        self.isAvailable = isAvailable
    }

    public var activeTokens: UInt64 { inputTokens + outputTokens }
    public var totalTokens: UInt64 { inputTokens + outputTokens + cacheTokens }
}

public struct CLITokenUsageSnapshot: Sendable, Equatable {
    public let items: [CLITokenUsageItem]

    public init(items: [CLITokenUsageItem]) {
        self.items = items
    }

    public var totalActiveTokens: UInt64 {
        items.reduce(0) { $0 + $1.activeTokens }
    }

    public var totalCacheTokens: UInt64 {
        items.reduce(0) { $0 + $1.cacheTokens }
    }

    public var grandTotalTokens: UInt64 {
        items.reduce(0) { $0 + $1.totalTokens }
    }

    public func shareFraction(for cli: AgentCLIKind) -> Double {
        guard totalActiveTokens > 0 else { return 0 }
        let value = items.first(where: { $0.cli == cli })?.activeTokens ?? 0
        return Double(value) / Double(totalActiveTokens)
    }
}

public struct MenuBarSystemSnapshot: Sendable, Equatable {
    public let capturedAt: Date
    public let cpu: CPUStatusSnapshot
    public let memory: MemoryStatusSnapshot
    public let storage: StorageStatusSnapshot
    public let tokenUsage: CLITokenUsageSnapshot

    public init(
        capturedAt: Date,
        cpu: CPUStatusSnapshot,
        memory: MemoryStatusSnapshot,
        storage: StorageStatusSnapshot,
        tokenUsage: CLITokenUsageSnapshot
    ) {
        self.capturedAt = capturedAt
        self.cpu = cpu
        self.memory = memory
        self.storage = storage
        self.tokenUsage = tokenUsage
    }
}

public enum MenuBarStatusViewState: Sendable, Equatable {
    case loading
    case empty(reason: String)
    case error(message: String)
    case populated(MenuBarSystemSnapshot)
}

public struct CLITokenDatabasePaths: Sendable, Equatable {
    public let claude: [URL]
    public let codex: [URL]
    public let copilot: [URL]

    public init(claude: [URL] = [], codex: [URL] = [], copilot: [URL] = []) {
        self.claude = claude
        self.codex = codex
        self.copilot = copilot
    }
}

@MainActor
public protocol MenuBarSystemStatusProviding {
    func captureStatusState() -> MenuBarStatusViewState
}

@MainActor
public final class LiveMenuBarSystemStatusProvider: MenuBarSystemStatusProviding {
    private struct CPUTicks {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
    }

    private let tokenDatabasePaths: CLITokenDatabasePaths
    private let ssdMountPath: String
    private var previousCPUTicks: CPUTicks?

    public init(
        tokenDatabasePaths: CLITokenDatabasePaths? = nil,
        ssdMountPath: String = "/Volumes/SSD"
    ) {
        self.tokenDatabasePaths = tokenDatabasePaths ?? Self.defaultTokenDatabasePaths()
        self.ssdMountPath = ssdMountPath
    }

    public func captureStatusState() -> MenuBarStatusViewState {
        let cpu = captureCPU()
        let memory = captureMemory()
        let storage = captureStorage()
        let tokenUsage = captureTokenUsage()
        return .populated(
            MenuBarSystemSnapshot(
                capturedAt: Date(),
                cpu: cpu,
                memory: memory,
                storage: storage,
                tokenUsage: tokenUsage
            )
        )
    }

    private func captureCPU() -> CPUStatusSnapshot {
        var loadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &loadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        let coreCount = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let loads = getLoadAverages()
        guard result == KERN_SUCCESS else {
            return CPUStatusSnapshot(
                usage: min(max(loads.one / Double(coreCount), 0), 1),
                user: 0,
                system: 0,
                idle: 1,
                coreCount: coreCount,
                loadOneMinute: loads.one,
                loadFiveMinutes: loads.five,
                loadFifteenMinutes: loads.fifteen
            )
        }

        let user = UInt64(loadInfo.cpu_ticks.0)
        let system = UInt64(loadInfo.cpu_ticks.1 + loadInfo.cpu_ticks.2)
        let idle = UInt64(loadInfo.cpu_ticks.3)
        let usage: Double
        let userFraction: Double
        let systemFraction: Double
        let idleFraction: Double
        if let previous = previousCPUTicks {
            let userDelta = user >= previous.user ? user - previous.user : 0
            let systemDelta = system >= previous.system ? system - previous.system : 0
            let idleDelta = idle >= previous.idle ? idle - previous.idle : 0
            let deltaTotal = userDelta + systemDelta + idleDelta
            usage = deltaTotal > 0 ? Double(userDelta + systemDelta) / Double(deltaTotal) : min(max(loads.one / Double(coreCount), 0), 1)
            userFraction = deltaTotal > 0 ? Double(userDelta) / Double(deltaTotal) : usage * 0.7
            systemFraction = deltaTotal > 0 ? Double(systemDelta) / Double(deltaTotal) : usage * 0.3
            idleFraction = deltaTotal > 0 ? Double(idleDelta) / Double(deltaTotal) : 1 - usage
        } else {
            usage = min(max(loads.one / Double(coreCount), 0), 1)
            userFraction = usage * 0.7
            systemFraction = usage * 0.3
            idleFraction = 1 - usage
        }
        previousCPUTicks = CPUTicks(user: user, system: system, idle: idle)
        return CPUStatusSnapshot(
            usage: min(max(usage, 0), 1),
            user: min(max(userFraction, 0), 1),
            system: min(max(systemFraction, 0), 1),
            idle: min(max(idleFraction, 0), 1),
            coreCount: coreCount,
            loadOneMinute: loads.one,
            loadFiveMinutes: loads.five,
            loadFifteenMinutes: loads.fifteen
        )
    }

    private func getLoadAverages() -> (one: Double, five: Double, fifteen: Double) {
        var values = [Double](repeating: 0, count: 3)
        let count = values.withUnsafeMutableBufferPointer {
            getloadavg($0.baseAddress, 3)
        }
        guard count == 3 else { return (0, 0, 0) }
        return (values[0], values[1], values[2])
    }

    private func captureMemory() -> MemoryStatusSnapshot {
        var vmInfo = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let pageSize = UInt64(max(hostPageSize(), 1))
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            return MemoryStatusSnapshot(
                usedBytes: 0,
                totalBytes: total,
                freeBytes: total,
                wiredBytes: 0,
                compressedBytes: 0,
                pressure: .normal
            )
        }
        let free = UInt64(vmInfo.free_count) * pageSize
        let inactive = UInt64(vmInfo.inactive_count) * pageSize
        let speculative = UInt64(vmInfo.speculative_count) * pageSize
        let wired = UInt64(vmInfo.wire_count) * pageSize
        let compressed = UInt64(vmInfo.compressor_page_count) * pageSize
        let used = total > free + inactive + speculative ? total - free - inactive - speculative : 0
        let fraction = total > 0 ? Double(used) / Double(total) : 0
        let pressure: MemoryPressureLevel = fraction >= 0.9 ? .critical : fraction >= 0.75 ? .warning : .normal
        return MemoryStatusSnapshot(
            usedBytes: used,
            totalBytes: total,
            freeBytes: free,
            wiredBytes: wired,
            compressedBytes: compressed,
            pressure: pressure
        )
    }

    private func hostPageSize() -> vm_size_t {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return size
    }

    private func captureStorage() -> StorageStatusSnapshot {
        let root = volumeSnapshot(
            id: "root",
            name: "Macintosh HD",
            mountPoint: "/",
            isExternalSSD: false
        )
        let ssd = volumeSnapshot(
            id: "ssd",
            name: "SSD",
            mountPoint: ssdMountPath,
            isExternalSSD: true,
            rootFileSystemID: fileSystemID(for: "/")
        )
        return StorageStatusSnapshot(systemVolume: root, ssdVolume: ssd)
    }

    private func volumeSnapshot(
        id: String,
        name: String,
        mountPoint: String,
        isExternalSSD: Bool,
        rootFileSystemID: (Int32, Int32)? = nil
    ) -> StorageVolumeSnapshot {
        var info = statfs()
        let success = mountPoint.withCString { statfs($0, &info) == 0 }
        let currentID = (info.f_fsid.val.0, info.f_fsid.val.1)
        let mounted = success && (rootFileSystemID.map { currentID != $0 } ?? true)
        guard mounted else {
            return StorageVolumeSnapshot(
                id: id,
                name: name,
                mountPoint: mountPoint,
                isMounted: false,
                isExternalSSD: isExternalSSD,
                usedBytes: 0,
                availableBytes: 0,
                totalBytes: 0
            )
        }
        let blockSize = UInt64(info.f_bsize)
        let total = UInt64(info.f_blocks) * blockSize
        let available = UInt64(info.f_bavail) * blockSize
        return StorageVolumeSnapshot(
            id: id,
            name: name,
            mountPoint: mountPoint,
            isMounted: true,
            isExternalSSD: isExternalSSD,
            usedBytes: total > available ? total - available : 0,
            availableBytes: available,
            totalBytes: total
        )
    }

    private func fileSystemID(for path: String) -> (Int32, Int32)? {
        var info = statfs()
        guard path.withCString({ statfs($0, &info) == 0 }) else { return nil }
        return (info.f_fsid.val.0, info.f_fsid.val.1)
    }

    private func captureTokenUsage() -> CLITokenUsageSnapshot {
        let items = AgentCLIKind.allCases.map { cli in
            let paths: [URL]
            switch cli {
            case .claude: paths = tokenDatabasePaths.claude
            case .codex: paths = tokenDatabasePaths.codex
            case .copilot: paths = tokenDatabasePaths.copilot
            }
            return readTokenUsage(cli: cli, paths: paths)
        }
        return CLITokenUsageSnapshot(items: items)
    }

    private func readTokenUsage(cli: AgentCLIKind, paths: [URL]) -> CLITokenUsageItem {
        let queries: [(String, String)]
        switch cli {
        case .claude:
            queries = [
                ("fact_turn", "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0) + COALESCE(SUM(cache_creation),0) FROM fact_turn;"),
                ("turn", "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0) + COALESCE(SUM(cache_creation),0) FROM turn;")
            ]
        case .codex:
            queries = [
                ("fact_request", "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0) + COALESCE(SUM(cache_write),0) FROM fact_request WHERE client IN ('codex-tui', 'codex_exec');"),
                ("req", "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0) + COALESCE(SUM(cache_write),0) FROM req;")
            ]
        case .copilot:
            queries = [
                ("assistant_usage_events", "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read_tokens),0) + COALESCE(SUM(cache_write_tokens),0) FROM assistant_usage_events;")
            ]
        }

        for path in paths {
            for (_, query) in queries {
                if let values = readSQLite(path: path.path, query: query) {
                    return CLITokenUsageItem(
                        cli: cli,
                        inputTokens: values.0,
                        outputTokens: values.1,
                        cacheTokens: values.2,
                        isAvailable: true
                    )
                }
            }
        }
        return CLITokenUsageItem(cli: cli, inputTokens: 0, outputTokens: 0, cacheTokens: 0, isAvailable: false)
    }

    private func readSQLite(path: String, query: String) -> (UInt64, UInt64, UInt64)? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            if let statement { sqlite3_finalize(statement) }
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return (
            UInt64(max(sqlite3_column_int64(statement, 0), 0)),
            UInt64(max(sqlite3_column_int64(statement, 1), 0)),
            UInt64(max(sqlite3_column_int64(statement, 2), 0))
        )
    }

    private static func defaultTokenDatabasePaths() -> CLITokenDatabasePaths {
        let isTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        guard !isTest else { return CLITokenDatabasePaths() }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return CLITokenDatabasePaths(
            claude: [home.appendingPathComponent(".claude/warehouse.db"), home.appendingPathComponent(".claude/claude_jsonl.db")],
            codex: [home.appendingPathComponent(".codex/warehouse.db"), home.appendingPathComponent(".codex/raven.db")],
            copilot: [home.appendingPathComponent(".copilot/session-store.db")]
        )
    }
}
#endif
