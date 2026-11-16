#if os(macOS)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(compartment.title).font(.caption.weight(.semibold))
                Spacer()
                Text("\(compartment.entries.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(compartment.entries) { entry in
                let expanded = hoveredJobID == entry.id || selectedEntryID == entry.id
                Button { select(entry) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Circle().fill(color(entry.semanticState)).frame(width: 8, height: 8)
                            Text(entry.definition.displayName).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(entry.definition.cadence.displayText).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        if expanded {
                            HStack {
                                Text(entry.statusText).font(.caption.weight(.semibold)).foregroundStyle(color(entry.semanticState))
                                if let date = entry.lastRunAt, let relative = ScheduledJobTimeFormatting.relativeText(from: date) { Text(relative).font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(entry.state?.summary ?? entry.state?.overviewMd ?? "—").font(.caption).lineLimit(1).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Button(DashboardL10n.tr("dashboard.scheduled_pulse.run_now", "立即运行")) { run(entry) }
                                Button(entry.launchdStatus?.isLoaded == true ? DashboardL10n.tr("dashboard.scheduled_pulse.stop", "停止") : DashboardL10n.tr("dashboard.scheduled_pulse.start", "启动")) { toggle(entry) }
                                Button(DashboardL10n.tr("dashboard.scheduled_pulse.copy_command", "复制诊断命令")) { copy(entry) }
                            }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                }
                .buttonStyle(.plain)
                .onHover { hoveredJobID = $0 ? entry.id : nil }
                .animation(.spring(response: 0.36, dampingFraction: 0.8), value: hoveredJobID)
            }
            if compartment.entries.isEmpty { Text("—").font(.caption).foregroundStyle(.tertiary) }
        }
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
            HStack(spacing: Space.gap / 2) {
                ForEach(ScheduledPulsePageTab.allCases) { tab in
                    Button(tab.title) { store.scheduledPulseTab = tab }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tint(store.scheduledPulseTab == tab ? theme.primary.primary : theme.neutrals.text(.body))
                        .frame(minWidth: 28, minHeight: 28)
                        .accessibilityAddTraits(store.scheduledPulseTab == tab ? .isSelected : [])
                        .captureDashboardGeometry(id: "pulse-tab-\(tab.id)", role: "button")
                }
            }

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
            if let installerError {
                Text(installerError).font(.caption).foregroundStyle(theme.dangerOnSubtle)
            }
        }
    }

    private var organizerBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(DashboardL10n.tr("dashboard.scheduled_pulse.result.title", "定时任务结果"), systemImage: "folder")
                    .font(.headline)
                Spacer()
                Text(DashboardL10n.tr("dashboard.scheduled_pulse.organizer.subtitle", "按分类收纳"))
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
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.definition.displayName).font(.title3.weight(.semibold))
                            Text("\(entry.statusText) · \(entry.definition.launchAgentLabel)").font(.caption).foregroundStyle(jobColor(entry.semanticState))
                            if let asOf = entry.state?.sourceAsOf { Text(asOf).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if !entry.actions.isEmpty {
                            Button(DashboardL10n.tr("dashboard.scheduled_pulse.pending_actions", "去待办处理")) {
                                store.selectedSection = .actionItems
                                store.scheduledPulseTab = .needActions
                            }.buttonStyle(.borderedProminent).controlSize(.small).frame(minHeight: 28)
                        }
                    }
                    stageReceiptStrip(entry.state?.stages ?? [])
                    Text(entry.state?.summary ?? entry.state?.overviewMd ?? DashboardL10n.tr("dashboard.scheduled_pulse.no_success_receipt", "尚无成功执行回执；状态未知，不视为失败。"))
                        .font(.body).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(DashboardL10n.tr("dashboard.scheduled_pulse.run_now", "立即运行")) { store.runScheduledJobNow(entry.id) }
                            .buttonStyle(.borderedProminent).frame(minWidth: 28, minHeight: 28).captureDashboardGeometry(id: "pulse-run", role: "button")
                        Button(DashboardL10n.tr("dashboard.scheduled_pulse.refresh_status", "刷新状态")) { store.refreshFromProvider() }
                            .buttonStyle(.bordered).frame(minWidth: 28, minHeight: 28).captureDashboardGeometry(id: "pulse-refresh", role: "button")
                        Button(entry.launchdStatus?.isLoaded == true ? DashboardL10n.tr("dashboard.scheduled_pulse.stop", "停止") : DashboardL10n.tr("dashboard.scheduled_pulse.start", "启动")) {
                            handle(entry.launchdStatus?.isLoaded == true ? store.stopScheduledJob(entry.id) : store.startScheduledJob(entry.id))
                        }.buttonStyle(.bordered).frame(minWidth: 28, minHeight: 28).captureDashboardGeometry(id: "pulse-service", role: "button")
                        Button(DashboardL10n.tr("dashboard.scheduled_pulse.copy_command", "复制诊断命令")) { store.copyScheduledJobCommand(ScheduledJobStatus(definition: entry.definition, health: .healthy)) }
                            .buttonStyle(.bordered).frame(minWidth: 28, minHeight: 28).captureDashboardGeometry(id: "pulse-diagnostics", role: "button")
                    }
                }
                .padding(16)
            } else {
                Text(DashboardL10n.tr("dashboard.scheduled_pulse.empty", "暂无定时任务回执"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 180, alignment: .leading).padding(16)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.neutrals.border, lineWidth: 1) }
    }

    private var selectedEntry: ScheduledJobFrameworkEntry? {
        let entries = store.scheduledJobFrameworkSnapshot.overviewEntries
        return entries.first { $0.id == store.selectedFrameworkJobID } ?? entries.first
    }

    @State private var hoveredJobID: ScheduledPulseJobID?
    @Environment(\.appearsActive) private var appearsActive

    public static func categorizedCompartments(from entries: [ScheduledJobFrameworkEntry]) -> [ScheduledPulseCompartment] {
        let exceptions = entries.filter { $0.isProblem || !$0.actions.isEmpty }
        let daily = entries.filter { if case .daily = $0.definition.cadence { return true }; return false }
        let interval = entries.filter { if case .interval = $0.definition.cadence { return true }; return false }
        return [
            ScheduledPulseCompartment(id: "exceptions", title: DashboardL10n.tr("dashboard.scheduled_pulse.compartment.exceptions", "异常与待处理"), entries: exceptions),
            ScheduledPulseCompartment(id: "daily", title: DashboardL10n.tr("dashboard.scheduled_pulse.compartment.daily", "每日核心流水线 (04:00–05:00)"), entries: daily),
            ScheduledPulseCompartment(id: "interval", title: DashboardL10n.tr("dashboard.scheduled_pulse.compartment.interval", "高频同步与巡检 (1m–5m)"), entries: interval)
        ]
    }

    private var pulseHealthStrip: some View {
        HStack(spacing: 10) {
            pulseMetric(title: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.online", "在线任务"), value: loadedJobsText, detail: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.registration", "LaunchAgent 注册"))
            pulseMetric(title: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.recent", "最近运行"), value: latestRunText, detail: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.success_priority", "任务回执 · 非服务加载时间"))
            pulseMetric(title: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.health", "阶段健康"), value: stageHealthText, detail: DashboardL10n.format("dashboard.scheduled_pulse.kpi.actions_format", "待拍板 %lld 项", store.scheduledJobFrameworkSnapshot.unacknowledgedActions.count))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pulseMetric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).fixedSize(horizontal: true, vertical: false)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(10)
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
            stageReceiptStrip(entry.state?.stages ?? [])
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

    private func stageReceiptStrip(_ stages: [ScheduledJobStageReceipt]) -> some View {
        let titles = [
            DashboardL10n.tr("dashboard.scheduled_pulse.stage.collect", "① 个人源采集"),
            DashboardL10n.tr("dashboard.scheduled_pulse.stage.warehouse", "② L2/L3 入仓"),
            DashboardL10n.tr("dashboard.scheduled_pulse.stage.retro", "③ Retro/ROI 诊断"),
            DashboardL10n.tr("dashboard.scheduled_pulse.stage.learning", "④ 学习寻题"),
            DashboardL10n.tr("dashboard.scheduled_pulse.stage.brief", "⑤ Brief 投递")
        ]
        let ids = ["collect", "normalize_merge", "retro_roi", "learning_topics", "digest_push"]
        return Grid(horizontalSpacing: Space.gap / 2) {
            GridRow {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                let stage = stages.first { $0.id == ids[index] }
                let semantic = stage?.semanticState ?? .unknown
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.caption.weight(.semibold)).lineLimit(2)
                    Text(semantic.title).font(.caption.weight(.medium)).foregroundStyle(stageColor(semantic))
                    if semantic != .running, let exitCode = stage?.exitCode { Text("exit \(exitCode)").font(.caption2.monospacedDigit()).fixedSize() }
                    if let duration = stage?.durationSec { Text("\(duration, specifier: "%.1f")s").font(.caption2.monospacedDigit()) }
                    if let asOf = stage?.sourceAsOf { Text(asOf).font(.caption2).lineLimit(1) }
                }
                .padding(7)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .captureDashboardGeometry(id: "stage-\(index)", role: "pulseStageTile")
            }
            }
        }
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
        store.scheduledPulseTab = entry.actions.isEmpty ? .overview : .needActions
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
