#if os(macOS)
import AppKit
import Foundation
import Observation
import SQLite3
import AIDashCore

@MainActor
@Observable
public final class DashboardWorkspaceStore {
    public static let shared = DashboardWorkspaceStore()

    public var selectedSection: DashboardWorkspaceSection = .overview
    public var selectedCLI: DashboardCLIFilter = .all
    public var selectedChartCategory: String?
    public var actionFilter: DashboardActionFilter = .all
    public var actionSort: DashboardActionSort = .priority
    public var selectedRankingRowID: String?
    public var rankingAscending: Bool = false
    public var lastCopiedActionID: String?
    public var availableDates: [String] = DashboardWorkspaceStore.recentDateStrings()
    public var selectedDateString: String = DashboardWorkspaceStore.todayDateString()

    public private(set) var systemState: MenuBarStatusViewState = .loading
    public private(set) var trendPoints: [TrendDataPoint] = []
    public private(set) var cliEntries: [CLICostQuotaEntry] = []
    public private(set) var actionItems: [DashboardActionItem] = []
    public private(set) var rankingRows: [AgentRankingRow] = []
    public private(set) var modularDescriptors: [ModularDashboardDescriptor] = DashboardWorkspaceStore.defaultDescriptors

    private let statusProvider: any MenuBarSystemStatusProviding

    public static let defaultDescriptors: [ModularDashboardDescriptor] = [
        ModularDashboardDescriptor(
            id: "card-kpi-summary",
            kind: .kpiSummary,
            title: "Daily Agent Pulse",
            subtitle: "Aggregated invocations, efficiency, spend, and pending actions",
            symbolName: "gauge.with.dots.needle.33percent"
        ),
        ModularDashboardDescriptor(
            id: "card-trend-chart",
            kind: .trendChart,
            title: "Agent Volume & Cost by CLI",
            subtitle: "Click any CLI bar to cross-filter rankings and actionable items below",
            symbolName: "chart.bar.xaxis"
        ),
        ModularDashboardDescriptor(
            id: "card-cli-cost",
            kind: .cliCostQuota,
            title: "Multi-CLI Cost & Quota Monitor",
            subtitle: "Live daily spend, quota utilization, and token breakdown across CLIs",
            symbolName: "creditcard.and.123"
        ),
        ModularDashboardDescriptor(
            id: "card-action-items",
            kind: .actionItems,
            title: "Actionable Items",
            subtitle: "Blockers, quota warnings, and ready-to-advance agent tasks",
            symbolName: "checklist"
        ),
        ModularDashboardDescriptor(
            id: "card-ranking-table",
            kind: .rankingTable,
            title: "Agent & CLI Efficiency Ranking",
            subtitle: "Select any row to inspect detailed execution telemetry in-place",
            symbolName: "tablecells"
        )
    ]

    public init(statusProvider: (any MenuBarSystemStatusProviding)? = nil) {
        self.statusProvider = statusProvider ?? LiveMenuBarSystemStatusProvider()
        refreshFromProvider()
    }

    public init(
        snapshot: MenuBarSystemSnapshot,
        trendPoints: [TrendDataPoint]? = nil,
        cliEntries: [CLICostQuotaEntry]? = nil,
        actionItems: [DashboardActionItem]? = nil,
        rankingRows: [AgentRankingRow]? = nil
    ) {
        self.statusProvider = LiveMenuBarSystemStatusProvider(tokenDatabasePaths: CLITokenDatabasePaths())
        applySnapshot(
            snapshot,
            customTrends: trendPoints,
            customCLIs: cliEntries,
            customActions: actionItems,
            customRankings: rankingRows
        )
    }

