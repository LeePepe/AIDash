#if os(macOS)
import SwiftUI

@MainActor
public struct ScheduledPulsePageView: View {
    @Bindable public var store: DashboardWorkspaceStore
    @State private var installerError: String?

    public init(store: DashboardWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(
                DashboardL10n.tr("dashboard.scheduled_pulse.page_picker", "页面"),
                selection: $store.scheduledPulseTab
            ) {
                ForEach(ScheduledPulsePageTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(maxWidth: 280)

            switch store.scheduledPulseTab {
            case .overview:
                overview
            case .needActions:
                needActions
            }
        }
        .onAppear {
            _ = ScheduledPulseLaunchdInstaller.shared.registerLiveJobs()
            if store.scheduledJobFrameworkSnapshot.entries.isEmpty {
                store.refreshFromProvider()
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            pulseHealthStrip
            SolidModularCardContainer(
                title: DashboardL10n.tr("dashboard.scheduled_pulse.result.title", "定时任务结果"),
                subtitle: DashboardL10n.tr("dashboard.scheduled_pulse.result.subtitle", "按登记表动态汇总 · 只读产出"),
                symbolName: "checkmark.circle"
            ) {
                HStack(spacing: 8) {
                    ForEach(store.scheduledJobFrameworkSnapshot.entries) { entry in
                        Button {
                            select(entry)
                        } label: {
                            Text("\(entry.definition.displayName) · \(entry.statusText)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(entry.semanticState.semanticHealth == .neutral ? Color.secondary : (entry.isProblem ? Color.orange : Color.green))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color(nsColor: .windowBackgroundColor), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(entry.definition.displayName)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.scheduledJobFrameworkSnapshot.entries) { entry in
                    overviewBlock(entry)
                }
            }

            frameworkControls

            if let installerError {
                Text(installerError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var pulseHealthStrip: some View {
        HStack(spacing: 10) {
            pulseMetric(title: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.online", "在线任务"), value: "\(store.scheduledPulseSnapshot.jobs.filter { $0.definition.isLive }.count)/\(store.scheduledPulseSnapshot.jobs.count)", detail: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.registration", "LaunchAgent 注册"))
            pulseMetric(title: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.recent", "最近运行"), value: latestRunText, detail: DashboardL10n.tr("dashboard.scheduled_pulse.kpi.success_priority", "成功回执优先"))
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
        let dates = store.scheduledJobFrameworkSnapshot.entries.compactMap(\.lastRunAt)
        guard let date = dates.max() else { return DashboardL10n.tr("dashboard.scheduled_pulse.unknown", "未知") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var stageHealthText: String {
        let stages = store.scheduledJobFrameworkSnapshot.entries.flatMap { $0.state?.stages ?? [] }
        guard !stages.isEmpty else { return DashboardL10n.tr("dashboard.scheduled_pulse.unknown", "未知") }
        return "\(stages.filter(\.isSuccess).count)/\(stages.count)"
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
        let isProblem = entry.isProblem
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(entry.definition.displayName).font(.headline)
                Spacer(minLength: 4)
                Text(entry.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.semanticState.semanticHealth == .neutral ? Color.secondary : (isProblem ? Color.orange : Color.green))
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
                    .buttonStyle(.borderedProminent).controlSize(.small).disabled(store.runningJobIDs.contains(entry.id))
                if store.runningJobIDs.contains(entry.id) { ProgressView().controlSize(.small) }
                Button(DashboardL10n.tr("dashboard.scheduled_pulse.refresh_status", "刷新状态")) { store.refreshFromProvider() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button(DashboardL10n.tr("dashboard.scheduled_pulse.copy_command", "复制诊断命令")) { store.copyScheduledJobCommand(ScheduledJobStatus(definition: entry.definition, health: .healthy)) }
                    .buttonStyle(.bordered).controlSize(.small)
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
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                let stage = stages.indices.contains(index) ? stages[index] : nil
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.caption.weight(.semibold)).lineLimit(2)
                    Text(stage?.isKnown == true ? (stage?.isSuccess == true ? DashboardL10n.tr("dashboard.scheduled_pulse.stage.passed", "通过") : DashboardL10n.tr("dashboard.scheduled_pulse.stage.error", "异常")) : DashboardL10n.tr("dashboard.scheduled_pulse.stage.unknown", "未知"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(stage?.isSuccess == true ? Color.green : (stage?.isKnown == true ? Color.orange : Color.secondary))
                    if let exitCode = stage?.exitCode { Text("exit \(exitCode)").font(.caption2.monospacedDigit()) }
                    if let duration = stage?.durationSec { Text("\(duration, specifier: "%.1f")s").font(.caption2.monospacedDigit()) }
                    if let asOf = stage?.sourceAsOf { Text(asOf).font(.caption2).lineLimit(1) }
                }
                .padding(7)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
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
