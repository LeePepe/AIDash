#if os(macOS)
import AppKit
import SwiftUI
import AIDashUI

public struct ActionItemsCardView: View {
    @Bindable public var store: DashboardWorkspaceStore
    public var onToggleDone: ((String, String, Bool) -> Void)?

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
            HStack(spacing: 8) {
                Picker(DashboardL10n.tr("dashboard.actions.filter_label", "Filter"), selection: $store.actionFilter) {
                    ForEach(DashboardActionFilter.allCases) { filter in
                        Text(filter.displayTitle).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

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
                .frame(minHeight: 28)
            }
        } content: {
            if store.filteredActionItems.isEmpty {
                ContentUnavailableView {
                    Label(DashboardL10n.tr("dashboard.actions.empty_title", "No Matching Actionable Items"), systemImage: "checkmark.seal")
                } description: {
                    Text(DashboardL10n.tr("dashboard.actions.empty_desc", "No actionable items match the active filter combination."))
                } actions: {
                    if store.hasScopedSubFilter {
                        Button(DashboardL10n.tr("dashboard.actions.reset_filter", "Reset Scoped Filter")) {
                            store.clearScopedFilterOnly()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(minHeight: 140)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.filteredActionItems) { item in
                        actionItemRow(item)
                    }
                }
            }
        }
    }

    private func actionItemRow(_ item: DashboardActionItem) -> some View {
        let priorityColor = DashboardSemanticColorPalette.color(for: item.priority.health)
        return HStack(alignment: .top, spacing: 10) {
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

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.priority.label)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(priorityColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(priorityColor)
                    Text(item.sourceTag)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                }
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let command = item.command {
                    Text("$ \(command)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
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
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minHeight: 28)
                }
                if let urlString = item.externalURLString, let url = URL(string: urlString) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label(DashboardL10n.tr("dashboard.actions.open_link", "Open"), systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minHeight: 28)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
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
                    TableColumn(DashboardL10n.tr("dashboard.ranking.col_role", "Agent Role"), value: \.agentName)
                    TableColumn(DashboardL10n.tr("dashboard.ranking.col_provider", "CLI Provider"), value: \.providerName)
                    TableColumn(DashboardL10n.tr("dashboard.ranking.col_runs", "Runs")) { row in
                        Text(row.runs.formatted(.number))
                            .monospacedDigit()
                    }
                    TableColumn(DashboardL10n.tr("dashboard.ranking.col_tokens", "Tokens")) { row in
                        Text(row.totalTokens.formatted(.number))
                            .monospacedDigit()
                    }
                    TableColumn(DashboardL10n.tr("dashboard.ranking.col_success", "Success Rate")) { row in
                        HStack(spacing: 4) {
                            Image(systemName: row.health.symbolName)
                                .foregroundStyle(DashboardSemanticColorPalette.color(for: row.health))
                            Text(String(format: "%.1f%%", row.successRate * 100))
                                .monospacedDigit()
                        }
                    }
                    TableColumn(DashboardL10n.tr("dashboard.ranking.col_latency", "Avg Latency")) { row in
                        Text(DashboardL10n.format("dashboard.ranking.latency_value_format", "%.1fs", row.avgDurationSeconds))
                            .monospacedDigit()
                    }
                    TableColumn(DashboardL10n.tr("dashboard.ranking.col_cost", "Today Cost")) { row in
                        Text(String(format: "$%.2f", row.costUSD))
                            .monospacedDigit()
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 165)

                if let selected = store.selectedRankingRow {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(selected.agentName) · \(selected.providerName)")
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
    @Environment(\.onToggleDone) private var onToggleDone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: DashboardWorkspaceStore? = nil) {
        _store = State(initialValue: store ?? DashboardWorkspaceStore.shared)
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if case let .populated(snapshot) = store.systemState {
                        workspaceDetailContent(snapshot: snapshot)
                    }
                }
                .padding(20)
                .frame(maxWidth: 1280, alignment: .leading)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 6) {
                        Button {
                            store.selectPreviousDate()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!store.canSelectPreviousDate)

                        Text(store.selectedDateString)
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()

                        Button {
                            store.selectNextDate()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!store.canSelectNextDate)

                        Button(DashboardL10n.tr("dashboard.toolbar.today", "Today")) {
                            store.selectToday()
                        }
                        .controlSize(.small)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Picker(DashboardL10n.tr("dashboard.toolbar.cli_scope", "CLI Scope"), selection: $store.selectedCLI) {
                        ForEach(DashboardCLIFilter.allCases) { cli in
                            Text(cli.shortLabel).tag(cli)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
                ToolbarItem(placement: .primaryAction) {
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
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
    }

    private var sidebarContent: some View {
        List(selection: $store.selectedSection) {
            Section(DashboardL10n.tr("dashboard.sidebar.title", "AIDash Workspace")) {
                ForEach(DashboardWorkspaceSection.allCases) { section in
                    Label(section.title, systemImage: section.symbolName)
                        .badge(badgeCount(for: section))
                        .tag(section)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text(DashboardL10n.format("dashboard.sidebar.today_spend_format", "Today $%.2f", store.todayTotalCostUSD))
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func badgeCount(for section: DashboardWorkspaceSection) -> Int {
        switch section {
        case .overview, .actionItems:
            return store.pendingActionCount
        case .systemAndCosts:
            return store.highestQuotaWarningCount
        case .agentEfficiency:
            return 0
        }
    }

    @ViewBuilder
    private func workspaceDetailContent(snapshot: MenuBarSystemSnapshot) -> some View {
        switch store.selectedSection {
        case .overview:
            SystemTelemetryStripView(snapshot: snapshot)
            KPISummaryCardView(metrics: store.effectiveKPIMetrics)
            TrendChartCardView(
                points: store.filteredTrendPoints,
                selectedCategory: store.selectedChartCategory,
                onSelectCategory: { store.toggleChartCategory($0) },
                onClearSelection: { store.clearChartSelection() }
            )
            CLICostQuotaCardView(
                entries: store.filteredCLIEntries,
                todayTotalUSD: store.todayTotalCostUSD,
                periodTotalUSD: store.periodTotalCostUSD
            )
            ActionItemsCardView(store: store, onToggleDone: onToggleDone)
            RankingTableCardView(store: store)
        case .agentEfficiency:
            KPISummaryCardView(metrics: store.effectiveKPIMetrics)
            TrendChartCardView(
                points: store.filteredTrendPoints,
                selectedCategory: store.selectedChartCategory,
                onSelectCategory: { store.toggleChartCategory($0) },
                onClearSelection: { store.clearChartSelection() }
            )
            RankingTableCardView(store: store)
        case .actionItems:
            KPISummaryCardView(metrics: store.effectiveKPIMetrics)
            ActionItemsCardView(store: store, onToggleDone: onToggleDone)
        case .systemAndCosts:
            SystemTelemetryStripView(snapshot: snapshot)
            CLICostQuotaCardView(
                entries: store.filteredCLIEntries,
                todayTotalUSD: store.todayTotalCostUSD,
                periodTotalUSD: store.periodTotalCostUSD
            )
            TrendChartCardView(
                points: store.filteredTrendPoints,
                selectedCategory: store.selectedChartCategory,
                onSelectCategory: { store.toggleChartCategory($0) },
                onClearSelection: { store.clearChartSelection() }
            )
        }
    }
}
#endif