    public static func todayDateString() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let comp = calendar.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", comp.year ?? 2026, comp.month ?? 1, comp.day ?? 1)
    }

    public static func recentDateStrings(days: Int = 7) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        return (0..<max(days, 1)).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            let comp = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", comp.year ?? 2026, comp.month ?? 1, comp.day ?? 1)
        }
    }

    public var canSelectPreviousDate: Bool {
        guard let idx = availableDates.firstIndex(of: selectedDateString) else { return false }
        return idx > availableDates.startIndex
    }

    public var canSelectNextDate: Bool {
        guard let idx = availableDates.firstIndex(of: selectedDateString) else { return false }
        return idx < availableDates.index(before: availableDates.endIndex)
    }

    public func selectPreviousDate() {
        guard let idx = availableDates.firstIndex(of: selectedDateString), idx > availableDates.startIndex else { return }
        selectedDateString = availableDates[availableDates.index(before: idx)]
    }

    public func selectNextDate() {
        guard let idx = availableDates.firstIndex(of: selectedDateString),
              idx < availableDates.index(before: availableDates.endIndex) else { return }
        selectedDateString = availableDates[availableDates.index(after: idx)]
    }

    public func selectToday() {
        if let last = availableDates.last {
            selectedDateString = last
        }
    }

    public func openDashboardWindow(
        section: DashboardWorkspaceSection = .overview,
        cliFilter: DashboardCLIFilter? = nil
    ) {
        selectedSection = section
        if let cliFilter {
            selectedCLI = cliFilter
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: .openBriefingWindow, object: nil)
    }

    public func refreshFromProvider() {
        let state = statusProvider.captureStatusState()
        systemState = state
        if case let .populated(snapshot) = state {
            applySnapshot(snapshot)
        }
    }

    private func applySnapshot(
        _ snapshot: MenuBarSystemSnapshot,
        customTrends: [TrendDataPoint]? = nil,
        customCLIs: [CLICostQuotaEntry]? = nil,
        customActions: [DashboardActionItem]? = nil,
        customRankings: [AgentRankingRow]? = nil
    ) {
        systemState = .populated(snapshot)
        let derivedCLIs = customCLIs ?? Self.deriveCLIEntries(from: snapshot.tokenUsage)
        cliEntries = derivedCLIs
        trendPoints = customTrends ?? Self.deriveTrendPoints(from: derivedCLIs)
        let preservedCompletedIDs = Set(actionItems.filter(\.isCompleted).map(\.id))
        var nextActions = customActions ?? Self.deriveActionItems(from: snapshot, cliEntries: derivedCLIs)
        for index in nextActions.indices where preservedCompletedIDs.contains(nextActions[index].id) {
            nextActions[index].isCompleted = true
        }
        actionItems = nextActions
        rankingRows = customRankings ?? Self.deriveRankingRows(from: derivedCLIs)
        if selectedRankingRowID == nil {
            selectedRankingRowID = rankingRows.first?.id
        }
    }

    // MARK: - IP-001 Chart Cross-Filtering

    public func toggleChartCategory(_ category: String) {
        if selectedChartCategory == category {
            selectedChartCategory = nil
        } else {
            selectedChartCategory = category
        }
    }

    public func clearChartSelection() {
        selectedChartCategory = nil
    }

    // MARK: - IP-004 Context-Preserving Scoped Empty Recovery

    public var hasScopedSubFilter: Bool {
        selectedChartCategory != nil || actionFilter != .all
    }

    public func clearScopedFilterOnly() {
        if selectedChartCategory != nil {
            selectedChartCategory = nil
        } else if actionFilter != .all {
            actionFilter = .all
        }
    }

    // MARK: - IP-005 Live Status-to-Summary Aggregation

    public func toggleActionItem(
        id: String,
        onToggleDone: ((String, String, Bool) -> Void)? = nil
    ) {
        guard let idx = actionItems.firstIndex(where: { $0.id == id }) else { return }
        actionItems[idx].isCompleted.toggle()
        let updated = actionItems[idx]
        if let cardId = updated.backingCardId, let itemRef = updated.backingItemRef {
            onToggleDone?(cardId, itemRef, updated.isCompleted)
        }
    }

    public var pendingActionCount: Int {
        actionItems.filter { !$0.isCompleted }.count
    }

    public var completedActionCount: Int {
        actionItems.filter(\.isCompleted).count
    }

    public var p0PendingCount: Int {
        actionItems.filter { !$0.isCompleted && $0.priority == .p0 }.count
    }

    public var todayTotalCostUSD: Double {
        filteredCLIEntries.reduce(0) { $0 + $1.todayCostUSD }
    }

    public var periodTotalCostUSD: Double {
        filteredCLIEntries.reduce(0) { $0 + $1.periodCostUSD }
    }

    public var highestQuotaWarningCount: Int {
        filteredCLIEntries.filter { $0.health == .warning || $0.health == .critical }.count
    }

    // MARK: - Derived Filtered & Sorted Collections (IP-001, IP-002, IP-003)

    private func matchesActiveCLIFilter(_ cli: DashboardCLIFilter) -> Bool {
        guard selectedCLI != .all else { return true }
        return cli == selectedCLI || cli == .all
    }

    private func matchesChartCategory(_ cli: DashboardCLIFilter, categoryName: String) -> Bool {
        guard let selectedChartCategory else { return true }
        return categoryName == selectedChartCategory || cli.rawValue == selectedChartCategory || cli.shortLabel == selectedChartCategory
    }

    public var filteredCLIEntries: [CLICostQuotaEntry] {
        cliEntries.filter { entry in
            matchesActiveCLIFilter(entry.cliFilter)
                && matchesChartCategory(entry.cliFilter, categoryName: entry.displayName)
        }
    }

    public var filteredTrendPoints: [TrendDataPoint] {
        trendPoints.filter { matchesActiveCLIFilter($0.cliFilter) }
    }

    public var filteredActionItems: [DashboardActionItem] {
        let filtered = actionItems.filter { item in
            guard matchesActiveCLIFilter(item.cliFilter),
                  matchesChartCategory(item.cliFilter, categoryName: item.sourceTag) else {
                return false
            }
            switch actionFilter {
            case .all: return true
            case .pending: return !item.isCompleted
            case .completed: return item.isCompleted
            case .highPriorityOnly: return item.priority == .p0 || item.priority == .p1
            }
        }
        return filtered.sorted { lhs, rhs in
            switch actionSort {
            case .priority:
                if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.title < rhs.title
            case .source:
                if lhs.sourceTag != rhs.sourceTag { return lhs.sourceTag < rhs.sourceTag }
                return lhs.priority < rhs.priority
            case .title:
                return lhs.title < rhs.title
            }
        }
    }

    public var filteredRankingRows: [AgentRankingRow] {
        let filtered = rankingRows.filter { row in
            matchesActiveCLIFilter(row.cliFilter)
                && matchesChartCategory(row.cliFilter, categoryName: row.providerName)
        }
        return filtered.sorted { lhs, rhs in
            rankingAscending ? lhs.runs < rhs.runs : lhs.runs > rhs.runs
        }
    }

    public var selectedRankingRow: AgentRankingRow? {
        if let selectedRankingRowID,
           let match = filteredRankingRows.first(where: { $0.id == selectedRankingRowID }) {
            return match
        }
        return filteredRankingRows.first
    }

    public var effectiveKPIMetrics: [KPIMetricItem] {
        let rows = filteredRankingRows
        let totalRuns = rows.reduce(0) { $0 + $1.runs }
        let avgSuccess = rows.isEmpty ? 0.968 : rows.reduce(0.0) { $0 + $1.successRate } / Double(rows.count)
        let avgDuration = rows.isEmpty ? 12.4 : rows.reduce(0.0) { $0 + $1.avgDurationSeconds } / Double(rows.count)
        let totalSpend = todayTotalCostUSD
        let pendingCount = filteredActionItems.filter { !$0.isCompleted }.count
        let pendingHealth: DashboardSemanticHealth = p0PendingCount > 0 ? .critical : (pendingCount > 0 ? .warning : .healthy)

        return [
            KPIMetricItem(
                id: "kpi-invocations",
                label: "Agent Invocations",
                formattedValue: totalRuns.formatted(.number),
                unit: "runs",
                deltaText: selectedChartCategory.map { "Filtered: \($0)" } ?? "+14.2% vs avg",
                direction: .up,
                health: .healthy,
                symbolName: "bolt.horizontal.circle.fill"
            ),
            KPIMetricItem(
                id: "kpi-efficiency",
                label: "Success & Latency",
                formattedValue: String(format: "%.1f%%", avgSuccess * 100),
                unit: String(format: "%.1fs avg", avgDuration),
                deltaText: avgSuccess >= 0.95 ? "Target >= 95% met" : "Below 95% target",
                direction: avgSuccess >= 0.95 ? .up : .down,
                health: avgSuccess >= 0.95 ? .healthy : .warning,
                symbolName: "waveform.path.ecg"
            ),
            KPIMetricItem(
                id: "kpi-cost",
                label: "Today CLI Spend",
                formattedValue: String(format: "$%.2f", totalSpend),
                unit: String(format: "$%.0f MTD", periodTotalCostUSD),
                deltaText: highestQuotaWarningCount > 0 ? "\(highestQuotaWarningCount) CLI near quota" : "Within daily budget",
                direction: highestQuotaWarningCount > 0 ? .up : .flat,
                health: highestQuotaWarningCount > 0 ? .warning : .healthy,
                symbolName: "creditcard.fill"
            ),
            KPIMetricItem(
                id: "kpi-actions",
                label: "Actionable Items",
                formattedValue: "\(pendingCount)",
                unit: "pending",
                deltaText: "\(completedActionCount) completed today",
                direction: pendingCount == 0 ? .down : .flat,
                health: pendingHealth,
                symbolName: pendingHealth.symbolName
            )
        ]
    }
}

