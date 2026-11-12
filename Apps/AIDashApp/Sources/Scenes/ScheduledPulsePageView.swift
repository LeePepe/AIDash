#if os(macOS)
import Darwin
import SwiftUI

@MainActor
public struct ScheduledPulsePageView: View {
    @Bindable public var store: DashboardWorkspaceStore
    @State private var installerError: String?
    @State private var expandedOverviewSections: Set<String> = []
    @State private var collapsedOverviewSections: Set<String> = []
    @State private var expandedOverflowSections: Set<String> = []

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
                    Text(tabTitle(tab)).tag(tab)
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
                        Button { select(entry) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: entry.semanticState.symbolName)
                                    .accessibilityHidden(true)
                                Text(entry.statusText)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DashboardSemanticColorPalette.color(for: entry.semanticState.semanticHealth))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(nsColor: .windowBackgroundColor), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(entry.definition.displayName), \(entry.statusText)")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.scheduledJobFrameworkSnapshot.overviewEntries) { entry in
                    scheduledJobCard(entry)
                }
            }

            if let installerError {
                Text(installerError)
                    .font(.caption)
                    .foregroundStyle(DashboardSemanticColorPalette.color(for: .critical))
            }
        }
    }

    private func scheduledJobCard(_ entry: ScheduledJobFrameworkEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.definition.displayName)
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(entry.definition.cadence.displayText)
                        if let lastRun = ScheduledJobTimeFormatting.relativeText(from: entry.lastRunAt) {
                            Text(lastRun)
                        } else {
                            Text(DashboardL10n.tr("dashboard.scheduled_pulse.time.never", "尚未运行"))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                statusPill(entry)
                Button(DashboardL10n.tr("dashboard.scheduled_pulse.run_now", "立即运行")) {
                    runNow(entry.id)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
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
            .frame(minHeight: 44)

            if let summary = entry.state?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                HStack(spacing: 6) {
                    ForEach(summary.split(separator: "·").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }, id: \.self) { part in
                        Text(part)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                    }
                    if !entry.actions.isEmpty {
                        Button(DashboardL10n.format("dashboard.scheduled_pulse.pending_actions_format", "%lld 个待处理", entry.actions.count)) {
                            store.selectedFrameworkJobID = entry.id
                            store.scheduledPulseTab = .needActions
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else if !entry.actions.isEmpty {
                Button(DashboardL10n.format("dashboard.scheduled_pulse.pending_actions_format", "%lld 个待处理", entry.actions.count)) {
                    store.selectedFrameworkJobID = entry.id
                    store.scheduledPulseTab = .needActions
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            let sections = ScheduledJobFrameworkLogic.parseOverview(entry.state?.overviewMd)
            if sections.isEmpty {
                if entry.state?.summary?.isEmpty != false && entry.lastTick == nil {
                    Text(DashboardL10n.tr("dashboard.scheduled_pulse.no_summary", "尚无汇总；等待 launchd 首次运行。"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                        overviewSection(section, id: "\(entry.id.rawValue):\(index)")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DashboardSemanticColorPalette.color(for: entry.semanticState.semanticHealth))
                .frame(width: 3)
        }
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(nsColor: .separatorColor), lineWidth: 1) }
    }

    private func statusPill(_ entry: ScheduledJobFrameworkEntry) -> some View {
        Label(entry.statusText, systemImage: entry.semanticState.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DashboardSemanticColorPalette.color(for: entry.semanticState.semanticHealth))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func overviewSection(_ section: ScheduledJobOverviewSection, id: String) -> some View {
        let bullets = ScheduledJobFrameworkLogic.prioritizedBullets(for: section)
        DisclosureGroup(isExpanded: sectionBinding(for: section, id: id)) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(bullets.visible, id: \.self) { bullet in
                    Text("• \(bullet)")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !bullets.collapsed.isEmpty {
                    DisclosureGroup(
                        DashboardL10n.format("dashboard.scheduled_pulse.expand_prs_format", "展开全部 %lld 个 PR", bullets.collapsed.count),
                        isExpanded: overflowBinding(for: id)
                    ) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(bullets.collapsed, id: \.self) { bullet in
                                Text("• \(bullet)")
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.top, 5)
        } label: {
            Text(section.heading)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func sectionBinding(for section: ScheduledJobOverviewSection, id: String) -> Binding<Bool> {
        Binding(
            get: {
                if section.isPriority { return !collapsedOverviewSections.contains(id) }
                return expandedOverviewSections.contains(id)
            },
            set: { expanded in
                if section.isPriority {
                    if expanded { collapsedOverviewSections.remove(id) } else { collapsedOverviewSections.insert(id) }
                } else if expanded {
                    expandedOverviewSections.insert(id)
                } else {
                    expandedOverviewSections.remove(id)
                }
            }
        )
    }

    private func overflowBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedOverflowSections.contains(id) },
            set: { expanded in
                if expanded { expandedOverflowSections.insert(id) } else { expandedOverflowSections.remove(id) }
            }
        )
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

    private func tabTitle(_ tab: ScheduledPulsePageTab) -> String {
        guard tab == .needActions else { return tab.title }
        let count = store.scheduledJobFrameworkSnapshot.unacknowledgedActions.count
        return count == 0 ? tab.title : DashboardL10n.format("dashboard.scheduled_pulse.tab.need_actions_count", "需要处理 (%lld)", count)
    }

    private func select(_ entry: ScheduledJobFrameworkEntry) {
        store.selectedFrameworkJobID = entry.id
        store.scheduledPulseTab = entry.actions.isEmpty ? .overview : .needActions
    }

    private func runNow(_ id: ScheduledPulseJobID) {
        guard let definition = ScheduledPulseRegistry.job(for: id) else { return }
        let result = ScheduledPulseLaunchdInstaller.productionLaunchctl([
            "kickstart", "-k", "gui/\(getuid())/\(definition.launchAgentLabel)"
        ])
        if result.succeeded {
            installerError = nil
            store.refreshFromProvider()
        } else {
            installerError = result.diagnosticSummary
        }
    }

    private func handle(_ outcome: ScheduledPulseLaunchdInstaller.RegistrationOutcome) {
        installerError = outcome.failureDescription
        if outcome.isHealthy { store.refreshFromProvider() }
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
