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

public enum MenuBarStatusSection: String, CaseIterable, Sendable, Equatable, Identifiable {
    case machine, cpu, memory, network, storage, tokenUsage
    public var id: String { rawValue }
    public var refreshIntervalSeconds: Int { isComputerSection ? 5 : 60 }
    public var isComputerSection: Bool { self != .tokenUsage }
}

public enum SystemThermalLevel: String, Sendable, Equatable {
    case nominal, fair, serious, critical
}

public struct MachineStatusSnapshot: Sendable, Equatable {
    public let chipName: String
    public let modelIdentifier: String
    public let totalCores: Int
    public let performanceCores: Int
    public let uptimeSeconds: TimeInterval
    public let thermalState: SystemThermalLevel

    public init(
        chipName: String = "Apple Silicon",
        modelIdentifier: String = "Mac",
        totalCores: Int = 0,
        performanceCores: Int = 0,
        uptimeSeconds: TimeInterval = 0,
        thermalState: SystemThermalLevel = .nominal
    ) {
        self.chipName = chipName
        self.modelIdentifier = modelIdentifier
        self.totalCores = totalCores
        self.performanceCores = performanceCores
        self.uptimeSeconds = uptimeSeconds
        self.thermalState = thermalState
    }
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
    public let history: [Double]

    public init(
        usage: Double,
        user: Double,
        system: Double,
        idle: Double,
        coreCount: Int,
        loadOneMinute: Double,
        loadFiveMinutes: Double,
        loadFifteenMinutes: Double,
        history: [Double] = []
    ) {
        self.usage = usage
        self.user = user
        self.system = system
        self.idle = idle
        self.coreCount = coreCount
        self.loadOneMinute = loadOneMinute
        self.loadFiveMinutes = loadFiveMinutes
        self.loadFifteenMinutes = loadFifteenMinutes
        self.history = history
    }
}

public enum MemoryPressureLevel: String, Sendable, Equatable { case normal, warning, critical }

public struct MemoryStatusSnapshot: Sendable, Equatable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let pressure: MemoryPressureLevel
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64

    public init(
        usedBytes: UInt64,
        totalBytes: UInt64,
        freeBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        pressure: MemoryPressureLevel,
        swapUsedBytes: UInt64 = 0,
        swapTotalBytes: UInt64 = 0
    ) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.pressure = pressure
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
    }

    public var usageFraction: Double { totalBytes > 0 ? min(max(Double(usedBytes) / Double(totalBytes), 0), 1) : 0 }
    public var swapUsageFraction: Double { swapTotalBytes > 0 ? min(max(Double(swapUsedBytes) / Double(swapTotalBytes), 0), 1) : 0 }
}

public struct NetworkStatusSnapshot: Sendable, Equatable {
    public let interfaceName: String
    public let ipAddress: String?
    public let isConnected: Bool
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double
    public let totalReceivedBytes: UInt64
    public let totalSentBytes: UInt64
    public let throughputHistory: [Double]

