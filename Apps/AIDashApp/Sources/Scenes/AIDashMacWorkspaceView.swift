#if os(macOS)
// swiftlint:disable file_length
import AppKit
import SwiftUI
import AIDashUI

public enum OverviewWorkbenchLens: String, CaseIterable, Sendable, Equatable, Identifiable {
    case trends
    case rankings
    case actionItems
    case skills

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .trends: return DashboardL10n.tr("dashboard.lens.trends", "Token Trends")
        case .rankings: return DashboardL10n.tr("dashboard.lens.rankings", "M2 / M1 Ranking")
        case .actionItems: return DashboardL10n.tr("dashboard.lens.actions", "Actionable Items")
        case .skills: return "Skills ROI"
        }
    }

    public var symbolName: String {
        switch self {
        case .trends: return "chart.bar.xaxis"
        case .rankings: return "tablecells"
        case .actionItems: return "checklist"
        case .skills: return "sparkles.square.filled.on.square"
        }
    }
}

public struct SkillsRoiDiagnosticsCardView: View {
    let summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?
    @State private var lens = "Usage"

    public init(summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?) { self.summary = summary }

    public var body: some View {
        SolidModularCardContainer(title: DashboardL10n.tr("dashboard.skills_roi.title", "Skills 效能与上下文 ROI 诊断 (S1–S12)"), subtitle: freshnessText, symbolName: "sparkles.square.filled.on.square") {
            Picker(DashboardL10n.tr("dashboard.skills_roi.lens", "分析视角"), selection: $lens) {
                Text(DashboardL10n.tr("dashboard.skills_roi.usage", "Usage")).tag("Usage")
                Text(DashboardL10n.tr("dashboard.skills_roi.disclosure", "Disclosure / Escapes")).tag("Disclosure / Escapes")
                Text(DashboardL10n.tr("dashboard.skills_roi.context", "Context")).tag("Context")
            }
            .pickerStyle(.segmented).controlSize(.small).frame(maxWidth: 430)
            if let roi = summary?.skillsROI {
                let selected = roi.metrics.filter { key, _ in
                    switch lens {
                    case "Usage":
                        return key.hasPrefix("S1") || key.hasPrefix("S2") || key.hasPrefix("S3") || key.hasPrefix("S4") || key.hasPrefix("S6") || key.hasPrefix("S10")
                    case "Disclosure / Escapes":
                        return key.hasPrefix("S7") || key.hasPrefix("S8") || key.hasPrefix("S9")
                    default:
                        return key.hasPrefix("S11") || key.hasPrefix("S12")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(selected.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key).font(.caption.weight(.semibold))
                            Spacer()
                            Text(selected[key] ?? DashboardL10n.tr("dashboard.skills_roi.metric_unknown", "unknown")).font(.caption.monospacedDigit()).fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                .padding(.top, 4)
            } else {
                Text(DashboardL10n.tr("dashboard.skills_roi.missing", "unknown / missing · 等待 metadata-only skills-roi.json"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var freshnessText: String {
        guard let roi = summary?.skillsROI else { return DashboardL10n.tr("dashboard.skills_roi.coverage_unknown", "Coverage: unknown") }
        let window = roi.window ?? DashboardL10n.tr("dashboard.skills_roi.window_unknown", "unknown window")
        let asOf = roi.sourceAsOf ?? DashboardL10n.tr("dashboard.skills_roi.as_of_unknown", "unknown as_of")
        let sample = roi.sampleSize.map(String.init) ?? DashboardL10n.tr("dashboard.skills_roi.sample_unknown", "unknown sample")
        return "Window: \(window) · as of \(asOf) · sample \(sample) · \(roi.coverageStatus)"
    }
}

public struct ActionItemsCardView: View {
    @Bindable public var store: DashboardWorkspaceStore
    public var onToggleDone: ((String, String, Bool) -> Void)?
    @State private var expandedActionID: String?
    @State private var selectedDecisions: [String: String] = [:]
    @State private var selectedTargets: [String: Set<String>] = [:]
    @State private var noteInputs: [String: String] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        store: DashboardWorkspaceStore,
        onToggleDone: ((String, String, Bool) -> Void)? = nil
    ) {
        self.store = store
        self.onToggleDone = onToggleDone
    }

    public var body: some View {
        SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.card.actions.title", "Actionable Items"),
            subtitle: DashboardL10n.format(
                "dashboard.actions.subtitle_format",
                "%lld pending · %lld completed",
                store.pendingActionCount,
                store.completedActionCount
            ),
            symbolName: "checklist"
        ) {
            HStack(spacing: 12) {
                Picker(DashboardL10n.tr("dashboard.actions.filter_label", "Filter"), selection: $store.actionFilter) {
                    ForEach(DashboardActionFilter.allCases) { filter in
                        Text(filter.displayTitle).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)

                Menu {
                    Picker(DashboardL10n.tr("dashboard.actions.sort_by", "Sort By"), selection: $store.actionSort) {
                        ForEach(DashboardActionSort.allCases) { sort in
                            Text(sort.displayTitle).tag(sort)
                        }
                    }
                } label: {
                    Label(
                        DashboardL10n.format("dashboard.actions.sort_button_format", "Sort: %@", store.actionSort.displayTitle),
                        systemImage: "arrow.up.arrow.down"
                    )
                        .font(.caption)
                }
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 28)
            }
        } content: {
            domainSummaryStrip
            if store.filteredActionItems.isEmpty {
                actionEmptyStateContent
                    .frame(minHeight: 150)
            } else if store.selectedActionDomain == nil {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(DashboardActionDomain.allCases) { domain in
                        let items = store.filteredActionItems.filter { $0.resolvedDomain == domain }
                        if !items.isEmpty {
                            domainSection(domain, items: items)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(store.filteredActionItems) { item in actionItemRow(item) }
                }
            }
        }
    }

    private var domainSummaryStrip: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(DashboardActionDomain.allCases) { domain in
                let count = store.filteredActionItems.filter { !$0.isCompleted && $0.resolvedDomain == domain }.count
                Button {
                    store.selectedActionDomain = store.selectedActionDomain == domain ? nil : domain
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: domain.symbolName)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(domain.title).font(.caption.weight(.semibold))
                            Text(domain.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        Text("\(count)").font(.caption.monospacedDigit().weight(.bold)).fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(store.selectedActionDomain == domain ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(store.selectedActionDomain == domain ? Color.accentColor : Color.primary)
                .help(domain.subtitle)
            }
        }
    }

    private func domainSection(_ domain: DashboardActionDomain, items: [DashboardActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: domain.symbolName)
                Text(domain.title).font(.caption.weight(.semibold))
                Text("\(items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
            }
            ForEach(items) { item in actionItemRow(item) }
        }
    }

    @ViewBuilder
    private var actionEmptyStateContent: some View {
        if store.actionItems.isEmpty {
            ContentUnavailableView {
                Label(
                    DashboardL10n.tr("menubar.pulse.empty_healthy_title", "System & CLI quotas are all healthy"),
                    systemImage: "checkmark.shield.fill"
                )
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.green)
            } description: {
                Text(DashboardL10n.tr("menubar.pulse.empty_healthy_desc", "Zero approval blockers, quota alerts, or memory pressure warnings."))
            } actions: {
                Button(DashboardL10n.tr("dashboard.toolbar.refresh", "Refresh")) {
                    store.refreshFromProvider()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if store.pendingActionCount == 0 && store.actionFilter == .pending {
            ContentUnavailableView {
                Label(
                    DashboardL10n.tr("menubar.pulse.empty_resolved_title", "All actionable items resolved"),
                    systemImage: "checkmark.seal.fill"
                )
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.green)
            } description: {
                Text(
                    DashboardL10n.format(
                        "menubar.pulse.empty_resolved_desc_format",
                        "Cleared %lld item(s). Click 'Undo' above to restore.",
                        store.completedActionCount
                    )
                )
            } actions: {
                Button(DashboardL10n.tr("dashboard.action_filter.completed", "Completed")) {
                    store.actionFilter = .completed
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        } else {
            ContentUnavailableView {
                Label(DashboardL10n.tr("dashboard.actions.empty_title", "No Matching Actionable Items"), systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(DashboardL10n.tr("dashboard.actions.empty_desc", "No actionable items match the active filter combination."))
            } actions: {
                if store.hasScopedSubFilter {
                    Button(DashboardL10n.tr("dashboard.actions.reset_filter", "Reset Scoped Filter")) {
                        store.clearScopedFilterOnly()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private func statusTintColor(for status: DashboardActionStatus) -> Color {
        switch status {
        case .triage: return .purple
        case .blocked: return .red
        case .inProgress: return .blue
        case .done: return .green
        }
    }

    private func actionItemRow(_ item: DashboardActionItem) -> some View {
        let priorityColor = DashboardSemanticColorPalette.color(for: item.priority.health)
        let statusColor = statusTintColor(for: item.status)
        let effectiveExpandedID = expandedActionID ?? store.filteredActionItems.first(where: { !$0.isCompleted })?.id
        let isExpanded = effectiveExpandedID == item.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Toggle(
                    isOn: Binding(
                        get: { item.isCompleted },
                        set: { _ in store.toggleActionItem(id: item.id, onToggleDone: onToggleDone) }
                    )
                ) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .frame(minWidth: 28, minHeight: 28)
                .accessibilityLabel(DashboardL10n.format("dashboard.actions.mark_completed_format", "Mark %@ as completed", item.title))

                Button {
                    let toggleBlock = { expandedActionID = isExpanded ? "__none__" : item.id }
                    if reduceMotion { toggleBlock() } else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { toggleBlock() }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(item.priority.label)
                            .font(.caption2.weight(.bold)).monospacedDigit().padding(.horizontal, 6).padding(.vertical, 2)
                            .background(priorityColor.opacity(0.16), in: Capsule()).foregroundStyle(priorityColor)
                        Label(item.status.displayTitle, systemImage: item.status.symbolName)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(statusColor)
                        Label(item.sourceTag, systemImage: item.sourceSymbolName)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                        Label(item.projectFolderName, systemImage: "folder")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                        Text(item.title).font(.body.weight(.medium)).strikethrough(item.isCompleted)
                            .foregroundStyle(item.isCompleted ? .secondary : .primary).lineLimit(1)
                        if let refLabel = item.displayRefLabel, !item.title.contains(refLabel) {
                            Text(refLabel)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                actionRowAccessoryButtons(item)
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.summary)
                        .font(.callout)
                        .lineSpacing(2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if item.isLearningTopic || item.isProposal {
                        specializedMetadata(for: item)
                    }
                    if let command = item.command {
                        Text("$ \(command)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if !item.isCompleted {
                        actionInlineDecisionBar(item)
                    }
                }
                .padding(.leading, 38)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
    }

    private func specializedMetadata(for item: DashboardActionItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let whyNow = item.whyNow { Label(whyNow, systemImage: "questionmark.circle") }
            if let sourceURI = item.sourceURI {
                Label(DashboardL10n.format("dashboard.actions.source_format", "来源: %@", sourceURI), systemImage: "link")
            }
            if !item.coverageRefs.isEmpty {
                Label(DashboardL10n.format("dashboard.actions.coverage_format", "覆盖: %@", item.coverageRefs.joined(separator: ", ")), systemImage: "checkmark.shield")
            }
            if let evidence = item.evidence { Label(evidence, systemImage: "chart.bar.doc.horizontal") }
            if let freshness = item.freshness { Label(freshness, systemImage: "clock") }
            Text(item.isLearningTopic ? DashboardL10n.tr("dashboard.learning.boundary", "批准后由后台启动 knowledge-digest；不自动发博客，不同步 design-studio。") : DashboardL10n.tr("dashboard.proposal.receipt_note", "审批记录 Owner 意图，不代表任务已完成；后续权威 Done/Dismiss 仍可生效。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private func actionInlineDecisionBar(_ item: DashboardActionItem) -> some View {
        let options = item.decisionOptions
        let defaultDecision = item.status == .inProgress && options.contains("Done") ? "Done" : (options.first ?? "Approve")
        let decisionBinding = Binding<String>(
            get: { selectedDecisions[item.id] ?? defaultDecision },
            set: { selectedDecisions[item.id] = $0 }
        )
        let noteBinding = Binding<String>(
            get: { noteInputs[item.id] ?? "" },
            set: { noteInputs[item.id] = String($0.prefix(item.noteMaxLength)) }
        )
        VStack(alignment: .leading, spacing: 6) {
            if !item.targetOptions.isEmpty {
                HStack(spacing: 10) {
                    Text(DashboardL10n.tr("dashboard.actions.targets_label", "Targets:"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(item.targetOptions, id: \.self) { target in
                        Toggle(
                            target,
                            isOn: Binding(
                                get: { selectedTargets[item.id, default: []].contains(target) },
                                set: { isOn in
                                    if isOn {
                                        selectedTargets[item.id, default: []].insert(target)
                                    } else {
                                        selectedTargets[item.id, default: []].remove(target)
                                    }
                                }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.caption)
                    }
                }
            }
            HStack(spacing: 8) {
                Picker(DashboardL10n.tr("dashboard.actions.decision_label", "Decision"), selection: decisionBinding) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)

                TextField(
                    DashboardL10n.tr("dashboard.actions.note_placeholder", "Note / instruction (optional, max 80 chars)"),
                    text: noteBinding
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 320)

                Button {
                    let chosenDecision = selectedDecisions[item.id] ?? defaultDecision
                    let chosenTargets = selectedTargets[item.id] ?? []
                    let chosenNote = noteInputs[item.id] ?? ""
                    store.submitActionItemDecision(
                        item,
                        decision: chosenDecision,
                        targets: chosenTargets,
                        note: chosenNote,
                        onToggleDone: onToggleDone
                    )
                } label: {
                    Label(
                        DashboardL10n.tr("dashboard.actions.submit_decision", "Apply"),
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(minHeight: 28)
            }
        }
        .padding(.top, 2)
    }

    private func actionRowAccessoryButtons(_ item: DashboardActionItem) -> some View {
        let isDispatched = store.lastDispatchedActionID == item.id
        return HStack(spacing: 6) {
            Button {
                store.dispatchActionToHerdr(item)
            } label: {
                Label(
                    isDispatched
                        ? DashboardL10n.tr("dashboard.actions.dispatched_herdr", "Sent to Herdr")
                        : DashboardL10n.tr("dashboard.actions.run_in_herdr", "Run in Herdr"),
                    systemImage: isDispatched ? "checkmark" : "terminal.fill"
                )
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(minHeight: 28)

            if let command = item.command {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    store.lastCopiedActionID = item.id
                } label: {
                    Label(
                        store.lastCopiedActionID == item.id
                            ? DashboardL10n.tr("dashboard.actions.copied", "Copied")
                            : DashboardL10n.tr("dashboard.actions.copy_command", "Copy Command"),
                        systemImage: store.lastCopiedActionID == item.id ? "checkmark" : "doc.on.doc"
                    )
                    .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.bordered).controlSize(.small).frame(minHeight: 28)
            }
            if let urlString = item.externalURLString, let url = URL(string: urlString) {
                Button { NSWorkspace.shared.open(url) } label: {
                    Label(DashboardL10n.tr("dashboard.actions.open_link", "Open"), systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered).controlSize(.small).frame(minHeight: 28)
            }
        }
    }
}

public struct RankingTableCardView: View {
    @Bindable public var store: DashboardWorkspaceStore

    public init(store: DashboardWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.card.ranking.title", "Agent & CLI Efficiency Ranking"),
            subtitle: DashboardL10n.tr("dashboard.card.ranking.subtitle", "Select a row to inspect detailed execution telemetry in-place"),
            symbolName: "tablecells"
        ) {
            Button {
                store.rankingAscending.toggle()
            } label: {
                Label(
                    store.rankingAscending
                        ? DashboardL10n.tr("dashboard.ranking.sort_asc", "Runs: Ascending")
                        : DashboardL10n.tr("dashboard.ranking.sort_desc", "Runs: Descending"),
                    systemImage: store.rankingAscending ? "arrow.up" : "arrow.down"
                )
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minHeight: 28)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Table(store.filteredRankingRows, selection: $store.selectedRankingRowID) {
                    TableColumn(DashboardL10n.tr("dashboard.ranking.col_role", "M2 / M1 Role"), value: \.agentName)
                    TableColumn(DashboardL10n.tr("dashboard.ranking.col_model", "Model")) { row in
                        Text(row.modelName.isEmpty ? row.providerName : row.modelName)
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                    }
                    TableColumn(DashboardL10n.tr("dashboard.ranking.col_provider", "CLI Provider"), value: \.providerName)
                    TableColumn(DashboardL10n.tr("dashboard.ranking.col_runs", "Runs")) { row in
                        Text(row.runs.formatted(.number))
                            .monospacedDigit()
                    }
                    TableColumn(DashboardL10n.tr("dashboard.ranking.col_tokens", "Tokens")) { row in
                        Text(DashboardTokenFormatter.compact(row.totalTokens))
                            .monospacedDigit()
                    }
                    TableColumn(DashboardL10n.tr("dashboard.ranking.col_latency", "Avg Latency")) { row in
                        HStack(spacing: 4) {
                            Image(systemName: row.health.symbolName)
                                .foregroundStyle(DashboardSemanticColorPalette.color(for: row.health))
                            Text(DashboardL10n.format("dashboard.ranking.latency_value_format", "%.1fs", row.avgDurationSeconds))
                                .monospacedDigit()
                        }
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 165)

                if let selected = store.selectedRankingRow {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(selected.agentName) · \(selected.modelName.isEmpty ? selected.providerName : selected.modelName)")
                                .font(.subheadline.weight(.semibold))
                            Text(selected.detailSummary)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            if let issue = selected.recentIssue {
                                Text(issue)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor))
                    )
                }
            }
        }
    }
}

public struct AIDashMacWorkspaceView: View {
    @State private var store: DashboardWorkspaceStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var activeOverviewLens: OverviewWorkbenchLens = .trends
    @Environment(\.onToggleDone) private var onToggleDone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        store: DashboardWorkspaceStore? = nil,
        scheduledActionWriter: ((ScheduledJobAction, [ScheduledJobActionResponse]) -> Bool)? = nil,
        acknowledgedScheduledActionIDs: Set<String> = []
    ) {
        let resolvedStore = store ?? DashboardWorkspaceStore.shared
        resolvedStore.scheduledActionWriter = scheduledActionWriter
        resolvedStore.acknowledgedScheduledActionIDs = acknowledgedScheduledActionIDs
        _store = State(initialValue: resolvedStore)
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if case let .populated(snapshot) = store.systemState {
                        workspaceDetailContent(snapshot: snapshot)
                    }
                }
                .padding(20)
                .frame(maxWidth: 1280, alignment: .leading)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .navigationTitle(store.selectedSection.title)
            .toolbar {
                if store.selectedSection != .settings && store.selectedSection != .scheduledPulse {
                    ToolbarItem(placement: .principal) {
                        unifiedDateNavigationToolbarCluster
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        if case let .populated(snapshot) = store.systemState {
                            hardwareCompanionPill(snapshot: snapshot)
                        }
                        refreshToolbarButton
                    }
                }
            }
        }
    }

    private var unifiedDateNavigationToolbarCluster: some View {
        HStack(spacing: 6) {
            Button {
                store.selectPreviousDate()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .disabled(!store.canSelectPreviousDate)

            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.selectedDateString)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            Button {
                store.selectNextDate()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .disabled(!store.canSelectNextDate)

            Divider()
                .frame(height: 14)

            Button(DashboardL10n.tr("dashboard.toolbar.today", "Today")) {
                store.selectToday()
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.65), in: Capsule())
    }

    private var refreshToolbarButton: some View {
        Button {
            if reduceMotion {
                store.refreshFromProvider()
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    store.refreshFromProvider()
                }
            }
        } label: {
            Label(DashboardL10n.tr("dashboard.toolbar.refresh", "Refresh"), systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .keyboardShortcut("r", modifiers: .command)
    }

    private func hardwareCompanionPill(snapshot: MenuBarSystemSnapshot) -> some View {
        let cpuPct = Int((snapshot.cpu.usage * 100).rounded())
        let memStr = MenuBarStatusView.compactMemoryPair(used: snapshot.memory.usedBytes, total: snapshot.memory.totalBytes)
        let isWarn = snapshot.cpu.usage >= 0.75 || snapshot.memory.pressure != .normal
        let tint: Color = isWarn ? .orange : .secondary
        return Button {
            store.selectedSection = .systemAndCosts
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu").font(.caption2).foregroundStyle(tint)
                Text("CPU \(cpuPct)% · \(memStr)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.75), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(
            DashboardL10n.format(
                "dashboard.telemetry.load_avg_format",
                "Load %.1f / %.1f / %.1f",
                snapshot.cpu.loadOneMinute,
                snapshot.cpu.loadFiveMinutes,
                snapshot.cpu.loadFifteenMinutes
            )
        )
    }

    private var sidebarContent: some View {
        List(selection: $store.selectedSection) {
            Section(DashboardL10n.tr("dashboard.sidebar.title", "AIDash Workspace")) {
                ForEach(DashboardWorkspaceSection.primaryNavigationSections) { section in
                    Label(section.title, systemImage: section.symbolName)
                        .badge(badgeCount(for: section))
                        .tag(section)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(DashboardL10n.format("dashboard.sidebar.today_tokens_format", "Today %@ tok", DashboardTokenFormatter.compact(store.todayGrandTotalTokens)))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        store.selectedSection = .settings
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: DashboardWorkspaceSection.settings.symbolName)
                            Text(DashboardWorkspaceSection.settings.title)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            store.selectedSection == .settings
                                ? Color.accentColor.opacity(0.18)
                                : Color(nsColor: .windowBackgroundColor).opacity(0.75),
                            in: Capsule()
                        )
                        .foregroundStyle(store.selectedSection == .settings ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(",", modifiers: .command)
                    .accessibilityLabel(DashboardWorkspaceSection.settings.title)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private func badgeCount(for section: DashboardWorkspaceSection) -> Int {
        switch section {
        case .overview, .actionItems:
            return store.pendingActionCount
        case .scheduledPulse:
            return store.scheduledJobFrameworkSnapshot.entries.filter(\.isProblem).count
        case .systemAndCosts:
            return store.highestQuotaWarningCount
        case .agentEfficiency, .settings:
            return 0
        }
    }

    @ViewBuilder
    private func workspaceDetailContent(snapshot: MenuBarSystemSnapshot) -> some View {
        switch store.selectedSection {
        case .overview:
            // Axis Y Cap: Strictly 3 Visual Container Groups (Overview -> Zoom & Filter -> Details-on-Demand Lens)
            KPISummaryCardView(metrics: store.effectiveKPIMetrics) { metricID in
                switch metricID {
                case "kpi-invocations", "kpi-efficiency": activeOverviewLens = .rankings
                case "kpi-actions": activeOverviewLens = .actionItems
                default: activeOverviewLens = .trends
                }
            }
            CLICostQuotaCardView(
                entries: store.filteredCLIEntries,
                todayTotalUSD: store.todayTotalCostUSD,
                periodTotalUSD: store.periodTotalCostUSD,
                selectedCategory: store.selectedChartCategory,
                onSelectCategory: { store.toggleChartCategory($0) }
            )
            overviewWorkbenchLensSection
        case .scheduledPulse:
            ScheduledPulsePageView(store: store)
        case .agentEfficiency:
            KPISummaryCardView(metrics: store.effectiveKPIMetrics)
            TrendChartCardView(
                points: store.filteredTrendPoints,
                selectedCategory: store.selectedChartCategory,
                onSelectCategory: { store.toggleChartCategory($0) },
                onClearSelection: { store.clearChartSelection() }
            )
            RankingTableCardView(store: store)
            SkillsRoiDiagnosticsCardView(summary: store.liveEfficiencySummary)
        case .actionItems:
            KPISummaryCardView(metrics: store.effectiveKPIMetrics)
            ActionItemsCardView(store: store, onToggleDone: onToggleDone)
        case .systemAndCosts:
            SystemTelemetryStripView(snapshot: snapshot)
            CLICostQuotaCardView(
                entries: store.filteredCLIEntries,
                todayTotalUSD: store.todayTotalCostUSD,
                periodTotalUSD: store.periodTotalCostUSD,
                selectedCategory: store.selectedChartCategory,
                onSelectCategory: { store.toggleChartCategory($0) }
            )
            TrendChartCardView(
                points: store.filteredTrendPoints,
                selectedCategory: store.selectedChartCategory,
                onSelectCategory: { store.toggleChartCategory($0) },
                onClearSelection: { store.clearChartSelection() },
                showInlineCrossFilterPills: false
            )
        case .settings:
            DashboardSettingsPageView(store: store)
        }
    }

    private var overviewWorkbenchLensSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label(
                    DashboardL10n.tr("dashboard.lens.section_title", "Analytical & Execution Workbench"),
                    systemImage: "rectangle.3.group"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Picker(DashboardL10n.tr("dashboard.lens.picker_label", "Workbench Lens"), selection: $activeOverviewLens) {
                    ForEach(OverviewWorkbenchLens.allCases) { lens in
                        Text(lensTitleWithBadge(lens)).tag(lens)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 380)
            }
            .padding(.horizontal, 4)

            switch activeOverviewLens {
            case .trends:
                TrendChartCardView(
                    points: store.filteredTrendPoints,
                    selectedCategory: store.selectedChartCategory,
                    onSelectCategory: { store.toggleChartCategory($0) },
                    onClearSelection: { store.clearChartSelection() },
                    showInlineCrossFilterPills: false
                )
            case .rankings:
                RankingTableCardView(store: store)
            case .actionItems:
                ActionItemsCardView(store: store, onToggleDone: onToggleDone)
            case .skills:
                SkillsRoiDiagnosticsCardView(summary: store.liveEfficiencySummary)
            }
        }
    }

    private func lensTitleWithBadge(_ lens: OverviewWorkbenchLens) -> String {
        if lens == .actionItems && store.pendingActionCount > 0 {
            return "\(lens.title) (\(store.pendingActionCount))"
        }
        return lens.title
    }
}
#endif
