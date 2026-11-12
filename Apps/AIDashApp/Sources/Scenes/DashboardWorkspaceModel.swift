#if os(macOS)
// swiftlint:disable file_length
import AppKit
import Darwin
import Foundation
import Observation
import SQLite3
import SwiftUI
import AIDashCore

@MainActor
@Observable
// swiftlint:disable:next type_body_length
public final class DashboardWorkspaceStore {
    private static var _sharedInstance: DashboardWorkspaceStore?
    public static var shared: DashboardWorkspaceStore {
        if let existing = _sharedInstance {
            return existing
        }
        let created = DashboardWorkspaceStore(deferInitialRefresh: true)
        _sharedInstance = created
        created.refreshFromProvider()
        return created
    }

    public var selectedSection: DashboardWorkspaceSection = .overview
    public var selectedCLI: DashboardCLIFilter = .all
    public var selectedChartCategory: String?
    public var actionFilter: DashboardActionFilter = .all
    public var selectedLinearActionFilter: String = "all"
    public var actionSort: DashboardActionSort = .priority
    public var selectedRankingRowID: String?
    public var rankingAscending: Bool = false
    public var lastCopiedActionID: String?
    public var lastDispatchedActionID: String?
    public var selectedScheduledJobID: ScheduledPulseJobID?
    public var scheduledPulseSchedulerFilter: ScheduledPulseSchedulerFilter = .all
    public var scheduledPulseHealthFilter: ScheduledPulseHealthFilter = .all
    public var lastCopiedScheduledJobID: ScheduledPulseJobID?
    public var scheduledPulseTab: ScheduledPulsePageTab = .overview
    public var selectedFrameworkJobID: ScheduledPulseJobID?
    public var scheduledActionWriter: ((ScheduledJobAction, [ScheduledJobActionResponse]) -> Bool)?
    public var acknowledgedScheduledActionIDs: Set<String> = [] {
        didSet {
            guard oldValue != acknowledgedScheduledActionIDs else { return }
            let entries = scheduledJobFrameworkSnapshot.entries.map { entry in
                ScheduledJobFrameworkEntry(
                    definition: entry.definition,
                    state: entry.state,
                    actions: entry.actions.filter { !$0.isAcknowledged(in: acknowledgedScheduledActionIDs) }
                )
            }
            scheduledJobFrameworkSnapshot = ScheduledJobFrameworkSnapshot(
                capturedAt: scheduledJobFrameworkSnapshot.capturedAt,
                entries: entries
            )
            for idx in actionItems.indices {
                if let ackKey = actionItems[idx].acknowledgementKey,
                   acknowledgedScheduledActionIDs.contains(ackKey) {
                    actionItems[idx].isCompleted = true
                    actionItems[idx].status = .done
                }
            }
        }
    }
    public var availableDates: [String] = DashboardWorkspaceStore.recentDateStrings()
    public var selectedDateString: String = DashboardWorkspaceStore.todayDateString()

    public private(set) var systemState: MenuBarStatusViewState = .loading
    public private(set) var trendPoints: [TrendDataPoint] = []
    public private(set) var cliEntries: [CLICostQuotaEntry] = []
    public private(set) var actionItems: [DashboardActionItem] = []
    public private(set) var rankingRows: [AgentRankingRow] = []
    public private(set) var liveEfficiencySummary: LiveDashboardTelemetryReader.LiveEfficiencySummary?
    public private(set) var scheduledPulseSnapshot: ScheduledPulseSnapshot = .defaultSnapshot()
    public private(set) var scheduledJobFrameworkSnapshot: ScheduledJobFrameworkSnapshot = .init(capturedAt: Date(), entries: [])
    public private(set) var modularDescriptors: [ModularDashboardDescriptor] = DashboardWorkspaceStore.defaultDescriptors

    private let statusProvider: any MenuBarSystemStatusProviding

    public static let defaultDescriptors: [ModularDashboardDescriptor] = [
        ModularDashboardDescriptor(
            id: "card-kpi-summary",
            kind: .kpiSummary,
            title: DashboardL10n.tr("dashboard.card.kpi.title", "Daily Agent Summary"),
            subtitle: DashboardL10n.tr("dashboard.card.kpi.subtitle", "Key invocations, efficiency, cost, and action status"),
            symbolName: "gauge.with.dots.needle.33percent"
        ),
        ModularDashboardDescriptor(
            id: "card-trend-chart",
            kind: .trendChart,
            title: DashboardL10n.tr("dashboard.card.trend.title", "Agent Invocations & Spend by CLI"),
            subtitle: DashboardL10n.tr("dashboard.card.trend.subtitle", "Click any bar to cross-filter tables and actionable items below"),
            symbolName: "chart.bar.xaxis"
        ),
        ModularDashboardDescriptor(
            id: "card-cli-cost",
            kind: .cliCostQuota,
            title: DashboardL10n.tr("dashboard.card.cli_cost.title", "Multi-CLI Cost & Quota Monitor"),
            subtitle: DashboardL10n.tr("dashboard.card.cli_cost.subtitle", "Daily spend, cycle cumulative cost, and quota utilization"),
            symbolName: "creditcard.and.123"
        ),
        ModularDashboardDescriptor(
            id: "card-action-items",
            kind: .actionItems,
            title: DashboardL10n.tr("dashboard.card.actions.title", "Actionable Items"),
            subtitle: DashboardL10n.tr("dashboard.card.actions.subtitle", "Blockers, quota warnings, and ready-to-advance agent tasks"),
            symbolName: "checklist"
        ),
        ModularDashboardDescriptor(
            id: "card-ranking-table",
            kind: .rankingTable,
            title: DashboardL10n.tr("dashboard.card.ranking.title", "Agent & CLI Efficiency Ranking"),
            subtitle: DashboardL10n.tr("dashboard.card.ranking.subtitle", "Select a row to inspect detailed execution telemetry in-place"),
            symbolName: "tablecells"
        )
    ]

