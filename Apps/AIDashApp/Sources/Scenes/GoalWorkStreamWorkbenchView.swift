#if os(macOS)
// swiftlint:disable file_length
import AppKit
import DesignKit
import SwiftUI

public enum GoalWorkStreamFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case activeAndBlocked
    case needsOptimization
    case delivered

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            return DashboardL10n.tr("dashboard.work_status.filter_all", "全部 Goal")
        case .activeAndBlocked:
            return DashboardL10n.tr("dashboard.work_status.filter_active", "在跑与阻塞")
        case .needsOptimization:
            return DashboardL10n.tr("dashboard.work_status.filter_optimize", "待 AI 提效")
        case .delivered:
            return DashboardL10n.tr("dashboard.work_status.filter_delivered", "已交付")
        }
    }

    public func matches(_ goal: WorkStatusGoalRow) -> Bool {
        let normalizedStatus = goal.status.lowercased()
        switch self {
        case .all:
            return true
        case .activeAndBlocked:
            if goal.isUnassignedBucket { return false }
            return ["active", "in_progress", "in_review", "blocked", "planning", "accepting", "ready"].contains(normalizedStatus)
                || (goal.outputs.prNumber == nil && !["done", "merged", "completed", "cancelled", "canceled"].contains(normalizedStatus))
        case .needsOptimization:
            return goal.aiSignals.contains { $0.severity == "warning" || $0.severity == "info" }
                || goal.actionSplit.spinReworkCalls > 0
                || goal.skillsUsed.contains(where: \.emptyLoad)
        case .delivered:
            return ["done", "merged", "completed"].contains(normalizedStatus) || goal.outputs.prNumber != nil
        }
    }
}

public struct SessionReceiptPresentation: Identifiable, Equatable, Sendable {
    public let goalTitle: String
    public let goalRepo: String?
    public let session: WorkStatusSessionReceipt
    public var id: String { "\(goalTitle):\(session.id)" }

    public init(goalTitle: String, goalRepo: String?, session: WorkStatusSessionReceipt) {
        self.goalTitle = goalTitle
        self.goalRepo = goalRepo
        self.session = session
    }
}

public enum WorkStatusFormatter {
    public static func durationText(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        if clamped < 60 {
            return String(format: "%.0fs", clamped)
        }
        let minutes = clamped / 60.0
        if minutes < 60 {
            return String(format: "%.0fm", minutes)
        }
        let hours = minutes / 60.0
        if hours < 48 {
            return String(format: "%.1fh", hours)
        }
        return String(format: "%.1fd", hours / 24.0)
    }

    public static func plainRoleBadge(roleKey: String, zh: String, en: String, locale: Locale) -> String {
        let isZh = locale.language.languageCode?.identifier.hasPrefix("zh") ?? true
        switch roleKey.lowercased() {
        case "m3": return isZh ? "总控" : "Coordinator"
        case "m2": return isZh ? "编排" : "Dispatcher"
        case "m1": return isZh ? "Goal 主控" : "Goal Lead"
        case "designer": return isZh ? "设计" : "Design"
        case "writer": return isZh ? "编码" : "Coding"
        case "reviewer": return isZh ? "审查" : "Review"
        case "explorer": return isZh ? "探查" : "Explore"
        case "pr_monitor": return isZh ? "交付监控" : "Monitor"
        default:
            let fallback = isZh ? zh : en
            return fallback.isEmpty ? (isZh ? "编码" : "Coding") : fallback
        }
    }

    public static func plainReviewBadge(_ goal: WorkStatusGoalRow, locale: Locale) -> (label: String, tone: GoalBadgeTone)? {
        guard let raw = goal.reviewRoundBadge, !raw.isEmpty else { return nil }
        let isZh = locale.language.languageCode?.identifier.hasPrefix("zh") ?? true
        if goal.isFirstPassReview {
            return (
                isZh
                    ? DashboardL10n.tr("dashboard.work_status.review_first_pass", "一次过审")
                    : DashboardL10n.tr("dashboard.work_status.review_first_pass_en", "First-Pass"),
                .success
            )
        }
        if goal.isSecondRoundReview {
            return (
                isZh
                    ? DashboardL10n.tr("dashboard.work_status.review_second_round", "二轮收敛")
                    : DashboardL10n.tr("dashboard.work_status.review_second_round_en", "2-Round Converged"),
                .primary
            )
        }
        return (
            isZh
                ? DashboardL10n.tr("dashboard.work_status.review_multi_round", "多轮返工")
                : DashboardL10n.tr("dashboard.work_status.review_multi_round_en", "Multi-Round Rework"),
            .warning
        )
    }

    public static func sanitizedSummary(_ raw: String?) -> String? {
        LiveDashboardTelemetryReaderSanitizer.sanitizeSummary(raw)
    }
}

public enum GoalFilterSegmentedBarVariant: String, CaseIterable, Sendable {
    case pillCapsule
    case underlinedTabStrip
}

