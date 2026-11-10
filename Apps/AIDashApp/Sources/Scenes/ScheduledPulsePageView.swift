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
            if store.scheduledJobFrameworkSnapshot.entries.isEmpty {
                store.refreshFromProvider()
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                            Text("\(entry.definition.displayName) \(entry.isSuccess ? "✓" : "✗")")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(entry.isSuccess ? .green : .orange)
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

            if store.scheduledJobFrameworkSnapshot.allHaveNoState {
                Text(DashboardL10n.tr("dashboard.scheduled_pulse.no_summary", "还没有汇总。"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(store.scheduledJobFrameworkSnapshot.overviewEntries) { entry in
                        overviewBlock(entry)
                    }
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
                Text(entry.isSuccess
                    ? DashboardL10n.tr("dashboard.scheduled_pulse.success", "成功")
                    : DashboardL10n.tr("dashboard.scheduled_pulse.needs_attention", "需要处理"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isProblem ? .orange : .green)
            }
            if let overviewMd = entry.state?.overviewMd, !overviewMd.isEmpty {
                Text(overviewMd).font(.body).fixedSize(horizontal: false, vertical: true)
            } else if let summary = entry.state?.summary, !summary.isEmpty {
                Text(summary).font(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if isProblem { Rectangle().fill(Color.orange).frame(width: 3) }
        }
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 1) }
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

    @ViewBuilder
    private func controlView(_ control: ScheduledJobActionControl) -> some View {
        switch control.kind {
        case .confirm:
            Label(control.title, systemImage: "checkmark.circle").font(.subheadline)
        case .singleSelect:
            Picker(control.title, selection: binding(for: control)) {
                ForEach(control.options, id: \.self) { option in Text(option).tag(option) }
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