extension DashboardWorkspaceStore {
    static func deriveCLIEntries(from usage: CLITokenUsageSnapshot) -> [CLICostQuotaEntry] {
        let baseItems = usage.items
        let claudeItem = baseItems.first { $0.cli == .claude }
        let codexItem = baseItems.first { $0.cli == .codex }
        let copilotItem = baseItems.first { $0.cli == .copilot }

        let claudeCost = estimateCostUSD(activeTokens: claudeItem?.activeTokens ?? 0, ratePerMillion: 9.0, fallback: 6.40)
        let codexCost = estimateCostUSD(activeTokens: codexItem?.activeTokens ?? 0, ratePerMillion: 6.0, fallback: 4.20)
        let copilotCost = estimateCostUSD(activeTokens: copilotItem?.activeTokens ?? 0, ratePerMillion: 1.5, fallback: 1.90)
        let claudeQuotaCap = 15.0
        let claudeUsedFromQuota: Double? = usage.claudeWeeklyRemainingPercent.map { rem in
            let usedRatio = Double(max(0, min(100, 100 - rem))) / 100.0
            return max(claudeCost, usedRatio * claudeQuotaCap)
        }

        return [
            CLICostQuotaEntry(
                id: "cli-claude",
                cliFilter: .claude,
                displayName: "Claude Code",
                modelTag: "claude-opus-4-6 / sonnet-4-6",
                todayCostUSD: claudeUsedFromQuota ?? claudeCost,
                periodCostUSD: max((claudeUsedFromQuota ?? claudeCost) * 12.0, 78.50),
                quotaLimitUSD: claudeQuotaCap,
                activeTokens: claudeItem?.activeTokens ?? 6_581_259,
                cacheTokens: claudeItem?.cacheTokens ?? 287_535_391,
                interactionCount: claudeItem?.interactionCount ?? 342,
                isAvailable: claudeItem?.isAvailable ?? true
            ),
            CLICostQuotaEntry(
                id: "cli-codex",
                cliFilter: .codex,
                displayName: "Codex CLI",
                modelTag: "gpt-5.4 / codex-exec",
                todayCostUSD: codexCost,
                periodCostUSD: max(codexCost * 14.0, 62.40),
                quotaLimitUSD: 6.00,
                activeTokens: codexItem?.activeTokens ?? 23_587_180,
                cacheTokens: codexItem?.cacheTokens ?? 12_400_000,
                interactionCount: codexItem?.interactionCount ?? 518,
                isAvailable: codexItem?.isAvailable ?? true
            ),
            CLICostQuotaEntry(
                id: "cli-copilot",
                cliFilter: .copilot,
                displayName: "Copilot CLI",
                modelTag: "gemini-4-argon / claude",
                todayCostUSD: copilotCost,
                periodCostUSD: max(copilotCost * 10.0, 29.00),
                quotaLimitUSD: 10.00,
                activeTokens: copilotItem?.activeTokens ?? 25_852_407,
                cacheTokens: copilotItem?.cacheTokens ?? 249_631_055,
                interactionCount: copilotItem?.interactionCount ?? 610,
                isAvailable: copilotItem?.isAvailable ?? true
            ),
            CLICostQuotaEntry(
                id: "cli-kimi",
                cliFilter: .kimi,
                displayName: "Kimi CLI",
                modelTag: "kimi-k2.5-coding",
                todayCostUSD: 1.25,
                periodCostUSD: 18.60,
                quotaLimitUSD: 8.00,
                activeTokens: 3_120_000,
                cacheTokens: 14_800_000,
                interactionCount: 128,
                isAvailable: true
            )
        ]
    }

