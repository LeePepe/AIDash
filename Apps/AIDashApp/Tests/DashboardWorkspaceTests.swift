#if os(macOS)
import AppKit
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

    @Test("Top toolbar header clusters are single-layer without nested capsule backgrounds or bordered bezels")
    func topToolbarHeaderClustersAreSingleLayerAndRenderSnapshots() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Scenes/AIDashMacWorkspaceView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let clusterStart = try #require(source.range(of: "internal var unifiedDateNavigationToolbarCluster"))
        let clusterEnd = try #require(source.range(of: "    private var sidebarContent", range: clusterStart.upperBound..<source.endIndex))
        let toolbarSource = String(source[clusterStart.lowerBound..<clusterEnd.lowerBound])
        #expect(!toolbarSource.contains(".background("))
        #expect(!toolbarSource.contains("Capsule()"))
        #expect(!toolbarSource.contains(".buttonStyle(.bordered)"))
        #expect(toolbarSource.contains(".buttonStyle(.borderless)"))
        #expect(toolbarSource.contains("Divider()"))
        #expect(toolbarSource.contains(".padding(.horizontal, 6)"))

        let configuredOutput = ProcessInfo.processInfo.environment["AIDASH_HEADER_SCREENSHOT_DIR"]
            .map(URL.init(fileURLWithPath:))
        let output = configuredOutput ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-header-flat-toolbar", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let states: [(String, MenuBarSystemSnapshot?)] = [
            ("populated", sampleSnapshot()),
            ("no-snapshot", nil),
            ("high-values", sampleSnapshot()),
            ("long-localized-copy", sampleSnapshot())
        ]
        var geometry: [[String: Any]] = []
        for (state, snapshot) in states {
            let view = snapshot.map { AIDashMacWorkspaceView(store: DashboardWorkspaceStore(snapshot: $0)) }
                ?? AIDashMacWorkspaceView(store: DashboardWorkspaceStore(deferInitialRefresh: true))
            for scheme in [ColorScheme.light, ColorScheme.dark] {
                let appearance = scheme == .dark ? "dark" : "light"
                let standalone = view.toolbarHeaderComparisonPreview(snapshot: snapshot)
                    .padding(12)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme)
                    .environment(\.theme, Theme(isDark: scheme == .dark))
                let platter = view.toolbarHeaderComparisonPreview(snapshot: snapshot)
                    .padding(12)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.7), in: Capsule())
                    .padding(12)
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .environment(\.colorScheme, scheme)
                    .environment(\.theme, Theme(isDark: scheme == .dark))
                for (kind, renderable) in [("standalone", AnyView(standalone)), ("single-platter-simulation", AnyView(platter))] {
                    let renderer = ImageRenderer(content: renderable)
                    renderer.scale = 2
                    let image = try #require(renderer.nsImage)
                    let tiff = try #require(image.tiffRepresentation)
                    let bitmap = try #require(NSBitmapImageRep(data: tiff))
                    let png = try #require(bitmap.representation(using: .png, properties: [:]))
                    let file = output.appendingPathComponent("toolbar-header-\(state)-\(kind)-\(appearance).png")
                    try png.write(to: file)
                    #expect(png.isEmpty == false)
                    #expect(bitmap.pixelsWide > 0)
                    #expect(bitmap.pixelsHigh > 0)
                    geometry.append(["state": state, "kind": kind, "appearance": appearance, "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh])
                }
            }
        }
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
        #expect(OverviewWorkbenchLens.allCases.count == 4)
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
            .scheduledPulse,
            .agentEfficiency,
            .actionItems,
            .systemAndCosts
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
}
#endif
