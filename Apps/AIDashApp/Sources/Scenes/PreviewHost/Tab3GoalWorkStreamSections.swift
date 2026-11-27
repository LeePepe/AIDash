#if os(macOS)
import DesignKit
import SwiftUI

private enum Tab3GoalWorkbenchMode: String, CaseIterable {
    case compactPrimaryRows
    case splitReceiptPanel
    case bentoGoalSwimlanes
    case spectrumTimelineMatrix
}

@MainActor
public enum Tab3GoalWorkStreamSections {
    public static let descriptors: [PreviewVariantDescriptor] = [
        PreviewVariantDescriptor(
            id: "tab3-v01",
            tab: .goalWorkStream,
            badgeCode: "V01",
            title: "Goal 聚合紧凑行与四段动作光谱（原地展开子会话）",
            metricTags: ["活跃 3 / 完结 24 ▲", "一次过审率 89% ▲", "平均耗时 24m ▼"],
            symbolName: "point.3.connected.trianglepath.dotted",
            topologySignature: "tab3-v01:compact-4kpi-pills+goal-4seg-bars+inplace-session-drawer"
        ),
        PreviewVariantDescriptor(
            id: "tab3-v02",
            tab: .goalWorkStream,
            badgeCode: "V02",
            title: "Goal 主列表 + 右侧单页会话工作账单联排台",
            metricTags: ["零原始流水堆砌", "Skill 空挂秒级高亮 ▼", "单页账单直达 ▲"],
            symbolName: "sidebar.right",
            topologySignature: "tab3-v02:primary-goal-list+inline-receipt-sidepanel+skill-touch-drawer"
        ),
        PreviewVariantDescriptor(
            id: "tab3-v03",
            tab: .goalWorkStream,
            badgeCode: "V03",
            title: "三态状态泳道（在跑 · 待提效 · 已交付）Bento 看板",
            metricTags: ["在跑与阻塞实时分流", "待 AI 提效项 ▼ -34%", "合入 PR 闭环 ▲"],
            symbolName: "rectangle.split.3x1",
            topologySignature: "tab3-v03:3swimlane-bento-columns+4seg-mini-bars+signal-summary-drawer"
        ),
        PreviewVariantDescriptor(
            id: "tab3-v04",
            tab: .goalWorkStream,
            badgeCode: "V04",
            title: "14 天动作光谱热力矩阵与耗时收敛轨迹",
            metricTags: ["读 / 改 / 测 / 重试四维矩阵", "空转重试占比 14% → 4% ▼", "交付节奏 ▲"],
            symbolName: "waveform.path.ecg.rectangle",
            topologySignature: "tab3-v04:action-spectrum-matrix+rework-drop-sparkline+session-breakdown-drawer"
        ),
    ]

    @ViewBuilder
    public static func view(
        for descriptor: PreviewVariantDescriptor,
        data: AIDashPreviewSampleData,
        globalExpandAll: Bool,
        speed: PreviewSpeedMultiplier
    ) -> some View {
        PreviewGoalWorkStreamVariantCard(
            descriptor: descriptor,
            mode: mode(for: descriptor),
            data: data,
            globalExpandAll: globalExpandAll,
            speed: speed
        )
    }

