#if os(macOS)
import Foundation
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
        #expect(LiveDashboardTelemetryReader.sanitizeSQLToken("2026-11-07") == "2026-11-07")
        _ = MenuBarStatusView(state: .populated(sampleSnapshot())).body
    }
}
#endif