    public init(
        statusProvider: (any MenuBarSystemStatusProviding)? = nil,
        deferInitialRefresh: Bool = false
    ) {
        self.statusProvider = statusProvider ?? LiveMenuBarSystemStatusProvider()
        if !deferInitialRefresh {
            refreshFromProvider()
        }
    }

    public init(
        snapshot: MenuBarSystemSnapshot,
        trendPoints: [TrendDataPoint]? = nil,
        cliEntries: [CLICostQuotaEntry]? = nil,
        actionItems: [DashboardActionItem]? = nil,
        rankingRows: [AgentRankingRow]? = nil,
        scheduledPulseSnapshot: ScheduledPulseSnapshot? = nil
    ) {
        self.statusProvider = LiveMenuBarSystemStatusProvider(tokenDatabasePaths: CLITokenDatabasePaths())
        if let scheduledPulseSnapshot {
            self.scheduledPulseSnapshot = scheduledPulseSnapshot
            self.scheduledPulseHealthFilter = ScheduledPulseLogic.defaultHealthFilter(for: scheduledPulseSnapshot)
        }
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
        reloadCurrentSnapshotForSelectedDate()
    }

    public func selectNextDate() {
        guard let idx = availableDates.firstIndex(of: selectedDateString),
              idx < availableDates.index(before: availableDates.endIndex) else { return }
        selectedDateString = availableDates[availableDates.index(after: idx)]
        reloadCurrentSnapshotForSelectedDate()
    }

    public func selectToday() {
        if let last = availableDates.last {
            selectedDateString = last
            reloadCurrentSnapshotForSelectedDate()
        }
    }

    private func reloadCurrentSnapshotForSelectedDate() {
        if case let .populated(snapshot) = systemState {
            applySnapshot(snapshot)
        }
    }

    private static var standaloneDashboardWindow: NSWindow?

    public func openDashboardWindow(section: DashboardWorkspaceSection = .overview, cliFilter: DashboardCLIFilter? = nil) {
        selectedSection = section
        if let cliFilter { selectedCLI = cliFilter }
        if let app = NSApp {
            app.setActivationPolicy(.regular)
            app.activate(ignoringOtherApps: true)
            let candidateWindows = app.windows.filter { $0.canBecomeMain && !$0.className.contains("StatusBar") }
            if let existing = candidateWindows.first {
                existing.makeKeyAndOrderFront(nil)
            } else if LiveDashboardTelemetryReader.isLiveEnvironment {
                Self.makeOrReuseDashboardWindow(store: self).makeKeyAndOrderFront(nil)
            }
        }
        NotificationCenter.default.post(name: .openBriefingWindow, object: nil)
    }

    private static func makeOrReuseDashboardWindow(store: DashboardWorkspaceStore) -> NSWindow {
        if let win = standaloneDashboardWindow { return win }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1160, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = "AIDash"
        win.toolbarStyle = .unified
        win.minSize = NSSize(width: 920, height: 600)
        win.isReleasedWhenClosed = false
        win.center()
        win.contentView = NSHostingView(rootView: AIDashMacWorkspaceView(store: store))
        standaloneDashboardWindow = win
        return win
    }

    public func refreshFromProvider() {
        let state = statusProvider.captureStatusState()
        systemState = state
        scheduledPulseSnapshot = LiveDashboardTelemetryReader.loadScheduledPulseSnapshot()
        scheduledPulseHealthFilter = ScheduledPulseLogic.defaultHealthFilter(for: scheduledPulseSnapshot)
        selectedScheduledJobID = scheduledPulseSnapshot.jobs.first?.id
        scheduledJobFrameworkSnapshot = LiveDashboardTelemetryReader.loadScheduledJobFrameworkSnapshot(
            acknowledgedActionIDs: acknowledgedScheduledActionIDs
        )
        if case let .populated(snapshot) = state {
            applySnapshot(snapshot)
        }
    }

    public func updateScheduledPulseSnapshot(_ snapshot: ScheduledPulseSnapshot) {
        scheduledPulseSnapshot = snapshot
        scheduledPulseHealthFilter = ScheduledPulseLogic.defaultHealthFilter(for: snapshot)
        if let selectedScheduledJobID,
           snapshot.jobs.contains(where: { $0.id == selectedScheduledJobID }) {
            self.selectedScheduledJobID = selectedScheduledJobID
        } else {
            selectedScheduledJobID = snapshot.jobs.first?.id
        }
    }

