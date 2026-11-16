#if os(macOS)
// swiftlint:disable file_length
import SwiftUI
import DesignKit

public struct ScheduledPulseCompartment: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let entries: [ScheduledJobFrameworkEntry]

    public init(id: String, title: String, entries: [ScheduledJobFrameworkEntry]) {
        self.id = id
        self.title = title
        self.entries = entries
    }
}

struct ScheduledPulseDisplayStage: Identifiable, Sendable {
    let id: String
    let title: String
    let semanticState: ScheduledStageState
    let exitCode: Int?
    let durationSec: Double?
    let sourceAsOf: String?
}

enum ScheduledPulseStageCatalog {
    static func stages(for entry: ScheduledJobFrameworkEntry) -> [ScheduledPulseDisplayStage] {

        let titles = titles(for: entry.id)
        let receipts = entry.state?.stages ?? []
        return titles.enumerated().map { index, definition in
            let receipt = receipts.indices.contains(index) ? receipts[index] : nil
            let semanticState = receipt?.semanticState ?? synthesizedState(for: entry.semanticState, index: index)
            let exitCode = receipt?.exitCode ?? (semanticState == .failed ? Int(entry.launchdExitCode ?? 1) : nil)
            return ScheduledPulseDisplayStage(
                id: definition.id,
                title: definition.title,
                semanticState: semanticState,
                exitCode: exitCode,
                durationSec: receipt?.durationSec,
                sourceAsOf: receipt?.sourceAsOf
            )
        }
    }

    static func labels(for id: ScheduledPulseJobID) -> [String] {
        titles(for: id).map(\.title)
    }

    private static func synthesizedState(for state: ScheduledJobSemanticState, index: Int) -> ScheduledStageState {
        switch state {
        case .healthy: return .passed
        case .running: return index < 2 ? .passed : (index == 2 ? .running : .unknown)
        case .failed: return index < 2 ? .passed : (index == 2 ? .failed : .unknown)
        case .partial: return index < 2 ? .passed : (index == 2 ? .warning : .unknown)
        case .coalesced: return index == 0 ? .warning : .unknown
        case .noState: return .unknown
        }
    }