    public static func v01(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View {
        view(for: descriptors[0], data: data, globalExpandAll: globalExpandAll, speed: speed)
    }

    public static func v02(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View {
        view(for: descriptors[1], data: data, globalExpandAll: globalExpandAll, speed: speed)
    }

    public static func v03(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View {
        view(for: descriptors[2], data: data, globalExpandAll: globalExpandAll, speed: speed)
    }

    public static func v04(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View {
        view(for: descriptors[3], data: data, globalExpandAll: globalExpandAll, speed: speed)
    }

    private static func mode(for descriptor: PreviewVariantDescriptor) -> Tab3GoalWorkbenchMode {
        switch descriptor.id {
        case "tab3-v01": return .compactPrimaryRows
        case "tab3-v02": return .splitReceiptPanel
        case "tab3-v03": return .bentoGoalSwimlanes
        default: return .spectrumTimelineMatrix
        }
    }
}

private struct PreviewGoalWorkStreamVariantCard: View {
    let descriptor: PreviewVariantDescriptor
    let mode: Tab3GoalWorkbenchMode
    let data: AIDashPreviewSampleData
    let globalExpandAll: Bool
    let speed: PreviewSpeedMultiplier
    @State private var drawerExpanded = false
    @State private var selectedGoalIndex = 0
    @State private var activeFilter: GoalWorkStreamFilter = .all
    @Environment(\.theme) private var theme

    private var expanded: Bool { globalExpandAll || drawerExpanded }
    private var goals: [PreviewGoalWorkMetric] { data.goalStreams }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: descriptor.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.title)
                        .font(.headline.weight(.semibold))
                    Text(descriptor.metricTags.joined(separator: "  ·  "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    withAnimation(speed.spring()) { drawerExpanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            mainStage
            ClippedRevealLayout(progress: expanded ? 1 : 0) {
                PreviewSurface {
                    expandedSessionReceiptDrawer
                }
                .padding(.top, 8)
            }
            .clipped()
            .allowsHitTesting(expanded)
            .opacity(expanded ? 1 : 0)
            .animation(speed.spring(), value: expanded)
        }
        .padding(14)
        .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.neutrals.border.opacity(0.6), lineWidth: 1))
    }

    @ViewBuilder
    private var mainStage: some View {
        switch mode {
        case .compactPrimaryRows:
            compactPrimaryRowsStage
        case .splitReceiptPanel:
            splitReceiptPanelStage
        case .bentoGoalSwimlanes:
            bentoGoalSwimlanesStage
        case .spectrumTimelineMatrix:
            spectrumTimelineMatrixStage
        }
    }

    private var compactPrimaryRowsStage: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                GoalFilterSegmentedBar(selection: $activeFilter, variant: .pillCapsule)
                Spacer()
                PreviewPill("4 段动作占比", tint: theme.primary.primary)
            }
            ForEach(Array(filteredGoals.enumerated()), id: \.element.id) { idx, goal in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(goal.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        PreviewPill(goal.repoName, tint: .secondary)
                        PreviewPill(goal.reviewBadge, tint: goal.reworkPct > 8 ? theme.warning : theme.success)
                        Spacer()
                        Text(String(format: "%.0fm · %d 文件 · %d 会话", goal.durationMinutes, goal.filesChanged, goal.sessionCount))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    WorkStatusActionSplitBar(
                        split: WorkStatusActionSplit(
                            searchReadCalls: Int(goal.searchPct),
                            codeEditCalls: Int(goal.editPct),
                            verifyScriptCalls: Int(goal.verifyPct),
                            spinReworkCalls: Int(goal.reworkPct)
                        ),
                        height: 7
                    )
                    HStack(spacing: 6) {
                        Text(goal.skillsSummary.joined(separator: "  ·  "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button(selectedGoalIndex == idx ? "账单聚焦中" : "查看子会话") {
                            selectedGoalIndex = idx
                            drawerExpanded = true
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2.weight(.semibold))
                    }
                }
                .padding(9)
                .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private var splitReceiptPanelStage: some View {
        let activeGoal = goals.isEmpty ? nil : goals[selectedGoalIndex % goals.count]
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(goals.enumerated()), id: \.element.id) { idx, goal in
                    Button {
                        selectedGoalIndex = idx
                    } label: {
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(goal.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(goal.repoName) · \(Int(goal.durationMinutes))m · \(goal.sessionCount) 会话")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(goal.deltaText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(goal.reworkPct > 8 ? theme.warningOnSubtle : theme.successOnSubtle)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selectedGoalIndex == idx ? theme.primary.primary.opacity(0.14) : theme.neutrals.card,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            if let activeGoal {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("单页工作账单预览")
                            .font(.caption.weight(.bold))
                        Spacer()
                        if activeGoal.prNumber > 0 {
                            PreviewPill("PR #\(activeGoal.prNumber)", tint: theme.success)
                        }
                    }
                    WorkStatusActionSplitBar(
                        split: WorkStatusActionSplit(
                            searchReadCalls: Int(activeGoal.searchPct),
                            codeEditCalls: Int(activeGoal.editPct),
                            verifyScriptCalls: Int(activeGoal.verifyPct),
                            spinReworkCalls: Int(activeGoal.reworkPct)
                        ),
                        height: 8
                    )
                    Text(activeGoal.aiSignalLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    ForEach(activeGoal.childSessions.prefix(2)) { sess in
                        HStack(spacing: 6) {
                            Text(sess.roleTitle)
                                .font(.caption2.weight(.semibold))
                            Text(sess.durationText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(sess.ioText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private var bentoGoalSwimlanesStage: some View {
        let lanes: [(String, [PreviewGoalWorkMetric], Color)] = [
            ("在跑与审查", filteredGoals.filter { $0.status == "active" || $0.status == "in_review" }, theme.primary.primary),
            ("待 AI 提效", filteredGoals.filter { $0.reworkPct > 0 || $0.status == "daily" }, theme.warning),
            ("已交付闭环", filteredGoals.filter { $0.status == "done" || $0.prNumber > 0 }, theme.success),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            GoalFilterSegmentedBar(selection: $activeFilter, variant: .underlinedTabStrip)
            HStack(alignment: .top, spacing: 8) {
                ForEach(lanes, id: \.0) { laneTitle, items, tint in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(laneTitle)
                                .font(.caption.weight(.bold))
                            Spacer()
                            PreviewPill("\(items.count)", tint: tint)
                        }
                        ForEach(items.prefix(2)) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                WorkStatusActionSplitBar(
                                    split: WorkStatusActionSplit(
                                        searchReadCalls: Int(item.searchPct),
                                        codeEditCalls: Int(item.editPct),
                                        verifyScriptCalls: Int(item.verifyPct),
                                        spinReworkCalls: Int(item.reworkPct)
                                    ),
                                    height: 6
                                )
                                Text("\(Int(item.durationMinutes))m · \(item.filesChanged) 文件")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
    }

    private var spectrumTimelineMatrixStage: some View {
        let reworkDropSeries: [Double] = [14.2, 12.8, 10.5, 8.9, 7.1, 5.4, 4.0]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                GoalFilterSegmentedBar(selection: $activeFilter, variant: .underlinedTabStrip)
                Spacer()
                PreviewPill("重试占比 14.2% → 4.0% ▼", tint: theme.success)
            }
            PreviewSparkline(values: reworkDropSeries, tint: theme.success, height: 26)
            ForEach(filteredGoals.prefix(3)) { goal in
                HStack(spacing: 8) {
                    Text(goal.repoName)
                        .font(.caption2.weight(.semibold))
                        .frame(width: 72, alignment: .leading)
                    WorkStatusActionSplitBar(
                        split: WorkStatusActionSplit(
                            searchReadCalls: Int(goal.searchPct),
                            codeEditCalls: Int(goal.editPct),
                            verifyScriptCalls: Int(goal.verifyPct),
                            spinReworkCalls: Int(goal.reworkPct)
                        ),
                        height: 7
                    )
                    Text(String(format: "读%.0f%% 改%.0f%% 测%.0f%%", goal.searchPct, goal.editPct, goal.verifyPct))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 128, alignment: .trailing)
                }
            }
        }
    }

    private var filteredGoals: [PreviewGoalWorkMetric] {
        switch activeFilter {
        case .activeAndBlocked: return goals.filter { $0.status == "active" || $0.status == "in_review" }
        case .needsOptimization: return goals.filter { $0.reworkPct > 0 }
        case .delivered: return goals.filter { $0.prNumber > 0 }
        case .all: return goals
        }
    }

    private var expandedSessionReceiptDrawer: some View {
        let activeGoal = goals.isEmpty ? nil : goals[selectedGoalIndex % goals.count]
        return VStack(alignment: .leading, spacing: 6) {
            if let activeGoal {
                HStack {
                    Text("子会话账单明细 · \(activeGoal.title)")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(activeGoal.sessionCount) 个子会话")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ForEach(activeGoal.childSessions) { sess in
                    HStack(spacing: 8) {
                        PreviewPill(sess.roleTitle, tint: theme.primary.primary)
                        Text(sess.modelName)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Text(sess.durationText)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                        Text(sess.ioText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(DashboardTokenFormatter.compact(sess.tokens))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
#endif