    public func updateScheduledJobFrameworkSnapshot(_ snapshot: ScheduledJobFrameworkSnapshot) {
        scheduledJobFrameworkSnapshot = snapshot
        if let selectedFrameworkJobID,
           snapshot.entries.contains(where: { $0.id == selectedFrameworkJobID }) {
            self.selectedFrameworkJobID = selectedFrameworkJobID
        }
    }

    @discardableResult
    public func startScheduledJob(_ id: ScheduledPulseJobID) -> ScheduledPulseLaunchdInstaller.RegistrationOutcome {
        let outcome = ScheduledPulseLaunchdInstaller.shared.start(jobID: id)
        if outcome.isHealthy {
            scheduledJobFrameworkSnapshot = LiveDashboardTelemetryReader.loadScheduledJobFrameworkSnapshot(
                acknowledgedActionIDs: acknowledgedScheduledActionIDs
            )
        }
        return outcome
    }

    @discardableResult
    public func stopScheduledJob(_ id: ScheduledPulseJobID) -> ScheduledPulseLaunchdInstaller.RegistrationOutcome {
        let outcome = ScheduledPulseLaunchdInstaller.shared.stop(jobID: id)
        if outcome.isHealthy {
            scheduledJobFrameworkSnapshot = LiveDashboardTelemetryReader.loadScheduledJobFrameworkSnapshot(
                acknowledgedActionIDs: acknowledgedScheduledActionIDs
            )
        }
        return outcome
    }

    public func acknowledgeScheduledAction(
        _ action: ScheduledJobAction,
        responses: [ScheduledJobActionResponse]
    ) {
        if let scheduledActionWriter {
            guard scheduledActionWriter(action, responses) else { return }
        }
        acknowledgedScheduledActionIDs.insert(action.acknowledgementKey)
        let entries = scheduledJobFrameworkSnapshot.entries.map { entry in
            ScheduledJobFrameworkEntry(
                definition: entry.definition,
                state: entry.state,
                actions: entry.actions.filter { $0.acknowledgementKey != action.acknowledgementKey }
            )
        }
        scheduledJobFrameworkSnapshot = ScheduledJobFrameworkSnapshot(
            capturedAt: scheduledJobFrameworkSnapshot.capturedAt,
            entries: entries
        )
        for idx in actionItems.indices where actionItems[idx].acknowledgementKey == action.acknowledgementKey {
            actionItems[idx].isCompleted = true
            actionItems[idx].status = .done
        }
    }

