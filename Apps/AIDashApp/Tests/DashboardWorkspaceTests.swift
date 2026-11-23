#if os(macOS)
import AppKit
import CryptoKit
import Foundation
import SQLite3
import SwiftUI
import Testing
import DesignKit
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@MainActor
@Suite("Clean-Slate macOS Dashboard Workspace & Modular Cards")
struct DashboardWorkspaceTests {
    private func sampleSnapshot() -> MenuBarSystemSnapshot {
        let root = StorageVolumeSnapshot(
            id: "root",
            name: "Macintosh HD",
            mountPoint: "/",
            isMounted: true,
            isExternalSSD: false,
            usedBytes: 220 * 1_000_000_000,
            availableBytes: 280 * 1_000_000_000,
            totalBytes: 500 * 1_000_000_000
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
        return MenuBarSystemSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_762_000_000),
            machine: MachineStatusSnapshot(
                chipName: "Apple M4 Max",
                modelIdentifier: "Mac16,5",
                totalCores: 16,
                performanceCores: 12,
                uptimeSeconds: 86_400,
                thermalState: .nominal,
                efficiencyCores: 4,
                powerSummary: "AC"
            ),
            cpu: CPUStatusSnapshot(
                usage: 0.34,
                user: 0.22,
                system: 0.12,
                idle: 0.66,
                coreCount: 16,
                loadOneMinute: 4.2,
                loadFiveMinutes: 3.8,
                loadFifteenMinutes: 3.1
            ),
            memory: MemoryStatusSnapshot(
                usedBytes: 18 * 1_073_741_824,
                totalBytes: 32 * 1_073_741_824,
                freeBytes: 14 * 1_073_741_824,
                wiredBytes: 4 * 1_073_741_824,
                compressedBytes: 2 * 1_073_741_824,
                pressure: .normal
            ),
            storage: StorageStatusSnapshot(systemVolume: root, ssdVolume: ssd),
            tokenUsage: CLITokenUsageSnapshot(
                items: [
                    CLITokenUsageItem(
                        cli: .claude,
                        inputTokens: 420_000,
                        outputTokens: 180_000,
                        cacheTokens: 3_200_000,
                        isAvailable: true,
                        interactionCount: 310
                    ),
                    CLITokenUsageItem(
                        cli: .codex,
                        inputTokens: 910_000,
                        outputTokens: 240_000,
                        cacheTokens: 1_100_000,
                        isAvailable: true,
                        interactionCount: 520
                    ),
                    CLITokenUsageItem(
                        cli: .copilot,
                        inputTokens: 650_000,
                        outputTokens: 150_000,
                        cacheTokens: 4_500_000,
                        isAvailable: true,
                        interactionCount: 640
                    )
                ],
                claudeWeeklyRemainingPercent: 18
            ),
            attention: AttentionStatusSnapshot(
                needsPersonCount: 1,
                activeGoalCount: 2,
                items: [
                    AttentionStatusItem(
                        id: "goal-1",
                        title: "Approve Clean-Slate macOS dashboard rollout",
                        category: "Claude Code",
                        waitingOn: "Owner"
                    )
                ]
            )
        )
    }

    private func toolbarSnapshot(
        cpuUsage: Double,
        memoryUsedBytes: UInt64,
        memoryTotalBytes: UInt64,
        pressure: MemoryPressureLevel
    ) -> MenuBarSystemSnapshot {
        let base = sampleSnapshot()
        let cpu = CPUStatusSnapshot(
            usage: cpuUsage,
            user: cpuUsage * 0.6,
            system: cpuUsage * 0.4,
            idle: max(0, 1 - cpuUsage),
            coreCount: base.cpu.coreCount,
            loadOneMinute: 12.4,
            loadFiveMinutes: 10.1,
            loadFifteenMinutes: 8.7
        )
        let memory = MemoryStatusSnapshot(
            usedBytes: memoryUsedBytes,
            totalBytes: memoryTotalBytes,
            freeBytes: memoryTotalBytes - memoryUsedBytes,
            wiredBytes: 8 * 1_073_741_824,
            compressedBytes: 4 * 1_073_741_824,
            pressure: pressure
        )
        return MenuBarSystemSnapshot(
            capturedAt: base.capturedAt,
            machine: base.machine,
            cpu: cpu,
            memory: memory,
            network: base.network,
            storage: base.storage,
            tokenUsage: base.tokenUsage,
            attention: base.attention,
            gateway: base.gateway
        )
    }

    @Test("five canonical modular card descriptors and Codable round-trip are complete")
    func fiveModularCardSchemasRoundTrip() throws {
        #expect(ModularCardKind.allCases.map(\.rawValue) == [
            "kpi_summary",
            "trend_chart",
            "cli_cost_quota",
            "action_items",
            "ranking_table"
        ])
        let store = DashboardWorkspaceStore(snapshot: sampleSnapshot())
        #expect(store.modularDescriptors.count == 5)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let kpiData = try encoder.encode(store.effectiveKPIMetrics)
        let decodedKPIs = try decoder.decode([KPIMetricItem].self, from: kpiData)
        #expect(decodedKPIs == store.effectiveKPIMetrics)

        let cliData = try encoder.encode(store.cliEntries)
        let decodedCLIs = try decoder.decode([CLICostQuotaEntry].self, from: cliData)
        #expect(decodedCLIs == store.cliEntries)
    }

    @Test("IP-001 chart cross-filtering filters rankings, actions, and KPIs with tap-again reset")
    func chartCrossFilteringAndReset() {
        let store = DashboardWorkspaceStore(snapshot: sampleSnapshot())
        let fullCount = store.filteredRankingRows.count
        #expect(fullCount == 4)

        store.toggleChartCategory("Claude Code")
        #expect(store.selectedChartCategory == "Claude Code")
        #expect(store.filteredRankingRows.count == 1)
        #expect(store.filteredRankingRows.first?.providerName == "Claude Code")
        #expect(store.effectiveKPIMetrics.first?.deltaText.contains("Claude Code") == true)

        store.toggleChartCategory("Claude Code")
        #expect(store.selectedChartCategory == nil)
        #expect(store.filteredRankingRows.count == fullCount)
    }

    @Test("IP-002 orthogonal filter and sort preserves active CLI and chart filters")
    func orthogonalFilterAndSortPreservesContext() {
        let store = DashboardWorkspaceStore(snapshot: sampleSnapshot())
        store.selectedCLI = .claude
        store.actionFilter = .pending

        store.actionSort = .title
        #expect(store.selectedCLI == .claude)
        #expect(store.actionFilter == .pending)

        store.rankingAscending = true
        #expect(store.selectedCLI == .claude)
        let ascRuns = store.filteredRankingRows.map(\.runs)
        #expect(ascRuns == ascRuns.sorted())
    }

    @Test("IP-003 master-detail table selection updates detail in-place without reordering rows")
    func masterDetailSelectionPreservesRowOrder() {
        let store = DashboardWorkspaceStore(snapshot: sampleSnapshot())
        let initialOrder = store.filteredRankingRows.map(\.id)
        let targetID = initialOrder.last
        store.selectedRankingRowID = targetID

        #expect(store.selectedRankingRow?.id == targetID)
        #expect(store.filteredRankingRows.map(\.id) == initialOrder)
    }

    @Test("IP-004 scoped empty recovery clears narrow sub-filter while preserving CLI and section")
    func scopedEmptyRecoveryPreservesOuterContext() {
        let store = DashboardWorkspaceStore(snapshot: sampleSnapshot())
        store.selectedSection = .actionItems
        store.selectedCLI = .codex
        store.selectedChartCategory = "Claude Code"
        #expect(store.filteredActionItems.isEmpty)
        #expect(store.hasScopedSubFilter)

        store.clearScopedFilterOnly()
        #expect(store.selectedChartCategory == nil)
        #expect(store.selectedCLI == .codex)
        #expect(store.selectedSection == .actionItems)
    }

    @Test("IP-005 toggling action item synchronously recomputes summary counts and forwards event")
    func statusToSummaryAggregationAndEventForwarding() throws {
        var actions = [DashboardActionItem(
            id: "act-1",
            title: "Verify Codex quota alert",
            summary: "Quota at 82%",
            sourceTag: "Codex CLI",
            cliFilter: .codex,
            priority: .p0,
            isCompleted: false,
            command: "aidash schema list --quiet",
            backingCardId: "todo-card-1",
            backingItemRef: "title:verify-codex"
        )]
        actions.append(DashboardActionItem(
            id: "act-2",
            title: "Review daily digest",
            summary: "Routine check",
            sourceTag: "Claude Code",
            cliFilter: .claude,
            priority: .p2,
            isCompleted: false
        ))

        let store = DashboardWorkspaceStore(snapshot: sampleSnapshot(), actionItems: actions)
        #expect(store.pendingActionCount == 2)
        #expect(store.completedActionCount == 0)
        #expect(store.p0PendingCount == 1)

        var forwarded: (String, String, Bool)?
        store.toggleActionItem(id: "act-1") { cardId, ref, isDone in
            forwarded = (cardId, ref, isDone)
        }

        #expect(store.pendingActionCount == 1)
        #expect(store.completedActionCount == 1)
        #expect(store.p0PendingCount == 0)
        #expect(store.effectiveKPIMetrics.first(where: { $0.id == "kpi-actions" })?.formattedValue == "1")
        let event = try #require(forwarded)
        #expect(event.0 == "todo-card-1")
        #expect(event.1 == "title:verify-codex")
        #expect(event.2 == true)
    }

    @Test("Kanban source keeps completed cards visible under pending filter and honors job filters")
    func kanbanActionItemsIncludeDoneAndFilterByJob() {
        let actions = [
            DashboardActionItem(
                id: "eval-done",
                title: "Done eval rule",
                summary: "Already recorded",
                sourceTag: "Linear",
                priority: .p1,
                status: .done,
                isCompleted: true,
                jobID: .myPRSupervisor,
                labels: ["eval"]
            ),
            DashboardActionItem(
                id: "eval-triage",
                title: "Pending eval rule",
                summary: "Needs review",
                sourceTag: "Linear",
                priority: .p1,
                status: .triage,
                jobID: .myPRSupervisor,
                labels: ["eval"]
            ),
            DashboardActionItem(
                id: "other-job",
                title: "Other job item",
                summary: "Should be scoped out",
                sourceTag: "Linear",
                priority: .p1,
                status: .blocked,
                jobID: .aidataDigest,
                labels: ["bug-blocker"]
            )
        ]
        let store = DashboardWorkspaceStore(snapshot: sampleSnapshot(), actionItems: actions)
        store.actionFilter = .pending
        store.selectedLinearActionFilter = "eval"
        #expect(store.kanbanActionItems.map(\.id) == ["eval-triage", "eval-done"])
        store.selectedFrameworkJobID = .aidataDigest
        #expect(store.kanbanActionItems.map(\.id) == [])
    }

    @Test("eval decision line merge replaces every duplicate id with one latest record")
    func evalDecisionLinesAreIdempotentByID() throws {
        let replacement = try JSONSerialization.data(withJSONObject: [
            "id": "EVAL-1", "decision": "忽略", "note": "latest"
        ], options: [.sortedKeys])
        let existing = "{\"id\":\"EVAL-1\",\"decision\":\"旧\"}\n{\"id\":\"other\",\"decision\":\"保留\"}\n{\"id\":\"EVAL-1\",\"decision\":\"重复\"}\n"
        let merged = DashboardWorkspaceStore.replacingEvalDecisionLines(
            existing: existing,
            replacement: replacement,
            itemID: "EVAL-1"
        )
        let lines = merged.split(whereSeparator: \.isNewline)
        #expect(lines.count == 2)
        #expect(lines.filter { $0.contains("EVAL-1") }.count == 1)
        #expect(merged.contains("latest"))
        #expect(merged.contains("other"))
    }

    @Test("modular card views and workspace view construct bodies across all sections")
    func modularViewsRenderSmokeTest() {
        let snapshot = sampleSnapshot()
        let store = DashboardWorkspaceStore(snapshot: snapshot)
        for section in DashboardWorkspaceSection.allCases {
            store.selectedSection = section
            _ = AIDashMacWorkspaceView(store: store).body
        }
        _ = SystemTelemetryStripView(snapshot: snapshot).body
        _ = KPISummaryCardView(metrics: store.effectiveKPIMetrics).body
        _ = TrendChartCardView(
            points: store.filteredTrendPoints,
            selectedCategory: store.selectedChartCategory,
            onSelectCategory: { _ in },
            onClearSelection: {}
        ).body
        _ = CLICostQuotaCardView(
            entries: store.filteredCLIEntries,
            todayTotalUSD: store.todayTotalCostUSD,
            periodTotalUSD: store.periodTotalCostUSD
        ).body
        _ = ActionItemsCardView(store: store).body
        _ = RankingTableCardView(store: store).body
    }

    private func toolbarHeaderBitmap<Content: View>(
        for content: Content,
        scheme: ColorScheme
    ) throws -> NSBitmapImageRep {
        // Borderless buttons are AppKit-backed; ImageRenderer substitutes unsupported-view panels.
        _ = NSApplication.shared
        let appearance = try #require(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua))
        let hostingView = NSHostingView(rootView: content)
        hostingView.appearance = appearance
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView
        defer {
            window.contentView = nil
            window.close()
        }
        let fittingSize = hostingView.fittingSize
        #expect(fittingSize.width.isFinite && fittingSize.width > 0)
        #expect(fittingSize.height.isFinite && fittingSize.height > 0)
        window.setContentSize(fittingSize)
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        appearance.performAsCurrentDrawingAppearance {
            hostingView.displayIfNeeded()
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        }
        return bitmap
    }

    private func containsUnsupportedViewPlaceholder(_ bitmap: NSBitmapImageRep) -> Bool {
        for y in 0..<bitmap.pixelsHigh {
            var yellowRun = 0
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let isPlaceholderYellow = color.alphaComponent > 0.99
                    && color.redComponent > 0.99
                    && abs(color.greenComponent - 0.8) < 0.01
                    && color.blueComponent < 0.01
                yellowRun = isPlaceholderYellow ? yellowRun + 1 : 0
                if yellowRun >= 8 { return true }
            }
        }
        return false
    }

    @Test("Top toolbar header clusters are single-layer without nested capsule backgrounds or bordered bezels")
    func topToolbarHeaderClustersAreSingleLayerAndRenderSnapshots() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Scenes/AIDashMacWorkspaceView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let clusterStart = try #require(source.range(of: "internal func rightToolbarCluster(snapshot:"))
        let clusterEnd = try #require(source.range(of: "    private var sidebarContent", range: clusterStart.upperBound..<source.endIndex))
        let toolbarSource = String(source[clusterStart.lowerBound..<clusterEnd.lowerBound])
        #expect(!toolbarSource.contains(".background("))
        #expect(!toolbarSource.contains("Capsule()"))
        #expect(!toolbarSource.contains(".overlay("))
        #expect(!toolbarSource.contains(".shadow("))
        #expect(!toolbarSource.contains(".buttonStyle(.bordered)"))
        #expect(!toolbarSource.contains(".buttonStyle(.plain)"))
        #expect(toolbarSource.contains(".buttonStyle(.borderless)"))
        #expect(toolbarSource.contains("toolbar.hardwareCompanion"))
        #expect(toolbarSource.contains("Divider()"))
        #expect(toolbarSource.contains(".padding(.horizontal, 6)"))

        let environment = ProcessInfo.processInfo.environment
        let configuredPath: String? = [
            environment["AIDASH_HEADER_SCREENSHOT_DIR"],
            environment["TEST_RUNNER_AIDASH_HEADER_SCREENSHOT_DIR"]
        ].compactMap { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }.first
        let ownsOutput = configuredPath == nil
        let output = configuredPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("aidash-header-flat-toolbar-\(UUID().uuidString)", isDirectory: true)
        defer {
            if ownsOutput { try? FileManager.default.removeItem(at: output) }
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let selectedDate = DashboardWorkspaceStore.todayDateString()
        let states: [(name: String, snapshot: MenuBarSystemSnapshot?, date: String, cpu: String, memory: String)] = [
            ("populated", sampleSnapshot(), selectedDate, "34%", "18.0 / 32.0 GB"),
            ("no-snapshot", nil, selectedDate, "n/a", "n/a"),
            ("high-values", toolbarSnapshot(cpuUsage: 0.98, memoryUsedBytes: 62 * 1_073_741_824, memoryTotalBytes: 64 * 1_073_741_824, pressure: .warning), selectedDate, "98%", "62.0 / 64.0 GB"),
            ("long-localized-copy", sampleSnapshot(), "2026-11-11 · 周三 · 早间简报", "34%", "18.0 / 32.0 GB")
        ]
        var geometry: [[String: Any]] = []
        var hashes: [String: String] = [:]
        var pixelHashes: [String: String] = [:]
        for state in states {
            let store: DashboardWorkspaceStore
            if let snapshot = state.snapshot {
                store = DashboardWorkspaceStore(snapshot: snapshot)
            } else {
                store = DashboardWorkspaceStore(deferInitialRefresh: true)
            }
            store.availableDates = [state.date]
            store.selectedDateString = state.date
            let view = AIDashMacWorkspaceView(store: store)
            for scheme in [ColorScheme.light, ColorScheme.dark] {
                let appearance = scheme == .dark ? "dark" : "light"
                let standalone = view.toolbarHeaderComparisonPreview(snapshot: state.snapshot)
                    .padding(12)
                    .environment(\.colorScheme, scheme)
                    .environment(\.theme, Theme(isDark: scheme == .dark))
                let platters = HStack(spacing: 12) {
                    view.unifiedDateNavigationToolbarCluster
                        .padding(12)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7), in: Capsule())
                    view.rightToolbarCluster(snapshot: state.snapshot)
                        .padding(12)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7), in: Capsule())
                }
                .padding(12)
                .background(Color(nsColor: .underPageBackgroundColor))
                .environment(\.colorScheme, scheme)
                .environment(\.theme, Theme(isDark: scheme == .dark))
                for (kind, renderable) in [("standalone", AnyView(standalone)), ("two-platter-simulation", AnyView(platters))] {
                    let bitmap = try toolbarHeaderBitmap(for: renderable, scheme: scheme)
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    let image = try #require(bitmap.cgImage)
                    let pixelData = try #require(image.dataProvider?.data) as Data
                    let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
                    let pixelDigest = SHA256.hash(data: pixelData).map { String(format: "%02x", $0) }.joined()
                    let key = "\(state.name)-\(kind)-\(appearance)"
                    hashes[key] = digest
                    pixelHashes[key] = pixelDigest
                    let file = output.appendingPathComponent("toolbar-header-\(key).png")
                    try png.write(to: file)
                    #expect(png.isEmpty == false)
                    #expect(bitmap.pixelsWide > 0)
                    #expect(bitmap.pixelsHigh > 0)
                    #expect(!containsUnsupportedViewPlaceholder(bitmap), "Unsupported-view yellow panel in \(key)")
                    geometry.append(["state": state.name, "kind": kind, "appearance": appearance, "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh, "cpu": state.cpu, "memory": state.memory, "date": state.date, "sha256": digest, "pixelSHA256": pixelDigest])
                }
            }
        }
        let populatedDarkPixels = try #require(pixelHashes["populated-standalone-dark"])
        let highValuesDarkPixels = try #require(pixelHashes["high-values-standalone-dark"])
        #expect(populatedDarkPixels != highValuesDarkPixels)
        #expect(hashes["populated-standalone-dark"] != hashes["high-values-standalone-dark"])
        #expect(hashes["populated-standalone-light"] != hashes["high-values-standalone-light"])
        #expect(hashes["populated-standalone-light"] != hashes["long-localized-copy-standalone-light"])
        #expect(hashes["populated-two-platter-simulation-dark"] != hashes["high-values-two-platter-simulation-dark"])
        #expect(hashes["populated-two-platter-simulation-dark"] != hashes["long-localized-copy-two-platter-simulation-dark"])
        let geometryData = try JSONSerialization.data(withJSONObject: ["platform": "desktop", "children": geometry], options: [.prettyPrinted, .sortedKeys])
        try geometryData.write(to: output.appendingPathComponent("toolbar-header-geometry.json"))
    }

    @Test("shared workspace store initializes without dispatch_once re-entrancy trap")
    func sharedWorkspaceStoreIsReentrantSafe() {
        let shared = DashboardWorkspaceStore.shared
        #expect(shared === DashboardWorkspaceStore.shared)
        _ = AIDashMacWorkspaceView().body
    }

    @Test("Localizable.xcstrings provides complete en and zh-Hans translations for all dashboard and menubar keys")
    func xcstringsCatalogHasCompleteEnglishAndSimplifiedChineseTranslations() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: [String: Any]])
        #expect(strings.count >= 100)

        for (key, entry) in strings {
            let localizations = try #require(entry["localizations"] as? [String: [String: Any]], "Missing localizations for \(key)")
            for locale in ["en", "zh-Hans"] {
                let localeObj = try #require(localizations[locale], "Missing \(locale) translation for \(key)")
                let unit = try #require(localeObj["stringUnit"] as? [String: Any], "Missing stringUnit for \(key) [\(locale)]")
                let value = try #require(unit["value"] as? String, "Missing value for \(key) [\(locale)]")
                #expect(!value.isEmpty, "Empty \(locale) translation for \(key)")
                #expect(value != key, "Raw key leaked as translation for \(key) [\(locale)]")
            }
        }
    }

    @Test("LiveDashboardTelemetryReader parses real magpie quotas.json windows without fake caps")
    func liveTelemetryReaderParsesRealQuotas() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-quota-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let magpieURL = tempDir.appendingPathComponent("quotas.json")
        let payload = """
        {
          "claude/user@example.com": {
            "quota": {
              "provider": "claude",
              "windows": [
                {"name": "5 hours", "used": 12.5},
                {"name": "7 days", "used": 8.0}
              ]
            }
          },
          "cursor/user@example.com": {
            "quota": {
              "provider": "cursor",
              "windows": [
                {"name": "Weekly", "used": 27.67}
              ]
            }
          }
        }
        """
        try payload.write(to: magpieURL, atomically: true, encoding: .utf8)

        let parsed = LiveDashboardTelemetryReader.readQuotas(
            magpieQuotasURL: magpieURL,
            claudeFallbackURL: tempDir.appendingPathComponent("missing.json"),
            fallbackUsage: CLITokenUsageSnapshot(items: [])
        )
        #expect(abs((parsed.claudeSevenDayUsedFraction ?? -1) - 0.08) < 0.0001)
        #expect(abs((parsed.claudeFiveHourUsedFraction ?? -1) - 0.125) < 0.0001)
        #expect(abs((parsed.cursorWeeklyUsedFraction ?? -1) - 0.2767) < 0.0001)
        #expect(DashboardTokenFormatter.compact(4_980_000) == "5.0M")
        let store = DashboardWorkspaceStore(snapshot: sampleSnapshot())
        #expect(store.todayGrandTotalTokens > 0)
        #expect(store.periodGrandTotalTokens >= store.todayGrandTotalTokens)
        #expect(store.filteredTrendPoints.contains { $0.totalTokens > 0 })
        #expect(!store.actionItems.contains(where: { $0.id.hasPrefix("quota-") }))
        let pool = QuotaPoolSummary.summarize(entries: store.cliEntries)
        #expect(pool.trackedCount >= 2)
        #expect(pool.recommendedEntry != nil)
        #expect(LiveDashboardTelemetryReader.sanitizeSQLToken("2026-11-07") == "2026-11-07")
        store.openDashboardWindow(section: .actionItems)
        #expect(store.selectedSection == .actionItems)
        #expect(!store.actionItems.contains(where: { $0.id == "sys-memory-pressure" }))
        for item in store.actionItems {
            store.toggleActionItem(id: item.id)
        }
        #expect(store.pendingActionCount == 0)
        #expect(store.completedActionCount >= 1)
        #expect(store.cliEntries.contains(where: { $0.cliFilter == .kimi }))
        if let firstPoint = store.trendPoints.first {
            #expect(firstPoint.tokens(for: .all) == firstPoint.totalTokens)
            #expect(firstPoint.tokens(for: .input) + firstPoint.tokens(for: .output) + firstPoint.tokens(for: .cache) == firstPoint.totalTokens)
        }
        let hourlySample = [
            TrendDataPoint(
                id: "h1", bucketLabel: "2026-11-08 10:00", category: "Codex CLI",
                cliFilter: .codex, invocations: 10, successRate: 1.0, costUSD: 0,
                totalTokens: 1_000_000, inputTokens: 200_000, outputTokens: 100_000,
                cacheTokens: 700_000, bucketDate: Date(timeIntervalSince1970: 1_762_567_200)
            ),
            TrendDataPoint(
                id: "h2", bucketLabel: "2026-11-08 11:00", category: "Codex CLI",
                cliFilter: .codex, invocations: 5, successRate: 1.0, costUSD: 0,
                totalTokens: 500_000, inputTokens: 100_000, outputTokens: 50_000,
                cacheTokens: 350_000, bucketDate: Date(timeIntervalSince1970: 1_762_570_800)
            )
        ]
        #expect(TrendDataPoint.points(from: hourlySample, granularity: .threeDayHourly).count == 2)
        #expect(TrendDataPoint.points(from: hourlySample, granularity: .sevenDayDaily).first?.totalTokens == 1_500_000)
        #expect(TrendDataPoint.dailyKindBarSegments(from: hourlySample).count == 3)
        let dailyHover = try #require(TrendDataPoint.hoverSummary(forBucket: "11-08", in: hourlySample, granularity: .sevenDayDaily))
        #expect(dailyHover.totalTokens == 1_500_000)
        #expect(dailyHover.inputTokens == 300_000)
        #expect(dailyHover.outputTokens == 150_000)
        #expect(dailyHover.cacheTokens == 1_050_000)
        #expect(dailyHover.invocations == 15)
        #expect(dailyHover.formattedReadout.contains("1.5M"))
        let nearestBucket = TrendDataPoint.nearestHourlyBucketLabel(
            to: Date(timeIntervalSince1970: 1_762_567_500),
            in: hourlySample
        )
        #expect(nearestBucket == "2026-11-08 10:00")
        let hourlyHover = try #require(TrendDataPoint.hoverSummary(forBucket: "2026-11-08 10:00", in: hourlySample, granularity: .threeDayHourly))
        #expect(hourlyHover.totalTokens == 1_000_000)
        #expect(hourlyHover.inputTokens == 200_000)
        #expect(hourlyHover.outputTokens == 100_000)
        #expect(hourlyHover.cacheTokens == 700_000)
        #expect(hourlyHover.cliShares.first?.cli == .codex)

        let snap = sampleSnapshot()
        let prefs = MenuBarDisplayPreferences(persistToDefaults: false)
        #expect(prefs.badgeMetric == .todayTokens)
        #expect(MenuBarBadgeMetric.todayTokens.formattedStatusBarTitle(snapshot: snap, entries: store.cliEntries).contains("tok"))
        #expect(MenuBarBadgeMetric.sevenDayTokens.formattedStatusBarTitle(snapshot: snap, entries: store.cliEntries).contains("7d"))
        #expect(MenuBarBadgeMetric.cpu.formattedStatusBarTitle(snapshot: snap, entries: store.cliEntries) == " CPU 34%")
        #expect(MenuBarBadgeMetric.memory.formattedStatusBarTitle(snapshot: snap, entries: store.cliEntries) == " Mem 18/32G")
        #expect(MenuBarBadgeMetric.storage.formattedStatusBarTitle(snapshot: snap, entries: store.cliEntries).contains("Disk"))
        #expect(MenuBarBadgeMetric.cpuAndMemory.formattedStatusBarTitle(snapshot: snap, entries: store.cliEntries) == " CPU 34% · 18/32G")
        prefs.defaultChartGranularity = .threeDayHourly
        #expect(prefs.defaultChartGranularity == .threeDayHourly)
        #expect(store.cliEntries.filter(\.hasTrackedQuota).count == 3)
        let ravenDB = tempDir.appendingPathComponent("raven.db")
        let todayStr = DashboardWorkspaceStore.todayDateString()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var db: OpaquePointer?
        #expect(sqlite3_open(ravenDB.path, &db) == SQLITE_OK)
        if let db {
            let sql = """
            CREATE TABLE requests (timestamp INTEGER, client_name TEXT, model TEXT, resolved_model TEXT, input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER, cache_write_tokens INTEGER, latency_ms REAL, status_code INTEGER);
            INSERT INTO requests VALUES (\(nowMs), 'codex_cli_rs/0.167.0', 'gpt-5.6-luna', 'gpt-5.6-luna', 1000, 500, 2000, 0, 4200, 200);
            INSERT INTO requests VALUES (\(nowMs), 'codex_cli_rs/0.167.0', 'gpt-5.6-luna', '', 0, 0, 0, 0, 1200, 500);
            INSERT INTO requests VALUES (\(nowMs), 'codex_exec/0.167.0', 'gpt-5.6-luna', 'gpt-5.6-luna', 2000, 800, 1000, 0, 3100, 200);
            """
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
            sqlite3_close(db)
        }
        let ranked = LiveDashboardTelemetryReader.queryRealRankings(
            ravenURL: ravenDB,
            copilotURL: tempDir.appendingPathComponent("missing-copilot.db"),
            dateString: todayStr,
            fallbackEntries: store.cliEntries
        )
        let rustCodexRow = try #require(ranked.first(where: { $0.agentName.contains("M2 · Dispatcher (Codex)") }))
        #expect(rustCodexRow.modelName == "gpt-5.6-luna")
        #expect(rustCodexRow.runs == 2)
        #expect(rustCodexRow.totalTokens == 3500)
        #expect(abs(rustCodexRow.successRate - 0.5) < 0.001)
        let execCodexRow = try #require(ranked.first(where: { $0.agentName.contains("M1 · Writer (codex_exec)") }))
        #expect(execCodexRow.modelName == "gpt-5.6-luna")
        #expect(execCodexRow.runs == 1)
        #expect(execCodexRow.totalTokens == 3800)

        let cindyDB = tempDir.appendingPathComponent("cindy-test.db")
        var cdb: OpaquePointer?
        #expect(sqlite3_open(cindyDB.path, &cdb) == SQLITE_OK)
        if let cdb {
            let csql = """
            CREATE TABLE sessions (id TEXT, title TEXT, model TEXT, agent_kind TEXT, source TEXT);
            CREATE TABLE daily_session_usage (day TEXT, session_id TEXT, tokens INTEGER);
            CREATE TABLE messages (session_id TEXT, role TEXT);
            INSERT INTO sessions VALUES ('s1', 'CindyChat', 'gemini-4-argon', 'pi', 'desktop');
            INSERT INTO sessions VALUES ('s2', 'mimo', 'gpt-6.1-sol', 'codex', 'bot');
            INSERT INTO daily_session_usage VALUES ('\(todayStr)', 's1', 1600000);
            INSERT INTO daily_session_usage VALUES ('\(todayStr)', 's2', 22000);
            INSERT INTO messages VALUES ('s1', 'assistant');
            INSERT INTO messages VALUES ('s1', 'assistant');
            """
            #expect(sqlite3_exec(cdb, csql, nil, nil, nil) == SQLITE_OK)
            sqlite3_close(cdb)
        }
        var cindyRows: [AgentRankingRow] = []
        LiveDashboardTelemetryReader.appendCindyRankingRows(&cindyRows, cindyDirURL: tempDir, safeDate: todayStr)
        #expect(cindyRows.contains(where: { $0.agentName == "M2 · Cindy Desktop" && $0.modelName == "gemini-4-argon" }))
        #expect(cindyRows.contains(where: { $0.agentName == "M2 · Cindy Bot (mimo)" && $0.modelName == "gpt-6.1-sol" }))
        #expect(OverviewWorkbenchLens.allCases == [.trends, .rankings, .skills])
        #expect(!OverviewWorkbenchLens.trends.title.isEmpty)
        #expect(OverviewWorkbenchLens.rankings.symbolName == "tablecells")
        _ = DashboardSettingsPageView(store: store, prefs: prefs).body
        let proposalsURL = tempDir.appendingPathComponent("proposals.jsonl")
        let proposalsSample = """
        {"id":"p1","ts":"2026-11-08T00:00:00Z","agent":"retro-loop","title":"Shrink Review Ping-Pong","detail":"R1 fail 55%","priority":"high","status":"pending"}
        {"id":"p2","ts":"2026-11-08T00:00:00Z","agent":"retro-loop","title":"Old item","status":"dismissed"}
        """
        try proposalsSample.write(to: proposalsURL, atomically: true, encoding: .utf8)
        let parsedProposals = LiveDashboardTelemetryReader.parsePendingProposals(fromURL: proposalsURL)
        #expect(parsedProposals.count == 1)
        #expect(parsedProposals.first?.id == "proposal-p1")
        #expect(parsedProposals.first?.priority == .p0)
        _ = MenuBarStatusView(state: .populated(sampleSnapshot())).body
        _ = ActionItemsCardView(store: store).body
    }

    @Test("6-CLI auto-detection omits uninstalled DeepSeek and computes accurate auth/quota states for Kimi, Claude, and Grok")
    func sixCLIAutoDetectionAndAuthErrorStates() throws {
        #expect(AgentCLIKind.allCases == [.claude, .codex, .copilot, .kimi, .grok, .deepseek])
        #expect(DashboardCLIFilter.allCases == [.all, .claude, .codex, .copilot, .kimi, .grok, .deepseek])

        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-6cli-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)

        let now = Date(timeIntervalSince1970: 1_794_208_800)
        try FileManager.default.createDirectory(at: tempHome.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempHome.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        try Data("model = \"gpt-5\"\n".utf8).write(to: tempHome.appendingPathComponent(".codex/config.toml"))
        try FileManager.default.createDirectory(at: tempHome.appendingPathComponent(".copilot"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: tempHome.appendingPathComponent(".copilot/config.json"))
        try FileManager.default.createDirectory(at: tempHome.appendingPathComponent(".kimi-code/credentials"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempHome.appendingPathComponent(".grok/sessions/s1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempHome.appendingPathComponent(".config/magpie"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempHome.appendingPathComponent(".config/claude"), withIntermediateDirectories: true)

        #expect(LiveDashboardTelemetryReader.isCLIInstalled(.claude, homeURL: tempHome, includeSystemBinaries: false))
        #expect(LiveDashboardTelemetryReader.isCLIInstalled(.codex, homeURL: tempHome, includeSystemBinaries: false))
        #expect(LiveDashboardTelemetryReader.isCLIInstalled(.copilot, homeURL: tempHome, includeSystemBinaries: false))
        #expect(!LiveDashboardTelemetryReader.isCLIInstalled(.deepseek, homeURL: tempHome, includeSystemBinaries: false))

        let staleClaudeFallback = tempHome.appendingPathComponent(".config/claude/gtt-weekly-remaining-pct.json")
        try Data("{\"weekly_remaining_pct\":91,\"used_percentage\":9,\"measured_at\":\(now.timeIntervalSince1970 - 200_000)}".utf8)
            .write(to: staleClaudeFallback)

        let quotasURL = tempHome.appendingPathComponent(".config/magpie/quotas.json")
        let quotasJSON = """
        {
          "claude/user@example.com": {
            "at": "2026-11-05T00:00:00Z",
            "quota": {
              "provider": "claude",
              "readAt": "2026-11-05T00:00:00Z",
              "windows": [{"name": "7 days", "used": 9.0}]
            }
          },
          "cursor/user@example.com": {
            "at": "2026-11-09T07:00:00Z",
            "quota": {
              "provider": "cursor",
              "readAt": "2026-11-09T07:00:00Z",
              "windows": [{"name": "Weekly", "used": 28.0, "resetsAt": "2026-11-10T05:06:39.748Z"}]
            }
          },
          "grok/user@example.com": {
            "at": "2026-11-09T07:00:00Z",
            "quota": {
              "provider": "grok",
              "readAt": "2026-11-09T07:00:00Z",
              "windows": [{"name": "7 days", "used": 27.0, "resetsAt": "2026-11-10T05:06:39.748Z"}]
            }
          }
        }
        """
        try Data(quotasJSON.utf8).write(to: quotasURL)

        let expiredKimiCred = tempHome.appendingPathComponent(".kimi-code/credentials/kimi-code.json")
        try Data("{\"access_token\":\"tok\",\"expires_at\":\(Int(now.timeIntervalSince1970 - 7200))}".utf8)
            .write(to: expiredKimiCred)

        let grokAuthURL = tempHome.appendingPathComponent(".grok/auth.json")
        try Data("{\"https://auth.x.ai::client\":{\"expires_at\":\"2026-11-01T00:00:00Z\"}}".utf8)
            .write(to: grokAuthURL)

        let dataset = try #require(
            LiveDashboardTelemetryReader.loadDataset(
                forDate: "2026-11-09",
                homeURL: tempHome,
                fallbackUsage: CLITokenUsageSnapshot(items: []),
                includeSystemBinaries: false,
                now: now
            )
        )
        #expect(!dataset.entries.contains(where: { $0.cliFilter == .deepseek }))

        let claudeEntry = try #require(dataset.entries.first(where: { $0.cliFilter == .claude }))
        #expect(claudeEntry.authState == .notLoggedIn(loginCommand: "claude login"))
        #expect(claudeEntry.health == .warning)
        #expect(claudeEntry.authState.badgeTitle != nil)

        let kimiEntry = try #require(dataset.entries.first(where: { $0.cliFilter == .kimi }))
        #expect(kimiEntry.authState.isAuthError)
        #expect(kimiEntry.quotaLabel == nil)
        #expect(!kimiEntry.hasTrackedQuota)

        let grokEntry = try #require(dataset.entries.first(where: { $0.cliFilter == .grok }))
        #expect(grokEntry.authState.isAuthError)

        let pool = QuotaPoolSummary.summarize(entries: dataset.entries)
        #expect(pool.trackedCount == 1)
        #expect(pool.recommendedEntry?.cliFilter == .codex)

        try Data("{\"grok\":{\"expires\":\(Int((now.timeIntervalSince1970 + 3600) * 1000))}}".utf8)
            .write(to: tempHome.appendingPathComponent(".config/magpie/plugin-auth.json"))
        try Data("{\"access_token\":\"tok\",\"expires_at\":\(Int(now.timeIntervalSince1970 + 7200))}".utf8)
            .write(to: expiredKimiCred)
        let kimiUsagesPayload = """
        {
          "usage": {"limit":"100","used":"57","remaining":"43","resetTime":"2026-11-15T08:45:45.712409Z"},
          "usages": {
            "limit_5h": {"used_ratio": 0.0642, "reset_time": "2026-11-10T02:45:45Z"},
            "limit_7d": {"used_ratio": 0.5657, "reset_time": "2026-11-15T08:45:45Z"}
          }
        }
        """
        try Data(kimiUsagesPayload.utf8).write(to: tempHome.appendingPathComponent(".kimi-code/usages.json"))
        let refreshedDataset = try #require(
            LiveDashboardTelemetryReader.loadDataset(
                forDate: "2026-11-09",
                homeURL: tempHome,
                fallbackUsage: CLITokenUsageSnapshot(items: []),
                includeSystemBinaries: false,
                now: now
            )
        )
        let refreshedGrok = try #require(refreshedDataset.entries.first(where: { $0.cliFilter == .grok }))
        #expect(refreshedGrok.authState == .authenticated)
        #expect(abs((refreshedGrok.quotaUsedOverride ?? -1) - 0.27) < 0.0001)
        let refreshedKimi = try #require(refreshedDataset.entries.first(where: { $0.cliFilter == .kimi }))
        #expect(refreshedKimi.authState == .authenticated)
        #expect(refreshedKimi.hasTrackedQuota == true)
        #expect(refreshedKimi.quotaLabel != nil)
        #expect(abs((refreshedKimi.quotaUsedOverride ?? 0) - 0.5657) < 0.001)
        #expect(abs((refreshedKimi.secondaryQuotaUsed ?? 0) - 0.0642) < 0.001)
        #expect(refreshedKimi.secondaryQuotaLabel == "5h")
        #expect(refreshedKimi.quotaResetText == "Reset 11-15 08:45")
        #expect(refreshedKimi.health == .healthy)

        _ = CLICostQuotaCardView(entries: dataset.entries, todayTotalUSD: 0, periodTotalUSD: 0).body
    }

    @Test("one-click terminal login command validation, sidebar footer sections, and tail-read telemetry caching work as specified")
    func terminalLoginSidebarFooterAndTelemetryTailCache() throws {
        #expect(DashboardWorkspaceSection.primaryNavigationSections == [
            .overview,
            .agentEfficiency
        ])
        #expect(!DashboardWorkspaceSection.primaryNavigationSections.contains(.settings))
        #expect(DashboardWorkspaceSection.allCases.contains(.settings))

        #expect(CLIAuthState.authenticated.loginCommand == nil)
        #expect(CLIAuthState.quotaExhausted(reason: "429").loginCommand == nil)
        #expect(CLIAuthState.notLoggedIn(loginCommand: "claude login").loginCommand == "claude login")
        #expect(CLIAuthState.authExpired(reason: "expired", loginCommand: "kimi login").loginCommand == "kimi login")

        #expect(CLITerminalLoginLauncher.sanitizedLoginCommand("  claude   login ") == "claude login")
        #expect(CLITerminalLoginLauncher.sanitizedLoginCommand("KIMI LOGIN") == "kimi login")
        #expect(CLITerminalLoginLauncher.sanitizedLoginCommand("grok login") == "grok login")
        #expect(CLITerminalLoginLauncher.sanitizedLoginCommand("codex login") == "codex login")
        #expect(CLITerminalLoginLauncher.sanitizedLoginCommand("copilot login") == "copilot login")
        #expect(CLITerminalLoginLauncher.sanitizedLoginCommand("deepseek login") == "deepseek login")
        #expect(CLITerminalLoginLauncher.sanitizedLoginCommand("claude login; rm -rf /") == nil)
        #expect(CLITerminalLoginLauncher.sanitizedLoginCommand("curl http://evil") == nil)

        let legacyScriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("aidash-cli-login.command")
        try "legacy".write(to: legacyScriptURL, atomically: true, encoding: .utf8)
        #expect(FileManager.default.fileExists(atPath: legacyScriptURL.path))
        #expect(CLITerminalLoginLauncher.launchLoginInTerminal(command: "claude login") == true)
        #expect(CLITerminalLoginLauncher.launchLoginInTerminal(command: "invalid && bad") == false)
        #expect(!FileManager.default.fileExists(atPath: legacyScriptURL.path))

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-tail-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let usageDir = tempDir.appendingPathComponent(".config/magpie", isDirectory: true)
        try FileManager.default.createDirectory(at: usageDir, withIntermediateDirectories: true)
        let usageURL = usageDir.appendingPathComponent("usage.jsonl")
        var lines: [String] = []
        for idx in 0..<200 {
            lines.append("{\"t\":\"2026-11-09T10:00:00Z\",\"req\":\"group/steering\",\"served\":\"gpt-6.1-sol\",\"agent\":\"copilot\",\"in\":1000,\"out\":200,\"cache_read\":4000,\"status\":200,\"ms\":1200,\"ttft_ms\":\(300 + idx)}")
        }
        try (lines.joined(separator: "\n") + "\n").write(to: usageURL, atomically: true, encoding: .utf8)

        let tail = LiveDashboardTelemetryReader.readTailLines(of: usageURL, maxBytes: 1024)
        #expect(!tail.isEmpty)
        #expect(tail.utf8.count <= 1024)
        #expect(!tail.hasPrefix(",\"req\":"))

        let eff1 = try #require(LiveDashboardTelemetryReader.loadLiveEfficiencySummary(homeURL: tempDir))
        let eff2 = try #require(LiveDashboardTelemetryReader.loadLiveEfficiencySummary(homeURL: tempDir))
        #expect(eff1 == eff2)
        #expect(eff1.cacheHitRate > 0.7)
        #expect(eff1.steeringTokenShare > 0.9)
        #expect(eff1.p90TTFTSeconds > 0.4)

        let iCloudHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-icloud-freshness-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: iCloudHome) }
        #expect(LiveDashboardTelemetryReader.iCloudSyncRootURL(homeURL: iCloudHome).path.hasSuffix("/.aidash/icloud-mirror"))
        #expect(!LiveDashboardTelemetryReader.iCloudSyncRootURL(homeURL: iCloudHome).path.contains("Mobile Documents/com~apple~CloudDocs"))

        let localJobs = iCloudHome.appendingPathComponent("Library/Application Support/AIDash/jobs/aidata-digest", isDirectory: true)
        let mirrorJobs = LiveDashboardTelemetryReader.iCloudSyncRootURL(homeURL: iCloudHome)
            .appendingPathComponent("jobs/aidata-digest", isDirectory: true)
        let rawCloudDocsURL = iCloudHome.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/AIDashSync/jobs/aidata-digest/skills-roi.json"
        )
        try FileManager.default.createDirectory(at: localJobs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mirrorJobs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rawCloudDocsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        func skillsArtifact(_ timestamp: String, sampleSize: Int) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["generated_at": timestamp, "sample_size": sampleSize])
        }
        let localSkillURL = localJobs.appendingPathComponent("skills-roi.json")
        let mirrorSkillURL = mirrorJobs.appendingPathComponent("skills-roi.json")
        try skillsArtifact("2026-11-20T05:00:00Z", sampleSize: 1).write(to: localSkillURL)
        try skillsArtifact("2026-11-20T06:00:00Z", sampleSize: 99).write(to: mirrorSkillURL)
        try skillsArtifact("2026-11-20T07:00:00Z", sampleSize: 999).write(to: rawCloudDocsURL)
        #expect(LiveDashboardTelemetryReader.productionScheduledJobFileReader(rawCloudDocsURL) == nil)
        let selectedSkill = try #require(LiveDashboardTelemetryReader.selectFresherArtifactData(localURL: localSkillURL, iCloudURL: mirrorSkillURL))
        let selectedSkillObject = try #require(JSONSerialization.jsonObject(with: selectedSkill.data) as? [String: Any])
        #expect(selectedSkill.url == mirrorSkillURL)
        #expect(selectedSkillObject["sample_size"] as? Int == 99)

        let cloudBlocked = try #require(LiveDashboardTelemetryReader.selectFresherArtifactData(localURL: localSkillURL, iCloudURL: rawCloudDocsURL))
        #expect(cloudBlocked.url == localSkillURL)

        let agent = AgentEfficiencyWorkbenchSnapshot(sampleSize: 1, coverageStatus: "partial")
        var localAgent = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(agent)) as? [String: Any])
        localAgent["generated_at"] = "2026-11-20T05:00:00Z"
        var mirrorAgent = localAgent
        mirrorAgent["generated_at"] = "2026-11-20T06:00:00Z"
        mirrorAgent["sample_size"] = 77
        try JSONSerialization.data(withJSONObject: localAgent).write(to: localJobs.appendingPathComponent("agent-efficiency.json"))
        try JSONSerialization.data(withJSONObject: mirrorAgent).write(to: mirrorJobs.appendingPathComponent("agent-efficiency.json"))
        #expect(LiveDashboardTelemetryReader.loadAgentEfficiencySnapshot(homeURL: iCloudHome)?.sampleSize == 77)

        let store = DashboardWorkspaceStore(snapshot: sampleSnapshot())
        #expect(store.liveEfficiencySummary == nil)
        #expect(store.effectiveKPIMetrics.count == 4)

        for section in DashboardWorkspaceSection.allCases {
            store.selectedSection = section
            #expect(!store.selectedSection.title.isEmpty)
            _ = AIDashMacWorkspaceView(store: store).body
        }
        store.selectedSection = .overview
        if store.canSelectPreviousDate {
            let originalDate = store.selectedDateString
            store.selectPreviousDate()
            #expect(store.selectedDateString != originalDate)
            #expect(store.canSelectNextDate)
            store.selectToday()
            #expect(store.selectedDateString == originalDate)
        }
    }

    @Test("PreviewHost exposes two zero-jargon trend tabs, twenty unique topologies, isolated feedback bar, and receipt round-trip")
    func previewHostCatalogAndReceiptRoundTrip() throws {
        let tab1 = Tab1QuotasAndAgentEfficiencySections.descriptors
        let tab2 = Tab2SkillsArsenalInspectorSections.descriptors
        let all = tab1 + tab2
        #expect(tab1.count == 10)
        #expect(tab2.count == 10)
        #expect(Set(all.map(\.id)).count == 20)
        #expect(Set(all.map(\.topologySignature)).count == 20)
        #expect(all.allSatisfy { !$0.title.isEmpty && !$0.metricTags.isEmpty })

        let forbiddenJargon = [
            "Unpracticed", "光读不练", "Layer 0", "Layer 1", "Deadwood", "Unwired",
            "R1→R2", "exit=2", "Counter-Case", "S1_pin_drift", "S10_skill_roi_ranking",
            "Copy Eval Command", "Copy Path"
        ]
        for descriptor in all {
            let combined = ([descriptor.title] + descriptor.metricTags).joined(separator: " ")
            for banned in forbiddenJargon {
                #expect(!combined.localizedCaseInsensitiveContains(banned), "Forbidden jargon '\(banned)' in \(descriptor.id)")
            }
            #expect(
                combined.contains("▲") || combined.contains("▼"),
                "Expected time-trend delta indicator (▲ or ▼) in \(descriptor.id): \(combined)"
            )
        }

        let sample = AIDashPreviewSampleData.fallback()
        #expect(sample.skills.count == 24)
        #expect(sample.skills.allSatisfy { !$0.trend14d.isEmpty && ($0.deltaText.contains("▲") || $0.deltaText.contains("▼")) })
        #expect(sample.inspections.count == 7)
        #expect(sample.repos.map(\.repoName) == ["user-skills", "AIDash", "Financial", "VitalStride"])

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-selection-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var receipt = PreviewSelectionReceipt(selectedVariantID: tab1[0].id, starredVariantIDs: [tab2[0].id], notesByVariant: [tab1[0].id: "keep"])
        PreviewSelectionReceiptWriter.write(receipt, to: url)
        let loaded = PreviewSelectionReceiptWriter.read(from: url)
        #expect(loaded.selectedVariantID == tab1[0].id)
        #expect(loaded.starredVariantIDs == [tab2[0].id])
        #expect(loaded.notesByVariant[tab1[0].id] == "keep")
        receipt.touch()
        #expect(!receipt.updatedAt.isEmpty)

        let writer = PreviewSelectionReceiptWriter(path: url)
        var summaryUpdates = 0
        let summaryToken = writer.observeSummary { _, _ in summaryUpdates += 1 }
        defer { writer.removeSummaryObserver(summaryToken) }
        #expect(writer.toggleStar(tab1[1].id) == true)
        #expect(writer.select(tab1[1].id) == tab1[1].id)
        #expect(summaryUpdates == 2)
        _ = PreviewVariantFeedbackBar(variantID: tab1[1].id, receiptWriter: writer).body
        _ = PreviewSelectionSummaryPill(receiptWriter: writer).body
    }

    @Test("PreviewHost exports representative dark and light ImageRenderer states")
    func previewHostExportsRepresentativeStates() throws {
        let explicitPath = ProcessInfo.processInfo.environment["AIDASH_TK3_SCREENSHOT_DIR"]
            ?? ProcessInfo.processInfo.environment["TEST_RUNNER_AIDASH_TK3_SCREENSHOT_DIR"]
        let isTemporaryOutput = (explicitPath == nil)
        let output = explicitPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("aidash-previewhost-renders-\(UUID().uuidString)", isDirectory: true)
        defer {
            if isTemporaryOutput {
                try? FileManager.default.removeItem(at: output)
            }
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sample = AIDashPreviewSampleData.fallback()
        let views: [(String, AnyView)] = [
            ("tab1-v01", AnyView(Tab1QuotasAndAgentEfficiencySections.v01(data: sample, globalExpandAll: true, speed: .quarter))),
            ("tab1-v10", AnyView(Tab1QuotasAndAgentEfficiencySections.v10(data: sample, globalExpandAll: true, speed: .quarter))),
            ("tab2-v01", AnyView(Tab2SkillsArsenalInspectorSections.v01(data: sample, globalExpandAll: true, speed: .quarter))),
            ("tab2-v10", AnyView(Tab2SkillsArsenalInspectorSections.v10(data: sample, globalExpandAll: true, speed: .quarter)))
        ]
        for (name, view) in views {
            for scheme in [ColorScheme.dark, ColorScheme.light] {
                let renderer = ImageRenderer(content: view
                    .frame(width: 760, alignment: .topLeading)
                    .padding(16)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme))
                renderer.scale = 2
                let image = try #require(renderer.nsImage)
                let tiff = try #require(image.tiffRepresentation)
                let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
                let suffix = scheme == .dark ? "dark" : "light"
                let fileURL = output.appendingPathComponent("preview-\(name)-\(suffix).png")
                try png.write(to: fileURL)
                #expect(FileManager.default.fileExists(atPath: fileURL.path))
            }
        }
    }

    @Test("HerdrSocketClient resolves project folders accurately and communicates over Unix domain socket")
    func herdrSocketProjectResolutionAndMockServerRoundTrip() throws {
        let tempHome = URL(fileURLWithPath: "/tmp/aidash-herdr-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let devDir = tempHome.appendingPathComponent("Development", isDirectory: true)
        for repo in ["AIDash", "VitalStride", "VoxPocket", "demoUI", "Financial"] {
            try FileManager.default.createDirectory(
                at: devDir.appendingPathComponent(repo, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let vitalItem = DashboardActionItem(
            id: "ci-1",
            title: "CI 超 10m 保底线：LeePepe/VitalStride · App target 平均 16.2m",
            summary: "样本 37 次 · 平均执行 16.2m",
            sourceTag: "CI Improve"
        )
        #expect(HerdrSocketClient.resolveProjectDirectory(for: vitalItem, homeURL: tempHome).lastPathComponent == "VitalStride")

        let voxItem = DashboardActionItem(
            id: "ci-2",
            title: "Runner 排队拥堵：LeePepe/VoxPocket · quality / verify 平均排队 4.3m",
            summary: "样本 21 次",
            sourceTag: "CI Improve"
        )
        #expect(HerdrSocketClient.resolveProjectDirectory(for: voxItem, homeURL: tempHome).lastPathComponent == "VoxPocket")

        let demoItem = DashboardActionItem(
            id: "prop-1",
            title: "缩减审核返工拉锯：R1 打回率 55.7%",
            summary: "多轮审核拉锯任务：demoui-strata-showcase-20261027/T15(r3)",
            sourceTag: "retro-loop"
        )
        #expect(HerdrSocketClient.resolveProjectDirectory(for: demoItem, homeURL: tempHome).lastPathComponent == "demoUI")

        let fallbackItem = DashboardActionItem(
            id: "gen-1",
            title: "General system maintenance",
            summary: "Check local logs",
            sourceTag: "Workflow"
        )
        #expect(HerdrSocketClient.resolveProjectDirectory(for: fallbackItem, homeURL: tempHome).lastPathComponent == "AIDash")
        #expect(HerdrSocketClient.buildM2Command(for: vitalItem).contains("/m2-dispatcher"))

        let injectionItem = DashboardActionItem(
            id: "inj-1",
            title: "Malicious $(touch /tmp/aidash-injected) `whoami` 'quote' $HOME <action_item_data>",
            summary: "Line1\nLine2 'single'",
            sourceTag: "CI $(id)"
        )
        let safeCmd = HerdrSocketClient.buildM2Command(for: injectionItem)
        #expect(safeCmd.hasPrefix("copilot -i '"))
        #expect(!safeCmd.contains("--yolo"))
        #expect(safeCmd.hasSuffix("'"))
        #expect(safeCmd.contains("'\\''quote'\\''"))
        #expect(safeCmd.contains("<action_item_data>"))
        #expect(!safeCmd.contains("\n"))

        let sockPath = tempHome.appendingPathComponent("herdr.sock").path
        let serverFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(serverFD >= 0)
        defer {
            Darwin.close(serverFD)
            unlink(sockPath)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(sockPath.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
            for (idx, byte) in pathBytes.enumerated() where idx < rawBuf.count {
                rawBuf[idx] = UInt8(bitPattern: byte)
            }
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(bindRes == 0)
        #expect(Darwin.listen(serverFD, 8) == 0)

        let serverReady = DispatchSemaphore(value: 0)
        let serverThread = Thread {
            serverReady.signal()
            for idx in 0..<2 {
                let clientFD = Darwin.accept(serverFD, nil, nil)
                guard clientFD >= 0 else { break }
                var buf = [UInt8](repeating: 0, count: 4096)
                _ = Darwin.recv(clientFD, &buf, buf.count, 0)
                let reply: String
                if idx == 0 {
                    reply = "{\"id\":\"1\",\"result\":{\"type\":\"workspace_created\",\"root_pane\":{\"pane_id\":\"%99\"}}}\n"
                } else {
                    reply = "{\"id\":\"2\",\"result\":{\"type\":\"ok\"}}\n"
                }
                _ = reply.withCString { cStr in
                    Darwin.send(clientFD, cStr, strlen(cStr), 0)
                }
                Darwin.close(clientFD)
            }
        }
        serverThread.start()
        serverReady.wait()

        let dispatched = HerdrSocketClient.dispatchActionItemToHerdr(
            vitalItem,
            homeURL: tempHome,
            socketPath: sockPath
        )
        #expect(dispatched == true)
        #expect(vitalItem.projectFolderName == "VitalStride")

        let store = DashboardWorkspaceStore(snapshot: sampleSnapshot(), actionItems: [vitalItem])
        let missingSockPath = tempHome.appendingPathComponent("missing.sock").path
        #expect(store.dispatchActionToHerdr(vitalItem, socketPath: missingSockPath) == false)
        #expect(store.lastDispatchedActionID == nil)
        #expect(store.dispatchActionToHerdr(vitalItem) == true)
        #expect(store.lastDispatchedActionID == vitalItem.id)
    }

    @Test("pluggable TodoSyncProviderMode preferences persist to todo-sync.json and support standalone local mode")
    func todoSyncProviderModePreferencesAndConfigBridge() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-todo-sync-test-\(UUID().uuidString)", isDirectory: true)
        let configURL = tempDir.appendingPathComponent("todo-sync.json")
        let defaults = UserDefaults.standard
        let providerDefaultsKey = "aidash.todo_sync.provider_mode"
        let teamDefaultsKey = "aidash.todo_sync.team_key"
        let previousProvider = defaults.object(forKey: providerDefaultsKey)
        let previousTeam = defaults.object(forKey: teamDefaultsKey)
        defaults.removeObject(forKey: providerDefaultsKey)
        defaults.removeObject(forKey: teamDefaultsKey)
        defer {
            if let previousProvider {
                defaults.set(previousProvider, forKey: providerDefaultsKey)
            } else {
                defaults.removeObject(forKey: providerDefaultsKey)
            }
            if let previousTeam {
                defaults.set(previousTeam, forKey: teamDefaultsKey)
            } else {
                defaults.removeObject(forKey: teamDefaultsKey)
            }
            try? FileManager.default.removeItem(at: tempDir)
        }

        let prefs = MenuBarDisplayPreferences(persistToDefaults: true, todoSyncConfigFileURL: configURL)
        #expect(prefs.todoSyncProviderMode == .auto)
        #expect(prefs.todoSyncTeamKey == "TIA")
        #expect(TodoSyncProviderMode.allCases == [.auto, .localOnly, .linear])

        for mode in TodoSyncProviderMode.allCases {
            #expect(!mode.title.isEmpty)
            #expect(!mode.subtitle.isEmpty)
            #expect(!mode.symbolName.isEmpty)
        }

        prefs.todoSyncProviderMode = .localOnly
        let localData = try Data(contentsOf: configURL)
        let localJSON = try #require(JSONSerialization.jsonObject(with: localData) as? [String: String])
        #expect(localJSON["provider"] == "local")
        #expect(localJSON["teamKey"] == "TIA")

        prefs.todoSyncProviderMode = .linear
        prefs.todoSyncTeamKey = "  eng "
        #expect(prefs.todoSyncTeamKey == "ENG")
        #expect(defaults.string(forKey: teamDefaultsKey) == "ENG")
        let linearData = try Data(contentsOf: configURL)
        let linearJSON = try #require(JSONSerialization.jsonObject(with: linearData) as? [String: String])
        #expect(linearJSON["provider"] == "linear")
        #expect(linearJSON["teamKey"] == "ENG")

        let store = DashboardWorkspaceStore(snapshot: sampleSnapshot())
        _ = DashboardSettingsPageView(store: store, prefs: prefs).body
    }

    @Test("loadLiveImprovementActionItems consumes unified ActionableItem Schema v1 from actions.jsonl and supports native Approve / Done / Dismiss decisions")
    func unifiedActionableItemsSchemaV1AndDecisionSubmission() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-unified-actions-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let digestDir = tempHome.appendingPathComponent("Library/Application Support/AIDash/jobs/aidata-digest", isDirectory: true)
        try FileManager.default.createDirectory(at: digestDir, withIntermediateDirectories: true)

        let actionsURL = digestDir.appendingPathComponent("actions.jsonl")
        let sampleLines = [
            #"{"id":"linear-TIA-76","jobID":"aidata-digest","createdAt":"2026-11-11T16:00:00Z","title":"Personal AIDash rollout","description":"[in_progress] TIA-76 Personal AIDash rollout","status":"in_progress","source":"Linear","priority":"P1","ref":"linear://TIA-76","url":"https://github.com/LeePepe/AIDash/issues/76","labels":["pop"],"project":"LeePepe/AIDash","parentIssue":{"identifier":"TIA-83","title":"Parent queue","url":"https://github.com/LeePepe/AIDash/issues/83"},"controls":[{"id":"decision","kind":"singleSelect","title":"Action","options":["Approve","Done","Dismiss"]},{"id":"note","kind":"textInput","title":"Note","maxLength":80}]}"#,
            #"{"id":"EVAL-RULE-VIEW-SNAPSHOT-TEST","jobID":"aidata-digest","createdAt":"2026-11-11T16:00:00Z","title":"[Bing] external work noise","description":"external work","status":"triage","source":"Linear","priority":"P1","ref":"eval://EVAL-RULE-VIEW-SNAPSHOT-TEST","url":"https://msft.ghe.com/san/bing-growth-sapphire-app/pull/617","labels":["eval"],"project":"Bing","parentIssue":{"identifier":"TIA-83","title":"Parent queue","url":"https://github.com/LeePepe/AIDash/issues/83"},"controls":[]}"#,
            #"{"id":"proposal-review-pingpong","jobID":"aidata-digest","createdAt":"2026-11-11T16:00:00Z","title":"Shrink Review Ping-Pong","description":"R1 fail rate 55.7%","status":"triage","source":"Retro","priority":"P0","ref":"proposal://review-pingpong","url":"","controls":[{"id":"decision","kind":"singleSelect","title":"Action","options":["Approve","Done","Dismiss"]},{"id":"targets","kind":"multiSelect","title":"Targets","options":["item-a","item-b"]},{"id":"note","kind":"textInput","title":"Note","maxLength":80}]}"#,
            #"{"id":"gtt-blocker-1","jobID":"aidata-digest","createdAt":"2026-11-11T16:00:00Z","title":"GTT Blocker: aidash-ops","description":"Waiting on Owner GO","status":"blocked","source":"GTT Blocker","priority":"P0","ref":"aidash-ops","url":"","controls":[{"id":"decision","kind":"singleSelect","title":"Action","options":["Approve","Done","Dismiss"]},{"id":"note","kind":"textInput","title":"Note","maxLength":80}]}"#
        ]
        try (sampleLines.joined(separator: "\n") + "\n").write(to: actionsURL, atomically: true, encoding: .utf8)

        let loaded = LiveDashboardTelemetryReader.loadLiveImprovementActionItems(
            homeURL: tempHome,
            acknowledgedActionIDs: ["aidata-digest:gtt-blocker-1"]
        )
        #expect(loaded.count == 3)

        #expect(loaded.first(where: { $0.id == "EVAL-RULE-VIEW-SNAPSHOT-TEST" }) == nil)

        let linearItem = try #require(loaded.first(where: { $0.id == "linear-TIA-76" }))
        #expect(linearItem.status == .inProgress)
        #expect(!linearItem.isCompleted)
        #expect(linearItem.sourceTag == "Linear")
        #expect(linearItem.priority == .p1)
        #expect(linearItem.displayRefLabel == "TIA-76")
        #expect(linearItem.externalURLString == "https://github.com/LeePepe/AIDash/issues/76")
        #expect(linearItem.labels == ["pop"])
        #expect(linearItem.project == "LeePepe/AIDash")
        #expect(linearItem.parentIssueKey == "TIA-83")
        #expect(linearItem.parentIssueTitle == "Parent queue")
        #expect(linearItem.parentIssueURL == "https://github.com/LeePepe/AIDash/issues/83")
        #expect(linearItem.summary == "Personal AIDash rollout")
        #expect(linearItem.decisionOptions == ["Approve", "Done", "Dismiss"])

        let retroItem = try #require(loaded.first(where: { $0.id == "proposal-review-pingpong" }))
        #expect(retroItem.status == .triage)
        #expect(retroItem.sourceTag == "Retro")
        #expect(retroItem.priority == .p0)
        #expect(retroItem.targetOptions == ["item-a", "item-b"])
        let filterStore = DashboardWorkspaceStore(snapshot: sampleSnapshot(), actionItems: loaded)
        #expect(filterStore.availableLinearActionFilters.map(\.id) == ["all", "pop"])
        filterStore.selectedLinearActionFilter = "pop"
        #expect(filterStore.filteredActionItems.map(\.id) == ["linear-TIA-76"])

        let ackedItem = try #require(loaded.first(where: { $0.id == "gtt-blocker-1" }))
        #expect(ackedItem.status == .blocked)
        #expect(!ackedItem.isCompleted)

        let store = DashboardWorkspaceStore(snapshot: sampleSnapshot(), actionItems: loaded)
        var capturedAction: ScheduledJobAction?
        var capturedResponses: [ScheduledJobActionResponse] = []
        var toggledEvent: (String, String, Bool)?
        store.scheduledActionWriter = { action, responses in
            capturedAction = action
            capturedResponses = responses
            return true
        }
        store.submitActionItemDecision(
            retroItem,
            decision: "Approve",
            targets: ["item-b", "item-a"],
            note: "Ship in wave 1",
            onToggleDone: { cardId, itemRef, isDone in
                toggledEvent = (cardId, itemRef, isDone)
            }
        )
        #expect(capturedAction?.id == "proposal-review-pingpong")
        #expect(capturedResponses.contains(ScheduledJobActionResponse(controlID: "decision", value: "Approve")))
        #expect(capturedResponses.contains(ScheduledJobActionResponse(controlID: "targets", value: "item-a,item-b")))
        #expect(capturedResponses.contains(ScheduledJobActionResponse(controlID: "note", value: "Ship in wave 1")))
        #expect(store.acknowledgedScheduledActionIDs.contains("aidata-digest:proposal-review-pingpong"))
        #expect(store.actionItems.first(where: { $0.id == "proposal-review-pingpong" })?.isCompleted == false)
        #expect(store.actionItems.first(where: { $0.id == "proposal-review-pingpong" })?.status == .inProgress)
        #expect(toggledEvent?.0 == "scheduled-pulse/aidata-digest")
        #expect(toggledEvent?.1 == "proposal://review-pingpong")
        #expect(toggledEvent?.2 == false)
        _ = ActionItemsCardView(store: store).body
    }

    @Test("M2 topic resolution prefers explicit IDs and applies deterministic fallback rules")
    func m2TopicResolutionIsCanonical() {
        let explicit = DashboardActionItem(
            id: "unknown", title: "Unrelated", summary: "", sourceTag: "Linear", topicID: "sapphire-notification"
        )
        let chinaBug = DashboardActionItem(
            id: "BUG-AB11440223", title: "Bing CN devsync blocker", summary: "", sourceTag: "my-pr-supervisor"
        )
        let smartBanner = DashboardActionItem(
            id: "linear-TIA-76", title: "FlightBook SmartBanner Universal Link", summary: "", sourceTag: "Linear"
        )
        #expect(explicit.topicID == "sapphire-notification")
        #expect(explicit.targetRepo == "bing-growth-sapphire-app")
        #expect(chinaBug.topicID == "sapphire-china-bugs")
        #expect(smartBanner.topicID == "sapphire-smartbanner")
        #expect(smartBanner.topicGroup == "work-business")
    }

    @Test("Herdr JSON parsing binds known panes and falls back to NEW_M2")
    func herdrSessionParsingAndBinding() throws {
        let workspaces = #"{"result":{"workspaces":[{"workspace_id":"w1","label":"China bugs 修复","active_tab_id":"w1:t1","pane_count":1},{"workspace_id":"w10","label":"SmartBanner","active_tab_id":"w10:t1","pane_count":1}]}}"#
        let agents = #"{"result":{"agents":[{"workspace_id":"w1","pane_id":"w1:p1","cwd":"/Users/test/Development/bing-growth-sapphire-app","terminal_title_stripped":"Review bugs"},{"workspace_id":"w10","pane_id":"w10:p1","cwd":"/Users/test/Development/bing-growth-sapphire-app","terminal_title_stripped":"SmartBanner"}]}}"#
        let snapshot = LiveDashboardTelemetryReader.parseHerdrM2SessionSnapshot(workspaceOutput: workspaces, agentOutput: agents)
        let bindings = snapshot.bindings(for: DashboardTopicCatalog.builtInTopics)
        #expect(bindings["sapphire-china-bugs"]?.paneID == "w1:p1")
        #expect(bindings["sapphire-smartbanner"]?.paneID == "w10:p1")
        #expect(bindings["sapphire-notification"]?.isExisting == false)
        #expect(bindings["sapphire-notification"]?.badgeText == "🆕 NEW_M2 · bing-growth-sapphire-app")
    }

    @Test("Topic columns group cards and dispatch guards prevent repeats")
    func topicGroupingAndDispatchGuard() throws {
        let actions = [
            DashboardActionItem(id: "D617-5221157", title: "PR #617", summary: "China Bugs", sourceTag: "my-pr-supervisor", priority: .p0),
            DashboardActionItem(id: "linear-TIA-76", title: "SmartBanner Universal Link", summary: "", sourceTag: "Linear", priority: .p1)
        ]
        var calls = 0
        var targetJSON = ""
        let store = DashboardWorkspaceStore(
            snapshot: sampleSnapshot(), actionItems: actions,
            sessionBindings: ["sapphire-china-bugs": DashboardM2SessionBinding(topicID: "sapphire-china-bugs", paneID: "w1:p1", workspaceID: "w1", workspaceLabel: "China bugs 修复", targetRepo: "bing-growth-sapphire-app")],
            m2DispatchExecutor: { prompt, targets, pane in
                calls += 1
                targetJSON = targets
                #expect(prompt.contains("PR #617"))
                #expect(pane == "w1:p1")
                return DashboardM2DispatchResult(succeeded: true, receipt: "✓ 已派发至 w1:p1")
            }
        )
        #expect(store.topicColumns.map(\.id) == ["sapphire-china-bugs", "sapphire-smartbanner"])
        let first = store.dispatchStagedTopic(topicID: "sapphire-china-bugs")
        #expect(first.succeeded)
        #expect(calls == 1)
        #expect(targetJSON.contains("sapphire-china-bugs"))
        #expect(store.actionItems.first?.isCompleted == true)
        #expect(store.dispatchTopicToM2(topicID: "sapphire-china-bugs", items: [(actions[0], "Approve", "")]).succeeded == false)
        #expect(calls == 1)
    }

    @Test("Linear parent rows are removed when they only serve as containers")
    func linearParentContainerRowsAreDeduplicated() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-linear-parent-container-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let digestDir = tempHome.appendingPathComponent("Library/Application Support/AIDash/jobs/aidata-digest", isDirectory: true)
        try FileManager.default.createDirectory(at: digestDir, withIntermediateDirectories: true)
        let actionsURL = digestDir.appendingPathComponent("actions.jsonl")
        let lines = [
            #"{"id":"linear-TIA-83","jobID":"aidata-digest","title":"Parent","description":"Parent","status":"in_progress","source":"Linear","ref":"linear://TIA-83","controls":[{"id":"confirm","kind":"confirm","title":"Confirm"}],"parentIssue":{"identifier":"TIA-83","title":"Parent","url":"https://linear.app/example/issue/TIA-83"}}"#,
            #"{"id":"child-1","jobID":"aidata-digest","title":"Child","description":"Child","status":"triage","source":"Linear","ref":"linear://CHILD-1","controls":[{"id":"confirm","kind":"confirm","title":"Confirm"}],"parentIssue":{"identifier":"TIA-83","title":"Parent","url":"https://linear.app/example/issue/TIA-83"}}"#
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: actionsURL, atomically: true, encoding: .utf8)

        let loaded = LiveDashboardTelemetryReader.loadLiveImprovementActionItems(homeURL: tempHome)
        #expect(loaded.map(\.id) == ["child-1"])
    }

    @Test("AgentEfficiencyWorkbenchSnapshot decodes v1 JSON, falls back to warehouse.db, renders 4x2 PNGs, and exposes zero bare M1-M5 or S1-S12 codes")
    func agentEfficiencyWorkbenchDecodesRendersAndForbidsInternalCodes() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-agent-eff-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }
        let digestDir = tempHome.appendingPathComponent(
            "Library/Application Support/AIDash/jobs/aidata-digest",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: digestDir, withIntermediateDirectories: true)

        let snapshotJSON = """
        {
          "contract": "aidash-agent-efficiency/v1",
          "schema_version": 1,
          "window_cst": "14d",
          "window_start": "2026-11-06",
          "window_end": "2026-11-19",
          "source_as_of": "2026-11-19",
          "sample_size": 124,
          "coverage_status": "healthy",
          "roles": [
            {"role_key": "m3", "role_label": "总控协调", "role_label_en": "Top-Level Coordinator", "runs_count": 6, "goals_count": 4, "tasks_count": 6, "r1_count": 6, "r2_count": 0, "r3_plus_count": 0, "r1_pass_rate": 1.0, "median_duration_sec": 1.2, "p90_duration_sec": 2.8, "estimated_tokens": 1100000, "token_share_pct": 1.2},
            {"role_key": "m2", "role_label": "话题编排", "role_label_en": "Topic Dispatcher", "runs_count": 18, "goals_count": 10, "tasks_count": 14, "r1_count": 14, "r2_count": 0, "r3_plus_count": 0, "r1_pass_rate": 1.0, "median_duration_sec": 9.4, "p90_duration_sec": 26.0, "estimated_tokens": 8400000, "token_share_pct": 9.3},
            {"role_key": "m1", "role_label": "Goal 主控 (TL)", "role_label_en": "Goal Lead (TL)", "runs_count": 28, "goals_count": 12, "tasks_count": 24, "r1_count": 23, "r2_count": 1, "r3_plus_count": 0, "r1_pass_rate": 0.9583, "median_duration_sec": 1800.0, "p90_duration_sec": 4200.0, "estimated_tokens": 9200000, "token_share_pct": 10.2},
            {"role_key": "designer", "role_label": "视觉设计 (Designer)", "role_label_en": "Visual Design (Designer)", "runs_count": 8, "goals_count": 5, "tasks_count": 6, "r1_count": 5, "r2_count": 1, "r3_plus_count": 0, "r1_pass_rate": 0.8333, "median_duration_sec": 420.0, "p90_duration_sec": 680.0, "estimated_tokens": 6100000, "token_share_pct": 6.8},
            {"role_key": "writer", "role_label": "编码实现 (Writer)", "role_label_en": "Code Implementation (Writer)", "runs_count": 32, "goals_count": 12, "tasks_count": 24, "r1_count": 18, "r2_count": 4, "r3_plus_count": 2, "r1_pass_rate": 0.75, "median_duration_sec": 1560.0, "p90_duration_sec": 3900.0, "estimated_tokens": 36000000, "token_share_pct": 40.0},
            {"role_key": "reviewer", "role_label": "独立审查 (Reviewer)", "role_label_en": "Independent Review (Reviewer)", "runs_count": 20, "goals_count": 12, "tasks_count": 18, "r1_count": 13, "r2_count": 3, "r3_plus_count": 2, "r1_pass_rate": 0.7222, "median_duration_sec": 920.0, "p90_duration_sec": 2100.0, "estimated_tokens": 24000000, "token_share_pct": 26.7},
            {"role_key": "explorer", "role_label": "代码探查 (Explorer)", "role_label_en": "Code Exploration (Explorer)", "runs_count": 6, "goals_count": 4, "tasks_count": 6, "r1_count": 6, "r2_count": 0, "r3_plus_count": 0, "r1_pass_rate": 1.0, "median_duration_sec": 210.0, "p90_duration_sec": 540.0, "estimated_tokens": 2800000, "token_share_pct": 3.1},
            {"role_key": "pr_monitor", "role_label": "交付监控 (PR Monitor)", "role_label_en": "Delivery Monitor (PR Monitor)", "runs_count": 6, "goals_count": 6, "tasks_count": 6, "r1_count": 5, "r2_count": 1, "r3_plus_count": 0, "r1_pass_rate": 0.8333, "median_duration_sec": 640.0, "p90_duration_sec": 1800.0, "estimated_tokens": 2400000, "token_share_pct": 2.7}
          ],
          "round_summary": {
            "r1_count": 36,
            "r2_count": 8,
            "r3_plus_count": 4,
            "evaluated_tasks": 48,
            "r1_pass_rate": 0.75,
            "median_duration_sec": 1180.0,
            "p90_duration_sec": 3900.0,
            "steering_token_share": 0.207,
            "ttft_p90_sec": 3.8,
            "cache_hit_rate": 0.86
          },
          "daily_series": [
            {"day": "2026-11-17", "goals_completed": 4, "tasks_completed": 11, "r1_count": 9, "r2_count": 2, "r3_plus_count": 0, "r1_pass_rate": 0.8182, "median_duration_sec": 1120.0, "p90_duration_sec": 2800.0, "blocked_events": 1, "steering_tokens": 4200000, "coding_tokens": 18500000, "total_tokens": 22700000},
            {"day": "2026-11-18", "goals_completed": 5, "tasks_completed": 14, "r1_count": 11, "r2_count": 2, "r3_plus_count": 1, "r1_pass_rate": 0.7857, "median_duration_sec": 1340.0, "p90_duration_sec": 3400.0, "blocked_events": 2, "steering_tokens": 5100000, "coding_tokens": 21900000, "total_tokens": 27000000},
            {"day": "2026-11-19", "goals_completed": 3, "tasks_completed": 8, "r1_count": 7, "r2_count": 1, "r3_plus_count": 0, "r1_pass_rate": 0.875, "median_duration_sec": 980.0, "p90_duration_sec": 2200.0, "blocked_events": 0, "steering_tokens": 3300000, "coding_tokens": 14200000, "total_tokens": 17500000}
          ]
        }
        """
        let snapshotURL = digestDir.appendingPathComponent("agent-efficiency.json")
        try Data(snapshotJSON.utf8).write(to: snapshotURL)

        let summary = try #require(LiveDashboardTelemetryReader.loadLiveEfficiencySummary(homeURL: tempHome))
        let workbench = try #require(summary.agentEfficiency)
        #expect(workbench.coverageStatus == "healthy")
        #expect(workbench.sampleSize == 124)
        #expect(workbench.roles.count == 8)
        #expect(workbench.roundSummary.r1Count == 36)
        #expect(workbench.roundSummary.r2Count == 8)
        #expect(workbench.roundSummary.r3PlusCount == 4)
        #expect(workbench.dailySeries.count == 3)
        #expect(workbench.dailySeries.last?.shortDayLabel == "11-19")

        // Verify warehouse.db fallback when agent-efficiency.json is absent.
        let fallbackHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-agent-eff-fb-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fallbackHome) }
        let whDir = fallbackHome.appendingPathComponent("Development/AIDash/aidata/L3_merge", isDirectory: true)
        try FileManager.default.createDirectory(at: whDir, withIntermediateDirectories: true)
        let whURL = whDir.appendingPathComponent("warehouse.db")
        var whDB: OpaquePointer?
        #expect(sqlite3_open(whURL.path, &whDB) == SQLITE_OK)
        if let whDB {
            let whSQL = """
            CREATE TABLE fact_gtt_task_run (goal_uid TEXT, goal_id TEXT, task_id TEXT, role_name TEXT, round_no INTEGER, v5_verdict TEXT);
            CREATE TABLE fact_gtt_event (goal_uid TEXT, task_id TEXT, evt_type TEXT, cst_day TEXT);
            INSERT INTO fact_gtt_task_run VALUES ('m:g1', 'g1', 'T1', 'writer', 1, 'PASS');
            INSERT INTO fact_gtt_task_run VALUES ('m:g1', 'g1', 'T1', 'reviewer', 1, 'PASS');
            INSERT INTO fact_gtt_event VALUES ('m:g1', 'T1', 'DONE', '2026-11-19');
            INSERT INTO fact_gtt_event VALUES ('m:g1', NULL, 'GOAL_DONE', '2026-11-19');
            """
            #expect(sqlite3_exec(whDB, whSQL, nil, nil, nil) == SQLITE_OK)
            sqlite3_close(whDB)
        }
        let fbSummary = try #require(LiveDashboardTelemetryReader.loadLiveEfficiencySummary(homeURL: fallbackHome))
        let fbWorkbench = try #require(fbSummary.agentEfficiency)
        #expect(fbWorkbench.coverageStatus == "partial")
        #expect(fbWorkbench.roles.count == 8)
        #expect(fbWorkbench.dailySeries.first?.goalsCompleted == 1)

        // Strict Redline: zero bare M1-M5 or S1-S12 metric codes in AgentEfficiencyChartsCardView source or xcstrings keys.
        let cardSourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Scenes/DashboardModularCardViews.swift")
        let cardSource = try String(contentsOf: cardSourceURL, encoding: .utf8)
        let viewStart = try #require(cardSource.range(of: "public struct AgentEfficiencyChartsCardView: View"))
        let viewSnippet = String(cardSource[viewStart.lowerBound...])
        let forbiddenRegex = try NSRegularExpression(pattern: #"\b(?:M[1-5]|S(?:[1-9]|1[0-2]))\b"#)
        let matches = forbiddenRegex.matches(
            in: viewSnippet,
            range: NSRange(viewSnippet.startIndex..<viewSnippet.endIndex, in: viewSnippet)
        )
        #expect(matches.isEmpty, "Found forbidden bare M1-M5 or S1-S12 internal codes in AgentEfficiencyChartsCardView")

        // Render 4 states x 2 appearances PNGs for Visual Traceback when env dir is configured (or temp dir).
        let env = ProcessInfo.processInfo.environment
        let configuredDir: String? = [
            env["AIDASH_AGENT_EFF_SCREENSHOT_DIR"],
            env["TEST_RUNNER_AIDASH_AGENT_EFF_SCREENSHOT_DIR"],
        ].compactMap { val -> String? in
            guard let val, !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return val
        }.first
        let ownsOut = configuredDir == nil
        let outDir = configuredDir.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("aidash-agent-eff-shots-\(UUID().uuidString)", isDirectory: true)
        defer {
            if ownsOut { try? FileManager.default.removeItem(at: outDir) }
        }
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        var degradedSummary = summary
        degradedSummary.agentEfficiency = AgentEfficiencyWorkbenchSnapshot(
            schemaVersion: 1,
            windowCST: "14d",
            windowStart: "2026-11-06",
            windowEnd: "2026-11-19",
            sourceAsOf: "2026-11-19",
            sampleSize: workbench.sampleSize,
            coverageStatus: "error",
            roles: workbench.roles,
            roundSummary: workbench.roundSummary,
            dailySeries: workbench.dailySeries
        )

        let states: [(String, LiveDashboardTelemetryReader.LiveEfficiencySummary?)] = [
            ("populated", summary),
            ("partial", fbSummary),
            ("degraded", degradedSummary),
            ("empty", nil),
        ]
        for (stateName, stateSummary) in states {
            for scheme in [ColorScheme.light, ColorScheme.dark] {
                let appearance = scheme == .dark ? "dark" : "light"
                let card = AgentEfficiencyChartsCardView(summary: stateSummary)
                    .frame(width: 1080)
                    .padding(16)
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .environment(\.colorScheme, scheme)
                    .environment(\.theme, Theme(isDark: scheme == .dark))
                let bmp = try toolbarHeaderBitmap(for: card, scheme: scheme)
                let png = try #require(bmp.representation(using: .png, properties: [:]))
                #expect(!png.isEmpty)
                #expect(bmp.pixelsWide >= 1000)
                #expect(bmp.pixelsHigh >= 120)
                try png.write(to: outDir.appendingPathComponent("agent-efficiency-\(stateName)-\(appearance).png"))
            }
        }
    }

    @Test("SkillsRoiReport decodes skill_version_evolution and skill_retro, filters pseudo-skills, and renders 3 plain-language workbench sections with zero S1..S12 codes")
    func skillsWorkbenchV2DecodesFiltersPseudoSkillsAndRendersThreePlainSections() throws {
        let payloadJSON = """
        {
          "schema_version": 1,
          "window_cst": "30d",
          "window_start": "2026-10-24T00:00:00+08:00",
          "window_end": "2026-11-23T00:00:00+08:00",
          "source_as_of": "2026-11-22T19:00:00+08:00",
          "sample_size": 1868,
          "coverage_status": "healthy",
          "diagnostics": {
            "window_cst": "30d",
            "window_start": "2026-10-24T00:00:00+08:00",
            "window_end": "2026-11-23T00:00:00+08:00",
            "source_as_of": "2026-11-22T19:00:00+08:00",
            "sample_size": 1868,
            "coverage_status": "healthy",
            "S4_usage_and_r1": {
              "window_cst": "30d",
              "sample_size": 1868,
              "coverage_status": "healthy",
              "active_skills_count": 2,
              "idle_skills_30d": ["skills", "asset-screener"],
              "top_used_skills": [
                {"skill": "team-lead", "loads_7d": 42, "loads_30d": 168, "roi_score": 1.62, "r1_total": 24, "r1_pass_rate": 0.92},
                {"skill": "tests", "loads_7d": 5, "loads_30d": 12, "roi_score": 0.4},
                {"skill": "leepepe", "loads_7d": 2, "loads_30d": 4, "roi_score": 0.2}
              ]
            },
            "S10_skill_roi_ranking": [
              {"skill": "team-lead", "loads_7d": 42, "loads_30d": 168, "roi_score": 1.62, "r1_total": 24, "r1_pass_rate": 0.92},
              {"skill": "my-designer", "loads_7d": 28, "loads_30d": 96, "roi_score": 1.48, "r1_total": 16, "r1_pass_rate": 0.88},
              {"skill": "pull", "loads_7d": 3, "loads_30d": 9, "roi_score": 0.1},
              {"skill": "main", "loads_7d": 1, "loads_30d": 2, "roi_score": 0.1}
            ]
          },
          "skill_details": [
            {
              "window_cst": "30d",
              "sample_size": 168,
              "coverage_status": "healthy",
              "skill": "team-lead",
              "scope": "global",
              "repo": "user-skills",
              "skill_dir": "~/Development/user-skills/skills/team-lead",
              "skill_md_path": "SKILL.md",
              "skill_md_lines": 120,
              "frontmatter_tokens_est": 50,
              "body_tokens_est": 1800,
              "bundle_kb": 18.2,
              "loads_7d": 42,
              "loads_30d": 168,
              "roi_score": 1.62,
              "r1_pass_rate": 0.92,
              "status_label": "active",
              "references": [
                {"rel_path": "references/ledger.md", "line_count": 90, "tokens_est": 1200, "hits_30d": 35, "is_unhit": false}
              ],
              "scripts": [
                {"rel_path": "scripts/goal-queue.py", "calls_30d": 95, "success_rate": 0.98, "p95_ms": 240.0, "is_unpracticed": false}
              ],
              "eval_cases": [
                {"id": "EV-001", "title": "feedback_guard pre-review-check subcommand", "kind": "cli", "status": "active", "interceptions_30d": 6, "escapes_30d": 0}
              ]
            },
            {
              "window_cst": "30d",
              "sample_size": 96,
              "coverage_status": "healthy",
              "skill": "my-designer",
              "scope": "global",
              "repo": "user-skills",
              "skill_dir": "~/Development/user-skills/skills/my-designer",
              "skill_md_path": "SKILL.md",
              "loads_7d": 28,
              "loads_30d": 96,
              "roi_score": 1.48,
              "r1_pass_rate": 0.88,
              "status_label": "active",
              "references": [],
              "scripts": [],
              "eval_cases": []
            },
            {
              "skill": "tests",
              "scope": "global",
              "repo": "user-skills",
              "skill_dir": "~/Development/user-skills/skills/tests",
              "loads_7d": 5,
              "loads_30d": 12
            },
            {
              "skill": "scripts",
              "scope": "global",
              "repo": "user-skills",
              "skill_dir": "~/Development/user-skills/skills/scripts",
              "loads_7d": 2,
              "loads_30d": 6
            }
          ],
          "skill_version_evolution": [
            {
              "window_cst": "30d",
              "sample_size": 168,
              "coverage_status": "healthy",
              "skill": "team-lead",
              "semver": "1.4.0",
              "skill_version": "v58@a1b2c3d",
              "combined_version": "1.4.0+v58@a1b2c3d",
              "subtree_sha": "a1b2c3d",
              "commit_count": 58,
              "status": "improved",
              "status_label": "✅ 有效演进",
              "before_version": {
                "skill_version": "v57@6be2fb5",
                "semver": "1.3.0",
                "combined_version": "1.3.0+v57@6be2fb5",
                "commit_count": 57,
                "subtree_sha": "6be2fb5",
                "sessions": 64,
                "invocations": 64,
                "script_call_count": 120,
                "exit2_count": 12,
                "exit1_count": 4,
                "post_fix_errors": 12,
                "exit2_error_rate": 0.1,
                "broken_drawer_count": 2,
                "script_p50_ms": 620.0,
                "uptake_rate": 0.78,
                "r1_total": 12,
                "r1_pass": 9,
                "r1_pass_rate": 0.75
              },
              "current_version": {
                "skill_version": "v58@a1b2c3d",
                "semver": "1.4.0",
                "combined_version": "1.4.0+v58@a1b2c3d",
                "commit_count": 58,
                "subtree_sha": "a1b2c3d",
                "sessions": 104,
                "invocations": 104,
                "script_call_count": 180,
                "exit2_count": 0,
                "exit1_count": 2,
                "post_fix_errors": 0,
                "exit2_error_rate": 0.0,
                "broken_drawer_count": 0,
                "script_p50_ms": 240.0,
                "uptake_rate": 0.95,
                "r1_total": 24,
                "r1_pass": 22,
                "r1_pass_rate": 0.9167
              },
              "delta": {
                "exit2_error_rate_delta": -0.1,
                "exit2_count_delta": -12,
                "broken_drawer_delta": -2,
                "script_p50_ms_delta": -380.0,
                "uptake_rate_delta": 0.17,
                "r1_pass_rate_delta": 0.1667,
                "post_fix_errors": 0,
                "improved_dimensions": ["exit2_error_rate", "broken_drawer_count", "script_p50_ms", "uptake_rate", "r1_pass_rate"],
                "regressed_dimensions": []
              },
              "versions": [
                {
                  "skill_version": "v57@6be2fb5",
                  "semver": "1.3.0",
                  "combined_version": "1.3.0+v57@6be2fb5",
                  "commit_count": 57,
                  "subtree_sha": "6be2fb5",
                  "sessions": 64,
                  "invocations": 64,
                  "script_call_count": 120,
                  "exit2_count": 12,
                  "exit1_count": 4,
                  "post_fix_errors": 12,
                  "exit2_error_rate": 0.1,
                  "broken_drawer_count": 2,
                  "script_p50_ms": 620.0,
                  "uptake_rate": 0.78,
                  "r1_total": 12,
                  "r1_pass": 9,
                  "r1_pass_rate": 0.75
                },
                {
                  "skill_version": "v58@a1b2c3d",
                  "semver": "1.4.0",
                  "combined_version": "1.4.0+v58@a1b2c3d",
                  "commit_count": 58,
                  "subtree_sha": "a1b2c3d",
                  "sessions": 104,
                  "invocations": 104,
                  "script_call_count": 180,
                  "exit2_count": 0,
                  "exit1_count": 2,
                  "post_fix_errors": 0,
                  "exit2_error_rate": 0.0,
                  "broken_drawer_count": 0,
                  "script_p50_ms": 240.0,
                  "uptake_rate": 0.95,
                  "r1_total": 24,
                  "r1_pass": 22,
                  "r1_pass_rate": 0.9167
                }
              ]
            },
            {
              "window_cst": "30d",
              "sample_size": 12,
              "coverage_status": "healthy",
              "skill": "nas-smart-home",
              "semver": "1.0.0",
              "skill_version": "v3@0000001",
              "combined_version": "1.0.0+v3@0000001",
              "status": "observing",
              "status_label": "⏳ 样本积累中",
              "before_version": {
                "skill_version": "v2@0000000",
                "semver": "1.0.0",
                "sessions": 12,
                "exit2_count": 0,
                "broken_drawer_count": 0
              },
              "current_version": {
                "skill_version": "v3@0000001",
                "semver": "1.0.0",
                "sessions": 0,
                "exit2_count": 0,
                "broken_drawer_count": 0
              },
              "delta": {
                "exit2_error_rate_delta": 0.0,
                "exit2_count_delta": 0,
                "broken_drawer_delta": 0,
                "post_fix_errors": 0,
                "improved_dimensions": [],
                "regressed_dimensions": []
              }
            },
            {
              "skill": "leepepe",
              "semver": "1.0.0",
              "skill_version": "v1@bad",
              "status": "baseline",
              "current_version": {"skill_version": "v1@bad", "sessions": 1}
            }
          ],
          "skill_retro": {
            "sample_size": 1868,
            "slow_flywheel_ready": true,
            "summary": {
              "trigger_miss_skills": 4,
              "zero_action_load_skills": 5,
              "directional_drifts": 25,
              "unwired_drawers_count": 1,
              "true_deadwood_drawers_count": 3,
              "true_catcher_scripts_count": 41,
              "ceremonial_scripts_count": 22,
              "rigid_roadblock_scripts_count": 17,
              "latency_sink_scripts_count": 13,
              "wild_patterns_count": 5,
              "slow_flywheel_ready": true
            },
            "cross_repo_gate_health": {
              "repos_scanned": 16,
              "healthy_repos_count": 5,
              "drifted_repos_count": 11,
              "average_gate_health_score": 68.5,
              "total_findings": 32
            },
            "layer0_direction_and_triggers": {
              "trigger_misses": [
                {
                  "skill": "my-designer",
                  "missed_sessions": 223,
                  "domain_sessions": 581,
                  "miss_rate": 0.3838,
                  "samples": [
                    {
                      "session_id": "04b1852a-2d6",
                      "evidence_files": ["Apps/AIDashApp/Sources/Scenes/SkillsRoiDiagnosticsCardView.swift"]
                    }
                  ]
                }
              ],
              "zero_action_loads": [
                {
                  "skill": "team-lead",
                  "loads": 441,
                  "zero_action_sessions": 7,
                  "zero_action_rate": 0.0159
                }
              ],
              "directional_drifts": [
                {
                  "goal_id": "aidash-ops-ui-demo",
                  "task_id": "R7",
                  "event": "CHANGE_REQUEST",
                  "skills": []
                }
              ],
              "directional_drift_count": 25
            },
            "layer1_drawer_metabolism": {
              "hot_drawers": [
                {
                  "skill": "code-review",
                  "drawer": "references/output-contract.md",
                  "hits": 285,
                  "hit_sessions": 285,
                  "scenario_sessions": 388,
                  "scenario_hit_rate": 0.7345,
                  "line_count": 68,
                  "tokens_est": 631,
                  "classification": "hot_drawer",
                  "evolution_action": "Sink repeated command/checklist lines into deterministic script."
                }
              ],
              "on_demand_correction_drawers": [
                {
                  "skill": "code-review",
                  "drawer": "references/reviewer-prompts.md",
                  "hits": 199,
                  "hit_sessions": 199,
                  "scenario_sessions": 388,
                  "scenario_hit_rate": 0.5129,
                  "line_count": 58,
                  "tokens_est": 879,
                  "classification": "on_demand_correction_drawer",
                  "evolution_action": "Healthy runtime progressive disclosure."
                }
              ],
              "true_zero_hit_deadwood": [
                {
                  "skill": "m2-dispatcher",
                  "drawer": "references/runtime-profiles.yaml",
                  "hits": 0,
                  "hit_sessions": 0,
                  "scenario_sessions": 82,
                  "scenario_hit_rate": 0.0,
                  "line_count": 218,
                  "tokens_est": 8428,
                  "classification": "true_zero_hit_deadwood",
                  "evolution_action": "Scenario occurred 82x with 0 reads — candidate for archive/merge."
                }
              ]
            },
            "layer2_script_efficacy_and_speed": {
              "rigid_roadblocks": [
                {"skill": "team-lead", "script": "scripts/ci-monitor.py", "skill_version": "v58@cca4f3d", "total_exit_2_count": 116, "pre_fix_count": 4, "post_fix_count": 112, "failing_command_samples": ["skills/team-lead/scripts/ci-monitor.py"]},
                {"skill": "linear-board", "script": "scripts/linear-sync.py", "total_exit_2_count": 17, "post_fix_count": 17}
              ],
              "watermarked_resolved_roadblocks": [
                {"skill": "linear-board", "script": "scripts/linear-sync.py", "skill_version": "v49@2a7ca3a", "total_exit_2_count": 25, "pre_fix_count": 25, "post_fix_count": 0},
                {"skill": "skill-contract", "script": "scripts/skill_contract.py", "skill_version": "v15@3b4499b", "total_exit_2_count": 11, "pre_fix_count": 11, "post_fix_count": 0}
              ],
              "ceremonial_rubber_stamps": [
                {"skill": "my-designer", "script": "scripts/design_catalog.py", "calls": 25, "co_occurring_skill_escapes": 45, "p50_ms": 212.0}
              ],
              "latency_sinks": [
                {"skill": "team-lead", "script": "scripts/herdr-dispatch.sh", "calls": 1990, "primary_bottleneck": "external_wait", "p50_ms": 6862.0, "p95_ms": 74592.0}
              ]
            },
            "layer3_wild_patterns_and_eval": {
              "wild_patterns": [
                {
                  "pattern_signature": "python3 -c [json:json]",
                  "occurrences": 12,
                  "session_count": 4,
                  "candidate_skill": "aidash-content",
                  "examples": ["python3 -c 'import json'"]
                }
              ]
            },
            "proposals": [
              {
                "id": "skill-retro-l2-roadblock-team-lead-ci-monitor-py",
                "skill": "team-lead",
                "layer": "L2",
                "category": "rigid_roadblock",
                "priority": "P1",
                "rule_id": "RG-001",
                "title": "[Skill Retro L2] 柔化 `team-lead/ci-monitor.py` 参数路障（`exit=2` 触发 112 次）",
                "plain_reason": "`team-lead` 的脚本 `ci-monitor.py` 发生 112 次参数报错（exit=2），需补充兼容参数别名",
                "action": "Add compatible CLI flag aliases to ci-monitor.py",
                "human_what": "柔化 team-lead/ci-monitor.py 参数路障",
                "human_why": "发生 112 次 exit=2 参数报错，需补充兼容参数别名与报错自引导",
                "affected_repos": ["AIDash", "VitalStride"],
                "remediation_commands": [
                  "python3 skills/skill-retro/scripts/skill_retro.py emit-briefs --skill team-lead --emit-briefs ~/Development/handoff/skill-retro-team-lead --json"
                ]
              },
              {
                "id": "skill-retro-pseudo-tests",
                "skill": "tests",
                "layer": "L0",
                "priority": "P3",
                "title": "Should be filtered out"
              }
            ]
          },
          "skills_daily": [
            {"day": "2026-11-22", "source": "copilot-tool", "skill": "team-lead", "n": 18, "sessions": 9},
            {"day": "2026-11-22", "source": "copilot-tool", "skill": "pull", "n": 2, "sessions": 1}
          ]
        }
        """

        let report = try JSONDecoder().decode(SkillsRoiReport.self, from: Data(payloadJSON.utf8))

        // 1. Verify pseudo-skills (`tests`, `leepepe`, `pull`, `main`, `scripts`, `skills`) are completely filtered
        for token in ["tests", "leepepe", "pull", "main", "scripts", "skills"] {
            #expect(SkillsPseudoSkillGuard.isPseudoSkill(token))
            #expect(!report.skillDetails.contains { $0.skill == token })
            #expect(!report.diagnostics.usageRows.contains { $0.skill == token })
            #expect(!report.versionEvolution.contains { $0.skill == token })
            #expect(!report.skillsDaily.contains { $0.skill == token })
            #expect(!report.resolvedSkillRetro.proposals.contains { $0.skill == token })
        }
        #expect(report.skillDetails.map(\.skill) == ["team-lead", "my-designer"])
        #expect(report.versionEvolution.map(\.skill) == ["team-lead", "nas-smart-home"])

        // Verify default .meaningful filter hides 0->0 observing noise rows ("nas-smart-home") while .all reveals all
        let meaningfulRows = SkillsRoiDiagnosticsCardView.filterEvolutionRows(
            report.versionEvolution,
            filter: .meaningful,
            watermarkedSkills: Set(report.resolvedSkillRetro.watermarkedResolvedRoadblocks.map(\.skill))
        )
        #expect(meaningfulRows.map(\.skill) == ["team-lead"])
        let allEvoRows = SkillsRoiDiagnosticsCardView.filterEvolutionRows(
            report.versionEvolution,
            filter: .all
        )
        #expect(allEvoRows.map(\.skill) == ["team-lead", "nas-smart-home"])

        // 2. Verify skill_version_evolution decoding and formatting helpers
        let evo = try #require(report.versionEvolution.first)
        #expect(evo.semver == "1.4.0")
        #expect(evo.skillVersion == "v58@a1b2c3d")
        #expect(evo.combinedVersion == "1.4.0+v58@a1b2c3d")
        #expect(evo.status == "improved")
        #expect(evo.resolvedStatusLabel == "✅ 有效演进")
        #expect(evo.versionTransitionLabel == "v57@6be2fb5 → 1.4.0+v58@a1b2c3d")
        #expect(evo.beforeVersion?.exit2Count == 12)
        #expect(evo.currentVersion.exit2Count == 0)
        #expect(evo.delta.exit2CountDelta == -12)
        #expect(evo.delta.brokenDrawerDelta == -2)
        #expect(evo.versions.count == 2)
        #expect(SkillsRoiDiagnosticsCardView.cleanVersionLabel("1.4.0+v58@a1b2c3d") == "v58")
        #expect(SkillsRoiDiagnosticsCardView.cleanVersionLabel("v57@6be2fb5 → 1.4.0+v58@a1b2c3d") == "v57 → v58")
        let sampled = SkillVersionMetricsSnapshot(skillVersion: "v1", exit2ErrorRate: 0.9, r1Total: 4, r1Pass: 3, r1PassRate: 0.1)
        #expect(SkillsRoiDiagnosticsCardView.r1PassRate(for: sampled) == 0.75)
        let fallback = SkillVersionMetricsSnapshot(skillVersion: "v1", exit2ErrorRate: 0.9, r1PassRate: 0.8)
        #expect(SkillsRoiDiagnosticsCardView.r1PassRate(for: fallback) == 0.8)
        let missing = SkillVersionMetricsSnapshot(skillVersion: "v1", exit2ErrorRate: 0.9)
        #expect(SkillsRoiDiagnosticsCardView.r1PassRate(for: missing) == nil)
        let outOfRange = SkillVersionMetricsSnapshot(skillVersion: "v1", r1PassRate: 1e100)
        #expect(SkillsRoiDiagnosticsCardView.r1PassRate(for: outOfRange) == nil)
        let nonFinite = SkillVersionMetricsSnapshot(skillVersion: "v1", r1PassRate: .infinity)
        #expect(SkillsRoiDiagnosticsCardView.r1PassRate(for: nonFinite) == nil)

        // 3. Verify skill_retro 4-layer health summary & proposal decoding
        let retro = report.resolvedSkillRetro
        #expect(retro.sampleSize == 1868)
        #expect(retro.slowFlywheelReady == true)
        #expect(retro.triggerMissSkills == 4)
        #expect(retro.zeroActionLoadSkills == 5)
        #expect(retro.directionalDrifts == 25)
        #expect(retro.unwiredDrawersCount == 1)
        #expect(retro.trueDeadwoodDrawersCount == 3)
        #expect(retro.trueCatcherScriptsCount == 41)
        #expect(retro.rigidRoadblockScriptsCount == 17)
        #expect(retro.exit2RoadblockTotalCount == 129)
        #expect(retro.latencySinkScriptsCount == 13)
        #expect(retro.wildPatternsCount == 5)
        #expect(retro.triggerMisses.count == 1)
        #expect(retro.triggerMisses.first?.skill == "my-designer")
        #expect(retro.triggerMisses.first?.missedSessions == 223)
        #expect(retro.triggerMisses.first?.samples.first?.sessionId == "04b1852a-2d6")
        #expect(retro.zeroActionLoads.count == 1)
        #expect(retro.hotDrawers.count == 1)
        #expect(retro.onDemandDrawers.count == 1)
        #expect(retro.trueZeroHitDeadwood.count == 1)
        #expect(retro.rigidRoadblocks.first?.totalExit2Count == 116)
        #expect(retro.rigidRoadblocks.first?.preFixCount == 4)
        #expect(retro.rigidRoadblocks.first?.postFixCount == 112)
        #expect(retro.watermarkedResolvedRoadblocks.count == 2)
        #expect(retro.watermarkedResolvedRoadblocks.first?.preFixCount == 25)
        #expect(retro.watermarkedResolvedRoadblocks.first?.postFixCount == 0)
        #expect(retro.ceremonialRubberStamps.count == 1)
        #expect(retro.latencySinks.count == 1)
        #expect(retro.crossRepoGateHealth?.reposScanned == 16)
        #expect(retro.crossRepoGateHealth?.driftedReposCount == 11)
        #expect(retro.wildPatterns.count == 1)
        #expect(retro.proposals.count == 1)
        let prop = try #require(retro.proposals.first)
        #expect(prop.layer == "L2")
        #expect(prop.priority == "P1")
        #expect(prop.ruleId == "RG-001")
        #expect(prop.affectedRepos == ["AIDash", "VitalStride"])
        #expect(prop.displayTitle == "柔化 team-lead/ci-monitor.py 参数路障")
        #expect(prop.primaryRemediationCommand.contains("skill_retro.py emit-briefs --skill team-lead"))

        // 4. Verify rendering of the 5-level progressive disclosure workbench + inspector evolution sub-tab and zero bare S1..S12 codes
        let summary = LiveDashboardTelemetryReader.LiveEfficiencySummary(skillsROI: report)
        let recorder = DashboardGeometryRecorder()
        let workbenchView = SkillsRoiDiagnosticsCardView(
            summary: summary,
            initialLens: .evolution,
            initialSelectedSkill: "team-lead",
            initialSelectedPillar: .l2,
            initialSubTab: .evolution
        )
        .frame(width: 1120)
        .padding(16)
        .background(Color(nsColor: .underPageBackgroundColor))
        .environment(\.colorScheme, .dark)
        .environment(\.theme, Theme(isDark: true))
        .environment(\.dashboardGeometryRecorder, recorder)
        .coordinateSpace(name: "tk3-geometry")

        let bmp = try toolbarHeaderBitmap(for: workbenchView, scheme: .dark)
        #expect(bmp.pixelsWide >= 1000)
        #expect(bmp.pixelsHigh >= 300)

        let recordedIDs = Set(recorder.samples.map(\.id))
        #expect(recordedIDs.contains("skills-p0-vitals"))
        #expect(!recordedIDs.contains("skills-table-header"))
        #expect(!recordedIDs.contains("skills-status-stage"))
        #expect(!recordedIDs.contains("skills-four-layer-pulse"))
        #expect(!recordedIDs.contains("skills-inspector-detail"))
        #expect(!recordedIDs.contains("skills-primary-detail"))
        #expect(!recordedIDs.contains("inspector-collapse"))

        // The three lenses share one stage and never render the obsolete workbench.
        for lens in SkillsRoiLens.allCases {
            let lensRecorder = DashboardGeometryRecorder()
            let view = SkillsRoiDiagnosticsCardView(summary: summary, initialLens: lens)
                .frame(width: 1120).environment(\.theme, Theme(isDark: true))
                .environment(\.dashboardGeometryRecorder, lensRecorder)
            _ = try toolbarHeaderBitmap(for: view, scheme: .dark)
            let lensIDs = Set(lensRecorder.samples.map(\.id))
            #expect(!lensIDs.contains("skills-four-layer-pulse"))
            #expect(!lensIDs.contains("skills-inspector-detail"))
            #expect(!lensIDs.contains("inspector-file-skill-md"))
            #expect(!lensIDs.contains("skills-primary-detail"))
        }

        let bareAcademicRegex = try NSRegularExpression(pattern: #"\bS(?:[1-9]|1[0-2])\b"#)
        for text in [prop.displayTitle, prop.displayReason, evo.resolvedStatusLabel] {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            #expect(bareAcademicRegex.firstMatch(in: text, range: range) == nil)
        }

        // Verify that when skill_version_evolution is absent in older fixtures, versionEvolution stays empty (no fabricated v1@head / improved / P50 metrics)
        let canonical = try JSONDecoder().decode(SkillsRoiReport.self, from: TK3Fixtures.canonical())
        #expect(canonical.versionEvolution.isEmpty)
        #expect(canonical.skillRetro == nil)
        #expect(canonical.resolvedSkillRetro.proposals.isEmpty)

        // 5. Export 4 states x 2 appearances PNGs when AIDASH_WORKBENCH_V2_SCREENSHOT_DIR is set
        let env = ProcessInfo.processInfo.environment
        if let shotDirPath = [
            env["AIDASH_WORKBENCH_V2_SCREENSHOT_DIR"],
            env["TEST_RUNNER_AIDASH_WORKBENCH_V2_SCREENSHOT_DIR"]
        ].compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) {
            let shotDir = URL(fileURLWithPath: shotDirPath, isDirectory: true)
            try FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)

            let partialJSON = payloadJSON.replacingOccurrences(of: "\"coverage_status\": \"healthy\"", with: "\"coverage_status\": \"partial\"")
            let degradedJSON = payloadJSON.replacingOccurrences(of: "\"coverage_status\": \"healthy\"", with: "\"coverage_status\": \"error\"")
            let partialReport = try JSONDecoder().decode(SkillsRoiReport.self, from: Data(partialJSON.utf8))
            let degradedReport = try JSONDecoder().decode(SkillsRoiReport.self, from: Data(degradedJSON.utf8))

            let states: [(String, LiveDashboardTelemetryReader.LiveEfficiencySummary?)] = [
                ("populated", summary),
                ("partial", .init(skillsROI: partialReport)),
                ("degraded", .init(skillsROI: degradedReport)),
                ("empty", nil)
            ]
            for (stateName, stateSummary) in states {
                for scheme in [ColorScheme.light, ColorScheme.dark] {
                    let appearance = scheme == .dark ? "dark" : "light"
                    let v = SkillsRoiDiagnosticsCardView(
                        summary: stateSummary,
                        initialLens: .usage,
                        initialSelectedSkill: "team-lead",
                        initialSubTab: .evolution
                    )
                    .frame(width: 1120)
                    .padding(16)
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .environment(\.colorScheme, scheme)
                    .environment(\.theme, Theme(isDark: scheme == .dark))
                    let stateBmp = try toolbarHeaderBitmap(for: v, scheme: scheme)
                    if let png = stateBmp.representation(using: .png, properties: [:]) {
                        try png.write(to: shotDir.appendingPathComponent("skills-workbench-v2-\(stateName)-\(appearance).png"))
                    }
                }
            }
        }
    }
}
#endif