    public init(
        interfaceName: String = "—",
        ipAddress: String? = nil,
        isConnected: Bool = false,
        downloadBytesPerSecond: Double = 0,
        uploadBytesPerSecond: Double = 0,
        totalReceivedBytes: UInt64 = 0,
        totalSentBytes: UInt64 = 0,
        throughputHistory: [Double] = []
    ) {
        self.interfaceName = interfaceName
        self.ipAddress = ipAddress
        self.isConnected = isConnected
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.totalReceivedBytes = totalReceivedBytes
        self.totalSentBytes = totalSentBytes
        self.throughputHistory = throughputHistory
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
    public init(id: String, name: String, mountPoint: String, isMounted: Bool, isExternalSSD: Bool, usedBytes: UInt64, availableBytes: UInt64, totalBytes: UInt64) {
        self.id = id; self.name = name; self.mountPoint = mountPoint; self.isMounted = isMounted; self.isExternalSSD = isExternalSSD
        self.usedBytes = usedBytes; self.availableBytes = availableBytes; self.totalBytes = totalBytes
    }
    public var usageFraction: Double { totalBytes > 0 ? min(max(Double(usedBytes) / Double(totalBytes), 0), 1) : 0 }
}

public struct StorageStatusSnapshot: Sendable, Equatable {
    public let systemVolume: StorageVolumeSnapshot
    public let ssdVolume: StorageVolumeSnapshot
    public init(systemVolume: StorageVolumeSnapshot, ssdVolume: StorageVolumeSnapshot) { self.systemVolume = systemVolume; self.ssdVolume = ssdVolume }
    public var volumes: [StorageVolumeSnapshot] { [systemVolume, ssdVolume] }
}

public struct CLITokenUsageItem: Sendable, Equatable, Identifiable {
    public var id: String { cli.rawValue }
    public let cli: AgentCLIKind
    public let inputTokens: UInt64
    public let outputTokens: UInt64
    public let cacheTokens: UInt64
    public let isAvailable: Bool
    public let interactionCount: UInt64
    public init(cli: AgentCLIKind, inputTokens: UInt64, outputTokens: UInt64, cacheTokens: UInt64, isAvailable: Bool, interactionCount: UInt64 = 0) {
        self.cli = cli; self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.cacheTokens = cacheTokens; self.isAvailable = isAvailable; self.interactionCount = interactionCount
    }
    public var activeTokens: UInt64 { inputTokens + outputTokens }
    public var totalTokens: UInt64 { activeTokens + cacheTokens }
}

public struct CLITokenUsageSnapshot: Sendable, Equatable {
    public let items: [CLITokenUsageItem]
    public let claudeWeeklyRemainingPercent: Int?
    public init(items: [CLITokenUsageItem], claudeWeeklyRemainingPercent: Int? = nil) {
        self.items = items; self.claudeWeeklyRemainingPercent = claudeWeeklyRemainingPercent
    }
    public var totalActiveTokens: UInt64 { items.reduce(0) { $0 + $1.activeTokens } }
    public var totalCacheTokens: UInt64 { items.reduce(0) { $0 + $1.cacheTokens } }
    public var grandTotalTokens: UInt64 { items.reduce(0) { $0 + $1.totalTokens } }
    public var totalInteractions: UInt64 { items.reduce(0) { $0 + $1.interactionCount } }
    public func shareFraction(for cli: AgentCLIKind) -> Double {
        guard totalActiveTokens > 0 else { return 0 }
        return Double(items.first(where: { $0.cli == cli })?.activeTokens ?? 0) / Double(totalActiveTokens)
    }
}

public struct ComputerStatusSnapshot: Sendable, Equatable {
    public let capturedAt: Date
    public let machine: MachineStatusSnapshot
    public let cpu: CPUStatusSnapshot
    public let memory: MemoryStatusSnapshot
    public let network: NetworkStatusSnapshot
    public let storage: StorageStatusSnapshot
    public init(capturedAt: Date, machine: MachineStatusSnapshot = MachineStatusSnapshot(), cpu: CPUStatusSnapshot, memory: MemoryStatusSnapshot, network: NetworkStatusSnapshot = NetworkStatusSnapshot(), storage: StorageStatusSnapshot) {
        self.capturedAt = capturedAt; self.machine = machine; self.cpu = cpu; self.memory = memory; self.network = network; self.storage = storage
    }
}

public struct MenuBarSystemSnapshot: Sendable, Equatable {
    public let capturedAt: Date
    public let computerCapturedAt: Date
    public let tokenCapturedAt: Date
    public let machine: MachineStatusSnapshot
    public let cpu: CPUStatusSnapshot
    public let memory: MemoryStatusSnapshot
    public let network: NetworkStatusSnapshot
    public let storage: StorageStatusSnapshot
    public let tokenUsage: CLITokenUsageSnapshot