    private static func titles(for id: ScheduledPulseJobID) -> [(id: String, title: String)] {
        switch id {
        case .aidataDigest:
            return [
                ("collect", DashboardL10n.tr("dashboard.scheduled_pulse.stage.collect", "① Personal source collection")),
                ("normalize_merge", DashboardL10n.tr("dashboard.scheduled_pulse.stage.warehouse", "② L2/L3 warehouse")),
                ("retro_roi", DashboardL10n.tr("dashboard.scheduled_pulse.stage.retro", "③ Retro/ROI diagnostics")),
                ("learning_topics", DashboardL10n.tr("dashboard.scheduled_pulse.stage.learning", "④ Learning discovery")),
                ("digest_push", DashboardL10n.tr("dashboard.scheduled_pulse.stage.brief", "⑤ Brief delivery"))
            ]
        case .prAutoReview:
            return [
                ("queue_precheck", DashboardL10n.tr("dashboard.scheduled_pulse.stage.pr_auto_review.queue_precheck", "① Queue precheck")),
                ("diff_fetch", DashboardL10n.tr("dashboard.scheduled_pulse.stage.pr_auto_review.diff_fetch", "② Diff fetch")),
                ("dual_review", DashboardL10n.tr("dashboard.scheduled_pulse.stage.pr_auto_review.dual_review", "③ Dual review")),
                ("comment_writeback", DashboardL10n.tr("dashboard.scheduled_pulse.stage.pr_auto_review.comment_writeback", "④ Comment writeback")),
                ("receipt_archive", DashboardL10n.tr("dashboard.scheduled_pulse.stage.pr_auto_review.receipt_archive", "⑤ Receipt archive"))
            ]
        case .myPRSupervisor:
            return [
                ("pr_scan", DashboardL10n.tr("dashboard.scheduled_pulse.stage.my_pr_supervisor.pr_scan", "① PR scan")),
                ("policy_reconcile", DashboardL10n.tr("dashboard.scheduled_pulse.stage.my_pr_supervisor.policy_reconcile", "② Policy reconcile")),
                ("comment_scan", DashboardL10n.tr("dashboard.scheduled_pulse.stage.my_pr_supervisor.comment_scan", "③ Comment scan")),
                ("todo_create", DashboardL10n.tr("dashboard.scheduled_pulse.stage.my_pr_supervisor.todo_create", "④ Todo creation")),
                ("receipt_archive", DashboardL10n.tr("dashboard.scheduled_pulse.stage.my_pr_supervisor.receipt_archive", "⑤ Receipt archive"))
            ]
        case .dailyLearning:
            return [
                ("candidate_scan", DashboardL10n.tr("dashboard.scheduled_pulse.stage.daily_learning.candidate_scan", "① Candidate scan")),
                ("knowledge_dedupe", DashboardL10n.tr("dashboard.scheduled_pulse.stage.daily_learning.knowledge_dedupe", "② Knowledge dedupe")),
                ("topic_match", DashboardL10n.tr("dashboard.scheduled_pulse.stage.daily_learning.topic_match", "③ Topic match")),
                ("proposal_create", DashboardL10n.tr("dashboard.scheduled_pulse.stage.daily_learning.proposal_create", "④ Proposal creation")),
                ("board_sync", DashboardL10n.tr("dashboard.scheduled_pulse.stage.daily_learning.board_sync", "⑤ Board sync"))
            ]
        case .linearBotBridge:
            return [
                ("message_poll", DashboardL10n.tr("dashboard.scheduled_pulse.stage.linear_bot_bridge.message_poll", "① Message polling")),
                ("cursor_dedupe", DashboardL10n.tr("dashboard.scheduled_pulse.stage.linear_bot_bridge.cursor_dedupe", "② Cursor dedupe")),
                ("topic_route", DashboardL10n.tr("dashboard.scheduled_pulse.stage.linear_bot_bridge.topic_route", "③ Topic routing")),
                ("state_sync", DashboardL10n.tr("dashboard.scheduled_pulse.stage.linear_bot_bridge.state_sync", "④ State sync")),
                ("receipt_write", DashboardL10n.tr("dashboard.scheduled_pulse.stage.linear_bot_bridge.receipt_write", "⑤ Bridge receipt"))
            ]
        }
    }
}

@MainActor
private struct ScheduledPulseCompartmentView: View {
    let compartment: ScheduledPulseCompartment
    let selectedEntryID: ScheduledPulseJobID?
    @Binding var hoveredJobID: ScheduledPulseJobID?
    let select: (ScheduledJobFrameworkEntry) -> Void
    let run: (ScheduledJobFrameworkEntry) -> Void
    let toggle: (ScheduledJobFrameworkEntry) -> Void
    let copy: (ScheduledJobFrameworkEntry) -> Void
    let color: (ScheduledJobSemanticState) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(compartment.title).font(.caption.weight(.semibold))
                Spacer()
                Text("\(compartment.entries.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(compartment.entries) { entry in
                let expanded = hoveredJobID == entry.id || selectedEntryID == entry.id
                VStack(alignment: .leading, spacing: 7) {
                    Button { select(entry) } label: {
                        HStack(spacing: 8) {
                            Circle().fill(color(entry.semanticState)).frame(width: 8, height: 8)
                            Text(entry.definition.displayName).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 4)
                            Text(entry.statusText).font(.caption2.weight(.semibold)).foregroundStyle(color(entry.semanticState))
                            Text(entry.definition.cadence.displayText).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.definition.displayName)
                    .onHover { hoveredJobID = $0 ? entry.id : nil }
                    if expanded {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(entry.statusText).font(.caption.weight(.semibold)).foregroundStyle(color(entry.semanticState))
                                if let date = entry.lastRunAt, let relative = ScheduledJobTimeFormatting.relativeText(from: date) {
                                    Text(relative).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(summary(for: entry)).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Button(DashboardL10n.tr("dashboard.scheduled_pulse.run_now", "Run now")) { run(entry) }
                                    .frame(minWidth: 28, minHeight: 28)
                                Button(entry.launchdStatus?.isLoaded == true ? DashboardL10n.tr("dashboard.scheduled_pulse.stop", "Stop") : DashboardL10n.tr("dashboard.scheduled_pulse.start", "Start")) { toggle(entry) }
                                    .frame(minWidth: 28, minHeight: 28)
                                Button(DashboardL10n.tr("dashboard.scheduled_pulse.copy_command", "Copy diagnostic command")) { copy(entry) }
                                    .frame(minWidth: 28, minHeight: 28)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.leading, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(10)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.58), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1) }
                .onHover { hoveredJobID = $0 ? entry.id : nil }
                .animation(.spring(response: 0.36, dampingFraction: 0.8), value: expanded)
            }
            if compartment.entries.isEmpty { Text("—").font(.caption).foregroundStyle(.tertiary) }
        }
        .padding(10)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.48), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1) }
    }

    private func summary(for entry: ScheduledJobFrameworkEntry) -> String {
        if let summary = entry.state?.summary, !summary.isEmpty { return summary }
        if let section = ScheduledJobFrameworkLogic.parseOverview(entry.state?.overviewMd).first,
           let bullet = section.bullets.first { return bullet }
        return DashboardL10n.tr("dashboard.scheduled_pulse.no_summary", "No summary yet.")
    }
}