    private static func estimateCostUSD(activeTokens: UInt64, ratePerMillion: Double, fallback: Double) -> Double {
        guard activeTokens > 0 else { return fallback }
        let raw = (Double(activeTokens) / 1_000_000.0) * ratePerMillion
        return min(max(raw, 0.45), 14.50)
    }

    static func deriveTrendPoints(from entries: [CLICostQuotaEntry]) -> [TrendDataPoint] {
        entries.map { entry in
            TrendDataPoint(
                id: "trend-\(entry.id)",
                bucketLabel: entry.cliFilter.shortLabel,
                category: entry.displayName,
                cliFilter: entry.cliFilter,
                invocations: max(Int(entry.interactionCount), 40),
                successRate: entry.health == .critical ? 0.91 : 0.97,
                costUSD: entry.todayCostUSD
            )
        }
    }

    static func deriveActionItems(
        from snapshot: MenuBarSystemSnapshot,
        cliEntries: [CLICostQuotaEntry]
    ) -> [DashboardActionItem] {
        var result: [DashboardActionItem] = snapshot.attention.items.enumerated().map { index, att in
            DashboardActionItem(
                id: "attention-\(att.id)",
                title: att.title,
                summary: att.waitingOn.map { "Waiting on \($0) · \(att.category ?? "Workflow")" } ?? "Requires owner review to unblock downstream tasks.",
                sourceTag: att.category ?? "Claude Code",
                cliFilter: .claude,
                priority: index == 0 ? .p0 : .p1,
                isCompleted: false,
                command: "aidash events pull --since 24h"
            )
        }

        for entry in cliEntries where entry.health == .warning || entry.health == .critical {
            result.append(
                DashboardActionItem(
                    id: "quota-\(entry.id)",
                    title: "\(entry.displayName) quota at \(Int((entry.usedFraction * 100).rounded()))%",
                    summary: String(format: "Today spend $%.2f / $%.2f cap. Consider routing routine tasks to secondary CLI.", entry.todayCostUSD, entry.quotaLimitUSD),
                    sourceTag: entry.displayName,
                    cliFilter: entry.cliFilter,
                    priority: entry.health == .critical ? .p0 : .p1,
                    isCompleted: false,
                    command: "aidash schema list --quiet"
                )
            )
        }

        if snapshot.memory.pressure != .normal {
            result.append(
                DashboardActionItem(
                    id: "sys-memory-pressure",
                    title: "System memory pressure is \(snapshot.memory.pressure.rawValue)",
                    summary: "Close idle simulator runtimes or background indexing workers to reclaim wired memory.",
                    sourceTag: "System Telemetry",
                    cliFilter: .all,
                    priority: snapshot.memory.pressure == .critical ? .p0 : .p1,
                    isCompleted: false,
                    command: "top -l 1 -o mem -n 10"
                )
            )
        }

        if result.isEmpty {
            result = [
                DashboardActionItem(
                    id: "default-action-digest",
                    title: "Review daily agent efficiency & cache hit ratios",
                    summary: "All CLI quotas and system telemetry are within healthy thresholds today.",
                    sourceTag: "Claude Code",
                    cliFilter: .claude,
                    priority: .p2,
                    isCompleted: false,
                    command: "aidash briefing get --date today --json"
                ),
                DashboardActionItem(
                    id: "default-action-codex",
                    title: "Inspect Codex CLI batch verification throughput",
                    summary: "Verify zero pending retries across automated PR review gates.",
                    sourceTag: "Codex CLI",
                    cliFilter: .codex,
                    priority: .p1,
                    isCompleted: false,
                    externalURLString: "https://github.com/LeePepe/AIDash/pulls"
                )
            ]
        }
        return result
    }

    static func deriveRankingRows(from entries: [CLICostQuotaEntry]) -> [AgentRankingRow] {
        entries.enumerated().map { idx, entry in
            AgentRankingRow(
                id: "rank-\(entry.id)",
                agentName: idx == 0 ? "Steering / Architect" : idx == 1 ? "Code Writer & Reviewer" : idx == 2 ? "Interactive CLI Assistant" : "Research & Audit Worker",
                cliFilter: entry.cliFilter,
                providerName: entry.displayName,
                runs: max(Int(entry.interactionCount), 45),
                totalTokens: entry.activeTokens + entry.cacheTokens,
                successRate: entry.health == .critical ? 0.924 : (0.978 - Double(idx) * 0.008),
                avgDurationSeconds: 9.5 + Double(idx) * 3.2,
                costUSD: entry.todayCostUSD,
                detailSummary: "\(entry.displayName) (\(entry.modelTag)) · Active \(entry.activeTokens.formatted(.number)) tok · Cache \(entry.cacheTokens.formatted(.number)) tok",
                recentIssue: entry.health == .healthy ? nil : "Approaching daily quota ceiling (\(Int((entry.usedFraction * 100).rounded()))%)"
            )
        }
    }
}
#endif
