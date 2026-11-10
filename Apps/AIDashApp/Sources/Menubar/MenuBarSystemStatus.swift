#if os(macOS)
// swiftlint:disable file_length
import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.ps
import SQLite3

public enum AgentCLIKind: String, CaseIterable, Sendable, Equatable, Identifiable {
    case claude = "Claude Code"
    case codex = "Codex CLI"
    case copilot = "Copilot CLI"
    case kimi = "Kimi CLI"
    case grok = "Grok CLI"
    case deepseek = "DeepSeek CLI"
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
    public let efficiencyCores: Int
    public let powerSummary: String?

    public init(
        chipName: String = "Apple Silicon",
        modelIdentifier: String = "Mac",
        totalCores: Int = 0,
        performanceCores: Int = 0,
        uptimeSeconds: TimeInterval = 0,
        thermalState: SystemThermalLevel = .nominal,
        efficiencyCores: Int = 0,
        powerSummary: String? = nil
    ) {
        self.chipName = chipName
        self.modelIdentifier = modelIdentifier
        self.totalCores = totalCores
        self.performanceCores = performanceCores
        self.uptimeSeconds = uptimeSeconds
        self.thermalState = thermalState
        self.efficiencyCores = efficiencyCores
        self.powerSummary = powerSummary
    }
}

public struct GPUStatusSnapshot: Sendable, Equatable {
    public let deviceUtilization: Double
    public let rendererUtilization: Double
    public let tilerUtilization: Double
    public let inUseMemoryBytes: UInt64
    public let allocMemoryBytes: UInt64