@MainActor
public struct ScheduledPulsePageView: View {
    @Bindable public var store: DashboardWorkspaceStore
    @State private var installerError: String?
    @Environment(\.theme) private var theme
    private let registerJobs: @MainActor () -> Void

    public init(store: DashboardWorkspaceStore, registerJobs: (@MainActor () -> Void)? = nil) {
        self.store = store
        self.registerJobs = registerJobs ?? {
            guard JobActionsSources.isProductionEnvironment else { return }
            _ = ScheduledPulseLaunchdInstaller.shared.registerLiveJobs()
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch store.scheduledPulseTab {
            case .overview:
                overview
            case .needActions:
                needActions
            }
        }
        .onAppear {
            registerJobs()
            if store.scheduledJobFrameworkSnapshot.entries.isEmpty {
                store.refreshFromProvider()
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            pulseHealthStrip
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    organizerBox
                        .frame(minWidth: 250, idealWidth: 360, maxWidth: 420, alignment: .topLeading)
                    reportStage
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                VStack(alignment: .leading, spacing: 16) {
                    organizerBox
                    reportStage
                }
            }
            .frame(minHeight: 620, alignment: .topLeading)
            if let installerError {
                Text(installerError).font(.caption).foregroundStyle(theme.dangerOnSubtle)
            }
        }
    }