    public func submitActionItemDecision(
        _ item: DashboardActionItem,
        decision: String,
        targets: Set<String> = [],
        note: String = "",
        onToggleDone: ((String, String, Bool) -> Void)? = nil
    ) {
        let trimmedNote = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(item.noteMaxLength))
        if item.jobID == .myPRSupervisor, item.id.hasPrefix("D") {
            persistMyPRSupervisorDecision(itemID: item.id, decision: decision, note: trimmedNote)
        }
        if let jobID = item.jobID {
            let effectiveControls = item.controls.isEmpty
                ? [
                    ScheduledJobActionControl(id: "decision", kind: .singleSelect, title: "Action", options: ["Approve", "Done", "Dismiss"]),
                    ScheduledJobActionControl(id: "note", kind: .textInput, title: "Note", maxLength: 80)
                ]
                : item.controls
            let scheduledAction = ScheduledJobAction(
                id: item.id,
                jobID: jobID,
                title: item.title,
                descriptionMd: item.summary,
                controls: effectiveControls
            )
            var values: [String: String] = ["decision": decision]
            if !trimmedNote.isEmpty || effectiveControls.contains(where: { $0.id == "note" }) {
                values["note"] = trimmedNote
            }
            let responses = scheduledAction.resolvedResponses(
                values: values,
                selectedValues: targets.isEmpty ? [:] : ["targets": targets]
            )
            acknowledgeScheduledAction(scheduledAction, responses: responses)
        }
        if let idx = actionItems.firstIndex(where: { $0.id == item.id }) {
            actionItems[idx].isCompleted = true
            actionItems[idx].status = .done
            let updated = actionItems[idx]
            if let cardId = updated.backingCardId, let itemRef = updated.backingItemRef {
                onToggleDone?(cardId, itemRef, true)
            }
            if LiveDashboardTelemetryReader.isLiveEnvironment, updated.id.hasPrefix("proposal-") {
                LiveDashboardTelemetryReader.persistProposalStatus(item: updated)
            }
        }
    }

    private func persistMyPRSupervisorDecision(itemID: String, decision: String, note: String) {
        guard LiveDashboardTelemetryReader.isLiveEnvironment else { return }
        let homeURL = LiveMenuBarSystemStatusProvider.realUserHomeDirectoryURL()
        let configURL = homeURL.appendingPathComponent(
            "Development/job skills/my-pr-supervisor/config/my-prs.json"
        )
        let lockURL = URL(fileURLWithPath: configURL.path + ".lock")
        let fileManager = FileManager.default

        do {
            guard fileManager.fileExists(atPath: configURL.path) else { return }
            if !fileManager.fileExists(atPath: lockURL.path) {
                guard fileManager.createFile(atPath: lockURL.path, contents: nil) else { return }
            }
            let lockHandle = try FileHandle(forWritingTo: lockURL)
            defer { try? lockHandle.close() }
            guard flock(lockHandle.fileDescriptor, LOCK_EX) == 0 else { return }
            defer { _ = flock(lockHandle.fileDescriptor, LOCK_UN) }

            let data = try Data(contentsOf: configURL)
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var pendingDecisions = root["pending_decisions"] as? [String: Any] else {
                return
            }

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let matchingKeys: [String] = pendingDecisions.compactMap { key, value -> String? in
                guard let entry = value as? [String: Any],
                      (entry["decision_id"] as? String) == itemID else {
                    return nil
                }
                return key
            }
            guard !matchingKeys.isEmpty else { return }
            for key in matchingKeys {
                guard var entry = pendingDecisions[key] as? [String: Any] else { continue }
                entry["status"] = "owner_replied"
                entry["owner_choice"] = decision
                entry["owner_note"] = note
                entry["replied_at"] = timestamp
                pendingDecisions[key] = entry
            }

            root["pending_decisions"] = pendingDecisions
            let updatedData = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            try updatedData.write(to: configURL, options: .atomic)
        } catch {
            return
        }
    }

    public var scheduledPulseRows: [ScheduledJobStatus] {
        ScheduledPulseLogic.filteredJobs(
            from: scheduledPulseSnapshot,
            scheduler: scheduledPulseSchedulerFilter,
            health: scheduledPulseHealthFilter
        )
    }

    public var selectedScheduledJob: ScheduledJobStatus? {
        if let selectedScheduledJobID,
           let selected = scheduledPulseRows.first(where: { $0.id == selectedScheduledJobID }) {
            return selected
        }
        return scheduledPulseRows.first
    }

    public var scheduledPulseUnhealthyCount: Int {
        scheduledPulseSnapshot.jobs.filter(\.isUnhealthy).count
    }

    public var scheduledPulseLastTick: Date? {
        scheduledPulseSnapshot.jobs.compactMap(\.lastTick).max()
    }

    public func selectScheduledPulseKPI(_ metric: ScheduledPulseKPIMetric) {
        switch metric {
        case .enabled:
            scheduledPulseSchedulerFilter = .live
            scheduledPulseHealthFilter = .all
        case .unhealthy:
            scheduledPulseSchedulerFilter = .all
            scheduledPulseHealthFilter = .unhealthy
        case .lastTick:
            scheduledPulseSchedulerFilter = .all
            scheduledPulseHealthFilter = .all
        }
    }

    public func copyScheduledJobCommand(_ status: ScheduledJobStatus) {
        guard let command = status.definition.commandHint else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        lastCopiedScheduledJobID = status.id
    }

    private static func isArchivedActionItem(_ item: DashboardActionItem) -> Bool {
        if item.hasLinearLabel("bug-blocker") || item.hasLinearLabel("eval") || item.hasLinearLabel("pop") {
            return false
        }
        let haystack = [item.id, item.title, item.summary, item.sourceTag, item.backingItemRef ?? ""]
            .joined(separator: " ")
            .uppercased()
        return haystack.contains("EVAL_CANDIDATE") || haystack.contains("BUG_BLOCKER")
    }

    private func applySnapshot(
        _ snapshot: MenuBarSystemSnapshot,
        customTrends: [TrendDataPoint]? = nil,
        customCLIs: [CLICostQuotaEntry]? = nil,
        customActions: [DashboardActionItem]? = nil,
        customRankings: [AgentRankingRow]? = nil
    ) {
        systemState = .populated(snapshot)
        let liveDataset = (customCLIs == nil && customRankings == nil)
            ? LiveDashboardTelemetryReader.loadLiveDataset(forDate: selectedDateString, fallbackUsage: snapshot.tokenUsage)
            : nil
        let derivedCLIs = customCLIs ?? liveDataset?.entries ?? Self.deriveCLIEntries(from: snapshot.tokenUsage, forDate: selectedDateString)
        cliEntries = derivedCLIs
        trendPoints = customTrends ?? liveDataset?.trends ?? Self.deriveTrendPoints(from: derivedCLIs)
        let preservedCompletedIDs = Set(actionItems.filter(\.isCompleted).map(\.id))
        var nextActions = customActions ?? Self.deriveActionItems(
            from: snapshot,
            cliEntries: derivedCLIs,
            acknowledgedActionIDs: acknowledgedScheduledActionIDs
        )
        for index in nextActions.indices {
            if preservedCompletedIDs.contains(nextActions[index].id)
                || (nextActions[index].acknowledgementKey.map { acknowledgedScheduledActionIDs.contains($0) } ?? false) {
                nextActions[index].isCompleted = true
                nextActions[index].status = .done
            }
        }
        actionItems = nextActions.filter { !Self.isArchivedActionItem($0) }
        if !availableLinearActionFilters.contains(where: { $0.id == selectedLinearActionFilter }) {
            selectedLinearActionFilter = "all"
        }
        rankingRows = customRankings ?? liveDataset?.rankings ?? Self.deriveRankingRows(from: derivedCLIs)
        liveEfficiencySummary = (customCLIs == nil && customRankings == nil)
            ? LiveDashboardTelemetryReader.loadLiveEfficiencySummary()
            : nil
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
        selectedChartCategory != nil || actionFilter != .all || selectedLinearActionFilter != "all"
    }

    public func clearScopedFilterOnly() {
        if selectedChartCategory != nil {
            selectedChartCategory = nil
        } else if actionFilter != .all {
            actionFilter = .all
        } else if selectedLinearActionFilter != "all" {
            selectedLinearActionFilter = "all"
        }
    }

    // MARK: - IP-005 Live Status-to-Summary Aggregation

    public func toggleActionItem(
        id: String,
        onToggleDone: ((String, String, Bool) -> Void)? = nil
    ) {
        guard let idx = actionItems.firstIndex(where: { $0.id == id }) else { return }
        actionItems[idx].isCompleted.toggle()
        actionItems[idx].status = actionItems[idx].isCompleted ? .done : .triage
        let updated = actionItems[idx]
        if let cardId = updated.backingCardId, let itemRef = updated.backingItemRef {
            onToggleDone?(cardId, itemRef, updated.isCompleted)
        }
        if LiveDashboardTelemetryReader.isLiveEnvironment, updated.id.hasPrefix("proposal-") {
            LiveDashboardTelemetryReader.persistProposalStatus(item: updated)
        }
    }

    @discardableResult
    public func dispatchActionToHerdr(
        _ item: DashboardActionItem,
        socketPath: String? = nil
    ) -> Bool {
        if let socketPath {
            let ok = HerdrSocketClient.dispatchActionItemToHerdr(item, socketPath: socketPath)
            if ok { lastDispatchedActionID = item.id }
            return ok
        }
        let cmd = HerdrSocketClient.buildM2Command(for: item)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        if LiveDashboardTelemetryReader.isLiveEnvironment {
            let homeURL = LiveMenuBarSystemStatusProvider.realUserHomeDirectoryURL()
            let projectDir = HerdrSocketClient.resolveProjectDirectory(for: item, homeURL: homeURL)
            let label = "m2-\(projectDir.lastPathComponent)"
            let itemID = item.id
            Task.detached(priority: .userInitiated) { [weak self] in
                let ok = HerdrSocketClient.openWorkspaceAndStageText(
                    cwd: projectDir.path,
                    label: label,
                    stagedText: cmd,
                    submitWithEnter: false,
                    focus: true
                )
                if ok {
                    await MainActor.run {
                        self?.lastDispatchedActionID = itemID
                    }
                }
            }
            return true
        }
        lastDispatchedActionID = item.id
        return true
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

    public var todayTotalCostUSD: Double { filteredCLIEntries.reduce(0) { $0 + $1.todayCostUSD } }
    public var periodTotalCostUSD: Double { filteredCLIEntries.reduce(0) { $0 + $1.periodCostUSD } }
    public var todayTotalActiveTokens: UInt64 { filteredCLIEntries.reduce(0) { $0 + $1.activeTokens } }
    public var todayTotalCacheTokens: UInt64 { filteredCLIEntries.reduce(0) { $0 + $1.cacheTokens } }
    public var todayGrandTotalTokens: UInt64 { filteredCLIEntries.reduce(0) { $0 + $1.totalTokens } }
    public var periodGrandTotalTokens: UInt64 { filteredCLIEntries.reduce(0) { $0 + $1.periodTotalTokens } }
    public var highestQuotaWarningCount: Int { filteredCLIEntries.filter { $0.health == .warning || $0.health == .critical }.count }

    // MARK: - Derived Filtered & Sorted Collections (IP-001, IP-002, IP-003)

    private func matchesActiveCLIFilter(_ cli: DashboardCLIFilter) -> Bool {
        guard selectedCLI != .all else { return true }
        return cli == selectedCLI || cli == .all
    }

    private func matchesChartCategory(_ cli: DashboardCLIFilter, categoryName: String) -> Bool {
        guard let selectedChartCategory else { return true }
        return categoryName == selectedChartCategory || cli.rawValue == selectedChartCategory || cli.shortLabel == selectedChartCategory
    }

    public var availableCLIFilters: [DashboardCLIFilter] {
        var filters: [DashboardCLIFilter] = [.all]
        for cli in DashboardCLIFilter.allCases where cli != .all {
            if cliEntries.contains(where: { $0.cliFilter == cli }) {
                filters.append(cli)
            }
        }
        return filters.count > 1 ? filters : DashboardCLIFilter.allCases
    }

    public var availableLinearActionFilters: [DashboardLinearActionFilterChip] {
        let activeLinearItems = actionItems.filter { !$0.isCompleted && $0.isLinearNative }
        let orderedLabels: [(String, String)] = [
            ("needs-decision", "🔴 needs-decision · 需单独拍板"),
            ("pop", "🔐 label:pop · 待合入"),
            ("eval", "💡 label:eval · 评论改进建议"),
            ("bug-blocker", "🧱 label:bug-blocker · Bug 阻塞")
        ]
        var filters = [DashboardLinearActionFilterChip(id: "all", label: "全部")]
        var knownLabels = Set<String>()
        for (label, display) in orderedLabels {
            knownLabels.insert(label)
            let count = activeLinearItems.filter { item in
                label == "needs-decision" ? item.isNeedsDecision : item.hasLinearLabel(label)
            }.count
            if count > 0 {
                filters.append(DashboardLinearActionFilterChip(id: label, label: display, count: count))
            }
        }
        let extraLabels = Set(activeLinearItems.flatMap(\.labels))
            .filter { !knownLabels.contains($0.lowercased()) }
            .sorted()
        for label in extraLabels {
            let count = activeLinearItems.filter { $0.hasLinearLabel(label) }.count
            filters.append(DashboardLinearActionFilterChip(id: label, label: "label:\(label)", count: count))
        }
        return filters
    }

    private func matchesLinearActionFilter(_ item: DashboardActionItem) -> Bool {
        guard selectedLinearActionFilter != "all" else { return true }
        if selectedLinearActionFilter == "needs-decision" {
            return item.isNeedsDecision
        }
        return item.hasLinearLabel(selectedLinearActionFilter)
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
                  matchesChartCategory(item.cliFilter, categoryName: item.sourceTag),
                  matchesLinearActionFilter(item) else {
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
        let pendingCount = filteredActionItems.filter { !$0.isCompleted }.count
        let pendingHealth: DashboardSemanticHealth = p0PendingCount > 0 ? .critical : (pendingCount > 0 ? .warning : .healthy)
        let liveEff = liveEfficiencySummary

        let effDelta: String
        let effHealth: DashboardSemanticHealth
        if let liveEff, liveEff.reviewedTasksCount > 0 {
            let r1PassPct = Int(((1.0 - liveEff.r1ReviewFailRate) * 100).rounded())
            effDelta = "Review R1 Pass \(r1PassPct)% (\(liveEff.round3PlusCount) r3+) · P90 TTFT \(String(format: "%.1fs", liveEff.p90TTFTSeconds))"
            effHealth = liveEff.r1ReviewFailRate > 0.15 ? .warning : (avgSuccess >= 0.95 ? .healthy : .warning)
        } else {
            effDelta = avgSuccess >= 0.95
                ? DashboardL10n.tr("dashboard.kpi.efficiency.target_met", "Target >= 95% met")
                : DashboardL10n.tr("dashboard.kpi.efficiency.below_target", "Below 95% target")
            effHealth = avgSuccess >= 0.95 ? .healthy : .warning
        }

        let costDelta: String
        if highestQuotaWarningCount > 0 {
            costDelta = DashboardL10n.format("dashboard.kpi.cost.near_quota_format", "%lld CLI near quota", highestQuotaWarningCount)
        } else if let liveEff, liveEff.cacheHitRate > 0 {
            let cachePct = String(format: "%.1f%%", liveEff.cacheHitRate * 100)
            let steerPct = String(format: "%.1f%%", liveEff.steeringTokenShare * 100)
            costDelta = "Cache Hit \(cachePct) · Steering \(steerPct)"
        } else {
            costDelta = DashboardL10n.tr("dashboard.kpi.cost.within_budget", "Quota healthy")
        }

        return [
            KPIMetricItem(
                id: "kpi-invocations",
                label: DashboardL10n.tr("dashboard.kpi.invocations.label", "Agent Invocations"),
                formattedValue: totalRuns.formatted(.number),
                unit: DashboardL10n.tr("dashboard.kpi.invocations.unit", "runs"),
                deltaText: selectedChartCategory.map {
                    DashboardL10n.format("dashboard.kpi.filtered_format", "Filtered: %@", $0)
                } ?? DashboardL10n.tr("dashboard.kpi.invocations.delta", "+14.2% vs avg"),
                direction: .up,
                health: .healthy,
                symbolName: "bolt.horizontal.circle.fill"
            ),
            KPIMetricItem(
                id: "kpi-efficiency",
                label: DashboardL10n.tr("dashboard.kpi.efficiency.label", "Success & Latency"),
                formattedValue: String(format: "%.1f%%", avgSuccess * 100),
                unit: DashboardL10n.format("dashboard.kpi.efficiency.unit_format", "%.1fs avg", avgDuration),
                deltaText: effDelta,
                direction: effHealth == .healthy ? .up : .down,
                health: effHealth,
                symbolName: "waveform.path.ecg"
            ),
            KPIMetricItem(
                id: "kpi-cost",
                label: DashboardL10n.tr("dashboard.kpi.cost.label", "Today Total Tokens"),
                formattedValue: DashboardTokenFormatter.compact(todayGrandTotalTokens),
                unit: DashboardL10n.format("dashboard.kpi.tokens.period_unit_format", "7d %@", DashboardTokenFormatter.compact(periodGrandTotalTokens)),
                deltaText: costDelta,
                direction: highestQuotaWarningCount > 0 ? .up : .flat,
                health: highestQuotaWarningCount > 0 ? .warning : .healthy,
                symbolName: "sparkles"
            ),
            KPIMetricItem(
                id: "kpi-actions",
                label: DashboardL10n.tr("dashboard.kpi.actions.label", "Actionable Items"),
                formattedValue: "\(pendingCount)",
                unit: DashboardL10n.tr("dashboard.kpi.actions.unit", "pending"),
                deltaText: DashboardL10n.format("dashboard.kpi.actions.completed_format", "%lld completed today", completedActionCount),
                direction: pendingCount == 0 ? .down : .flat,
                health: pendingHealth,
                symbolName: pendingHealth.symbolName
            )
        ]
    }
}

extension DashboardWorkspaceStore {
    static func deriveCLIEntries(
        from usage: CLITokenUsageSnapshot,
        forDate dateString: String? = nil
    ) -> [CLICostQuotaEntry] {
        let targetDate = dateString ?? todayDateString()
        if let live = LiveDashboardTelemetryReader.loadLiveDataset(forDate: targetDate, fallbackUsage: usage) {
            return live.entries
        }
        let baseItems = usage.items
        let claudeItem = baseItems.first { $0.cli == .claude }
        let codexItem = baseItems.first { $0.cli == .codex }
        let copilotItem = baseItems.first { $0.cli == .copilot }

        let claudeCost = estimateCostUSD(activeTokens: claudeItem?.activeTokens ?? 0, ratePerMillion: 9.0, fallback: 0.0)
        let codexCost = estimateCostUSD(activeTokens: codexItem?.activeTokens ?? 0, ratePerMillion: 6.0, fallback: 0.0)
        let copilotCost = estimateCostUSD(activeTokens: copilotItem?.activeTokens ?? 0, ratePerMillion: 1.5, fallback: 0.0)
        let claudeQuotaCap = 15.0
        let claudeUsedFraction: Double? = usage.claudeWeeklyRemainingPercent.map { rem in
            Double(max(0, min(100, 100 - rem))) / 100.0
        }

        let weeklyQuotaLabel = DashboardL10n.tr("dashboard.quota.weekly_label", "7d Quota")
        let claudeQuotaLabel = DashboardL10n.tr("dashboard.quota.claude_7d_label", "Pro 7d Quota")

        return [
            CLICostQuotaEntry(
                id: "cli-claude",
                cliFilter: .claude,
                displayName: "Claude Code",
                modelTag: "claude-opus-4-6 / sonnet-4-6",
                todayCostUSD: claudeCost,
                periodCostUSD: claudeCost * 7.0,
                quotaLimitUSD: claudeQuotaCap,
                activeTokens: claudeItem?.activeTokens ?? 0,
                cacheTokens: claudeItem?.cacheTokens ?? 0,
                interactionCount: claudeItem?.interactionCount ?? 0,
                isAvailable: claudeItem?.isAvailable ?? true,
                quotaUsedOverride: claudeUsedFraction,
                quotaLabel: claudeQuotaLabel,
                secondaryQuotaUsed: claudeUsedFraction.map { min($0 * 0.4, 1.0) },
                secondaryQuotaLabel: "5h"
            ),
            CLICostQuotaEntry(
                id: "cli-codex",
                cliFilter: .codex,
                displayName: "Codex CLI",
                modelTag: "gpt-5.4 / codex-exec",
                todayCostUSD: codexCost,
                periodCostUSD: codexCost * 7.0,
                quotaLimitUSD: 15.0,
                activeTokens: codexItem?.activeTokens ?? 0,
                cacheTokens: codexItem?.cacheTokens ?? 0,
                interactionCount: codexItem?.interactionCount ?? 0,
                isAvailable: codexItem?.isAvailable ?? true,
                quotaLabel: weeklyQuotaLabel
            ),
            CLICostQuotaEntry(
                id: "cli-copilot",
                cliFilter: .copilot,
                displayName: "Copilot CLI",
                modelTag: "gemini-4-argon / gpt-5.6-luna",
                todayCostUSD: copilotCost,
                periodCostUSD: copilotCost * 7.0,
                quotaLimitUSD: 15.0,
                activeTokens: copilotItem?.activeTokens ?? 0,
                cacheTokens: copilotItem?.cacheTokens ?? 0,
                interactionCount: copilotItem?.interactionCount ?? 0,
                isAvailable: copilotItem?.isAvailable ?? true,
                quotaUsedOverride: 0.0,
                quotaLabel: nil
            ),
            CLICostQuotaEntry(
                id: "cli-kimi",
                cliFilter: .kimi,
                displayName: "Kimi CLI",
                modelTag: "Kimi Code (5h / 7d)",
                todayCostUSD: 0.0,
                periodCostUSD: 0.0,
                quotaLimitUSD: 15.0,
                activeTokens: 0,
                cacheTokens: 0,
                interactionCount: 0,
                isAvailable: true,
                quotaUsedOverride: 0.0,
                quotaLabel: weeklyQuotaLabel
            )
        ]
    }

    private static func estimateCostUSD(activeTokens: UInt64, ratePerMillion: Double, fallback: Double) -> Double {
        guard activeTokens > 0 else { return fallback }
        return (Double(activeTokens) / 1_000_000.0) * ratePerMillion
    }

    static func deriveTrendPoints(from entries: [CLICostQuotaEntry]) -> [TrendDataPoint] {
        entries.map { entry in
            let inTok = UInt64(Double(entry.activeTokens) * 0.72)
            let outTok = entry.activeTokens - inTok
            return TrendDataPoint(
                id: "trend-\(entry.id)",
                bucketLabel: entry.cliFilter.shortLabel,
                category: entry.displayName,
                cliFilter: entry.cliFilter,
                invocations: Int(entry.interactionCount),
                successRate: entry.health == .critical ? 0.91 : 0.99,
                costUSD: entry.todayCostUSD,
                totalTokens: entry.activeTokens + entry.cacheTokens,
                inputTokens: inTok,
                outputTokens: outTok,
                cacheTokens: entry.cacheTokens
            )
        }
    }

    static func deriveActionItems(
        from snapshot: MenuBarSystemSnapshot,
        cliEntries: [CLICostQuotaEntry],
        acknowledgedActionIDs: Set<String> = []
    ) -> [DashboardActionItem] {
        let liveItems = LiveDashboardTelemetryReader.loadLiveImprovementActionItems(
            acknowledgedActionIDs: acknowledgedActionIDs
        )
        if !liveItems.isEmpty && liveItems.contains(where: { $0.jobID == .aidataDigest }) {
            return liveItems
        }
        var result: [DashboardActionItem] = snapshot.attention.items.enumerated().map { index, att in
            DashboardActionItem(
                id: "attention-\(att.id)", title: att.title,
                summary: att.waitingOn.map {
                    DashboardL10n.format("dashboard.action.waiting_on_format", "Waiting on %@ · %@", $0, att.category ?? "Workflow")
                } ?? DashboardL10n.tr("dashboard.action.requires_review", "Requires owner review to unblock downstream tasks."),
                sourceTag: att.category ?? "Claude Code", cliFilter: .claude,
                priority: index == 0 ? .p0 : .p1, status: .blocked, isCompleted: false, command: "aidash events pull --since 24h"
            )
        }
        _ = cliEntries
        result.append(contentsOf: liveItems)
        if result.isEmpty && !LiveDashboardTelemetryReader.isLiveEnvironment {
            result = [
                DashboardActionItem(
                    id: "default-action-digest",
                    title: DashboardL10n.tr("dashboard.action.default_digest_title", "Review daily agent efficiency & cache hit ratios"),
                    summary: DashboardL10n.tr("dashboard.action.default_digest_summary", "All CLI quotas and system telemetry are within healthy thresholds today."),
                    sourceTag: "Claude Code", cliFilter: .claude, priority: .p2, isCompleted: false, command: "aidash briefing get --date today --json"
                ),
                DashboardActionItem(
                    id: "default-action-codex",
                    title: DashboardL10n.tr("dashboard.action.default_codex_title", "Inspect Codex CLI batch verification throughput"),
                    summary: DashboardL10n.tr("dashboard.action.default_codex_summary", "Verify zero pending retries across automated PR review gates."),
                    sourceTag: "Codex CLI", cliFilter: .codex, priority: .p1, isCompleted: false, externalURLString: "https://github.com/LeePepe/AIDash/pulls"
                )
            ]
        }
        return result
    }

    static func deriveRankingRows(from entries: [CLICostQuotaEntry]) -> [AgentRankingRow] {
        entries.enumerated().map { idx, entry in
            let roleName: String
            switch idx {
            case 0: roleName = DashboardL10n.tr("dashboard.role.steering", "M1 · Steering (TL)")
            case 1: roleName = DashboardL10n.tr("dashboard.role.writer_reviewer", "M1 · Writer")
            case 2: roleName = DashboardL10n.tr("dashboard.role.cli_assistant", "M2 · Dispatcher (CLI)")
            default: roleName = DashboardL10n.tr("dashboard.role.research_audit", "M1 · Reviewer")
            }
            let pct = Int((entry.usedFraction * 100).rounded())
            return AgentRankingRow(
                id: "rank-\(entry.id)", agentName: roleName, modelName: entry.modelTag, cliFilter: entry.cliFilter, providerName: entry.displayName,
                runs: max(Int(entry.interactionCount), 45), totalTokens: entry.totalTokens,
                successRate: entry.health == .critical ? 0.924 : (0.978 - Double(idx) * 0.008),
                avgDurationSeconds: 9.5 + Double(idx) * 3.2, costUSD: entry.todayCostUSD,
                detailSummary: DashboardL10n.format("dashboard.ranking.total_detail_format", "%@ (%@) · Total %@ tok · %lld runs", entry.displayName, entry.modelTag, DashboardTokenFormatter.compact(entry.totalTokens), Int(entry.interactionCount)),
                recentIssue: entry.health == .healthy ? nil : DashboardL10n.format("dashboard.ranking.issue_format", "Approaching daily quota ceiling (%lld%%)", pct)
            )
        }
    }
}
#endif
