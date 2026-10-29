#if os(macOS)
import Testing
import Foundation
import AppKit
import SwiftUI
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
        cpu: CPUStatusSnapshot(
            usage: 0.42,
            user: 0.25,
            system: 0.17,
            idle: 0.58,
            coreCount: 8,
            loadOneMinute: 1.1,
            loadFiveMinutes: 0.9,
            loadFifteenMinutes: 0.7
        ),
        memory: MemoryStatusSnapshot(
            usedBytes: 18 * 1_073_741_824,
            totalBytes: 24 * 1_073_741_824,
            freeBytes: 6 * 1_073_741_824,
            wiredBytes: 4 * 1_073_741_824,
            compressedBytes: 2 * 1_073_741_824,
            pressure: .normal
        ),
        storage: StorageStatusSnapshot(systemVolume: root, ssdVolume: ssd),
        tokenUsage: CLITokenUsageSnapshot(items: [
            CLITokenUsageItem(cli: .claude, inputTokens: 1_250_000, outputTokens: 350_000, cacheTokens: 2_400_000, isAvailable: true),
            CLITokenUsageItem(cli: .codex, inputTokens: 840_000, outputTokens: 160_000, cacheTokens: 500_000, isAvailable: true),
            CLITokenUsageItem(cli: .copilot, inputTokens: 620_000, outputTokens: 95_000, cacheTokens: 310_000, isAvailable: true)
        ])
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
            let suffix = isDark ? "dark" : "light"
            try data.write(to: outputDirectory.appendingPathComponent("\(name)-\(suffix).png"))
            if !isDark {
                renderedData[name] = data
            } else {
                #expect(renderedData[name] != data)
            }
        }
    }
}
#endif