    private var organizerBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(DashboardL10n.tr("dashboard.scheduled_pulse.result.title", "Scheduled job results"), systemImage: "folder")
                    .font(.headline)
                Spacer()
                Text(DashboardL10n.tr("dashboard.scheduled_pulse.organizer.subtitle", "Organized by cadence"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Self.categorizedCompartments(from: store.scheduledJobFrameworkSnapshot.entries)) { compartment in
                ScheduledPulseCompartmentView(
                    compartment: compartment,
                    selectedEntryID: selectedEntry?.id,
                    hoveredJobID: $hoveredJobID,
                    select: select,
                    run: { store.runScheduledJobNow($0.id) },
                    toggle: { entry in handle(entry.launchdStatus?.isLoaded == true ? store.stopScheduledJob(entry.id) : store.startScheduledJob(entry.id)) },
                    copy: { store.copyScheduledJobCommand(ScheduledJobStatus(definition: $0.definition, health: .healthy)) },
                    color: jobColor
                )
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.neutrals.border, lineWidth: 1) }
        .opacity(appearsActive ? 1 : 0.72)
    }

    private var reportStage: some View {
        Group {
            if let entry = selectedEntry {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.definition.displayName).font(.title3.weight(.semibold))
                            Text("\(entry.statusText) · \(entry.definition.launchAgentLabel)")
                                .font(.caption).foregroundStyle(jobColor(entry.semanticState))
                            HStack(spacing: 6) {
                                Text(entry.definition.launchAgentLabel)
                                if let asOf = entry.state?.sourceAsOf { Text("· \(asOf)") }
                            }
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if !entry.actions.isEmpty {
                            Button(DashboardL10n.format("dashboard.scheduled_pulse.pending_actions_format", "View pending actions (%lld)", entry.actions.count)) {
                                store.selectedSection = .actionItems
                                store.scheduledPulseTab = .needActions
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .frame(minHeight: 28)
                        }
                    }
                    stageReceiptStrip(for: entry)
                    overviewContent(for: entry)
                    terminalLog(for: entry)
                    HStack(spacing: 8) {
                        Button(DashboardL10n.tr("dashboard.scheduled_pulse.run_now", "Run now")) { store.runScheduledJobNow(entry.id) }
                            .buttonStyle(.borderedProminent).frame(minWidth: 28, minHeight: 28).captureDashboardGeometry(id: "pulse-run", role: "button")
                        Button(DashboardL10n.tr("dashboard.scheduled_pulse.refresh_status", "Refresh status")) { store.refreshFromProvider() }
                            .buttonStyle(.bordered).frame(minWidth: 28, minHeight: 28).captureDashboardGeometry(id: "pulse-refresh", role: "button")
                        Button(entry.launchdStatus?.isLoaded == true ? DashboardL10n.tr("dashboard.scheduled_pulse.stop", "Stop") : DashboardL10n.tr("dashboard.scheduled_pulse.start", "Start")) {
                            handle(entry.launchdStatus?.isLoaded == true ? store.stopScheduledJob(entry.id) : store.startScheduledJob(entry.id))
                        }
                        .buttonStyle(.bordered).frame(minWidth: 28, minHeight: 28).captureDashboardGeometry(id: "pulse-service", role: "button")
                        Button(DashboardL10n.tr("dashboard.scheduled_pulse.copy_command", "Copy diagnostic command")) { store.copyScheduledJobCommand(ScheduledJobStatus(definition: entry.definition, health: .healthy)) }
                            .buttonStyle(.bordered).frame(minWidth: 28, minHeight: 28).captureDashboardGeometry(id: "pulse-diagnostics", role: "button")
                    }
                }
                .padding(16)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(DashboardL10n.tr("dashboard.scheduled_pulse.empty", "No scheduled job receipts"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 180, alignment: .leading).padding(16)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.neutrals.border, lineWidth: 1) }
    }

    @ViewBuilder
    private func overviewContent(for entry: ScheduledJobFrameworkEntry) -> some View {
        let sections = ScheduledJobFrameworkLogic.parseOverview(entry.state?.overviewMd)
        if sections.isEmpty {
            Text(entry.state?.summary ?? DashboardL10n.tr("dashboard.scheduled_pulse.no_success_receipt", "No successful execution receipt yet; unknown is not failure."))
                .font(.body).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.heading).font(.subheadline.weight(.semibold))
                        let split = ScheduledJobFrameworkLogic.prioritizedBullets(for: section)
                        ForEach(Array(split.visible.enumerated()), id: \.offset) { _, bullet in
                            Label(bullet, systemImage: "circle.fill")
                                .font(.caption)
                                .labelStyle(.titleAndIcon)
                        }
                        if !split.collapsed.isEmpty {
                            Text(DashboardL10n.format("dashboard.scheduled_pulse.more_format", "+%lld more", split.collapsed.count))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.42), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func terminalLog(for entry: ScheduledJobFrameworkEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "terminal")
                Text(".a6l-log").fontWeight(.semibold)
                Spacer()
                Text(entry.definition.id.rawValue).foregroundStyle(.secondary)
            }
            .font(.system(.caption, design: .monospaced))
            ForEach(Array(diagnosticLines(for: entry).enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Text(line.level).foregroundStyle(line.color).frame(width: 42, alignment: .leading)
                    Text(line.message).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                }
                .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color(red: 0.09, green: 0.14, blue: 0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityIdentifier("a6l-log")
    }

    private func diagnosticLines(for entry: ScheduledJobFrameworkEntry) -> [(level: String, message: String, color: Color)] {
        let timestamp = entry.lastRunAt?.formatted(date: .abbreviated, time: .shortened) ?? DashboardL10n.tr("dashboard.scheduled_pulse.last_run.never", "never")
        let service = entry.launchdStatus.map { $0.isLoaded ? "loaded" : "unloaded" } ?? "unavailable"
        let pid = entry.launchdStatus?.runningPID.map(String.init) ?? "—"
        let exit = entry.launchdExitCode.map(String.init) ?? "—"
        var lines: [(String, String, Color)] = [
            ("INFO", "last run: \(timestamp)", theme.primary.onPrimarySubtle),
            ("INFO", "launchd: \(service) · pid \(pid) · exit \(exit)", theme.primary.onPrimarySubtle)
        ]
        if entry.semanticState == .failed {
            lines.append(("ERROR", "result: \(entry.statusText)", theme.dangerOnSubtle))
        } else if entry.semanticState == .partial || entry.semanticState == .noState {
            lines.append(("WARN", "result: \(entry.statusText)", theme.warningOnSubtle))
        }
        let overviewLines = ScheduledJobFrameworkLogic.parseOverview(entry.state?.overviewMd)
            .flatMap { $0.bullets }
            .prefix(2)
        for bullet in overviewLines {
            let isWarning = bullet.uppercased().contains("FAIL") || bullet.uppercased().contains("PENDING")
            lines.append((isWarning ? "WARN" : "INFO", bullet, isWarning ? theme.warningOnSubtle : theme.primary.onPrimarySubtle))
        }
        lines.append(("INFO", "$ \(entry.definition.commandHint ?? "launchctl print gui/$(id -u)/\(entry.definition.launchAgentLabel)")", theme.primary.onPrimarySubtle))
        return lines
    }

    private var selectedEntry: ScheduledJobFrameworkEntry? {
        let entries = store.scheduledJobFrameworkSnapshot.overviewEntries
        return entries.first { $0.id == store.selectedFrameworkJobID } ?? entries.first
    }

    @State private var hoveredJobID: ScheduledPulseJobID?
    @Environment(\.appearsActive) private var appearsActive

    public static func categorizedCompartments(from entries: [ScheduledJobFrameworkEntry]) -> [ScheduledPulseCompartment] {
        let exceptions = entries.filter { $0.isProblem || !$0.actions.isEmpty }
        let routineEntries = entries.filter { !exceptions.contains($0) }
        let daily = routineEntries.filter { if case .daily = $0.definition.cadence { return true }; return false }
        let interval = routineEntries.filter { if case .interval = $0.definition.cadence { return true }; return false }
        return [
            ScheduledPulseCompartment(id: "exceptions", title: DashboardL10n.tr("dashboard.scheduled_pulse.compartment.exceptions", "异常与待处理"), entries: exceptions),
            ScheduledPulseCompartment(id: "daily", title: DashboardL10n.tr("dashboard.scheduled_pulse.compartment.daily", "每日核心流水线 (04:00–05:00)"), entries: daily),
            ScheduledPulseCompartment(id: "interval", title: DashboardL10n.tr("dashboard.scheduled_pulse.compartment.interval", "高频同步与巡检 (1m–5m)"), entries: interval)
        ]
    }

    private var pulseHealthStrip: some View {
        HStack(spacing: 8) {
            pulseMetric(title: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.online", "Online jobs"), value: loadedJobsText, detail: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.registration", "LaunchAgent registration"))
            pulseMetric(title: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.recent", "Recent run"), value: latestRunText, detail: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.success_priority", "Job receipt · not service load time"))
            pulseMetric(title: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.health", "Stage health"), value: stageHealthText, detail: DashboardL10n.format("dashboard.scheduled_pulse.kpi.actions_format", "%lld pending decisions", store.scheduledJobFrameworkSnapshot.unacknowledgedActions.count))
            HStack(spacing: 6) {
                ForEach(ScheduledPulsePageTab.allCases) { tab in
                    Button(tab.title) { store.scheduledPulseTab = tab }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(store.scheduledPulseTab == tab ? theme.primary.primary : theme.neutrals.text(.body))
                        .frame(minWidth: 28, minHeight: 28)
                        .accessibilityAddTraits(store.scheduledPulseTab == tab ? .isSelected : [])
                        .captureDashboardGeometry(id: "pulse-tab-\(tab.id)", role: "button")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pulseMetric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.monospacedDigit()).fixedSize(horizontal: true, vertical: false)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 1) }
    }

    private var latestRunText: String {
        let dates = store.scheduledJobFrameworkSnapshot.entries.compactMap { $0.state?.lastRunAt }
        guard let date = dates.max() else { return DashboardL10n.tr("dashboard.scheduled_pulse.unknown", "未知") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var stageHealthText: String {
        let stages = store.scheduledJobFrameworkSnapshot.entries.flatMap { $0.state?.stages ?? [] }
        if stages.contains(where: { $0.semanticState == .running }) { return ScheduledStageState.running.title }
        guard !stages.isEmpty, stages.allSatisfy(\.isKnown) else { return DashboardL10n.tr("dashboard.scheduled_pulse.unknown", "未知") }
        return "\(stages.filter(\.isSuccess).count)/\(max(5, stages.count))"
    }

    private var loadedJobsText: String {
        let entries = store.scheduledJobFrameworkSnapshot.entries.filter { $0.definition.isLive }
        guard entries.contains(where: { $0.launchdStatus != nil }) else { return DashboardL10n.tr("dashboard.scheduled_pulse.unknown", "未知") }
        return "\(entries.filter { $0.launchdStatus?.isLoaded == true }.count)/\(entries.count)"
    }

    private func jobColor(_ state: ScheduledJobSemanticState) -> Color {
        switch state {
        case .running: return theme.primary.onPrimarySubtle
        case .healthy: return theme.successOnSubtle
        case .partial: return theme.warningOnSubtle
        case .failed: return theme.dangerOnSubtle
        case .noState, .coalesced: return theme.neutrals.text(.body)
        }
    }

    private func stageColor(_ state: ScheduledStageState) -> Color {
        switch state {
        case .running: return theme.primary.onPrimarySubtle
        case .passed: return theme.successOnSubtle
        case .warning: return theme.warningOnSubtle
        case .failed: return theme.dangerOnSubtle
        case .unknown: return theme.neutrals.text(.body)
        }
    }

    private var frameworkControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.scheduledJobFrameworkSnapshot.entries) { entry in
                HStack(spacing: 8) {
                    Text(entry.definition.displayName)
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 4)
                    Button(DashboardL10n.tr("dashboard.scheduled_pulse.start", "启动")) {
                        handle(store.startScheduledJob(entry.id))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button(DashboardL10n.tr("dashboard.scheduled_pulse.stop", "停止")) {
                        handle(store.stopScheduledJob(entry.id))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func overviewBlock(_ entry: ScheduledJobFrameworkEntry) -> some View {
        return VStack(alignment: .leading, spacing: Space.gap) {
            HStack(spacing: 8) {
                Text(entry.definition.displayName).font(.headline)
                Spacer(minLength: 4)
                Text(entry.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(jobColor(entry.semanticState))
            }
            Text("\(entry.definition.launchAgentLabel) · \(entry.definition.interpreterPath ?? "")")
                .font(.caption).foregroundStyle(theme.neutrals.text(.body))
                .fixedSize(horizontal: false, vertical: true)
            if let asOf = entry.state?.sourceAsOf {
                Text(DashboardL10n.format("dashboard.scheduled_pulse.source_as_of", "数仓观测截至 %@", asOf)).font(.caption)
            }
            if let overviewMd = entry.state?.overviewMd, !overviewMd.isEmpty {
                Text(overviewMd).font(.body).fixedSize(horizontal: false, vertical: true)
            } else if let summary = entry.state?.summary, !summary.isEmpty {
                Text(summary).font(.body).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(DashboardL10n.tr("dashboard.scheduled_pulse.no_success_receipt", "尚无成功执行回执；状态未知，不视为失败。"))
                    .font(.body).foregroundStyle(.secondary)
            }
            stageReceiptStrip(for: entry)
            if !entry.actions.isEmpty {
                Button {
                    store.selectedFrameworkJobID = entry.id
                    store.selectedSection = .actionItems
                } label: {
                    Label(DashboardL10n.format("dashboard.scheduled_pulse.pending_actions_format", "去待办处理 (%lld)", entry.actions.count), systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            HStack(spacing: 8) {
                Button(DashboardL10n.tr("dashboard.scheduled_pulse.run_now", "立即运行")) { store.runScheduledJobNow(entry.id) }
                    .buttonStyle(.borderedProminent).controlSize(.small).frame(minHeight: 28)
                    .disabled(store.runningJobIDs.contains(entry.id) || !entry.definition.isLive)
                    .captureDashboardGeometry(id: "pulse-run", role: "button")
                if store.runningJobIDs.contains(entry.id) { ProgressView().controlSize(.small) }
                Button(DashboardL10n.tr("dashboard.scheduled_pulse.refresh_status", "刷新状态")) { store.refreshFromProvider() }
                    .buttonStyle(.bordered).controlSize(.small).frame(minHeight: 28)
                    .captureDashboardGeometry(id: "pulse-refresh", role: "button")
                Button(entry.launchdStatus?.isLoaded == true ? DashboardL10n.tr("dashboard.scheduled_pulse.stop", "停止") : DashboardL10n.tr("dashboard.scheduled_pulse.start", "启动")) {
                    handle(entry.launchdStatus?.isLoaded == true ? store.stopScheduledJob(entry.id) : store.startScheduledJob(entry.id))
                }.buttonStyle(.bordered).controlSize(.small).frame(minHeight: 28)
                    .disabled(!entry.definition.isLive)
                    .captureDashboardGeometry(id: "pulse-service", role: "button")
                Button(DashboardL10n.tr("dashboard.scheduled_pulse.copy_command", "复制诊断命令")) { store.copyScheduledJobCommand(ScheduledJobStatus(definition: entry.definition, health: .healthy)) }
                    .buttonStyle(.bordered).controlSize(.small).frame(minHeight: 28)
                    .captureDashboardGeometry(id: "pulse-diagnostics", role: "button")
            }
            .frame(minHeight: 28)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 1) }
    }

    private func stageReceiptStrip(for entry: ScheduledJobFrameworkEntry) -> some View {
        let stages = ScheduledPulseStageCatalog.stages(for: entry)
        return HStack(alignment: .top, spacing: 6) {
            ForEach(Array(stages.enumerated()), id: \.1.id) { index, stage in
                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.title).font(.caption.weight(.semibold)).lineLimit(2)
                    Capsule()
                        .fill(stageColor(stage.semanticState).opacity(0.82))
                        .frame(height: 4)
                    Text(stage.semanticState.title).font(.caption2.weight(.medium)).foregroundStyle(stageColor(stage.semanticState))
                    if let exitCode = stage.exitCode, stage.semanticState != .running {
                        Text("exit \(exitCode)").font(.caption2.monospacedDigit()).fixedSize()
                    }
                    if let duration = stage.durationSec {
                        Text("\(duration, specifier: "%.1f")s").font(.caption2.monospacedDigit())
                    }
                    if let asOf = stage.sourceAsOf { Text(asOf).font(.caption2).lineLimit(1) }
                }
                .padding(7)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(stageColor(stage.semanticState).opacity(0.18))
                        .frame(width: 3)
                }
                .captureDashboardGeometry(id: "stage-\(index)", role: "pulseStageTile")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .captureDashboardGeometry(id: "pulse-stages", role: "pulseStageGrid")
    }

    private var needActions: some View {
        let actions = store.scheduledJobFrameworkSnapshot.unacknowledgedActions.filter { action in
            store.selectedFrameworkJobID == nil || action.jobID == store.selectedFrameworkJobID
        }
        return SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.scheduled_pulse.need_actions.title", "需要处理"),
            subtitle: DashboardL10n.tr("dashboard.scheduled_pulse.need_actions.subtitle", "任务自己声明控件；回执只写 UserEvent"),
            symbolName: "checklist"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if actions.isEmpty {
                    Text(DashboardL10n.tr("dashboard.scheduled_pulse.need_actions.empty", "没有需要你拍板的事。"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                } else {
                    ForEach(actions) { action in
                        ScheduledJobActionView(action: action) { responses in
                            store.acknowledgeScheduledAction(action, responses: responses)
                        }
                    }
                }
            }
        }
    }

    private func select(_ entry: ScheduledJobFrameworkEntry) {
        store.selectedFrameworkJobID = entry.id
        store.scheduledPulseTab = .overview
    }

    private func handle(_ outcome: ScheduledPulseLaunchdInstaller.RegistrationOutcome) {
        installerError = outcome.failureDescription
    }
}

@MainActor
private struct ScheduledJobActionView: View {
    let action: ScheduledJobAction
    let onAcknowledge: ([ScheduledJobActionResponse]) -> Void
    @State private var values: [String: String] = [:]
    @State private var selectedValues: [String: Set<String>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(action.title).font(.headline)
            Text(action.descriptionMd).font(.body).foregroundStyle(.secondary)
            ForEach(action.controls) { control in controlView(control) }
            HStack {
                Spacer()
                Button(DashboardL10n.tr("dashboard.scheduled_pulse.need_actions.confirm", "确认")) {
                    let responses = action.resolvedResponses(
                        values: values,
                        selectedValues: selectedValues
                    )
                    onAcknowledge(responses)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 1) }
    }

    private func decisionLabel(_ option: String) -> String {
        switch option {
        case "Approve": return DashboardL10n.tr("dashboard.decision.approve", "Approve")
        case "Snooze 7d": return DashboardL10n.tr("dashboard.decision.snooze_7d", "Snooze 7d")
        case "Done": return DashboardL10n.tr("dashboard.decision.done", "Done")
        case "Dismiss": return DashboardL10n.tr("dashboard.decision.dismiss", "Dismiss")
        default: return option
        }
    }

    @ViewBuilder
    private func controlView(_ control: ScheduledJobActionControl) -> some View {
        switch control.kind {
        case .confirm:
            Label(control.title, systemImage: "checkmark.circle").font(.subheadline)
        case .singleSelect:
            Picker(control.title, selection: binding(for: control)) {
                ForEach(control.options, id: \.self) { option in Text(decisionLabel(option)).tag(option) }
            }
            .pickerStyle(.menu)
        case .multiSelect:
            VStack(alignment: .leading, spacing: 4) {
                Text(control.title).font(.subheadline.weight(.semibold))
                ForEach(control.options, id: \.self) { option in
                    Toggle(option, isOn: Binding(
                        get: { selectedValues[control.id, default: []].contains(option) },
                        set: { isOn in
                            if isOn { selectedValues[control.id, default: []].insert(option) } else { selectedValues[control.id, default: []].remove(option) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        case .textInput:
            TextField(control.title, text: Binding(
                get: { values[control.id] ?? "" },
                set: { values[control.id] = String($0.prefix(control.effectiveMaxLength)) }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    private func binding(for control: ScheduledJobActionControl) -> Binding<String> {
        Binding(
            get: { values[control.id] ?? control.options.first ?? "" },
            set: { values[control.id] = $0 }
        )
    }
}
#endif