    public init(capturedAt: Date, computerCapturedAt: Date? = nil, tokenCapturedAt: Date? = nil, machine: MachineStatusSnapshot = MachineStatusSnapshot(), cpu: CPUStatusSnapshot, memory: MemoryStatusSnapshot, network: NetworkStatusSnapshot = NetworkStatusSnapshot(), storage: StorageStatusSnapshot, tokenUsage: CLITokenUsageSnapshot) {
        self.capturedAt = capturedAt; self.computerCapturedAt = computerCapturedAt ?? capturedAt; self.tokenCapturedAt = tokenCapturedAt ?? capturedAt
        self.machine = machine; self.cpu = cpu; self.memory = memory; self.network = network; self.storage = storage; self.tokenUsage = tokenUsage
    }
    public func updatingComputer(_ computer: ComputerStatusSnapshot) -> Self {
        Self(capturedAt: max(computer.capturedAt, tokenCapturedAt), computerCapturedAt: computer.capturedAt, tokenCapturedAt: tokenCapturedAt, machine: computer.machine, cpu: computer.cpu, memory: computer.memory, network: computer.network, storage: computer.storage, tokenUsage: tokenUsage)
    }
    public func updatingTokenUsage(_ tokenUsage: CLITokenUsageSnapshot, capturedAt: Date) -> Self {
        Self(capturedAt: max(computerCapturedAt, capturedAt), computerCapturedAt: computerCapturedAt, tokenCapturedAt: capturedAt, machine: machine, cpu: cpu, memory: memory, network: network, storage: storage, tokenUsage: tokenUsage)
    }
}

public enum MenuBarStatusViewState: Sendable, Equatable {
    case loading, empty(reason: String), error(message: String), populated(MenuBarSystemSnapshot)
}

public struct CLITokenDatabasePaths: Sendable, Equatable {
    public let claude: [URL]; public let codex: [URL]; public let copilot: [URL]; public let claudeQuotaFileURL: URL?
    public init(claude: [URL] = [], codex: [URL] = [], copilot: [URL] = [], claudeQuotaFileURL: URL? = nil) {
        self.claude = claude; self.codex = codex; self.copilot = copilot; self.claudeQuotaFileURL = claudeQuotaFileURL
    }
}

@MainActor
public protocol MenuBarSystemStatusProviding {
    func captureStatusState() -> MenuBarStatusViewState
    func captureComputerStatus() -> ComputerStatusSnapshot
    func captureTokenStatus() -> (usage: CLITokenUsageSnapshot, capturedAt: Date)
}

@MainActor
public final class LiveMenuBarSystemStatusProvider: MenuBarSystemStatusProviding {
    private let tokenDatabasePaths: CLITokenDatabasePaths
    private let ssdMountPath: String
    private var previousCPUTicks: [UInt64]?
    private var cpuUsageHistory: [Double] = []
    private var previousNetworkSample: (rx: UInt64, tx: UInt64, at: Date)?
    private var networkThroughputHistory: [Double] = []

    public init(tokenDatabasePaths: CLITokenDatabasePaths? = nil, ssdMountPath: String = "/Volumes/SSD") {
        self.tokenDatabasePaths = tokenDatabasePaths ?? Self.defaultTokenDatabasePaths()
        self.ssdMountPath = ssdMountPath
    }
    public func captureStatusState() -> MenuBarStatusViewState {
        let computer = captureComputerStatus()
        let tokens = captureTokenStatus()
        return .populated(MenuBarSystemSnapshot(capturedAt: max(computer.capturedAt, tokens.capturedAt), computerCapturedAt: computer.capturedAt, tokenCapturedAt: tokens.capturedAt, machine: computer.machine, cpu: computer.cpu, memory: computer.memory, network: computer.network, storage: computer.storage, tokenUsage: tokens.usage))
    }
    public func captureComputerStatus() -> ComputerStatusSnapshot {
        let now = Date()
        return ComputerStatusSnapshot(capturedAt: now, machine: captureMachine(), cpu: captureCPU(), memory: captureMemory(), network: captureNetwork(), storage: captureStorage())
    }
    public func captureTokenStatus() -> (usage: CLITokenUsageSnapshot, capturedAt: Date) {
        (captureTokenUsage(), Date())
    }