    public init(
        deviceUtilization: Double = 0,
        rendererUtilization: Double = 0,
        tilerUtilization: Double = 0,
        inUseMemoryBytes: UInt64 = 0,
        allocMemoryBytes: UInt64 = 0
    ) {
        self.deviceUtilization = deviceUtilization
        self.rendererUtilization = rendererUtilization
        self.tilerUtilization = tilerUtilization
        self.inUseMemoryBytes = inUseMemoryBytes
        self.allocMemoryBytes = allocMemoryBytes
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
    public let gpu: GPUStatusSnapshot
    public let topProcessName: String?
    public let topProcessValueText: String?

    public init(
        usage: Double,
        user: Double,
        system: Double,
        idle: Double,
        coreCount: Int,
        loadOneMinute: Double,
        loadFiveMinutes: Double,
        loadFifteenMinutes: Double,
        history: [Double] = [],
        gpu: GPUStatusSnapshot = GPUStatusSnapshot(),
        topProcessName: String? = nil,
        topProcessValueText: String? = nil
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
        self.gpu = gpu
        self.topProcessName = topProcessName
        self.topProcessValueText = topProcessValueText
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
    public let topProcessName: String?
    public let topProcessValueText: String?

    public init(
        usedBytes: UInt64,
        totalBytes: UInt64,
        freeBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        pressure: MemoryPressureLevel,
        swapUsedBytes: UInt64 = 0,
        swapTotalBytes: UInt64 = 0,
        topProcessName: String? = nil,
        topProcessValueText: String? = nil
    ) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.pressure = pressure
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.topProcessName = topProcessName
        self.topProcessValueText = topProcessValueText
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
    public let attention: AttentionStatusSnapshot
    public let gateway: GatewayStatusSnapshot

    public init(capturedAt: Date, computerCapturedAt: Date? = nil, tokenCapturedAt: Date? = nil, machine: MachineStatusSnapshot = MachineStatusSnapshot(), cpu: CPUStatusSnapshot, memory: MemoryStatusSnapshot, network: NetworkStatusSnapshot = NetworkStatusSnapshot(), storage: StorageStatusSnapshot, tokenUsage: CLITokenUsageSnapshot, attention: AttentionStatusSnapshot = AttentionStatusSnapshot(), gateway: GatewayStatusSnapshot = GatewayStatusSnapshot()) {
        self.capturedAt = capturedAt; self.computerCapturedAt = computerCapturedAt ?? capturedAt; self.tokenCapturedAt = tokenCapturedAt ?? capturedAt
        self.machine = machine; self.cpu = cpu; self.memory = memory; self.network = network; self.storage = storage; self.tokenUsage = tokenUsage; self.attention = attention; self.gateway = gateway
    }
    public func updatingComputer(_ computer: ComputerStatusSnapshot) -> Self {
        Self(capturedAt: max(computer.capturedAt, tokenCapturedAt), computerCapturedAt: computer.capturedAt, tokenCapturedAt: tokenCapturedAt, machine: computer.machine, cpu: computer.cpu, memory: computer.memory, network: computer.network, storage: computer.storage, tokenUsage: tokenUsage, attention: attention, gateway: gateway)
    }
    public func updatingTokenUsage(_ tokenUsage: CLITokenUsageSnapshot, capturedAt: Date) -> Self {
        Self(capturedAt: max(computerCapturedAt, capturedAt), computerCapturedAt: computerCapturedAt, tokenCapturedAt: capturedAt, machine: machine, cpu: cpu, memory: memory, network: network, storage: storage, tokenUsage: tokenUsage, attention: attention, gateway: gateway)
    }
}

public struct AttentionStatusItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let category: String?
    public let waitingOn: String?
    public init(id: String, title: String, category: String? = nil, waitingOn: String? = nil) {
        self.id = id; self.title = title; self.category = category; self.waitingOn = waitingOn
    }
}

public struct AttentionStatusSnapshot: Sendable, Equatable {
    public let needsPersonCount: Int
    public let activeGoalCount: Int
    public let items: [AttentionStatusItem]
    public init(needsPersonCount: Int = 0, activeGoalCount: Int = 0, items: [AttentionStatusItem] = []) {
        self.needsPersonCount = needsPersonCount; self.activeGoalCount = activeGoalCount; self.items = items
    }
}

public struct GatewayStatusSnapshot: Sendable, Equatable {
    public let magpieUp: Bool
    public let ravenUp: Bool
    public let falconUp: Bool
    public let jevRequests24h: Int
    public let jevStarredCount: Int
    public init(magpieUp: Bool = false, ravenUp: Bool = false, falconUp: Bool = false, jevRequests24h: Int = 0, jevStarredCount: Int = 0) {
        self.magpieUp = magpieUp; self.ravenUp = ravenUp; self.falconUp = falconUp; self.jevRequests24h = jevRequests24h; self.jevStarredCount = jevStarredCount
    }
}

public enum MenuBarStatusViewState: Sendable, Equatable {
    case loading, empty(reason: String), error(message: String), populated(MenuBarSystemSnapshot)
}

public struct CLITokenDatabasePaths: Sendable, Equatable {
    public let claude: [URL]; public let codex: [URL]; public let copilot: [URL]
    public let claudeQuotaFileURL: URL?
    public let magpieQuotaFileURL: URL?
    public init(
        claude: [URL] = [],
        codex: [URL] = [],
        copilot: [URL] = [],
        claudeQuotaFileURL: URL? = nil,
        magpieQuotaFileURL: URL? = nil
    ) {
        self.claude = claude
        self.codex = codex
        self.copilot = copilot
        self.claudeQuotaFileURL = claudeQuotaFileURL
        self.magpieQuotaFileURL = magpieQuotaFileURL
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
        return .populated(MenuBarSystemSnapshot(capturedAt: max(computer.capturedAt, tokens.capturedAt), computerCapturedAt: computer.capturedAt, tokenCapturedAt: tokens.capturedAt, machine: computer.machine, cpu: computer.cpu, memory: computer.memory, network: computer.network, storage: computer.storage, tokenUsage: tokens.usage, attention: captureAttention(), gateway: captureGateway()))
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
        let efficiency = sysctlInt("hw.perflevel1.physicalcpu") ?? max(total - performance, 0)
        return MachineStatusSnapshot(
            chipName: sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon",
            modelIdentifier: sysctlString("hw.model") ?? "Mac",
            totalCores: total,
            performanceCores: performance,
            uptimeSeconds: ProcessInfo.processInfo.systemUptime,
            thermalState: thermal,
            efficiencyCores: efficiency,
            powerSummary: capturePowerSummary()
        )
    }
    private func captureCPU() -> CPUStatusSnapshot {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        let coreCount = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let loads = getLoadAverages()
        let gpu = captureGPU()
        let topProcess = captureTopProcess(metric: .cpu)
        guard result == KERN_SUCCESS else {
            return CPUStatusSnapshot(
                usage: min(max(loads.one / Double(coreCount), 0), 1),
                user: 0,
                system: 0,
                idle: 1,
                coreCount: coreCount,
                loadOneMinute: loads.one,
                loadFiveMinutes: loads.five,
                loadFifteenMinutes: loads.fifteen,
                history: cpuUsageHistory,
                gpu: gpu,
                topProcessName: topProcess.name,
                topProcessValueText: topProcess.value
            )
        }
        let ticks = [UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3)]
        let breakdown = Self.computeCPUUsageBreakdown(currentTicks: ticks, previousTicks: previousCPUTicks)
        previousCPUTicks = ticks; cpuUsageHistory = Array((cpuUsageHistory + [breakdown.usage]).suffix(12))
        return CPUStatusSnapshot(usage: breakdown.usage, user: breakdown.user, system: breakdown.system, idle: breakdown.idle, coreCount: coreCount, loadOneMinute: loads.one, loadFiveMinutes: loads.five, loadFifteenMinutes: loads.fifteen, history: cpuUsageHistory, gpu: gpu, topProcessName: topProcess.name, topProcessValueText: topProcess.value)
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
        let topProcess = captureTopProcess(metric: .memory)
        guard result == KERN_SUCCESS else { return MemoryStatusSnapshot(usedBytes: 0, totalBytes: total, freeBytes: total, wiredBytes: 0, compressedBytes: 0, pressure: .normal, swapUsedBytes: swapOK ? swap.xsu_used : 0, swapTotalBytes: swapOK ? swap.xsu_total : 0, topProcessName: topProcess.name, topProcessValueText: topProcess.value) }
        let free = UInt64(vm.free_count) * page; let inactive = UInt64(vm.inactive_count) * page; let speculative = UInt64(vm.speculative_count) * page
        let used = total > free + inactive + speculative ? total - free - inactive - speculative : 0
        let fraction = total > 0 ? Double(used) / Double(total) : 0
        return MemoryStatusSnapshot(usedBytes: used, totalBytes: total, freeBytes: free, wiredBytes: UInt64(vm.wire_count) * page, compressedBytes: UInt64(vm.compressor_page_count) * page, pressure: fraction >= 0.9 ? .critical : fraction >= 0.75 ? .warning : .normal, swapUsedBytes: swapOK ? swap.xsu_used : 0, swapTotalBytes: swapOK ? swap.xsu_total : 0, topProcessName: topProcess.name, topProcessValueText: topProcess.value)
    }
    private func hostPageSize() -> vm_size_t { var size: vm_size_t = 0; host_page_size(mach_host_self(), &size); return size }
    private enum ProcessMetric { case cpu, memory }