@MainActor
public struct GoalFilterSegmentedBar: View {
    @Binding public var selection: GoalWorkStreamFilter
    public let variant: GoalFilterSegmentedBarVariant
    private let theme = Theme.system

    public init(
        selection: Binding<GoalWorkStreamFilter>,
        variant: GoalFilterSegmentedBarVariant = .pillCapsule
    ) {
        self._selection = selection
        self.variant = variant
    }

    public var body: some View {
        switch variant {
        case .pillCapsule:
            HStack(spacing: 3) {
                ForEach(GoalWorkStreamFilter.allCases) { item in
                    let isSelected = selection == item
                    Button {
                        selection = item
                    } label: {
                        Text(item.title)
                            .font(.caption.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? theme.neutrals.text1 : theme.neutrals.text2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(minHeight: 28)
                            .background(
                                isSelected ? theme.neutrals.card : Color.clear,
                                in: Capsule()
                            )
                            .overlay {
                                if isSelected {
                                    Capsule()
                                        .strokeBorder(theme.neutrals.border.opacity(0.65), lineWidth: 1)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(theme.neutrals.inner, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(theme.neutrals.border.opacity(0.45), lineWidth: 1)
            )
            .fixedSize(horizontal: true, vertical: false)
        case .underlinedTabStrip:
            HStack(spacing: 6) {
                ForEach(GoalWorkStreamFilter.allCases) { item in
                    let isSelected = selection == item
                    Button {
                        selection = item
                    } label: {
                        VStack(spacing: 4) {
                            Text(item.title)
                                .font(.caption.weight(isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? theme.primary.primary : theme.neutrals.text2)
                                .padding(.horizontal, 8)
                            Capsule()
                                .fill(isSelected ? theme.primary.primary : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

public enum GoalBadgeTone: Sendable {
    case success
    case warning
    case danger
    case primary
    case neutral
}

public struct WorkStatusActionSplitBar: View {
    public let split: WorkStatusActionSplit
    public let height: CGFloat
    @State private var hoveredSegment: Int?
    private let theme = Theme.system

    public init(split: WorkStatusActionSplit, height: CGFloat = 8) {
        self.split = split
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            let totalWidth = max(0, proxy.size.width)
            let srRatio = CGFloat(min(max(split.searchReadPct / 100.0, 0), 1))
            let ceRatio = CGFloat(min(max(split.codeEditPct / 100.0, 0), 1))
            let vsRatio = CGFloat(min(max(split.verifyScriptPct / 100.0, 0), 1))
            let swRatio = CGFloat(min(max(split.spinReworkPct / 100.0, 0), 1))
            let sumRatio = srRatio + ceRatio + vsRatio + swRatio

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.neutrals.inner)
                if sumRatio > 0.001 {
                    HStack(spacing: 1.5) {
                        if srRatio > 0 {
                            Rectangle()
                                .fill(theme.chartCategorical(0))
                                .frame(width: max(3, totalWidth * (srRatio / sumRatio)))
                        }
                        if ceRatio > 0 {
                            Rectangle()
                                .fill(theme.success)
                                .frame(width: max(3, totalWidth * (ceRatio / sumRatio)))
                        }
                        if vsRatio > 0 {
                            Rectangle()
                                .fill(theme.primary.primary)
                                .frame(width: max(3, totalWidth * (vsRatio / sumRatio)))
                        }
                        if swRatio > 0 {
                            Rectangle()
                                .fill(theme.warning)
                                .frame(width: max(3, totalWidth * (swRatio / sumRatio)))
                        }
                    }
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

@MainActor
public struct GoalWorkStreamWorkbenchView: View {
    public let summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?
    public let isLoading: Bool
    public let onRefresh: (() -> Void)?
    @State private var selectedFilter: GoalWorkStreamFilter = .all
    @State private var expandedGoalIDs: Set<String>
    @State private var activeReceipt: SessionReceiptPresentation?
    private let theme = Theme.system
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?,
        isLoading: Bool = false,
        initialFilter: GoalWorkStreamFilter = .all,
        initialExpandedGoalIDs: Set<String>? = nil,
        initialSelectedReceipt: SessionReceiptPresentation? = nil,
        onRefresh: (() -> Void)? = nil
    ) {
        self.summary = summary
        self.isLoading = isLoading
        self.onRefresh = onRefresh
        _selectedFilter = State(initialValue: initialFilter)
        if let initialExpandedGoalIDs {
            _expandedGoalIDs = State(initialValue: initialExpandedGoalIDs)
        } else if let firstAssigned = summary?.workStatus?.goals.first(where: { !$0.isUnassignedBucket })?.goalID
            ?? summary?.workStatus?.goals.first?.goalID {
            _expandedGoalIDs = State(initialValue: [firstAssigned])
        } else {
            _expandedGoalIDs = State(initialValue: [])
        }
        _activeReceipt = State(initialValue: initialSelectedReceipt)
    }

    private var snapshot: WorkStatusWorkbenchSnapshot? {
        summary?.workStatus
    }

    public var body: some View {
        SolidModularCardContainer(
            title: DashboardL10n.tr("dashboard.work_status.title", "Goal 与工作流工作台"),
            subtitle: headerSubtitle,
            symbolName: "point.3.connected.trianglepath.dotted"
        ) {
            headerAccessory
        } content: {
            workbenchBody
        }
        .sheet(item: $activeReceipt) { item in
            SessionWorkReceiptSheet(presentation: item)
        }
        .accessibilityIdentifier("dashboard.goalWorkStreamCard")
    }

    private var headerSubtitle: String {
        guard let snap = snapshot, snap.sampleSize > 0 else {
            return DashboardL10n.tr(
                "dashboard.work_status.subtitle_empty",
                "近 14 天 Goal 聚合工作流、四段动作光谱与单页会话账单"
            )
        }
        let asOf = snap.sourceAsOf ?? snap.windowEnd ?? "—"
        return DashboardL10n.format(
            "dashboard.work_status.subtitle_format",
            "窗口 %@ · 更新 %@ · %lld 个会话 · %lld 个活跃或归档 Goal",
            snap.windowCST,
            asOf,
            snap.sampleSize,
            snap.pulse.goalsCount
        )
    }

    @ViewBuilder
    private var headerAccessory: some View {
        let status = snapshot?.coverageStatus ?? (isLoading ? "loading" : "missing")
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(DashboardL10n.tr("dashboard.work_status.refreshing", "正在刷新"))
            }
            coverageCapsule(status: status)
        }
    }

    private func coverageCapsule(status: String) -> some View {
        let (label, fg, bg): (String, Color, Color) = {
            switch status {
            case "healthy":
                return (
                    DashboardL10n.tr("dashboard.work_status.cov_healthy", "数据完整"),
                    theme.successOnSubtle,
                    theme.success.opacity(0.15)
                )
            case "partial", "loading":
                return (
                    status == "loading"
                        ? DashboardL10n.tr("dashboard.work_status.cov_loading", "同步中")
                        : DashboardL10n.tr("dashboard.work_status.cov_partial", "部分覆盖"),
                    theme.warningOnSubtle,
                    theme.warning.opacity(0.15)
                )
            case "missing", "error":
                return (
                    DashboardL10n.tr("dashboard.work_status.cov_degraded", "待重采"),
                    theme.dangerOnSubtle,
                    theme.danger.opacity(0.15)
                )
            default:
                return (
                    DashboardL10n.tr("dashboard.work_status.cov_empty", "暂无样本"),
                    theme.text(.meta),
                    theme.neutrals.inner
                )
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg, in: Capsule())
            .foregroundStyle(fg)
    }

    @ViewBuilder
    private var workbenchBody: some View {
        let status = snapshot?.coverageStatus ?? (isLoading ? "loading" : "missing")
        switch status {
        case "missing", "error":
            degradedStateBanner(status: status)
        case "loading" where (snapshot?.goals.isEmpty ?? true):
            loadingSkeletonView
        case "unknown":
            emptyStateCard
        default:
            if let snap = snapshot, snap.sampleSize > 0, !snap.goals.isEmpty {
                populatedContent(snap)
            } else if isLoading {
                loadingSkeletonView
            } else {
                emptyStateCard
            }
        }
    }

    private func populatedContent(_ snap: WorkStatusWorkbenchSnapshot) -> some View {
        let filteredGoals = snap.goals.filter { selectedFilter.matches($0) }
        return VStack(alignment: .leading, spacing: 12) {
            if isLoading || snap.coverageStatus == "partial" {
                partialOrLoadingStrip(snap)
            }
            kpiPillsBand(snap)
            filterAndLegendBar(snap: snap, visibleCount: filteredGoals.count)
            if filteredGoals.isEmpty {
                scopedEmptyFilterBanner
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(filteredGoals.prefix(24))) { goal in
                        GoalWorkStreamExpandableRow(
                            goal: goal,
                            isExpanded: expandedGoalIDs.contains(goal.goalID),
                            locale: locale,
                            reduceMotion: reduceMotion,
                            onToggleExpand: { toggleGoal(goal.goalID) },
                            onOpenSessionReceipt: { session in
                                activeReceipt = SessionReceiptPresentation(
                                    goalTitle: goal.title,
                                    goalRepo: goal.repo,
                                    session: session
                                )
                            }
                        )
                    }
                }
            }
        }
    }

    private func toggleGoal(_ goalID: String) {
        let update = {
            if expandedGoalIDs.contains(goalID) {
                expandedGoalIDs.remove(goalID)
            } else {
                expandedGoalIDs.insert(goalID)
            }
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                update()
            }
        }
    }

    private func partialOrLoadingStrip(_ snap: WorkStatusWorkbenchSnapshot) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(
                    isLoading
                        ? DashboardL10n.tr("dashboard.work_status.inline_refreshing", "后台增量刷新中")
                        : DashboardL10n.tr("dashboard.work_status.inline_partial", "部分动作细项采集中")
                )
                .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(theme.warning.opacity(0.14), in: Capsule())
            .foregroundStyle(theme.warningOnSubtle)

            Text(DashboardL10n.format(
                "dashboard.work_status.partial_note_format",
                "已观测 %lld 个会话 · 缺省指标保持诚实留白",
                snap.sampleSize
            ))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Spacer(minLength: 4)
        }
        .accessibilityIdentifier("dashboard.goalWorkStreamPartialBanner")
        .accessibilityElement(children: .combine)
    }

    private func kpiPillsBand(_ snap: WorkStatusWorkbenchSnapshot) -> some View {
        let assigned = snap.goals.filter { !$0.isUnassignedBucket }
        let activeCount = assigned.filter { GoalWorkStreamFilter.activeAndBlocked.matches($0) }.count
        let blockedCount = assigned.filter { $0.status.lowercased() == "blocked" }.count
        let deliveredCount = assigned.filter { GoalWorkStreamFilter.delivered.matches($0) }.count
        let avgGoalMinutes = assigned.isEmpty
            ? (snap.pulse.durationSec / Double(max(1, snap.pulse.bucketsCount)) / 60.0)
            : (assigned.reduce(0.0) { $0 + $1.durationSec } / Double(assigned.count) / 60.0)
        let evaluated = assigned.filter { $0.reviewRoundBadge != nil }
        let firstPassCount = evaluated.filter(\.isFirstPassReview).count
        let passRateText: String = {
            if !evaluated.isEmpty {
                let pct = Int((100.0 * Double(firstPassCount) / Double(evaluated.count)).rounded())
                return "\(pct)%"
            }
            if let effRate = summary?.agentEfficiency?.roundSummary.r1PassRate {
                return "\(Int((effRate * 100.0).rounded()))%"
            }
            return "—"
        }()
        let optimizeSignalsCount = snap.goals.reduce(0) { acc, goal in
            acc + goal.aiSignals.filter { $0.severity == "warning" || $0.severity == "info" }.count
        }

        return DashboardResponsiveGrid(wideColumns: 4, compactColumns: 2) {
            kpiPillCard(
                id: "work-kpi-active",
                title: DashboardL10n.tr("dashboard.work_status.kpi_active", "活跃 / 阻塞 Goal"),
                primaryText: "\(activeCount) / \(blockedCount)",
                detailText: DashboardL10n.format(
                    "dashboard.work_status.kpi_active_sub",
                    "共 %lld 个独立 Goal",
                    snap.pulse.goalsCount
                ),
                tone: blockedCount > 0 ? .warning : .primary
            )
            kpiPillCard(
                id: "work-kpi-delivered",
                title: DashboardL10n.tr("dashboard.work_status.kpi_delivered", "14天完结 Goal / 合入 PR"),
                primaryText: "\(deliveredCount) / \(snap.pulse.prsTouchedCount) PR",
                detailText: DashboardL10n.format(
                    "dashboard.work_status.kpi_delivered_sub",
                    "改 %lld 文件 · %lld 提交",
                    snap.pulse.filesChangedCount,
                    snap.pulse.commitsCount
                ),
                tone: .success
            )
            kpiPillCard(
                id: "work-kpi-efficiency",
                title: DashboardL10n.tr("dashboard.work_status.kpi_pass_duration", "平均耗时 & 一次过审率"),
                primaryText: String(format: "%.0fm · %@", avgGoalMinutes, passRateText),
                detailText: DashboardL10n.format(
                    "dashboard.work_status.kpi_sessions_sub",
                    "%lld 会话 · %@ tok",
                    snap.pulse.sessionsCount,
                    DashboardTokenFormatter.compact(snap.pulse.totalTokens)
                ),
                tone: .primary
            )
            kpiPillCard(
                id: "work-kpi-signals",
                title: DashboardL10n.tr("dashboard.work_status.kpi_signals", "AI 识别待提效项"),
                primaryText: "\(optimizeSignalsCount)",
                detailText: DashboardL10n.format(
                    "dashboard.work_status.kpi_signals_sub",
                    "空载技能与重试摩擦汇总"
                ),
                tone: optimizeSignalsCount > 0 ? .warning : .success
            )
        }
    }

    private func kpiPillCard(
        id: String,
        title: String,
        primaryText: String,
        detailText: String,
        tone: GoalBadgeTone
    ) -> some View {
        let accent = color(for: tone)
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(primaryText)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
                .layoutPriority(1)
            Text(detailText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.neutrals.border.opacity(0.12), lineWidth: 1)
        )
        .captureDashboardGeometry(id: id, role: "kpiPill")
        .accessibilityElement(children: .combine)
    }

    private func filterAndLegendBar(snap: WorkStatusWorkbenchSnapshot, visibleCount: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                segmentedFilterPicker
                Spacer(minLength: 8)
                actionLegendItems(snap.pulse.actionSplit, visibleCount: visibleCount)
            }
            .frame(minWidth: 740)
            VStack(alignment: .leading, spacing: 8) {
                segmentedFilterPicker
                actionLegendItems(snap.pulse.actionSplit, visibleCount: visibleCount)
            }
        }
    }

    private var segmentedFilterPicker: some View {
        GoalFilterSegmentedBar(selection: $selectedFilter, variant: .pillCapsule)
            .captureDashboardGeometry(id: "work-status-filter", role: "segmented")
    }

    private func actionLegendItems(_ split: WorkStatusActionSplit, visibleCount: Int) -> some View {
        HStack(spacing: 10) {
            legendSwatch(
                label: DashboardL10n.tr("dashboard.work_status.seg_search", "搜索阅读"),
                pct: split.searchReadPct,
                tint: theme.chartCategorical(0)
            )
            legendSwatch(
                label: DashboardL10n.tr("dashboard.work_status.seg_edit", "编码产出"),
                pct: split.codeEditPct,
                tint: theme.success
            )
            legendSwatch(
                label: DashboardL10n.tr("dashboard.work_status.seg_verify", "测试脚本"),
                pct: split.verifyScriptPct,
                tint: theme.primary.primary
            )
            legendSwatch(
                label: DashboardL10n.tr("dashboard.work_status.seg_rework", "重试空转"),
                pct: split.spinReworkPct,
                tint: theme.warning
            )
            Text(DashboardL10n.format("dashboard.work_status.visible_count", "%lld 项", visibleCount))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(theme.neutrals.inner, in: Capsule())
        }
    }

    private func legendSwatch(label: String, pct: Double, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text("\(label) \(Int(pct.rounded()))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var scopedEmptyFilterBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(DashboardL10n.tr("dashboard.work_status.filter_empty", "当前筛选条件下暂无匹配的 Goal"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button {
                selectedFilter = .all
            } label: {
                Text(DashboardL10n.tr("dashboard.work_status.reset_filter", "查看全部 Goal"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minHeight: 28)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var loadingSkeletonView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(DashboardL10n.tr("dashboard.work_status.loading_title", "正在读取 Goal 与工作流快照…"))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
            }
            ForEach(0..<3, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.neutrals.card)
                    .frame(height: idx == 0 ? 64 : 52)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(theme.neutrals.inner)
                            .frame(width: idx == 0 ? 280 : 210, height: 14)
                            .padding(.leading, 14)
                    }
            }
        }
        .padding(12)
        .accessibilityIdentifier("dashboard.goalWorkStreamLoadingCard")
    }

    private var emptyStateCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(DashboardL10n.tr("dashboard.work_status.empty_title", "近 14 天暂无 Goal 与会话工作样本"))
                    .font(.subheadline.weight(.semibold))
                Text(DashboardL10n.tr(
                    "dashboard.work_status.empty_desc",
                    "待晨报流水线产出工作状态快照后，这里将展示 Goal 聚合耗时、四段动作占比与单页会话账单，不会伪造 0% 绿灯指标。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let onRefresh {
                Button(action: onRefresh) {
                    Label(
                        DashboardL10n.tr("dashboard.work_status.refresh_action", "刷新重试"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minHeight: 28)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.neutrals.border.opacity(0.12), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard.goalWorkStreamEmptyCard")
    }

    private func degradedStateBanner(status: String) -> some View {
        let isError = status == "error"
        let tint = isError ? theme.danger : theme.warning
        let textTint = isError ? theme.dangerOnSubtle : theme.warningOnSubtle
        let titleText = isError
            ? DashboardL10n.tr("dashboard.work_status.error_title", "工作流快照读取异常")
            : DashboardL10n.tr("dashboard.work_status.missing_title", "工作流数据源尚未就绪")
        let descText = isError
            ? DashboardL10n.tr(
                "dashboard.work_status.error_desc",
                "检测到工作状态快照解码或查询失败，已隐去零值以避免误导判断。"
            )
            : DashboardL10n.tr(
                "dashboard.work_status.missing_desc",
                "尚未发现本地或同步目录中的工作状态快照及数仓工作流表，可稍后刷新重试。"
            )
        return HStack(spacing: 12) {
            Image(systemName: isError ? "exclamationmark.octagon.fill" : "externaldrive.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(titleText)
                        .font(.subheadline.weight(.semibold))
                    Text(
                        isError
                            ? DashboardL10n.tr("dashboard.work_status.badge_error", "读取失败")
                            : DashboardL10n.tr("dashboard.work_status.badge_missing", "待采集")
                    )
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(textTint)
                }
                Text(descText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                onRefresh?()
            } label: {
                Label(
                    DashboardL10n.tr("dashboard.work_status.retry_button", "刷新重试"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(minHeight: 28)
            .accessibilityIdentifier("dashboard.goalWorkStreamRetryButton")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.32), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard.goalWorkStreamDegradedBanner")
    }

    private func color(for tone: GoalBadgeTone) -> Color {
        switch tone {
        case .success: return theme.successOnSubtle
        case .warning: return theme.warningOnSubtle
        case .danger: return theme.dangerOnSubtle
        case .primary: return theme.primary.primaryText
        case .neutral: return theme.text(.meta)
        }
    }
}

@MainActor
private struct GoalWorkStreamExpandableRow: View {
    let goal: WorkStatusGoalRow
    let isExpanded: Bool
    let locale: Locale
    let reduceMotion: Bool
    let onToggleExpand: () -> Void
    let onOpenSessionReceipt: (WorkStatusSessionReceipt) -> Void
    private let theme = Theme.system

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggleExpand) {
                goalSummaryHeader
            }
            .buttonStyle(.plain)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
            .accessibilityLabel(goalAccessibilitySummary)

            ClippedRevealLayout(progress: isExpanded ? 1.0 : 0.0) {
                expandedChildSessionsSection
                    .padding(.top, 8)
            }
            .clipped()
            .allowsHitTesting(isExpanded)
            .opacity(isExpanded ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.neutrals.border.opacity(0.12), lineWidth: 1)
        )
        .captureDashboardGeometry(id: "goal-row-\(goal.goalID)", role: "goalRow")
    }

    private var goalSummaryHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                statusDot
                Text(goal.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let repo = shortRepoName(goal.repo) {
                    capsuleTag(repo, fg: theme.text(.meta), bg: theme.neutrals.inner)
                }
                if let review = WorkStatusFormatter.plainReviewBadge(goal, locale: locale) {
                    capsuleTag(
                        review.label,
                        fg: fgColor(review.tone),
                        bg: bgColor(review.tone)
                    )
                }
                Spacer(minLength: 8)
                outputBadgesCluster
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }

            HStack(alignment: .center, spacing: 10) {
                WorkStatusActionSplitBar(split: goal.actionSplit, height: 7)
                    .frame(minWidth: 140, maxWidth: 260)
                Text(splitCompactText(goal.actionSplit))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(goal.skillsUsed.prefix(4)) { sk in
                            skillChip(sk)
                        }
                        ForEach(goal.aiSignals.filter { $0.severity == "warning" }.prefix(1)) { sig in
                            signalChip(sig)
                        }
                    }
                }
            }
        }
    }

    private var statusDot: some View {
        let s = goal.status.lowercased()
        let fill: Color = {
            if s == "blocked" { return theme.danger }
            if ["done", "merged", "completed"].contains(s) { return theme.success }
            if goal.isUnassignedBucket { return theme.text(.meta) }
            return theme.primary.primary
        }()
        return Circle()
            .fill(fill)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var outputBadgesCluster: some View {
        HStack(spacing: 6) {
            Text(WorkStatusFormatter.durationText(goal.durationSec))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
                .layoutPriority(1)
            if goal.outputs.filesChangedCount > 0 {
                capsuleTag(
                    DashboardL10n.format("dashboard.work_status.files_badge", "%lld 文件", goal.outputs.filesChangedCount),
                    fg: theme.text(.body),
                    bg: theme.neutrals.inner
                )
            }
            if let pr = goal.outputs.prNumber {
                capsuleTag(
                    "PR #\(pr)",
                    fg: theme.successOnSubtle,
                    bg: theme.success.opacity(0.15)
                )
            }
            capsuleTag(
                DashboardL10n.format("dashboard.work_status.sessions_badge", "%lld 会话", goal.outputs.sessionCount),
                fg: theme.primary.onPrimarySubtle,
                bg: theme.primary.primary.opacity(0.14)
            )
        }
    }

    private func skillChip(_ item: WorkStatusGoalSkillTouch) -> some View {
        let suffix: String = {
            if item.emptyLoad {
                return DashboardL10n.tr("dashboard.work_status.skill_empty_warn", "空挂预警")
            }
            if item.scriptSessions > 0 {
                return DashboardL10n.format("dashboard.work_status.skill_script_cnt", "%lld 脚本", item.scriptSessions)
            }
            return DashboardL10n.format("dashboard.work_status.skill_ref_cnt", "%lld 参考", item.referenceSessions)
        }()
        let fg = item.emptyLoad ? theme.warningOnSubtle : theme.text(.body)
        let bg = item.emptyLoad ? theme.warning.opacity(0.14) : theme.neutrals.inner
        return capsuleTag("\(item.skill) · \(suffix)", fg: fg, bg: bg)
    }

    private func signalChip(_ sig: WorkStatusAISignal) -> some View {
        let isZh = locale.language.languageCode?.identifier.hasPrefix("zh") ?? true
        let raw = isZh ? sig.labelZh : sig.labelEn
        let concise = raw.count > 26 ? String(raw.prefix(25)) + "…" : raw
        return capsuleTag(concise, fg: theme.warningOnSubtle, bg: theme.warning.opacity(0.14))
    }

    private var expandedChildSessionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if !goal.aiSignals.isEmpty {
                HStack(spacing: 6) {
                    ForEach(goal.aiSignals.prefix(2)) { sig in
                        let isZh = locale.language.languageCode?.identifier.hasPrefix("zh") ?? true
                        let tone: GoalBadgeTone = sig.severity == "positive" ? .success : (sig.severity == "warning" ? .warning : .primary)
                        HStack(spacing: 4) {
                            Image(systemName: sig.severity == "positive" ? "checkmark.seal.fill" : "sparkles")
                                .font(.caption2)
                                .accessibilityHidden(true)
                            Text(isZh ? sig.labelZh : sig.labelEn)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(bgColor(tone), in: Capsule())
                        .foregroundStyle(fgColor(tone))
                    }
                    Spacer(minLength: 4)
                }
            }

            ForEach(Array(goal.sessions.prefix(12))) { session in
                childSessionRow(session)
            }
        }
        .padding(.leading, 14)
    }

    private func childSessionRow(_ session: WorkStatusSessionReceipt) -> some View {
        let roleBadge = WorkStatusFormatter.plainRoleBadge(
            roleKey: session.roleKey,
            zh: session.roleLabelZh,
            en: session.roleLabelEn,
            locale: locale
        )
        return HStack(alignment: .center, spacing: 8) {
            capsuleTag(roleBadge, fg: theme.primary.onPrimarySubtle, bg: theme.primary.primary.opacity(0.14))
                .frame(minWidth: 62, alignment: .leading)
            Text(session.modelID ?? session.source)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(minWidth: 96, alignment: .leading)
                .lineLimit(1)
            Text(WorkStatusFormatter.durationText(session.durationSec))
                .font(.caption.monospacedDigit().weight(.medium))
                .frame(width: 48, alignment: .trailing)
                .layoutPriority(1)
            Text(DashboardL10n.format(
                "dashboard.work_status.session_io_format",
                "搜读 %lld · 改 %lld 文件",
                session.actionSplit.searchReadCalls,
                session.outputs.filesChangedCount
            ))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .layoutPriority(1)

            if !session.skillsUsed.isEmpty {
                Text(session.skillsUsed.prefix(2).map(\.skill).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let summaryText = WorkStatusFormatter.sanitizedSummary(session.summaryLabel) {
                Text(summaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)

            Button {
                onOpenSessionReceipt(session)
            } label: {
                Text(DashboardL10n.tr("dashboard.work_status.open_receipt", "查看工作账单"))
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minWidth: 28, minHeight: 28)
            .captureDashboardGeometry(id: "receipt-btn-\(session.id)", role: "button")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.neutrals.inner.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func capsuleTag(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(bg, in: Capsule())
            .foregroundStyle(fg)
            .lineLimit(1)
    }

    private func splitCompactText(_ s: WorkStatusActionSplit) -> String {
        DashboardL10n.format(
            "dashboard.work_status.split_compact_format",
            "读 %lld%% · 改 %lld%% · 测 %lld%%",
            Int(s.searchReadPct.rounded()),
            Int(s.codeEditPct.rounded()),
            Int(s.verifyScriptPct.rounded())
        )
    }

    private func shortRepoName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.split(separator: "/").last.map(String.init) ?? raw
    }

    private func fgColor(_ tone: GoalBadgeTone) -> Color {
        switch tone {
        case .success: return theme.successOnSubtle
        case .warning: return theme.warningOnSubtle
        case .danger: return theme.dangerOnSubtle
        case .primary: return theme.primary.onPrimarySubtle
        case .neutral: return theme.text(.meta)
        }
    }

    private func bgColor(_ tone: GoalBadgeTone) -> Color {
        switch tone {
        case .success: return theme.success.opacity(0.15)
        case .warning: return theme.warning.opacity(0.15)
        case .danger: return theme.danger.opacity(0.15)
        case .primary: return theme.primary.primary.opacity(0.14)
        case .neutral: return theme.neutrals.inner
        }
    }

    private var goalAccessibilitySummary: String {
        "\(goal.title), \(WorkStatusFormatter.durationText(goal.durationSec)), \(goal.outputs.filesChangedCount) files, \(goal.outputs.sessionCount) sessions"
    }
}

@MainActor
public struct SessionWorkReceiptSheet: View {
    public let presentation: SessionReceiptPresentation
    @State private var showExtendedMetadata = true
    @Environment(\.dismiss) private var dismiss
    private let theme = Theme.system
    @Environment(\.locale) private var locale

    public init(presentation: SessionReceiptPresentation) {
        self.presentation = presentation
    }

    private var session: WorkStatusSessionReceipt { presentation.session }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(DashboardL10n.tr("dashboard.work_status.receipt_title", "单页会话工作账单"))
                            .font(.headline.weight(.bold))
                        Text("#\(session.sessionIDShort)")
                            .font(.caption.monospaced().weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(theme.neutrals.inner, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    Text(presentation.goalTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    dismiss()
                } label: {
                    Text(DashboardL10n.tr("dashboard.work_status.receipt_close", "关闭"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minHeight: 28)
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            DashboardResponsiveGrid(wideColumns: 4, compactColumns: 2) {
                receiptMetricTile(
                    label: DashboardL10n.tr("dashboard.work_status.receipt_role", "分工角色"),
                    value: WorkStatusFormatter.plainRoleBadge(
                        roleKey: session.roleKey,
                        zh: session.roleLabelZh,
                        en: session.roleLabelEn,
                        locale: locale
                    ),
                    sub: session.modelID ?? session.source
                )
                receiptMetricTile(
                    label: DashboardL10n.tr("dashboard.work_status.receipt_duration", "执行耗时"),
                    value: WorkStatusFormatter.durationText(session.durationSec),
                    sub: DashboardL10n.format("dashboard.work_status.receipt_turns", "%lld 轮交互", session.turnCount)
                )
                receiptMetricTile(
                    label: DashboardL10n.tr("dashboard.work_status.receipt_tokens", "Token 消耗"),
                    value: DashboardTokenFormatter.compact(session.totalTokens),
                    sub: session.cstDay ?? "—"
                )
                receiptMetricTile(
                    label: DashboardL10n.tr("dashboard.work_status.receipt_outputs", "交付产出"),
                    value: DashboardL10n.format("dashboard.work_status.files_badge", "%lld 文件", session.outputs.filesChangedCount),
                    sub: session.outputs.prNumber.map { "PR #\($0) · \(session.outputs.commitsCount) commits" }
                        ?? "\(session.outputs.commitsCount) commits"
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(DashboardL10n.tr("dashboard.work_status.receipt_spectrum", "四段动作占比"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                WorkStatusActionSplitBar(split: session.actionSplit, height: 10)
                HStack(spacing: 12) {
                    receiptSplitLabel(
                        DashboardL10n.tr("dashboard.work_status.seg_search", "搜索阅读"),
                        calls: session.actionSplit.searchReadCalls,
                        pct: session.actionSplit.searchReadPct,
                        tint: theme.chartCategorical(0)
                    )
                    receiptSplitLabel(
                        DashboardL10n.tr("dashboard.work_status.seg_edit", "编码产出"),
                        calls: session.actionSplit.codeEditCalls,
                        pct: session.actionSplit.codeEditPct,
                        tint: theme.success
                    )
                    receiptSplitLabel(
                        DashboardL10n.tr("dashboard.work_status.seg_verify", "测试脚本"),
                        calls: session.actionSplit.verifyScriptCalls,
                        pct: session.actionSplit.verifyScriptPct,
                        tint: theme.primary.primary
                    )
                    receiptSplitLabel(
                        DashboardL10n.tr("dashboard.work_status.seg_rework", "重试空转"),
                        calls: session.actionSplit.spinReworkCalls,
                        pct: session.actionSplit.spinReworkPct,
                        tint: theme.warning
                    )
                }
            }
            .padding(12)
            .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(DashboardL10n.tr("dashboard.work_status.receipt_skills", "调用的 Skills 与命中情况"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if session.skillsUsed.isEmpty {
                    Text(DashboardL10n.tr("dashboard.work_status.receipt_no_skills", "本会话未显式挂载独立 Skill"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(session.skillsUsed) { sk in
                                let statusText = sk.emptyLoad
                                    ? DashboardL10n.tr("dashboard.work_status.skill_empty_warn", "空挂预警")
                                    : (sk.usedScript
                                        ? DashboardL10n.tr("dashboard.work_status.skill_hit_script", "命中脚本")
                                        : DashboardL10n.tr("dashboard.work_status.skill_hit_ref", "命中参考"))
                                Text("\(sk.skill) · \(statusText)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        (sk.emptyLoad ? theme.warning : theme.success).opacity(0.15),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(sk.emptyLoad ? theme.warningOnSubtle : theme.successOnSubtle)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let summaryText = WorkStatusFormatter.sanitizedSummary(session.summaryLabel) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DashboardL10n.tr("dashboard.work_status.receipt_summary", "任务摘要（已脱敏，不含原始对话流水）"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 580, height: 430, alignment: .topLeading)
        .background(theme.neutrals.bg)
        .accessibilityIdentifier("dashboard.sessionWorkReceiptSheet")
    }

    private func receiptMetricTile(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
            Text(sub)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func receiptSplitLabel(_ title: String, calls: Int, pct: Double, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text("\(title) \(calls) (\(Int(pct.rounded()))%)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
#endif