    // swiftlint:disable large_tuple
    public static func computeCPUUsageBreakdown(currentTicks: [UInt64], previousTicks: [UInt64]?) -> (usage: Double, user: Double, system: Double, idle: Double) {
        guard currentTicks.count == 4 else { return (0, 0, 0, 1) }
        let ticks = previousTicks.flatMap { $0.count == 4 ? zip(currentTicks, $0).map { $0 >= $1 ? $0 - $1 : 0 } : nil } ?? currentTicks
        let total = ticks.reduce(0, +)
        guard total > 0 else { return (0, 0, 0, 1) }
        let user = Double(ticks[Int(CPU_STATE_USER)] + ticks[Int(CPU_STATE_NICE)]) / Double(total)
        let system = Double(ticks[Int(CPU_STATE_SYSTEM)]) / Double(total)
        let idle = Double(ticks[Int(CPU_STATE_IDLE)]) / Double(total)
        return (min(max(user + system, 0), 1), user, system, idle)
    }
    // swiftlint:enable large_tuple

    private func captureMachine() -> MachineStatusSnapshot {
        let thermal: SystemThermalLevel
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .nominal
        }
        let total = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let performance = sysctlInt("hw.perflevel0.physicalcpu") ?? total
        return MachineStatusSnapshot(chipName: sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon", modelIdentifier: sysctlString("hw.model") ?? "Mac", totalCores: total, performanceCores: performance, uptimeSeconds: ProcessInfo.processInfo.systemUptime, thermalState: thermal)
    }
    private func captureCPU() -> CPUStatusSnapshot {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        let coreCount = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let loads = getLoadAverages()
        guard result == KERN_SUCCESS else { return CPUStatusSnapshot(usage: min(max(loads.one / Double(coreCount), 0), 1), user: 0, system: 0, idle: 1, coreCount: coreCount, loadOneMinute: loads.one, loadFiveMinutes: loads.five, loadFifteenMinutes: loads.fifteen, history: cpuUsageHistory) }
        let ticks = [UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3)]
        let breakdown = Self.computeCPUUsageBreakdown(currentTicks: ticks, previousTicks: previousCPUTicks)
        previousCPUTicks = ticks; cpuUsageHistory = Array((cpuUsageHistory + [breakdown.usage]).suffix(12))
        return CPUStatusSnapshot(usage: breakdown.usage, user: breakdown.user, system: breakdown.system, idle: breakdown.idle, coreCount: coreCount, loadOneMinute: loads.one, loadFiveMinutes: loads.five, loadFifteenMinutes: loads.fifteen, history: cpuUsageHistory)
    }
    private func getLoadAverages() -> (one: Double, five: Double, fifteen: Double) {
        var values = [Double](repeating: 0, count: 3)
        let count = values.withUnsafeMutableBufferPointer { getloadavg($0.baseAddress, 3) }
        return count == 3 ? (values[0], values[1], values[2]) : (0, 0, 0)
    }
    private func captureMemory() -> MemoryStatusSnapshot {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vm) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) } }
        var swap = xsw_usage(); var swapSize = MemoryLayout<xsw_usage>.size
        let swapOK = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0
        let total = ProcessInfo.processInfo.physicalMemory; let page = UInt64(max(hostPageSize(), 1))
        guard result == KERN_SUCCESS else { return MemoryStatusSnapshot(usedBytes: 0, totalBytes: total, freeBytes: total, wiredBytes: 0, compressedBytes: 0, pressure: .normal, swapUsedBytes: swapOK ? swap.xsu_used : 0, swapTotalBytes: swapOK ? swap.xsu_total : 0) }
        let free = UInt64(vm.free_count) * page; let inactive = UInt64(vm.inactive_count) * page; let speculative = UInt64(vm.speculative_count) * page
        let used = total > free + inactive + speculative ? total - free - inactive - speculative : 0
        let fraction = total > 0 ? Double(used) / Double(total) : 0
        return MemoryStatusSnapshot(usedBytes: used, totalBytes: total, freeBytes: free, wiredBytes: UInt64(vm.wire_count) * page, compressedBytes: UInt64(vm.compressor_page_count) * page, pressure: fraction >= 0.9 ? .critical : fraction >= 0.75 ? .warning : .normal, swapUsedBytes: swapOK ? swap.xsu_used : 0, swapTotalBytes: swapOK ? swap.xsu_total : 0)
    }
    private func hostPageSize() -> vm_size_t { var size: vm_size_t = 0; host_page_size(mach_host_self(), &size); return size }
    private func captureNetwork() -> NetworkStatusSnapshot {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return NetworkStatusSnapshot() }
        defer { freeifaddrs(first) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        var selected = "en0"; var address: String?; var received: UInt64 = 0; var sent: UInt64 = 0; var connected = false
        while let item = cursor?.pointee {
            let name = String(cString: item.ifa_name)
            if name.hasPrefix("en"), (item.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 {
                if let addr = item.ifa_addr {
                    if addr.pointee.sa_family == UInt8(AF_INET) {
                        var storage = sockaddr_in(); memcpy(&storage, addr, MemoryLayout<sockaddr_in>.size)
                        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        let value = withUnsafePointer(to: &storage.sin_addr) { inet_ntop(AF_INET, $0, &buffer, socklen_t(INET_ADDRSTRLEN)) }
                        address = value.map { String(cString: $0) }; selected = name; connected = true
                    } else if addr.pointee.sa_family == UInt8(AF_LINK), let data = item.ifa_data?.assumingMemoryBound(to: if_data.self) {
                        received = UInt64(data.pointee.ifi_ibytes); sent = UInt64(data.pointee.ifi_obytes)
                    }
                }
            }
            cursor = item.ifa_next
        }
        let now = Date(); var down = 0.0; var up = 0.0
        if let previous = previousNetworkSample {
            let elapsed = max(now.timeIntervalSince(previous.at), 0.001)
            down = Double(received >= previous.rx ? received - previous.rx : 0) / elapsed
            up = Double(sent >= previous.tx ? sent - previous.tx : 0) / elapsed
        }
        previousNetworkSample = (received, sent, now); networkThroughputHistory = Array((networkThroughputHistory + [down + up]).suffix(12))
        return NetworkStatusSnapshot(interfaceName: selected, ipAddress: address, isConnected: connected, downloadBytesPerSecond: down, uploadBytesPerSecond: up, totalReceivedBytes: received, totalSentBytes: sent, throughputHistory: networkThroughputHistory)
    }
    private func captureStorage() -> StorageStatusSnapshot {
        let root = volumeSnapshot(id: "root", name: "Macintosh HD", mountPoint: "/", isExternalSSD: false)
        let ssd = volumeSnapshot(id: "ssd", name: "SSD", mountPoint: ssdMountPath, isExternalSSD: true, rootFileSystemID: fileSystemID(for: "/"))
        return StorageStatusSnapshot(systemVolume: root, ssdVolume: ssd)
    }
    private func volumeSnapshot(id: String, name: String, mountPoint: String, isExternalSSD: Bool, rootFileSystemID: (Int32, Int32)? = nil) -> StorageVolumeSnapshot {
        var info = statfs(); let success = mountPoint.withCString { statfs($0, &info) == 0 }; let currentID = (info.f_fsid.val.0, info.f_fsid.val.1)
        guard success && (rootFileSystemID.map { currentID != $0 } ?? true) else { return StorageVolumeSnapshot(id: id, name: name, mountPoint: mountPoint, isMounted: false, isExternalSSD: isExternalSSD, usedBytes: 0, availableBytes: 0, totalBytes: 0) }
        let block = UInt64(info.f_bsize); let total = UInt64(info.f_blocks) * block; let available = UInt64(info.f_bavail) * block
        return StorageVolumeSnapshot(id: id, name: name, mountPoint: mountPoint, isMounted: true, isExternalSSD: isExternalSSD, usedBytes: total > available ? total - available : 0, availableBytes: available, totalBytes: total)
    }
    private func fileSystemID(for path: String) -> (Int32, Int32)? { var info = statfs(); guard path.withCString({ statfs($0, &info) == 0 }) else { return nil }; return (info.f_fsid.val.0, info.f_fsid.val.1) }
    private func captureTokenUsage() -> CLITokenUsageSnapshot {
        let items = AgentCLIKind.allCases.map { cli in readTokenUsage(cli: cli, paths: cli == .claude ? tokenDatabasePaths.claude : cli == .codex ? tokenDatabasePaths.codex : tokenDatabasePaths.copilot) }
        return CLITokenUsageSnapshot(items: items, claudeWeeklyRemainingPercent: readQuota())
    }
    private func readTokenUsage(cli: AgentCLIKind, paths: [URL]) -> CLITokenUsageItem {
        let queries: [String]
        switch cli {
        case .claude: queries = ["SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0) + COALESCE(SUM(cache_creation),0), COUNT(*) FROM fact_turn;", "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0) + COALESCE(SUM(cache_creation),0), COUNT(*) FROM turn;"]
        case .codex: queries = ["SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0) + COALESCE(SUM(cache_write),0), COUNT(*) FROM fact_request WHERE client IN ('codex-tui', 'codex_exec');", "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0) + COALESCE(SUM(cache_write),0), COUNT(*) FROM req;"]
        case .copilot: queries = ["SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read_tokens),0) + COALESCE(SUM(cache_write_tokens),0), COUNT(*) FROM assistant_usage_events;"]
        }
        for path in paths { for query in queries { if let values = readSQLite(path: path.path, query: query) { return CLITokenUsageItem(cli: cli, inputTokens: values.0, outputTokens: values.1, cacheTokens: values.2, isAvailable: true, interactionCount: values.3) } } }
        return CLITokenUsageItem(cli: cli, inputTokens: 0, outputTokens: 0, cacheTokens: 0, isAvailable: false)
    }
    // swiftlint:disable large_tuple
    private func readSQLite(path: String, query: String) -> (UInt64, UInt64, UInt64, UInt64)? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let database else { if let database { sqlite3_close(database) }; return nil }
        defer { sqlite3_close(database) }; sqlite3_busy_timeout(database, 100)
        var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else { if let statement { sqlite3_finalize(statement) }; return nil }
        defer { sqlite3_finalize(statement) }; guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return (UInt64(max(sqlite3_column_int64(statement, 0), 0)), UInt64(max(sqlite3_column_int64(statement, 1), 0)), UInt64(max(sqlite3_column_int64(statement, 2), 0)), UInt64(max(sqlite3_column_int64(statement, 3), 0)))
    }
    // swiftlint:enable large_tuple
    private func readQuota() -> Int? {
        guard let url = tokenDatabasePaths.claudeQuotaFileURL, let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let value = object["weekly_remaining_pct"] as? NSNumber else { return nil }
        return value.intValue
    }
    private static func defaultTokenDatabasePaths() -> CLITokenDatabasePaths {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return CLITokenDatabasePaths() }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let warehouse = home.appendingPathComponent("Development/AIDash/aidata/L3_merge/warehouse.db")
        return CLITokenDatabasePaths(
            claude: [warehouse, home.appendingPathComponent("Development/AIDash/aidata/L2_normalize/clean/claude_jsonl.db"), home.appendingPathComponent(".claude/warehouse.db"), home.appendingPathComponent(".claude/claude_jsonl.db")],
            codex: [warehouse, home.appendingPathComponent("Development/AIDash/aidata/L2_normalize/clean/raven.db"), home.appendingPathComponent(".codex/warehouse.db"), home.appendingPathComponent(".codex/raven.db")],
            copilot: [home.appendingPathComponent(".copilot/session-store.db")],
            claudeQuotaFileURL: home.appendingPathComponent(".config/claude/gtt-weekly-remaining-pct.json")
        )
    }
    private func sysctlString(_ name: String) -> String? {
        var size = 0; guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size); guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }; return String(cString: buffer)
    }
    private func sysctlInt(_ name: String) -> Int? { var value = 0; var size = MemoryLayout<Int>.size; return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil }
}
#endif
