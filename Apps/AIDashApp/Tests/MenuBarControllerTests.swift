#if os(macOS)
import Testing
import Foundation
import AppKit
import SwiftUI
import SQLite3
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

// MARK: - Localization contract tests
//
// These guard Constitution §F.1: every user-visible menu bar string must
// resolve through the String Catalog (`Localizable.xcstrings`) via the
// `String(localized:)` accessor, not a raw literal embedded in source.

@MainActor
@Test func menuBarAppNameIsLocalized() async throws {
    let value = MenuBarController.appName
    #expect(!value.isEmpty)
    #expect(value == "AIDash")
}

@MainActor
@Test func menuBarOpenBriefingIsLocalized() async throws {
    let value = MenuBarController.openBriefingTitle
    #expect(!value.isEmpty)
    #expect(value == "Open Briefing")
}

@MainActor
@Test func menuBarAboutIsLocalized() async throws {
    let value = MenuBarController.aboutTitle
    #expect(!value.isEmpty)
    #expect(value == "About AIDash")
}

@MainActor
@Test func menuBarQuitIsLocalized() async throws {
    let value = MenuBarController.quitTitle
    #expect(!value.isEmpty)
    #expect(value == "Quit AIDash")
}

// MARK: - Layout-recursion regression (MY-1034)
//
// The original menu-bar icon was an SF Symbol installed on a
// `NSStatusItem.variableLength` host without an explicit size or template
// flag. On macOS 26 that combination made AppKit re-enter
// `-layoutSubtreeIfNeeded` during the initial layout pass, producing the
// `_NSDetectedLayoutRecursion` warning that MY-1017 was supposed to fix.
// This test pins the contract that prevents that recursion: a fixed-length
// status item plus a template image whose `size` is set before being
// handed to the button.
@MainActor
@Test func menuBarStatusItemUsesFixedLengthAndSizedTemplateIcon() async throws {
    let controller = MenuBarController()
    defer {
        controller.stopPeriodicRefresh()
        if let item = controller.statusItemForTesting {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    let item = try #require(controller.statusItemForTesting)
    #expect(item.length == NSStatusItem.squareLength)

    let icon = try #require(item.button?.image)
    #expect(icon.isTemplate)
    #expect(icon.size == NSSize(width: 18, height: 18))
    #expect(icon.accessibilityDescription == MenuBarController.appName)
}

@MainActor
@Test func summaryMenuItemsAreHiddenButRemainTaggedAndUpdated() async throws {
    let controller = MenuBarController(statusProvider: MenuBarStatusProviderSpy())
    defer {
        controller.stopPeriodicRefresh()
        if let item = controller.statusItemForTesting {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    let menu = try #require(controller.statusItemForTesting?.menu)
    let summaryItems = (1001...1008).compactMap { menu.item(withTag: $0) }
    #expect(summaryItems.count == 8)
    #expect(summaryItems.allSatisfy { $0.isHidden && !$0.isEnabled })
    #expect(menu.items.first?.isSeparatorItem == false)
    #expect(menu.items.dropFirst().first?.isSeparatorItem == true)
    controller.refreshComputerSections()
    #expect(menu.item(withTag: 1001)?.title.contains("CPU") == true)
}

@MainActor
@Test func statusSnapshotsCalculateUsageAndShares() async throws {
    let cpu = CPUStatusSnapshot(
        usage: 0.5,
        user: 0.3,
        system: 0.2,
        idle: 0.5,
        coreCount: 8,
        loadOneMinute: 1,
        loadFiveMinutes: 0.8,
        loadFifteenMinutes: 0.6
    )
    let memory = MemoryStatusSnapshot(
        usedBytes: 75,
        totalBytes: 100,
        freeBytes: 25,
        wiredBytes: 10,
        compressedBytes: 5,
        pressure: .warning
    )
    let root = StorageVolumeSnapshot(
        id: "root",
        name: "Macintosh HD",
        mountPoint: "/",
        isMounted: true,
        isExternalSSD: false,
        usedBytes: 75,
        availableBytes: 25,
        totalBytes: 100
    )
    let ssd = StorageVolumeSnapshot(
        id: "ssd",
        name: "SSD",
        mountPoint: "/Volumes/SSD",
        isMounted: false,
        isExternalSSD: true,
        usedBytes: 0,
        availableBytes: 0,
        totalBytes: 0
    )
    let usage = CLITokenUsageSnapshot(items: [
        CLITokenUsageItem(cli: .claude, inputTokens: 10, outputTokens: 20, cacheTokens: 5, isAvailable: true),
        CLITokenUsageItem(cli: .codex, inputTokens: 30, outputTokens: 0, cacheTokens: 10, isAvailable: true),
        CLITokenUsageItem(cli: .copilot, inputTokens: 0, outputTokens: 0, cacheTokens: 0, isAvailable: false)
    ])
    let snapshot = MenuBarSystemSnapshot(
        capturedAt: Date(),
        cpu: cpu,
        memory: memory,
        storage: StorageStatusSnapshot(systemVolume: root, ssdVolume: ssd),
        tokenUsage: usage
    )

    #expect(snapshot.cpu.usage == 0.5)
    #expect(snapshot.memory.usageFraction == 0.75)
    #expect(snapshot.storage.ssdVolume.isMounted == false)
    #expect(snapshot.tokenUsage.totalActiveTokens == 60)
    #expect(snapshot.tokenUsage.grandTotalTokens == 75)
    #expect(snapshot.tokenUsage.shareFraction(for: .codex) == 0.5)
    #expect(MenuBarController.cliTokenSummary(cli: .claude, usage: usage).contains("Claude Code"))
    #expect(MenuBarController.cliTokenSummary(cli: .claude, usage: usage).contains("30"))
    #expect(MenuBarController.cliTokenSummary(cli: .copilot, usage: usage).contains("unavailable"))

    let mountedSSD = StorageVolumeSnapshot(
        id: "ssd",
        name: "SSD",
        mountPoint: "/Volumes/SSD",
        isMounted: true,
        isExternalSSD: true,
        usedBytes: 120 * 1_000_000_000,
        availableBytes: 380 * 1_000_000_000,
        totalBytes: 500 * 1_000_000_000
    )
    #expect(mountedSSD.isMounted)
    #expect(mountedSSD.usageFraction == 0.24)
}

@MainActor
@Test func cpuUsageBreakdownUsesDarwinTickOrder() async throws {
    let breakdown = LiveMenuBarSystemStatusProvider.computeCPUUsageBreakdown(
        currentTicks: [60, 30, 900, 10],
        previousTicks: nil
    )

    #expect(breakdown.usage == 0.10)
    #expect(breakdown.user == 0.07)
    #expect(breakdown.system == 0.03)
    #expect(breakdown.idle == 0.90)
}

@MainActor
@Test func statusProviderUsesExplicitDatabasePathsInTests() async throws {
    let provider = LiveMenuBarSystemStatusProvider(
        tokenDatabasePaths: CLITokenDatabasePaths(
            claude: [URL(fileURLWithPath: "/does-not-exist/claude.db")],
            codex: [URL(fileURLWithPath: "/does-not-exist/codex.db")],
            copilot: [URL(fileURLWithPath: "/does-not-exist/copilot.db")]
        ),
        ssdMountPath: "/does-not-exist/SSD"
    )
    guard case let .populated(snapshot) = provider.captureStatusState() else {
        Issue.record("Expected a populated snapshot from system telemetry.")
        return
    }

    #expect(snapshot.tokenUsage.items.allSatisfy { !$0.isAvailable })
    #expect(snapshot.storage.ssdVolume.isMounted == false)
}

@MainActor
@Test func statusViewRendersAllPolymorphicStates() async throws {
    let root = StorageVolumeSnapshot(
        id: "root",
        name: "Macintosh HD",
        mountPoint: "/",
        isMounted: true,
        isExternalSSD: false,
        usedBytes: 180 * 1_000_000_000,
        availableBytes: 280 * 1_000_000_000,
        totalBytes: 460 * 1_000_000_000
    )
    let ssd = StorageVolumeSnapshot(
        id: "ssd",
        name: "SSD",
        mountPoint: "/Volumes/SSD",
        isMounted: false,
        isExternalSSD: true,
        usedBytes: 0,
        availableBytes: 0,
        totalBytes: 0
    )
    let snapshot = MenuBarSystemSnapshot(
        capturedAt: Date(),
        machine: MachineStatusSnapshot(
            chipName: "Apple M6",
            modelIdentifier: "Mac18,5",
            totalCores: 12,
            performanceCores: 6,
            uptimeSeconds: 9 * 86_400 + 1 * 3600 + 24 * 60,
            thermalState: .nominal
        ),
        cpu: CPUStatusSnapshot(
            usage: 0.42,
            user: 0.25,
            system: 0.17,
            idle: 0.58,
            coreCount: 12,
            loadOneMinute: 11.26,
            loadFiveMinutes: 27.40,
            loadFifteenMinutes: 25.14,
            history: [0.18, 0.24, 0.31, 0.28, 0.35, 0.48, 0.52, 0.44, 0.39, 0.46, 0.38, 0.42]
        ),
        memory: MemoryStatusSnapshot(
            usedBytes: 18 * 1_073_741_824,
            totalBytes: 24 * 1_073_741_824,
            freeBytes: 6 * 1_073_741_824,
            wiredBytes: 4 * 1_073_741_824,
            compressedBytes: 2 * 1_073_741_824,
            pressure: .normal,
            swapUsedBytes: 3_881_877_504,
            swapTotalBytes: 5_368_709_120
        ),
        network: NetworkStatusSnapshot(
            interfaceName: "en0",
            ipAddress: "192.168.31.90",
            isConnected: true,
            downloadBytesPerSecond: 12_850_000,
            uploadBytesPerSecond: 1_940_000,
            totalReceivedBytes: 83_018_782_236,
            totalSentBytes: 237_855_478_549,
            throughputHistory: [3.2, 5.8, 4.1, 9.4, 14.2, 11.6, 8.5, 12.1, 15.8, 10.4, 13.2, 14.8]
        ),
        storage: StorageStatusSnapshot(systemVolume: root, ssdVolume: ssd),
        tokenUsage: CLITokenUsageSnapshot(items: [
            CLITokenUsageItem(cli: .claude, inputTokens: 135_736, outputTokens: 6_445_523, cacheTokens: 2_875_353_916, isAvailable: true, interactionCount: 9_705),
            CLITokenUsageItem(cli: .codex, inputTokens: 209_568_635, outputTokens: 26_303_166, cacheTokens: 0, isAvailable: true, interactionCount: 38_644),
            CLITokenUsageItem(cli: .copilot, inputTokens: 25_826_997_826, outputTokens: 25_409_302, cacheTokens: 24_963_105_519, isAvailable: true, interactionCount: 101_210)
        ], claudeWeeklyRemainingPercent: 91)
    )
    let states: [(String, MenuBarStatusViewState)] = [
        ("populated", .populated(snapshot)),
        ("empty", .empty(reason: "No local sources")),
        ("loading", .loading),
        ("error", .error(message: "Try again"))
    ]
    let outputDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aidash-menubar-shots-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: outputDirectory) }
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let exportDirectory = ProcessInfo.processInfo.environment["AIDASH_SCREENSHOT_EXPORT_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Development/handoff/aidash-sb/screenshots", isDirectory: true)
    try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
    var renderedData: [String: Data] = [:]

    for (name, state) in states {
        for isDark in [false, true] {
            let scheme: ColorScheme = isDark ? .dark : .light
            let view = MenuBarStatusView(state: state)
                .designTheme(seed: .lime, neutral: .slate)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2.0
            let tiff = try #require(renderer.nsImage?.tiffRepresentation)
            let data = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            #expect(!data.isEmpty)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            #expect(bitmap.pixelsWide == 760)
            #expect(bitmap.pixelsHigh > 0)
            let suffix = isDark ? "dark" : "light"
            try data.write(to: outputDirectory.appendingPathComponent("\(name)-\(suffix).png"))
            try data.write(to: exportDirectory.appendingPathComponent("\(name)-\(suffix).png"))
            if !isDark {
                renderedData[name] = data
            } else {
                #expect(renderedData[name] != data)
            }
        }

        #expect(MenuBarStatusView.formatLoadAverages(one: 11.26, five: 27.40, fifteen: 25.14) == "11.3 / 27.4 / 25.1")
        #expect(MenuBarStatusView.compactMemoryPair(used: 18 * 1_073_741_824, total: 24 * 1_073_741_824) == "18.0 / 24.0 GB")
    }
}

@MainActor
@Test func menuBarLocalizationNeverLeaksRawKeys() async throws {
    let keys = [
        "menubar.status.active_format",
        "menubar.status.claude_quota",
        "menubar.status.total",
        "menubar.status.turns_reqs",
        "menubar.status.interaction",
        "menubar.status.in_out_format",
        "menubar.status.cache_format",
        "menubar.status.uptime",
        "menubar.status.storage_detail"
    ]
    for key in keys {
        #expect(!MenuBarController.resolveLocalized(key, "fallback").contains("menubar."))
        #expect(!MenuBarStatusView.resolveLocalized(key, "fallback").contains("menubar."))
    }
    let usage = CLITokenUsageSnapshot(items: [
        CLITokenUsageItem(cli: .claude, inputTokens: 135_736, outputTokens: 6_445_523, cacheTokens: 2_875_353_916, isAvailable: true, interactionCount: 9_705)
    ])
    #expect(!MenuBarController.tokenSummary(usage).contains("menubar."))
    #expect(!MenuBarController.cliTokenSummary(cli: .claude, usage: usage).contains("menubar."))
}

@MainActor
@Test func sectionalRefreshCadencesAndNewMetrics() async throws {
    #expect(MenuBarStatusSection.machine.refreshIntervalSeconds == 5)
    #expect(MenuBarStatusSection.storage.isComputerSection)
    #expect(MenuBarStatusSection.tokenUsage.refreshIntervalSeconds == 60)
    #expect(!MenuBarStatusSection.tokenUsage.isComputerSection)
    let memory = MemoryStatusSnapshot(usedBytes: 80, totalBytes: 100, freeBytes: 20, wiredBytes: 10, compressedBytes: 5, pressure: .warning, swapUsedBytes: 25, swapTotalBytes: 100)
    #expect(memory.swapUsageFraction == 0.25)
    let usage = CLITokenUsageSnapshot(items: [CLITokenUsageItem(cli: .claude, inputTokens: 10, outputTokens: 5, cacheTokens: 2, isAvailable: true, interactionCount: 9)], claudeWeeklyRemainingPercent: 91)
    #expect(usage.totalInteractions == 9)
    #expect(usage.claudeWeeklyRemainingPercent == 91)
    let machine = MachineStatusSnapshot(chipName: "Apple M6", modelIdentifier: "Mac18,5", totalCores: 12, performanceCores: 8, uptimeSeconds: 3660, thermalState: .nominal)
    #expect(machine.performanceCores == 8)
}

@MainActor
@Test func sectionalRefreshesOnlyCaptureTheirOwnProvider() async throws {
    let provider = MenuBarStatusProviderSpy()
    let controller = MenuBarController(statusProvider: provider)
    defer {
        controller.stopPeriodicRefresh()
        if let item = controller.statusItemForTesting {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    provider.computerStatusCallCount = 0
    provider.tokenStatusCallCount = 0
    let originalTokenDate = provider.tokenSnapshotDate
    controller.refreshComputerSections()
    #expect(provider.computerStatusCallCount == 1)
    #expect(provider.tokenStatusCallCount == 0)
    guard case let .populated(computerState) = controller.statusStateForTesting else {
        Issue.record("Expected populated state after computer refresh.")
        return
    }
    #expect(computerState.tokenCapturedAt == originalTokenDate)

    provider.computerStatusCallCount = 0
    provider.tokenStatusCallCount = 0
    let originalComputerDate = computerState.computerCapturedAt
    controller.refreshTokenSection()
    #expect(provider.computerStatusCallCount == 0)
    #expect(provider.tokenStatusCallCount == 1)
    guard case let .populated(tokenState) = controller.statusStateForTesting else {
        Issue.record("Expected populated state after token refresh.")
        return
    }
    #expect(tokenState.computerCapturedAt == originalComputerDate)
}

@MainActor
@Test func tokenProviderReadsInteractionCountAndClaudeQuota() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aidash-token-fixture-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let databaseURL = directory.appendingPathComponent("claude.db")
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    defer {
        if let database {
            sqlite3_close(database)
        }
    }
    let schema = """
    CREATE TABLE fact_turn (input_tokens INTEGER, output_tokens INTEGER, cache_read INTEGER, cache_creation INTEGER);
    INSERT INTO fact_turn VALUES (10, 20, 3, 4);
    INSERT INTO fact_turn VALUES (30, 40, 5, 6);
    """
    #expect(sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK)
    let quotaURL = directory.appendingPathComponent("quota.json")
    try Data(#"{"weekly_remaining_pct":91}"#.utf8).write(to: quotaURL)

    let provider = LiveMenuBarSystemStatusProvider(
        tokenDatabasePaths: CLITokenDatabasePaths(
            claude: [databaseURL],
            claudeQuotaFileURL: quotaURL
        )
    )
    let result = provider.captureTokenStatus()
    let claude = try #require(result.usage.items.first(where: { $0.cli == .claude }))
    #expect(claude.interactionCount == 2)
    #expect(claude.inputTokens == 40)
    #expect(claude.outputTokens == 60)
    #expect(claude.cacheTokens == 18)
    #expect(result.usage.claudeWeeklyRemainingPercent == 91)
}

@MainActor
private final class MenuBarStatusProviderSpy: MenuBarSystemStatusProviding {
    var computerStatusCallCount = 0
    var tokenStatusCallCount = 0
    let computerSnapshotDate = Date(timeIntervalSince1970: 1_000)
    let tokenSnapshotDate = Date(timeIntervalSince1970: 2_000)

    func captureStatusState() -> MenuBarStatusViewState {
        .populated(MenuBarSystemSnapshot(
            capturedAt: tokenSnapshotDate,
            computerCapturedAt: computerSnapshotDate,
            tokenCapturedAt: tokenSnapshotDate,
            cpu: CPUStatusSnapshot(usage: 0.1, user: 0.05, system: 0.05, idle: 0.9, coreCount: 8, loadOneMinute: 0, loadFiveMinutes: 0, loadFifteenMinutes: 0),
            memory: MemoryStatusSnapshot(usedBytes: 1, totalBytes: 2, freeBytes: 1, wiredBytes: 0, compressedBytes: 0, pressure: .normal),
            storage: StorageStatusSnapshot(
                systemVolume: StorageVolumeSnapshot(id: "root", name: "Root", mountPoint: "/", isMounted: true, isExternalSSD: false, usedBytes: 1, availableBytes: 1, totalBytes: 2),
                ssdVolume: StorageVolumeSnapshot(id: "ssd", name: "SSD", mountPoint: "/Volumes/SSD", isMounted: false, isExternalSSD: true, usedBytes: 0, availableBytes: 0, totalBytes: 0)
            ),
            tokenUsage: CLITokenUsageSnapshot(items: [])
        ))
    }

    func captureComputerStatus() -> ComputerStatusSnapshot {
        computerStatusCallCount += 1
        return ComputerStatusSnapshot(
            capturedAt: Date(timeIntervalSince1970: 3_000),
            cpu: CPUStatusSnapshot(usage: 0.2, user: 0.1, system: 0.1, idle: 0.8, coreCount: 8, loadOneMinute: 0, loadFiveMinutes: 0, loadFifteenMinutes: 0),
            memory: MemoryStatusSnapshot(usedBytes: 1, totalBytes: 2, freeBytes: 1, wiredBytes: 0, compressedBytes: 0, pressure: .normal),
            storage: StorageStatusSnapshot(
                systemVolume: StorageVolumeSnapshot(id: "root", name: "Root", mountPoint: "/", isMounted: true, isExternalSSD: false, usedBytes: 1, availableBytes: 1, totalBytes: 2),
                ssdVolume: StorageVolumeSnapshot(id: "ssd", name: "SSD", mountPoint: "/Volumes/SSD", isMounted: false, isExternalSSD: true, usedBytes: 0, availableBytes: 0, totalBytes: 0)
            )
        )
    }

    func captureTokenStatus() -> (usage: CLITokenUsageSnapshot, capturedAt: Date) {
        tokenStatusCallCount += 1
        return (CLITokenUsageSnapshot(items: []), Date(timeIntervalSince1970: 4_000))
    }
}
#endif