    private func captureTopProcess(metric: ProcessMetric) -> (name: String?, value: String?) {
        var pids = [pid_t](repeating: 0, count: 2048)
        let bytes = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, Int32($0.count))
        }
        guard bytes > 0 else { return (nil, nil) }
        var best: (name: String, value: UInt64)?
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride) where pid > 0 {
            var task = proc_taskinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, Int32(MemoryLayout<proc_taskinfo>.size))
            guard size == MemoryLayout<proc_taskinfo>.size else { continue }
            let value: UInt64
            switch metric {
            case .cpu: value = task.pti_total_user + task.pti_total_system
            case .memory: value = task.pti_resident_size
            }
            guard value > 0 else { continue }
            var buffer = [CChar](repeating: 0, count: 256)
            guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            let name = String(cString: buffer)
            if best == nil || value > best!.value { best = (name, value) }
        }
        guard let best else { return (nil, nil) }
        return (best.name, metric == .memory ? formatProcessBytes(best.value) : formatProcessTicks(best.value))
    }

    private func formatProcessBytes(_ bytes: UInt64) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: "%.1f%@", value, units[index])
    }

    private func formatProcessTicks(_ ticks: UInt64) -> String {
        if ticks >= 1_000_000_000 {
            return String(format: "%.1fB ticks", Double(ticks) / 1_000_000_000)
        } else if ticks >= 1_000_000 {
            return String(format: "%.1fM ticks", Double(ticks) / 1_000_000)
        } else if ticks >= 1_000 {
            return String(format: "%.1fK ticks", Double(ticks) / 1_000)
        }
        return "\(ticks) ticks"
    }

    private func captureGPU() -> GPUStatusSnapshot {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else {
            return GPUStatusSnapshot()
        }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any],
                  let performance = dictionary["PerformanceStatistics"] as? [String: Any] else { continue }
            func number(_ key: String) -> Double { (performance[key] as? NSNumber)?.doubleValue ?? 0 }
            func bytes(_ key: String) -> UInt64 { (performance[key] as? NSNumber).map { UInt64(max($0.int64Value, 0)) } ?? 0 }
            return GPUStatusSnapshot(
                deviceUtilization: number("Device Utilization %") / 100,
                rendererUtilization: number("Renderer Utilization %") / 100,
                tilerUtilization: number("Tiler Utilization %") / 100,
                inUseMemoryBytes: bytes("In use system memory"),
                allocMemoryBytes: bytes("Alloc system memory")
            )
        }
        return GPUStatusSnapshot()
    }

    private func capturePowerSummary() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let state = description[kIOPSPowerSourceStateKey as String] as? String else { continue }
            if state == kIOPSACPowerValue as String { return "AC" }
            if let current = description[kIOPSCurrentCapacityKey as String] as? NSNumber {
                return "\(current.intValue)%"
            }
        }
        return nil
    }

    private func captureNetwork() -> NetworkStatusSnapshot {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return NetworkStatusSnapshot() }
        defer { freeifaddrs(first) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        struct InterfaceStats {
            var ipv4: String?
            var received: UInt64 = 0
            var sent: UInt64 = 0
        }
        var interfaces: [String: InterfaceStats] = [:]
        while let item = cursor?.pointee {
            let name = String(cString: item.ifa_name)
            if name.hasPrefix("en"), (item.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 {
                var stats = interfaces[name, default: InterfaceStats()]
                if let addr = item.ifa_addr {
                    if addr.pointee.sa_family == UInt8(AF_INET) {
                        var storage = sockaddr_in(); memcpy(&storage, addr, MemoryLayout<sockaddr_in>.size)
                        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        let value = withUnsafePointer(to: &storage.sin_addr) { inet_ntop(AF_INET, $0, &buffer, socklen_t(INET_ADDRSTRLEN)) }
                        stats.ipv4 = value.map { String(cString: $0) }
                    } else if addr.pointee.sa_family == UInt8(AF_LINK), let data = item.ifa_data?.assumingMemoryBound(to: if_data.self) {
                        stats.received = UInt64(data.pointee.ifi_ibytes); stats.sent = UInt64(data.pointee.ifi_obytes)
                    }
                }
                interfaces[name] = stats
            }
            cursor = item.ifa_next
        }
        let selected = interfaces["en0"]?.ipv4 != nil
            ? "en0"
            : interfaces.keys.sorted().first(where: { interfaces[$0]?.ipv4 != nil }) ?? "en0"
        let selectedStats = interfaces[selected] ?? InterfaceStats()
        let address = selectedStats.ipv4
        let received = selectedStats.received
        let sent = selectedStats.sent
        let connected = address != nil
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
        let items = AgentCLIKind.allCases.map { cli in
            switch cli {
            case .claude:
                return readTokenUsage(cli: cli, paths: tokenDatabasePaths.claude)
            case .codex:
                return readTokenUsage(cli: cli, paths: tokenDatabasePaths.codex)
            case .copilot:
                return readTokenUsage(cli: cli, paths: tokenDatabasePaths.copilot)
            case .kimi, .grok, .deepseek:
                return readTokenUsage(cli: cli, paths: [])
            }
        }
        return CLITokenUsageSnapshot(items: items, claudeWeeklyRemainingPercent: readQuota())
    }
    private func readTokenUsage(cli: AgentCLIKind, paths: [URL]) -> CLITokenUsageItem {
        let queries: [String]
        switch cli {
        case .claude: queries = ["SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0) + COALESCE(SUM(cache_creation),0), COUNT(*) FROM fact_turn;", "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0) + COALESCE(SUM(cache_creation),0), COUNT(*) FROM turn;"]
        case .codex: queries = ["SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0) + COALESCE(SUM(cache_write),0), COUNT(*) FROM fact_request WHERE client IN ('codex-tui', 'codex_exec');", "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0) + COALESCE(SUM(cache_write),0), COUNT(*) FROM req;"]
        case .copilot: queries = ["SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read_tokens),0) + COALESCE(SUM(cache_write_tokens),0), COUNT(*) FROM assistant_usage_events;"]
        case .kimi, .grok, .deepseek: queries = []
        }
        for path in paths {
            if path.lastPathComponent == "warehouse.db",
               let values = readSQLite(path: path.path, query: deviceTokenUsageQuery(for: cli)) {
                return CLITokenUsageItem(cli: cli, inputTokens: values.0, outputTokens: values.1, cacheTokens: values.2, isAvailable: true, interactionCount: values.3)
            }
            for query in queries {
                if let values = readSQLite(path: path.path, query: query) {
                    return CLITokenUsageItem(cli: cli, inputTokens: values.0, outputTokens: values.1, cacheTokens: values.2, isAvailable: true, interactionCount: values.3)
                }
            }
        }
        return CLITokenUsageItem(cli: cli, inputTokens: 0, outputTokens: 0, cacheTokens: 0, isAvailable: false)
    }
    private func deviceTokenUsageQuery(for cli: AgentCLIKind) -> String {
        let pattern: String
        switch cli {
        case .claude: pattern = "%claude%"
        case .codex: pattern = "%codex%"
        case .copilot: pattern = "%copilot%"
        case .kimi: pattern = "%kimi%"
        case .grok: pattern = "%grok%"
        case .deepseek: pattern = "%deepseek%"
        }
        return "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0) + COALESCE(SUM(cache_write),0), COALESCE(SUM(invocations),0) FROM fact_device_token_daily WHERE device_id != '__all__' AND lower(cli) LIKE '\(pattern)' HAVING COUNT(*) > 0;"
    }

    // swiftlint:disable large_tuple
    private func readSQLite(path: String, query: String) -> (UInt64, UInt64, UInt64, UInt64)? {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        if let result = runSQLiteQuery(target: path, flags: flags, query: query) {
            return result
        }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return runSQLiteQuery(
            target: "file:\(encodedPath)?mode=ro&immutable=1",
            flags: flags | SQLITE_OPEN_URI,
            query: query
        )
    }

    private func runSQLiteQuery(target: String, flags: Int32, query: String) -> (UInt64, UInt64, UInt64, UInt64)? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(target, &database, flags, nil) == SQLITE_OK, let database else { if let database { sqlite3_close(database) }; return nil }
        defer { sqlite3_close(database) }; sqlite3_busy_timeout(database, 100)
        var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else { if let statement { sqlite3_finalize(statement) }; return nil }
        defer { sqlite3_finalize(statement) }; guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return (UInt64(max(sqlite3_column_int64(statement, 0), 0)), UInt64(max(sqlite3_column_int64(statement, 1), 0)), UInt64(max(sqlite3_column_int64(statement, 2), 0)), UInt64(max(sqlite3_column_int64(statement, 3), 0)))
    }
    // swiftlint:enable large_tuple
    private func readQuota() -> Int? {
        var urls = [tokenDatabasePaths.claudeQuotaFileURL, tokenDatabasePaths.magpieQuotaFileURL].compactMap { $0 }
        let isLive = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        if isLive {
            urls.append(Self.realUserHomeDirectoryURL().appendingPathComponent(".config/magpie/quotas.json"))
        }
        let now = Date()
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let value = object["weekly_remaining_pct"] as? NSNumber {
                if isLive, let measuredAt = (object["measured_at"] as? NSNumber)?.doubleValue {
                    if now.timeIntervalSince1970 - measuredAt > 86_400 { continue }
                }
                return value.intValue
            }
            if let claude = object["claude"] as? [String: Any],
               let sevenDays = claude["7 days"] as? [String: Any],
               let used = sevenDays["used"] as? NSNumber {
                return max(0, min(100, 100 - used.intValue))
            }
        }
        return nil
    }
    private func captureAttention() -> AttentionStatusSnapshot {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return AttentionStatusSnapshot() }
        let url = Self.realUserHomeDirectoryURL().appendingPathComponent("Development/handoff/_watch/attention-status.json")
        guard let data = try? Data(contentsOf: url) else { return AttentionStatusSnapshot() }
        struct WireItem: Decodable { let id: String; let title: String; let category: String?; let waitingOn: String? }
        struct Wire: Decodable { let needsPersonCount: Int?; let activeGoalCount: Int?; let items: [WireItem]? }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return AttentionStatusSnapshot() }
        return AttentionStatusSnapshot(needsPersonCount: wire.needsPersonCount ?? wire.items?.count ?? 0, activeGoalCount: wire.activeGoalCount ?? 0, items: wire.items?.map { AttentionStatusItem(id: $0.id, title: $0.title, category: $0.category, waitingOn: $0.waitingOn) } ?? [])
    }
    private func captureGateway() -> GatewayStatusSnapshot {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return GatewayStatusSnapshot() }
        let home = Self.realUserHomeDirectoryURL()
        let magpieConfig = home.appendingPathComponent(".config/magpie")
        let ravenSupport = home.appendingPathComponent("Library/Application Support/raven")
        let falcon = home.appendingPathComponent("Library/Application Support/Falcon/falcon.sqlite")
        let magpieUp = portOpen(3425)
            || runningProcess(named: "magpie")
            || fileExists(at: magpieConfig.appendingPathComponent("served.json"))
            || fileExists(at: magpieConfig.appendingPathComponent("quotas.json"))
        let served = magpieConfig.appendingPathComponent("served.json")
        let ravenUp = portOpen(7024)
            || fileContains(served, substring: "raven")
            || fileExists(at: ravenSupport.appendingPathComponent("raven.db"))
            || fileExists(at: ravenSupport.appendingPathComponent("clean/raven.db"))
            || fileExists(at: home.appendingPathComponent("Development/AIDash/aidata/L2_normalize/clean/raven.db"))
        let falconUp = portOpen(19823)
            || runningProcess(named: "Falcon")
            || fileExists(at: falcon)
            || fileExists(at: home.appendingPathComponent("Library/Application Support/Falcon/instance.lock"))
        let requests = readSQLiteCount(path: falcon.path, query: "SELECT COUNT(*) FROM requests WHERE received_at >= (strftime('%s','now') - 978307200 - 86400);")
            ?? readSQLiteCount(path: falcon.path, query: "SELECT COUNT(*) FROM requests WHERE created_at >= datetime('now','-1 day');")
            ?? 0
        let starred = readSQLiteCount(path: falcon.path, query: "SELECT COUNT(*) FROM requests WHERE json_extract(summary_json, '$.starredAt') IS NOT NULL OR review_state = 'starred';")
            ?? readSQLiteCount(path: falcon.path, query: "SELECT COUNT(*) FROM requests WHERE starredAt IS NOT NULL;")
            ?? 0
        return GatewayStatusSnapshot(magpieUp: magpieUp, ravenUp: ravenUp, falconUp: falconUp, jevRequests24h: requests, jevStarredCount: starred)
    }
    private func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
    private func fileContains(_ url: URL, substring: String) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return contents.localizedCaseInsensitiveContains(substring)
    }
    private func runningProcess(named name: String) -> Bool {
        var pids = [pid_t](repeating: 0, count: 2048)
        let bytes = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, Int32($0.count))
        }
        guard bytes > 0 else { return false }
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride) where pid > 0 {
            var nameBuffer = [CChar](repeating: 0, count: 256)
            if proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0,
               String(cString: nameBuffer) == name {
                return true
            }
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0,
               URL(fileURLWithPath: String(cString: pathBuffer)).lastPathComponent == name {
                return true
            }
        }
        return false
    }
    private func portOpen(_ port: UInt16) -> Bool {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        return connected
    }
    private func readSQLiteCount(path: String, query: String) -> Int? {
        guard let value = readSQLite(path: path, query: query) else { return nil }
        return Int(value.0)
    }
    private static func defaultTokenDatabasePaths() -> CLITokenDatabasePaths {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return CLITokenDatabasePaths() }
        let home = realUserHomeDirectoryURL()
        let warehouse = home.appendingPathComponent("Development/AIDash/aidata/L3_merge/warehouse.db")
        return CLITokenDatabasePaths(
            claude: [warehouse, home.appendingPathComponent("Development/AIDash/aidata/L2_normalize/clean/claude_jsonl.db"), home.appendingPathComponent(".claude/warehouse.db"), home.appendingPathComponent(".claude/claude_jsonl.db")],
            codex: [warehouse, home.appendingPathComponent("Development/AIDash/aidata/L2_normalize/clean/raven.db"), home.appendingPathComponent(".codex/warehouse.db"), home.appendingPathComponent(".codex/raven.db")],
            copilot: [home.appendingPathComponent(".copilot/session-store.db")],
            claudeQuotaFileURL: home.appendingPathComponent(".config/claude/gtt-weekly-remaining-pct.json")
        )
    }
    internal static func realUserHomeDirectoryURL() -> URL {
        if let passwd = getpwuid(getuid()), let pwDir = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: pwDir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
    private func sysctlString(_ name: String) -> String? {
        var size = 0; guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size); guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }; return String(cString: buffer)
    }
    private func sysctlInt(_ name: String) -> Int? { var value = 0; var size = MemoryLayout<Int>.size; return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil }
}
#endif
