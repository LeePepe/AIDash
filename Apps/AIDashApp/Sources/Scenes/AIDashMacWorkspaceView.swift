#if os(macOS)
// swiftlint:disable file_length
import AppKit
import SwiftUI
import AIDashCore
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
        case .skills: return DashboardL10n.tr("dashboard.lens.skills_roi", "Skills ROI")
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
                healthPills(for: roi)
                let selected = diagnosticEntries(for: roi)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(selected, id: \.key) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.key).font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text(entry.value).font(.caption.monospacedDigit()).fixedSize(horizontal: true, vertical: false).lineLimit(2)
                        }
                    }
                    if lens == "Usage" && !roi.skillsDaily.isEmpty {
                        Text("skills_daily · \(roi.skillsDaily.count) day/source/skill rows").font(.caption2).foregroundStyle(.secondary)
                        ForEach(roi.skillsDaily.prefix(3), id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
                .padding(.top, 4)
            } else {
                Text(DashboardL10n.tr("dashboard.skills_roi.missing", "unknown / missing · 等待 metadata-only skills-roi.json"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func healthPills(for roi: LiveDashboardTelemetryReader.SkillsRoiSnapshot) -> some View {
        let ids = ["S1_pin_drift", "S2_gate_catch", "S3_skill_health", "S11_context_composition"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(ids, id: \.self) { id in
                VStack(alignment: .leading, spacing: 3) {
                    Text(id).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(diagnosticValue(roi, section: id)).font(.caption2.monospacedDigit()).lineLimit(2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }

    private func diagnosticValue(_ roi: LiveDashboardTelemetryReader.SkillsRoiSnapshot, section: String) -> String {
        let fields = roi.diagnostics[section] ?? [:]
        return fields.first(where: { $0.key != "window_cst" && $0.key != "source_as_of" && $0.key != "sample_size" && $0.key != "coverage_status" })?.value ?? DashboardL10n.tr("dashboard.skills_roi.metric_unknown", "unknown")
    }

    private func diagnosticEntries(for roi: LiveDashboardTelemetryReader.SkillsRoiSnapshot) -> [(key: String, value: String)] {
        let allowed: (String) -> Bool = { key in
            switch lens {
            case "Usage": return key.hasPrefix("S1_") || key.hasPrefix("S2_") || key.hasPrefix("S3_") || key.hasPrefix("S4_") || key.hasPrefix("S6_") || key.hasPrefix("S10_")
            case "Disclosure / Escapes": return key.hasPrefix("S7_") || key.hasPrefix("S8_") || key.hasPrefix("S9_")
            default: return key.hasPrefix("S11_") || key.hasPrefix("S12_")
            }
        }
        return roi.diagnostics.keys.sorted().flatMap { section in
            roi.diagnostics[section, default: [:]].keys.sorted().compactMap { field in
                let key = "\(section).\(field)"
                return allowed(section) ? (key, roi.diagnostics[section]?[field] ?? DashboardL10n.tr("dashboard.skills_roi.metric_unknown", "unknown")) : nil
            }
        }
    }

    private var freshnessText: String {
        guard let roi = summary?.skillsROI else { return DashboardL10n.tr("dashboard.skills_roi.coverage_unknown", "Coverage: unknown") }
        let window = roi.window ?? DashboardL10n.tr("dashboard.skills_roi.window_unknown", "unknown window")
        let range = [roi.windowStart, roi.windowEnd].compactMap { $0 }.joined(separator: "→")
        let asOf = roi.sourceAsOf ?? DashboardL10n.tr("dashboard.skills_roi.as_of_unknown", "unknown as_of")
        let sample = roi.sampleSize.map(String.init) ?? DashboardL10n.tr("dashboard.skills_roi.sample_unknown", "unknown sample")
        return "Window: \(window)\(range.isEmpty ? "" : " · \(range)") · as of \(asOf) · sample \(sample) · \(roi.coverageStatus)"
    }
}

// swiftlint:disable:next type_body_length
public struct ActionItemsCardView: View {
    @Bindable public var store: DashboardWorkspaceStore
    public var onToggleDone: ((String, String, Bool) -> Void)?
    @State private var expandedActionID: String?
    @State private var selectedDecisions: [String: String] = [:]
    @State private var selectedTargets: [String: Set<String>] = [:]
    @State private var noteInputs: [String: String] = [:]
    @State private var expandedLinearClusterLabels: Set<String> = []
    @State private var expandedBugBlockers = false
    @State private var collapsedDomains: Set<DashboardActionDomain> = []
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
            VStack(alignment: .leading, spacing: 8) {
                if let parent = parentIssueForBoard {
                    parentIssueBanner(parent)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.topicGroupFilters, id: \.id) { filter in
                            Button(filter.title) { store.selectedTopicGroup = filter.id }
                                .buttonStyle(.bordered)
                                .tint(store.selectedTopicGroup == filter.id ? .accentColor : nil)
                                .controlSize(.small)
                        }
                    }
                }
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.topicLabelFilters, id: \.id) { filter in
                            Button(filter.title) { store.selectedTopicLabelFilter = filter.id }
                                .buttonStyle(.bordered)
                                .tint(store.selectedTopicLabelFilter == filter.id ? .accentColor : nil)
                                .controlSize(.small)
                        }
                    }
                }
                if store.availableLinearActionFilters.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(store.availableLinearActionFilters) { filter in
                                Button {
                                    store.selectedLinearActionFilter = filter.id
                                } label: {
                                    Text(linearFilterTitle(filter))
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.bordered)
                                .tint(store.selectedLinearActionFilter == filter.id ? .accentColor : nil)
                                .controlSize(.small)
                                .frame(minHeight: 28)
                            }
                        }
                    }
                }
            }
        } content: {
            domainSummaryStrip
            if kanbanBoardItems.isEmpty {
                actionEmptyStateContent
                    .frame(minHeight: 150)
            } else if store.selectedActionDomain == nil {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(DashboardActionDomain.allCases) { domain in
                        let items = store.filteredActionItems.filter { $0.resolvedDomain == domain }
                        if !items.isEmpty { domainSection(domain, items: items) }
                    }
                }
            } else {
                kanbanBoardContent
            }
        }
    }

    private struct KanbanColumn {
        let title: String
        let status: DashboardActionStatus
        let tint: Color
    }

    private struct KanbanButtonStyleModifier: ViewModifier {
        let prominent: Bool

        @ViewBuilder
        func body(content: Content) -> some View {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }

    private var parentIssueForBoard: DashboardActionItem? {
        store.actionItems.first { $0.parentIssueKey == "TIA-83" }
    }

    private func linearFilterTitle(_ filter: DashboardLinearActionFilterChip) -> String {
        if filter.id == "all" { return "全部" }
        let label = filter.id == "needs-decision" ? "needs-decision" : filter.id
        let count = filter.count.map { " (\($0))" } ?? ""
        return "🏷️ \(label)\(count)"
    }

    private func parentIssueBanner(_ item: DashboardActionItem) -> some View {
        let parentKey = item.parentIssueKey ?? "TIA-83"
        let parentTitle = item.parentIssueTitle ?? "[Bing] PR 审查意见修复与 CI 门禁值守队列"
        return HStack(spacing: 8) {
            Text("🔗 \(parentKey) · \(parentTitle)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if let project = item.project, !project.isEmpty {
                Text(project)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.14), in: Capsule())
            }
            Spacer(minLength: 4)
            if let url = URLPolicy.validate(item.parentIssueURL) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("打开 Linear TIA-83 ↗", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minHeight: 28)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: Capsule())
    }

    private var kanbanBoardItems: [DashboardActionItem] {
        store.kanbanActionItems
    }

    private var kanbanColumns: [KanbanColumn] {
        [
            KanbanColumn(title: "🔴 Blocked 卡点", status: .blocked, tint: DashboardSemanticColorPalette.color(for: .critical)),
            KanbanColumn(title: "🔵 Todo 待操作", status: .inProgress, tint: DashboardSemanticColorPalette.color(for: .neutral)),
            KanbanColumn(title: "🟠 Triage 待审阅", status: .triage, tint: DashboardSemanticColorPalette.color(for: .warning)),
            KanbanColumn(title: "🟢 Done 已完成", status: .done, tint: DashboardSemanticColorPalette.color(for: .healthy))
        ]
    }

    private var kanbanBoardContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(store.topicColumns) { column in
                    topicColumn(column)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func topicColumn(_ column: DashboardTopicColumn) -> some View {
        let bugItems = column.items.filter { $0.hasLinearLabel("bug-blocker") }
        let regularItems = column.items.filter { !$0.hasLinearLabel("bug-blocker") }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(column.topic.topicTitle)
                        .font(.subheadline.weight(.bold))
                    Text(column.topic.topicID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.12), in: Capsule())
                    Spacer(minLength: 4)
                    Text("\(column.pendingCount)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
                Text(column.session.badgeText)
                    .font(.caption2)
                    .foregroundStyle(column.session.isExisting ? .green : .secondary)
                    .lineLimit(1)
                    .help(column.session.badgeText)
                HStack(spacing: 6) {
                    Button {
                        let result = store.dispatchStagedTopic(topicID: column.topic.id, onToggleDone: onToggleDone)
                        if !result.succeeded { expandedActionID = nil }
                    } label: {
                        Label("⚡ 派发给此 M2 (已选 \(store.stagedItems(for: column.topic.id).count) 项) →", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(column.items.allSatisfy(\.isCompleted))
                }
                if let status = store.lastDispatchedTopicStatus[column.topic.id] {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(status.hasPrefix("✓") ? .green : .orange)
                }
            }
            if regularItems.isEmpty && bugItems.isEmpty {
                Text("无事项").font(.caption).foregroundStyle(.secondary).frame(minHeight: 80)
            } else {
                ForEach(regularItems) { item in kanbanCard(item) }
                if !bugItems.isEmpty && column.topic.id == "sapphire-china-bugs" {
                    DisclosureGroup("📦 未提 PR 的 Bug 阻塞 (\(bugItems.count))", isExpanded: $expandedBugBlockers) {
                        ForEach(bugItems) { item in kanbanCard(item) }
                    }
                    .font(.caption.weight(.semibold))
                } else {
                    ForEach(bugItems) { item in kanbanCard(item) }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 300, idealWidth: 340, maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func kanbanColumn(_ column: KanbanColumn) -> some View {
        let items = kanbanBoardItems.filter { item in
            if column.status == .done {
                return item.isCompleted || item.status == .done
            }
            return !item.isCompleted && item.status == column.status
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: column.status.symbolName)
                    .foregroundStyle(column.tint)
                    .accessibilityHidden(true)
                Text(column.title)
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 4)
                Text("\(items.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
            if items.isEmpty {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .frame(minHeight: 80)
                    .overlay {
                        Text("无事项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        kanbanCard(item)
                    }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 260, idealWidth: 290, maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // swiftlint:disable:next function_body_length
    private func kanbanCard(_ item: DashboardActionItem) -> some View {
        let isDone = item.isCompleted || item.status == .done
        let isExpanded = expandedActionID == item.id
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(item.priority.label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DashboardSemanticColorPalette.color(for: item.priority.health).opacity(0.16), in: Capsule())
                    .foregroundStyle(DashboardSemanticColorPalette.color(for: item.priority.health))
                if let parent = item.parentIssueKey, !parent.isEmpty {
                    Text(parent)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
                ForEach(item.labels, id: \.self) { label in
                    Button {
                        store.selectedLinearActionFilter = label
                    } label: {
                        Text("🏷️ \(label)")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(store.selectedLinearActionFilter == label ? .accentColor : nil)
                }
                Spacer(minLength: 4)
                if let url = URLPolicy.validate(item.externalURLString) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 28, minHeight: 28)
                    .accessibilityLabel("打开链接")
                }
            }

            Button {
                toggleExpanded(item.id)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .strikethrough(isDone)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "收起 \(item.title)" : "展开 \(item.title)")

            if isExpanded {
                Divider()
                Text(item.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !isDone {
                    TextField(
                        "补充说明 / 指令（可选）",
                        text: Binding(
                            get: { noteInputs[item.id] ?? "" },
                            set: { noteInputs[item.id] = String($0.prefix(item.noteMaxLength)) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                }
                if !isDone {
                    actionRowAccessoryButtons(item)
                    if URLPolicy.validate(item.externalURLString) != nil {
                        openExternalActionButton(item, title: "打开 PR ↗", prominent: false)
                    }
                }
            }

            kanbanActionFooter(item, isDone: isDone)
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func kanbanActionFooter(_ item: DashboardActionItem, isDone: Bool) -> some View {
        if isDone {
            Label(store.lastDispatchedTopicStatus[item.topicID] ?? "已处理", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(DashboardSemanticColorPalette.color(for: .healthy))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                switch actionItemKind(item) {
                case .popGate:
                    HStack(spacing: 6) {
                        openExternalActionButton(item, title: "打开 PR 合并 ↗", prominent: true)
                        markDoneButton(item)
                    }
                case .decision:
                    VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(item.decisionOptions.prefix(2).enumerated()), id: \.offset) { index, option in
                        Button {
                            store.stageTopicDecision(item, decision: option)
                        } label: {
                            Text(store.stagedTopicDecisions[item.id] == option ? "✓ \(option)" : option)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .modifier(KanbanButtonStyleModifier(prominent: store.stagedTopicDecisions[item.id] == option || (store.stagedTopicDecisions[item.id] == nil && index == 0)))
                        .controlSize(.small)
                        .frame(minHeight: 28)
                    }
                }
                case .evalRule:
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    evalFooterButton(item, title: "两个都加", decision: "两个都加", prominent: true)
                    evalFooterButton(item, title: "记规范", decision: "记入编码规范 (防再犯)", prominent: false)
                    evalFooterButton(item, title: "入题库", decision: "加入审查题库 (防漏审)", prominent: false)
                    evalFooterButton(item, title: "忽略", decision: "忽略", prominent: false)
                }
                case .general:
                    HStack(spacing: 6) {
                        approveButton(item)
                        ignoreButton(item)
                    }
                }
                Button {
                    let decision = store.stagedTopicDecisions[item.id] ?? item.decisionOptions.first ?? "Approve"
                    _ = store.dispatchTopicToM2(
                        topicID: item.topicID,
                        items: [(item, decision, noteInputs[item.id] ?? "")],
                        onToggleDone: onToggleDone
                    )
                } label: {
                    Label("立即派发 →", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(minHeight: 28)
            }
        }
    }

    private func openExternalActionButton(_ item: DashboardActionItem, title: String, prominent: Bool) -> some View {
        Button {
            if let url = URLPolicy.validate(item.externalURLString) { NSWorkspace.shared.open(url) }
        } label: {
            Text(title)
        }
        .modifier(KanbanButtonStyleModifier(prominent: prominent))
        .controlSize(.small)
        .frame(minHeight: 28)
        .disabled(URLPolicy.validate(item.externalURLString) == nil)
    }

    private func markDoneButton(_ item: DashboardActionItem) -> some View {
        Button {
            store.submitActionItemDecision(item, decision: "Done", onToggleDone: onToggleDone)
        } label: {
            Label("✓ 已完成", systemImage: "checkmark")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: 28)
    }

    private func evalFooterButton(_ item: DashboardActionItem, title: String, decision: String, prominent: Bool) -> some View {
        Button {
            store.stageTopicDecision(item, decision: decision)
        } label: {
            Text(store.stagedTopicDecisions[item.id] == decision ? "✓ \(title)" : title)
                .frame(maxWidth: .infinity)
        }
        .modifier(KanbanButtonStyleModifier(prominent: store.stagedTopicDecisions[item.id] == decision || prominent))
        .controlSize(.small)
        .frame(minHeight: 28)
    }

    private func approveButton(_ item: DashboardActionItem) -> some View {
        Button {
            store.submitActionItemDecision(item, decision: "Approve", onToggleDone: onToggleDone)
        } label: {
            Label("✓ 批准处理", systemImage: "checkmark")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .frame(minHeight: 28)
    }

    private func ignoreButton(_ item: DashboardActionItem) -> some View {
        Button {
            store.submitActionItemDecision(item, decision: "忽略", onToggleDone: onToggleDone)
        } label: {
            Text("忽略")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: 28)
    }

    private static let linearClusterLabels = ["pop", "eval", "bug-blocker"]

    private func actionItemsContent(_ items: [DashboardActionItem]) -> some View {
        var parentKeys: [String] = []
        for item in items where item.isLinearNative {
            guard let key = item.parentIssueKey, !key.isEmpty else { continue }
            if !parentKeys.contains(key) { parentKeys.append(key) }
        }
        let groupedIDs = Set(items.filter { item in
            guard let key = item.parentIssueKey else { return false }
            return parentKeys.contains(key)
        }.map(\.id))
        let standaloneItems = items.filter { !groupedIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(parentKeys, id: \.self) { key in
                let groupItems = items.filter { $0.parentIssueKey == key }
                linearParentGroup(key: key, items: groupItems)
            }
            if !standaloneItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(DashboardL10n.tr("dashboard.actions.system_section", "系统与独立事项"))
                        .font(.headline)
                    ForEach(standaloneItems) { item in
                        actionItemRow(item)

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
        ViewThatFits(in: .horizontal) {
            domainGrid(columns: 4)
            domainGrid(columns: 2)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { domainTiles } }
        }
    }

    private func domainGrid(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            domainTiles
        }
    }

    @ViewBuilder
    private var domainTiles: some View {
        ForEach(DashboardActionDomain.allCases) { domain in
            let count = store.actionItems.filter { !$0.isCompleted && $0.resolvedDomain == domain }.count
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

    private func domainSection(_ domain: DashboardActionDomain, items: [DashboardActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if collapsedDomains.contains(domain) { collapsedDomains.remove(domain) } else { collapsedDomains.insert(domain) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: domain.symbolName)
                    Text(domain.title).font(.caption.weight(.semibold))
                    Text("\(items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
                    Image(systemName: collapsedDomains.contains(domain) ? "chevron.down" : "chevron.up").font(.caption2)
                }
            }
            .buttonStyle(.plain)
            if !collapsedDomains.contains(domain) {
                ForEach(items) { item in actionItemRow(item) }
            }
        }
    }

    @ViewBuilder
    private func linearParentGroup(key: String, items: [DashboardActionItem]) -> some View {
        let decisionItems = items.filter(\.isNeedsDecision)
        let decisionIDs = Set(decisionItems.map(\.id))
        let clusterItems = items.filter { item in
            !decisionIDs.contains(item.id)
                && Self.linearClusterLabels.contains(where: item.hasLinearLabel)
        }
        let clusterIDs = Set(clusterItems.map(\.id))
        let otherItems = items.filter { !decisionIDs.contains($0.id) && !clusterIDs.contains($0.id) }
        VStack(alignment: .leading, spacing: 8) {
            linearParentHeader(key: key, items: items)
            if !decisionItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(DashboardL10n.tr("dashboard.actions.needs_decision_section", "需单独拍板"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(decisionItems) { item in
                        actionItemRow(item)
                    }
                }
            }
            ForEach(Self.linearClusterLabels, id: \.self) { label in
                let labelItems = clusterItems.filter { $0.hasLinearLabel(label) }
                if !labelItems.isEmpty {
                    linearClusterRow(label: label, items: labelItems)
                }
            }
            ForEach(otherItems) { item in
                actionItemRow(item)
            }
        }
    }

    private func linearParentHeader(key: String, items: [DashboardActionItem]) -> some View {
        let first = items.first
        let needsDecisionCount = items.filter(\.isNeedsDecision).count
        let popCount = items.filter { $0.hasLinearLabel("pop") }.count
        let evalCount = items.filter { $0.hasLinearLabel("eval") }.count
        let bugCount = items.filter { $0.hasLinearLabel("bug-blocker") }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "link.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(key)
                    .font(.headline.monospaced())
                if let project = first?.project, !project.isEmpty {
                    Text("Project: \(project)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.14), in: Capsule())
                }
                Spacer(minLength: 4)
                if let url = URLPolicy.validate(first?.parentIssueURL) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label(
                            DashboardL10n.format("dashboard.actions.open_parent_format", "打开 Linear %@ ↗", key),
                            systemImage: "arrow.up.right.square"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minHeight: 28)
                }
            }
            if let title = first?.parentIssueTitle, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
            }
            Text(DashboardL10n.format(
                "dashboard.actions.parent_summary_format",
                "%lld 需拍板 · %lld 待 PoP · %lld 评论建议 · %lld Bug 阻塞",
                needsDecisionCount, popCount, evalCount, bugCount
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func linearClusterRow(label: String, items: [DashboardActionItem]) -> some View {
        let isExpanded = expandedLinearClusterLabels.contains(label) || store.selectedLinearActionFilter == label
        let labelText = linearClusterTitle(for: label)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    toggleLinearCluster(label)
                } label: {
                    Label(
                        "\(labelText) (\(items.count))",
                        systemImage: isExpanded ? "chevron.down" : "chevron.right"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .frame(minHeight: 28)
                Spacer(minLength: 4)
                if label == "pop", let url = URLPolicy.validate(items.first?.externalURLString) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label(DashboardL10n.tr("dashboard.actions.open_cluster_pr", "一键打开 PR ↗"), systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minHeight: 28)
                }
                Text(DashboardL10n.format("dashboard.actions.expand_cluster_format", "展开逐条处理 (%lld)", items.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { item in
                        actionItemRow(item)
                    }
                }
                .padding(.leading, 14)
            }
        }
    }

    private func linearClusterTitle(for label: String) -> String {
        switch label {
        case "pop": return "📦 🏷️ pop · 待 PoP / 手动合入"
        case "eval": return "📦 🏷️ eval · Triage 评论衍生改进建议"
        default: return "📦 🏷️ bug-blocker · Triage 未提 PR 的 Bug 阻塞"
        }
    }

    private func toggleLinearCluster(_ label: String) {
        if expandedLinearClusterLabels.contains(label) {
            expandedLinearClusterLabels.remove(label)
        } else {
            expandedLinearClusterLabels.insert(label)
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

    private enum ActionItemKind: Equatable {
        case evalRule
        case popGate
        case decision
        case general
    }

    private func actionItemKind(_ item: DashboardActionItem) -> ActionItemKind {
        if item.hasLinearLabel("eval") || item.id.hasPrefix("EVAL-") {
            return .evalRule
        }
        if item.hasLinearLabel("needs-decision") {
            return .decision
        }
        let haystack = [item.id, item.title, item.summary, item.sourceTag, item.backingItemRef ?? ""]
            .joined(separator: " ")
            .uppercased()
        if haystack.contains("PR_POP_GATE") || item.id.uppercased().hasPrefix("POP") {
            return .popGate
        }
        if haystack.contains("PR_DECISION") || (item.jobID == .myPRSupervisor && item.id.uppercased().hasPrefix("D")) {
            return .decision
        }
        return .general
    }

    private func evalRulePreview(_ summary: String) -> String {
        summary.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? summary
    }

    private func statusTintColor(for status: DashboardActionStatus) -> Color {
        DashboardSemanticColorPalette.color(for: status.health)
    }

    private func actionItemRow(_ item: DashboardActionItem) -> some View {
        let priorityColor = DashboardSemanticColorPalette.color(for: item.priority.health)
        let statusColor = statusTintColor(for: item.status)
        let isExpanded = expandedActionID == item.id
        let hasDecisionControl = item.controls.contains { $0.id == "decision" && !$0.options.isEmpty }
        let requiresChoice = !item.targetOptions.isEmpty || (hasDecisionControl && item.decisionOptions.count > 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    store.toggleActionItem(id: item.id, onToggleDone: onToggleDone)
                } label: {
                    Image(systemName: item.status.symbolName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DashboardL10n.format("dashboard.actions.mark_completed_format", "Mark %@ as completed", item.title))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(item.priority.label)
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(priorityColor.opacity(0.16), in: Capsule())
                            .foregroundStyle(priorityColor)
                        Text(item.title)
                            .font(.body.weight(.semibold))
                            .strikethrough(item.isCompleted)
                            .foregroundStyle(item.isCompleted ? .secondary : .primary)
                            .lineLimit(actionItemKind(item) == .evalRule ? nil : 1)
                            .fixedSize(horizontal: false, vertical: actionItemKind(item) == .evalRule)
                        if let refLabel = item.displayRefLabel, !item.title.contains(refLabel) {
                            Text(refLabel)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        actionQuickButtons(item, requiresChoice: requiresChoice)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(actionItemKind(item) == .evalRule ? evalRulePreview(item.summary) : item.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(actionItemKind(item) == .evalRule || actionItemKind(item) == .decision ? 2 : 1)
                            .truncationMode(.tail)
                        Spacer(minLength: 6)
                        Text("\(item.sourceTag) · \(item.projectFolderName)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if actionItemKind(item) == .evalRule {
                        evalRuleExpandedContent(item)
                    } else {
                        Text(item.summary)
                            .font(.body)
                            .lineSpacing(2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if item.isLearningTopic || item.isProposal {
                        specializedMetadata(for: item)
                    }
                    if actionItemKind(item) != .evalRule, let command = item.command {

                        Text("$ \(command)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if !item.isCompleted {
                        actionInlineDecisionBar(item)
                    }
                    if actionItemKind(item) != .evalRule {
                        actionRowAccessoryButtons(item)
                    }
                }
                .padding(.leading, 32)
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
    private func evalRuleExpandedContent(_ item: DashboardActionItem) -> some View {
        Text(item.summary)
            .font(.body)
            .lineSpacing(2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        if let url = URLPolicy.validate(item.externalURLString) {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label(
                    DashboardL10n.tr("dashboard.actions.eval.open_pr", "打开 PR ↗"),
                    systemImage: "arrow.up.right.square"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minHeight: 28)
        }
    }

    @ViewBuilder
    private func evalRuleQuickButtons(_ item: DashboardActionItem) -> some View {
        Button {
            store.submitActionItemDecision(
                item,
                decision: "两个都加",
                note: noteInputs[item.id] ?? "",
                onToggleDone: onToggleDone
            )
        } label: {
            Text(DashboardL10n.tr("dashboard.actions.eval.add_both", "两个都加"))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .frame(minHeight: 28)
        Button {
            store.submitActionItemDecision(
                item,
                decision: "记入编码规范 (防再犯)",
                note: noteInputs[item.id] ?? "",
                onToggleDone: onToggleDone
            )
        } label: {
            Text(DashboardL10n.tr("dashboard.actions.eval.add_rule", "记入编码规范"))
        }
        .help("写入仓内 .claude/skills/ios-best-practices，防 AI 写代码再犯")
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: 28)
        Button {
            store.submitActionItemDecision(
                item,
                decision: "加入审查题库 (防漏审)",
                note: noteInputs[item.id] ?? "",
                onToggleDone: onToggleDone
            )
        } label: {
            Text(DashboardL10n.tr("dashboard.actions.eval.add_eval", "加入审查题库"))
        }
        .help("写入 pr-auto-review 黄金评测集，防 AI 审 PR 漏抓")
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: 28)
        Button {
            store.submitActionItemDecision(item, decision: "忽略", onToggleDone: onToggleDone)
        } label: {
            Text(DashboardL10n.tr("dashboard.actions.eval.ignore", "忽略"))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: 28)
        evalDetailsButton(for: item)
    }

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func actionQuickButtons(_ item: DashboardActionItem, requiresChoice: Bool) -> some View {
        switch actionItemKind(item) {
        case .evalRule:
            evalRuleQuickButtons(item)
        case .popGate:
            if let url = URLPolicy.validate(item.externalURLString) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(
                        DashboardL10n.tr("dashboard.actions.open_pr_merge", "打开 PR 合并 ↗"),
                        systemImage: "arrow.up.right.square"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(minHeight: 28)
            }
            Button {
                store.submitActionItemDecision(item, decision: "Done", onToggleDone: onToggleDone)
            } label: {
                Label(
                    DashboardL10n.tr("dashboard.actions.mark_done", "✓ 已完成"),
                    systemImage: "checkmark"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minHeight: 28)
        case .decision:
            ForEach(Array(item.decisionOptions.prefix(2).enumerated()), id: \.offset) { _, option in
                Button {
                    store.submitActionItemDecision(
                        item,
                        decision: option,
                        note: noteInputs[item.id] ?? "",
                        onToggleDone: onToggleDone
                    )
                } label: {
                    Text(decisionLabel(option))
                        .lineLimit(1)
                }
                .help(decisionLabel(option))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(minHeight: 28)
            }
            detailsButton(for: item)
        case .general:
            if let url = URLPolicy.validate(item.externalURLString) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(
                        DashboardL10n.tr("dashboard.actions.open_link", "打开 Linear ↗"),
                        systemImage: "arrow.up.right.square"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minHeight: 28)
            }
            if requiresChoice {
                Button {
                    toggleExpanded(item.id)
                } label: {
                    Label(
                        DashboardL10n.format("dashboard.actions.choose_handling_format", "选择处理 (%lld)", item.decisionOptions.count),
                        systemImage: expandedActionID == item.id ? "chevron.up" : "chevron.down"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minHeight: 28)
            } else {
                Button {
                    let decision = item.status == .inProgress ? "Done" : "Approve"
                    store.submitActionItemDecision(item, decision: decision, onToggleDone: onToggleDone)
                } label: {
                    Label(
                        item.status == .inProgress
                            ? DashboardL10n.tr("dashboard.actions.done", "Done")
                            : DashboardL10n.tr("dashboard.actions.approve", "Approve"),
                        systemImage: "checkmark"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(minHeight: 28)
            }
            detailsButton(for: item)
        }
    }

    private func evalDetailsButton(for item: DashboardActionItem) -> some View {
        Button {
            toggleExpanded(item.id)
        } label: {
            Text(expandedActionID == item.id ? "详情 ▴" : "详情 ▾")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: 28)
    }

    private func detailsButton(for item: DashboardActionItem) -> some View {
        Button {
            toggleExpanded(item.id)
        } label: {
            Label(
                DashboardL10n.tr("dashboard.actions.details", "详情"),
                systemImage: expandedActionID == item.id ? "chevron.up" : "chevron.down"
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: 28)
    }

    private func toggleExpanded(_ id: String) {
        let update = { expandedActionID = expandedActionID == id ? nil : id }
        if reduceMotion { update() } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { update() }
        }
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
                        Text(decisionLabel(option)).tag(option)
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
