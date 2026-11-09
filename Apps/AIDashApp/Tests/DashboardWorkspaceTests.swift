#if os(macOS)
import Foundation
import SQLite3
import SwiftUI
import Testing
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
        #expect(store.cliEntries.filter(\.hasTrackedQuota).count == 2)
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
        #expect(OverviewWorkbenchLens.allCases.count == 3)
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
        #expect(refreshedKimi.quotaLabel == nil)
        #expect(refreshedKimi.health == .healthy)

        _ = CLICostQuotaCardView(entries: dataset.entries, todayTotalUSD: 0, periodTotalUSD: 0).body
    }

    @Test("one-click terminal login command validation, sidebar footer sections, and tail-read telemetry caching work as specified")
    func terminalLoginSidebarFooterAndTelemetryTailCache() throws {
        #expect(DashboardWorkspaceSection.primaryNavigationSections == [
            .overview,
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

        #expect(CLITerminalLoginLauncher.launchLoginInTerminal(command: "claude login") == true)
        #expect(CLITerminalLoginLauncher.launchLoginInTerminal(command: "invalid && bad") == false)
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("aidash-cli-login.command")
        let scriptText = try String(contentsOf: scriptURL, encoding: .utf8)
        #expect(scriptText.contains("claude login"))

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
}
#endif
