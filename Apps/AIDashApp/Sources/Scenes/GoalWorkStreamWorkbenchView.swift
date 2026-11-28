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
    private let theme = Theme.system

    public init(split: WorkStatusActionSplit, height: CGFloat = 8) {
        self.split = split
        self.height = height
    }

    public var body: some View {
        let srRatio = CGFloat(min(max(split.searchReadPct / 100.0, 0), 1))
        let ceRatio = CGFloat(min(max(split.codeEditPct / 100.0, 0), 1))
        let vsRatio = CGFloat(min(max(split.verifyScriptPct / 100.0, 0), 1))
        let swRatio = CGFloat(min(max(split.spinReworkPct / 100.0, 0), 1))
        let sumRatio = srRatio + ceRatio + vsRatio + swRatio

        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let capsulePath = Capsule().path(in: rect)
            context.fill(capsulePath, with: .color(theme.neutrals.inner))
            guard sumRatio > 0.001, size.width > 0, size.height > 0 else { return }

            let segments: [(ratio: CGFloat, color: Color)] = [
                (srRatio, theme.chartCategorical(0)),
                (ceRatio, theme.success),
                (vsRatio, theme.primary.primary),
                (swRatio, theme.warning),
            ].filter { $0.ratio > 0 }
            guard !segments.isEmpty else { return }

            var clipContext = context
            clipContext.clip(to: capsulePath)
            let gap: CGFloat = 1.5
            let totalGap = gap * CGFloat(max(0, segments.count - 1))
            let usableWidth = max(0, size.width - totalGap)
            var currentX: CGFloat = 0
            for (index, segment) in segments.enumerated() {
                let rawWidth = usableWidth * (segment.ratio / sumRatio)
                let segmentWidth = index == segments.count - 1
                    ? max(0, size.width - currentX)
                    : min(max(3, rawWidth), max(0, size.width - currentX))
                let segRect = CGRect(x: currentX, y: 0, width: segmentWidth, height: size.height)
                clipContext.fill(Path(segRect), with: .color(segment.color))
                currentX += segmentWidth + gap
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

public enum GoalConvergenceHeaderVariant: String, CaseIterable, Sendable {
    case dualTrackDeck
    case compactCohortRibbon
}

public enum GoalStreamHierarchyVariant: String, CaseIterable, Sendable {
    case focusTopWithRepoAccordion
    case beforeAfterVersionSplit
}

public enum GoalExpandedDiagnosticVariant: String, CaseIterable, Sendable {
    case watermarkPillsPlusRoleRelayBar
    case timelineStepRelayList
}

@MainActor
public struct WorkStreamTrendMiniSparkline: View {
    public let values: [Double]
    public let tint: Color
    public let height: CGFloat
    private let theme = Theme.system

    public init(values: [Double], tint: Color, height: CGFloat = 22) {
        self.values = values
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            guard values.count >= 2, size.width > 4, size.height > 4 else {
                let midY = rect.midY
                var baseLine = Path()
                baseLine.move(to: CGPoint(x: 2, y: midY))
                baseLine.addLine(to: CGPoint(x: max(2, size.width - 2), y: midY))
                context.stroke(
                    baseLine,
                    with: .color(theme.neutrals.border.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])
                )
                if let single = values.first {
                    let dot = Path(ellipseIn: CGRect(x: size.width / 2 - 2.5, y: midY - 2.5, width: 5, height: 5))
                    context.fill(dot, with: .color(single >= 0 ? tint : theme.neutrals.text2))
                }
                return
            }
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let span = max(0.0001, maxV - minV)
            let padX: CGFloat = 3
            let padY: CGFloat = 3
            let usableW = max(1, size.width - padX * 2)
            let usableH = max(1, size.height - padY * 2)

            var linePath = Path()
            var areaPath = Path()
            var lastPt = CGPoint.zero
            for (idx, val) in values.enumerated() {
                let x = padX + usableW * CGFloat(idx) / CGFloat(max(1, values.count - 1))
                let norm = maxV == minV ? 0.5 : CGFloat((val - minV) / span)
                let y = padY + usableH * (1.0 - norm)
                let pt = CGPoint(x: x, y: y)
                if idx == 0 {
                    linePath.move(to: pt)
                    areaPath.move(to: CGPoint(x: pt.x, y: size.height - 1))
                    areaPath.addLine(to: pt)
                } else {
                    linePath.addLine(to: pt)
                    areaPath.addLine(to: pt)
                }
                lastPt = pt
            }
            areaPath.addLine(to: CGPoint(x: lastPt.x, y: size.height - 1))
            areaPath.closeSubpath()

            context.fill(areaPath, with: .color(tint.opacity(0.12)))
            context.stroke(linePath, with: .color(tint), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            context.fill(Path(ellipseIn: CGRect(x: lastPt.x - 2.5, y: lastPt.y - 2.5, width: 5, height: 5)), with: .color(tint))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

@MainActor
public struct RoleRelayDurationBar: View {
    public let items: [WorkStatusRoleRelayItem]
    public let locale: Locale
    public let height: CGFloat
    private let theme = Theme.system

    public init(items: [WorkStatusRoleRelayItem], locale: Locale = .current, height: CGFloat = 8) {
        self.items = items
        self.locale = locale
        self.height = height
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let capsule = Capsule().path(in: rect)
                context.fill(capsule, with: .color(theme.neutrals.inner))
                let nonEmpty = items.filter { $0.sharePct > 0 || $0.durationSec > 0 }
                let totalPct = nonEmpty.reduce(0.0) { $0 + max(0.1, $1.sharePct) }
                guard !nonEmpty.isEmpty, totalPct > 0, size.width > 0 else { return }

                var clipCtx = context
                clipCtx.clip(to: capsule)
                let gap: CGFloat = 1.5
                let usableW = max(0, size.width - gap * CGFloat(max(0, nonEmpty.count - 1)))
                var curX: CGFloat = 0
                for (idx, item) in nonEmpty.enumerated() {
                    let ratio = CGFloat(max(0.1, item.sharePct) / totalPct)
                    let segW = idx == nonEmpty.count - 1
                        ? max(0, size.width - curX)
                        : min(max(4, usableW * ratio), max(0, size.width - curX))
                    let segRect = CGRect(x: curX, y: 0, width: segW, height: size.height)
                    clipCtx.fill(Path(segRect), with: .color(roleColor(for: item.roleKey, hasRework: item.reworkCalls > 0)))
                    curX += segW + gap
                }
            }
            .frame(height: height)
            .accessibilityHidden(true)

            HStack(spacing: 6) {
                ForEach(items.prefix(6)) { item in
                    let roleText = WorkStatusFormatter.plainRoleBadge(
                        roleKey: item.roleKey,
                        zh: item.roleLabelZh,
                        en: item.roleLabelEn,
                        locale: locale
                    )
                    let tint = roleColor(for: item.roleKey, hasRework: item.reworkCalls > 0)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(tint)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text("\(roleText) \(WorkStatusFormatter.durationText(item.durationSec)) (\(Int(item.sharePct.rounded()))%)")
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundStyle(item.reworkCalls > 0 ? theme.warningOnSubtle : theme.text(.body))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (item.reworkCalls > 0 ? theme.warning.opacity(0.14) : theme.neutrals.inner),
                        in: Capsule()
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func roleColor(for key: String, hasRework: Bool) -> Color {
        if hasRework { return theme.warning }
        switch key.lowercased() {
        case "m3", "m2": return theme.chartCategorical(2)
        case "m1": return theme.primary.primary
        case "explorer": return theme.chartCategorical(0)
        case "designer": return theme.chartCategorical(3)
        case "writer": return theme.success
        case "reviewer": return theme.chartCategorical(1)
        default: return theme.primary.primary
        }
    }
}

@MainActor
public struct WorkStreamConvergenceTrendStrip: View {
    public let trendSummary: WorkStatusTrendSummary
    public let timeSeries: [WorkStatusTimeSeriesPoint]
    public let pulse: WorkStatusPulseSummary
    public let variant: GoalConvergenceHeaderVariant
    private let theme = Theme.system

    public init(
        trendSummary: WorkStatusTrendSummary,
        timeSeries: [WorkStatusTimeSeriesPoint],
        pulse: WorkStatusPulseSummary,
        variant: GoalConvergenceHeaderVariant = .dualTrackDeck
    ) {
        self.trendSummary = trendSummary
        self.timeSeries = timeSeries
        self.pulse = pulse
        self.variant = variant
    }

    public var body: some View {
        let fpSeries = timeSeries.compactMap(\.firstPassRate)
        let durSeries = timeSeries.compactMap(\.medianGoalDurationSec).map { $0 / 60.0 }
        let spinSeries = timeSeries.map(\.spinReworkPct)

        let fpValue = trendSummary.firstPassRatePct.map { "\(Int($0.rounded()))%" } ?? "—"
        let fpDelta = trendSummary.firstPassDeltaPct.map { val -> String in
            let sign = val >= 0 ? "▲ +" : "▼ "
            return String(format: "%@%.0f%%", sign, val)
        }
        let fpTone: GoalBadgeTone = {
            guard let d = trendSummary.firstPassDeltaPct else {
                return trendSummary.firstPassRatePct != nil ? .success : .neutral
            }
            return d >= 0 ? .success : .warning
        }()

        let durValue = trendSummary.medianGoalDurationSec.map { WorkStatusFormatter.durationText($0) } ?? "—"
        let durDelta = trendSummary.medianDurationDeltaSec.map { val -> String in
            let mins = val / 60.0
            let sign = mins <= 0 ? "▼ " : "▲ +"
            return String(format: "%@%.0fm", sign, mins)
        }
        let durTone: GoalBadgeTone = {
            guard let d = trendSummary.medianDurationDeltaSec else { return .primary }
            return d <= 0 ? .success : .warning
        }()

        let spinValue = String(format: "%.1f%%", trendSummary.spinReworkPct)
        let spinDelta = trendSummary.spinReworkDeltaPct.map { val -> String in
            let sign = val <= 0 ? "▼ " : "▲ +"
            return String(format: "%@%.1f%%", sign, val)
        }
        let spinTone: GoalBadgeTone = (trendSummary.spinReworkDeltaPct ?? 0) <= 0 && trendSummary.spinReworkPct <= 8.0
            ? .success
            : .warning

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.primary.primary)
                    .accessibilityHidden(true)
                Text(DashboardL10n.tr("dashboard.work_status.trend_strip_title", "随时间收敛趋势"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 6)
                Text(DashboardL10n.format(
                    "dashboard.work_status.trend_strip_meta",
                    "%lld Goal · %lld PR · %lld 会话",
                    pulse.goalsCount,
                    pulse.prsTouchedCount,
                    pulse.sessionsCount
                ))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            if variant == .dualTrackDeck {
                HStack(alignment: .top, spacing: 8) {
                    trendMetricCard(
                        id: "work-trend-first-pass",
                        title: DashboardL10n.tr("dashboard.work_status.metric_first_pass", "一次过审率"),
                        valueText: fpValue,
                        deltaText: fpDelta,
                        series: fpSeries,
                        tone: fpTone
                    )
                    trendMetricCard(
                        id: "work-trend-median-duration",
                        title: DashboardL10n.tr("dashboard.work_status.metric_median_duration", "单 Goal 中位耗时"),
                        valueText: durValue,
                        deltaText: durDelta,
                        series: durSeries,
                        tone: durTone
                    )
                    trendMetricCard(
                        id: "work-trend-spin-rework",
                        title: DashboardL10n.tr("dashboard.work_status.metric_spin_rework", "重试空转占比"),
                        valueText: spinValue,
                        deltaText: spinDelta,
                        series: spinSeries,
                        tone: spinTone
                    )
                }
            } else {
                HStack(spacing: 10) {
                    compactRibbonItem(
                        title: DashboardL10n.tr("dashboard.work_status.metric_first_pass", "一次过审率"),
                        valueText: fpValue,
                        deltaText: fpDelta,
                        tone: fpTone
                    )
                    Divider().frame(height: 22)
                    compactRibbonItem(
                        title: DashboardL10n.tr("dashboard.work_status.metric_median_duration", "单 Goal 中位耗时"),
                        valueText: durValue,
                        deltaText: durDelta,
                        tone: durTone
                    )
                    Divider().frame(height: 22)
                    compactRibbonItem(
                        title: DashboardL10n.tr("dashboard.work_status.metric_spin_rework", "重试空转占比"),
                        valueText: spinValue,
                        deltaText: spinDelta,
                        tone: spinTone
                    )
                    Spacer(minLength: 6)
                    WorkStreamTrendMiniSparkline(values: spinSeries.isEmpty ? fpSeries : spinSeries, tint: theme.success, height: 22)
                        .frame(width: 96)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.neutrals.border.opacity(0.14), lineWidth: 1)
        )
        .captureDashboardGeometry(id: "work-convergence-trend-strip", role: "trendStrip")
    }

    private func trendMetricCard(
        id: String,
        title: String,
        valueText: String,
        deltaText: String?,
        series: [Double],
        tone: GoalBadgeTone
    ) -> some View {
        let fg = fgTone(tone)
        let sparkTint = sparkColor(tone)
        return VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(valueText)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(fg)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let deltaText {
                    Text(deltaText)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(bgTone(tone), in: Capsule())
                        .foregroundStyle(fg)
                        .lineLimit(1)
                }
            }
            WorkStreamTrendMiniSparkline(values: series, tint: sparkTint, height: 20)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.neutrals.inner.opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .captureDashboardGeometry(id: id, role: "trendMetric")
        .accessibilityElement(children: .combine)
    }

    private func compactRibbonItem(title: String, valueText: String, deltaText: String?, tone: GoalBadgeTone) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(valueText)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(fgTone(tone))
            if let deltaText {
                Text(deltaText)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(fgTone(tone))
            }
        }
    }

    private func fgTone(_ tone: GoalBadgeTone) -> Color {
        switch tone {
        case .success: return theme.successOnSubtle
        case .warning: return theme.warningOnSubtle
        case .danger: return theme.dangerOnSubtle
        case .primary: return theme.primary.primaryText
        case .neutral: return theme.text(.meta)
        }
    }

    private func bgTone(_ tone: GoalBadgeTone) -> Color {
        switch tone {
        case .success: return theme.success.opacity(0.15)
        case .warning: return theme.warning.opacity(0.15)
        case .danger: return theme.danger.opacity(0.15)
        case .primary: return theme.primary.primary.opacity(0.14)
        case .neutral: return theme.neutrals.inner
        }
    }

    private func sparkColor(_ tone: GoalBadgeTone) -> Color {
        switch tone {
        case .success: return theme.success
        case .warning: return theme.warning
        case .danger: return theme.danger
        case .primary: return theme.primary.primary
        case .neutral: return theme.neutrals.text2
        }
    }
}

@MainActor
public struct SkillVersionCohortComparisonStrip: View {
    public let cohorts: [WorkStatusSkillVersionCohort]
    @Binding public var selectedCohortID: String?
    public let variant: GoalConvergenceHeaderVariant
    private let theme = Theme.system

    public init(
        cohorts: [WorkStatusSkillVersionCohort],
        selectedCohortID: Binding<String?>,
        variant: GoalConvergenceHeaderVariant = .dualTrackDeck
    ) {
        self.cohorts = cohorts
        self._selectedCohortID = selectedCohortID
        self.variant = variant
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.primary.primary)
                    .accessibilityHidden(true)
                Text(DashboardL10n.tr("dashboard.work_status.cohort_strip_title", "按技能版本前后对比"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 6)
                if selectedCohortID != nil {
                    Button {
                        selectedCohortID = nil
                    } label: {
                        Text(DashboardL10n.tr("dashboard.work_status.cohort_clear_focus", "退出版本对照"))
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .frame(minHeight: 28)
                } else {
                    Text(DashboardL10n.tr("dashboard.work_status.cohort_click_hint", "点击版本锚点聚焦前后 Goal"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if cohorts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(DashboardL10n.tr(
                        "dashboard.work_status.cohort_empty",
                        "当前窗口暂无跨版本水位对照样本，待技能升级并关联新旧 Goal 后自动呈现。"
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.neutrals.inner.opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if variant == .dualTrackDeck {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(cohorts.prefix(2)) { cohort in
                        cohortDeckButton(cohort)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(cohorts.prefix(3)) { cohort in
                        cohortRibbonPillButton(cohort)
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.neutrals.border.opacity(0.14), lineWidth: 1)
        )
        .captureDashboardGeometry(id: "work-skill-cohort-strip", role: "cohortStrip")
    }

    private func cohortDeckButton(_ cohort: WorkStatusSkillVersionCohort) -> some View {
        let isSelected = selectedCohortID == cohort.cohortID
        let hasRecurrence = cohort.postFixRecurrenceCount > 0
        let fpCompare: String = {
            let bText = cohort.beforeFirstPassPct.map { "\(Int($0.rounded()))%" } ?? "—"
            let aText = cohort.afterFirstPassPct.map { "\(Int($0.rounded()))%" } ?? "—"
            return "过审 \(bText)→\(aText)"
        }()
        let rwDeltaText: String = {
            let sign = cohort.reworkDeltaPct <= 0 ? "▼ " : "▲ +"
            return String(format: "空转 %@%.0f%%", sign, cohort.reworkDeltaPct)
        }()

        return Button {
            selectedCohortID = isSelected ? nil : cohort.cohortID
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(cohort.skill)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(cohort.previousVersion) → \(cohort.currentVersion)")
                        .font(.caption2.monospaced().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.primary.primary.opacity(0.15), in: Capsule())
                        .foregroundStyle(theme.primary.onPrimarySubtle)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(fpCompare)
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.primary)
                    Text(rwDeltaText)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(cohort.reworkDeltaPct <= 0 ? theme.successOnSubtle : theme.warningOnSubtle)
                }
                HStack(spacing: 6) {
                    Text(DashboardL10n.format(
                        "dashboard.work_status.cohort_sample_counts",
                        "前 %lld · 后 %lld Goal",
                        cohort.beforeGoalsCount,
                        cohort.afterGoalsCount
                    ))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(
                        hasRecurrence
                            ? DashboardL10n.format("dashboard.work_status.cohort_recurrence_cnt", "复发 %lld", cohort.postFixRecurrenceCount)
                            : DashboardL10n.tr("dashboard.work_status.cohort_clean", "新版零复发")
                    )
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((hasRecurrence ? theme.warning : theme.success).opacity(0.15), in: Capsule())
                    .foregroundStyle(hasRecurrence ? theme.warningOnSubtle : theme.successOnSubtle)
                }
            }
            .padding(9)
            .frame(minWidth: 215, alignment: .leading)
            .background(
                isSelected ? theme.primary.primary.opacity(0.13) : theme.neutrals.inner.opacity(0.75),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.primary.primary : theme.neutrals.border.opacity(0.2),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 28)
        .captureDashboardGeometry(id: "cohort-anchor-\(cohort.cohortID)", role: "cohortAnchor")
    }

    private func cohortRibbonPillButton(_ cohort: WorkStatusSkillVersionCohort) -> some View {
        let isSelected = selectedCohortID == cohort.cohortID
        let hasRecurrence = cohort.postFixRecurrenceCount > 0
        return Button {
            selectedCohortID = isSelected ? nil : cohort.cohortID
        } label: {
            HStack(spacing: 5) {
                Text("\(cohort.skill) \(cohort.previousVersion)→\(cohort.currentVersion)")
                    .font(.caption2.weight(.semibold))
                if let delta = cohort.firstPassDeltaPct {
                    Text(String(format: "%@%.0f%%", delta >= 0 ? "▲+" : "▼", delta))
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(delta >= 0 ? theme.successOnSubtle : theme.warningOnSubtle)
                }
                if hasRecurrence {
                    Text("复发\(cohort.postFixRecurrenceCount)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(theme.warningOnSubtle)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .background(
                isSelected ? theme.primary.primary.opacity(0.16) : theme.neutrals.inner,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? theme.primary.primary : theme.neutrals.border.opacity(0.3), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
public struct GoalWorkStreamWorkbenchView: View {
    public let summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?
    public let isLoading: Bool
    public let headerVariant: GoalConvergenceHeaderVariant
    public let hierarchyVariant: GoalStreamHierarchyVariant
    public let diagnosticVariant: GoalExpandedDiagnosticVariant
    public let onRefresh: (() -> Void)?
    @State private var selectedFilter: GoalWorkStreamFilter = .all
    @State private var selectedCohortID: String?
    @State private var expandedGoalIDs: Set<String>
    @State private var expandedRepos: Set<String>
    @State private var isUnassignedExpanded: Bool
    @State private var activeReceipt: SessionReceiptPresentation?
    private let theme = Theme.system
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?,
        isLoading: Bool = false,
        initialFilter: GoalWorkStreamFilter = .all,
        initialSelectedCohortID: String? = nil,
        initialExpandedGoalIDs: Set<String>? = nil,
        initialExpandedRepos: Set<String> = [],
        initialUnassignedExpanded: Bool = false,
        headerVariant: GoalConvergenceHeaderVariant = .dualTrackDeck,
        hierarchyVariant: GoalStreamHierarchyVariant = .focusTopWithRepoAccordion,
        diagnosticVariant: GoalExpandedDiagnosticVariant = .watermarkPillsPlusRoleRelayBar,
        initialSelectedReceipt: SessionReceiptPresentation? = nil,
        onRefresh: (() -> Void)? = nil
    ) {
        self.summary = summary
        self.isLoading = isLoading
        self.headerVariant = headerVariant
        self.hierarchyVariant = hierarchyVariant
        self.diagnosticVariant = diagnosticVariant
        self.onRefresh = onRefresh
        _selectedFilter = State(initialValue: initialFilter)
        _selectedCohortID = State(initialValue: initialSelectedCohortID)
        _expandedRepos = State(initialValue: initialExpandedRepos)
        _isUnassignedExpanded = State(initialValue: initialUnassignedExpanded)
        if let initialExpandedGoalIDs {
            _expandedGoalIDs = State(initialValue: initialExpandedGoalIDs)
        } else if let firstFocusAnomaly = summary?.workStatus?.goals.first(where: { $0.isFocusAnomaly })?.goalID {
            _expandedGoalIDs = State(initialValue: [firstFocusAnomaly])
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
        let activeCohort = selectedCohortID.flatMap { cid in
            snap.skillVersionCohorts.first(where: { $0.cohortID == cid })
        }
        return VStack(alignment: .leading, spacing: 12) {
            if isLoading || snap.coverageStatus == "partial" {
                partialOrLoadingStrip(snap)
            }
            topDualTrackConvergenceHeader(snap)
            filterAndLegendBar(snap: snap, visibleCount: filteredGoals.filter { !$0.isUnassignedBucket }.count)
            if let activeCohort {
                cohortComparisonFocusMatrix(cohort: activeCohort, allGoals: snap.goals)
            } else if hierarchyVariant == .beforeAfterVersionSplit, let defaultCohort = snap.skillVersionCohorts.first {
                cohortComparisonFocusMatrix(cohort: defaultCohort, allGoals: snap.goals)
            } else if filteredGoals.isEmpty {
                scopedEmptyFilterBanner
            } else {
                threeTierDeflattenedStream(snap: snap, filteredGoals: filteredGoals)
            }
        }
    }

    @ViewBuilder
    private func topDualTrackConvergenceHeader(_ snap: WorkStatusWorkbenchSnapshot) -> some View {
        if headerVariant == .dualTrackDeck {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    WorkStreamConvergenceTrendStrip(
                        trendSummary: snap.trendSummary,
                        timeSeries: snap.timeSeries,
                        pulse: snap.pulse,
                        variant: .dualTrackDeck
                    )
                    SkillVersionCohortComparisonStrip(
                        cohorts: snap.skillVersionCohorts,
                        selectedCohortID: $selectedCohortID,
                        variant: .dualTrackDeck
                    )
                }
                .frame(minWidth: 820)

                VStack(alignment: .leading, spacing: 10) {
                    WorkStreamConvergenceTrendStrip(
                        trendSummary: snap.trendSummary,
                        timeSeries: snap.timeSeries,
                        pulse: snap.pulse,
                        variant: .dualTrackDeck
                    )
                    SkillVersionCohortComparisonStrip(
                        cohorts: snap.skillVersionCohorts,
                        selectedCohortID: $selectedCohortID,
                        variant: .dualTrackDeck
                    )
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                WorkStreamConvergenceTrendStrip(
                    trendSummary: snap.trendSummary,
                    timeSeries: snap.timeSeries,
                    pulse: snap.pulse,
                    variant: .compactCohortRibbon
                )
                SkillVersionCohortComparisonStrip(
                    cohorts: snap.skillVersionCohorts,
                    selectedCohortID: $selectedCohortID,
                    variant: .compactCohortRibbon
                )
            }
        }
    }

    private func cohortComparisonFocusMatrix(cohort: WorkStatusSkillVersionCohort, allGoals: [WorkStatusGoalRow]) -> some View {
        let goalByID = Dictionary(uniqueKeysWithValues: allGoals.map { ($0.goalID, $0) })
        let beforeGoals = cohort.beforeGoalIDs.compactMap { goalByID[$0] }
        let afterGoals = cohort.afterGoalIDs.compactMap { goalByID[$0] }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.primary.primary)
                    .accessibilityHidden(true)
                Text(DashboardL10n.format(
                    "dashboard.work_status.cohort_focus_banner",
                    "版本对照聚焦：%@（%@ → %@）",
                    cohort.skill,
                    cohort.previousVersion,
                    cohort.currentVersion
                ))
                .font(.caption.weight(.bold))
                Spacer(minLength: 8)
                if selectedCohortID != nil {
                    Button {
                        selectedCohortID = nil
                    } label: {
                        Text(DashboardL10n.tr("dashboard.work_status.cohort_back_stream", "返回全量视图"))
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(minHeight: 28)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    cohortLaneColumn(
                        title: DashboardL10n.format(
                            "dashboard.work_status.cohort_before_lane",
                            "升级前样本 · %@（%lld）",
                            cohort.previousVersion,
                            beforeGoals.count
                        ),
                        subtitle: cohort.beforeFirstPassPct.map { "一次过审 \(Int($0.rounded()))% · 空转 \(Int(cohort.beforeReworkPct.rounded()))%" }
                            ?? "空转 \(Int(cohort.beforeReworkPct.rounded()))%",
                        goals: beforeGoals,
                        tone: .neutral
                    )
                    cohortLaneColumn(
                        title: DashboardL10n.format(
                            "dashboard.work_status.cohort_after_lane",
                            "升级后样本 · %@（%lld）",
                            cohort.currentVersion,
                            afterGoals.count
                        ),
                        subtitle: cohort.afterFirstPassPct.map { "一次过审 \(Int($0.rounded()))% · 空转 \(Int(cohort.afterReworkPct.rounded()))%" }
                            ?? "空转 \(Int(cohort.afterReworkPct.rounded()))%",
                        goals: afterGoals,
                        tone: cohort.postFixRecurrenceCount > 0 ? .warning : .success
                    )
                }
                .frame(minWidth: 780)

                VStack(alignment: .leading, spacing: 10) {
                    cohortLaneColumn(
                        title: "升级前样本 · \(cohort.previousVersion)（\(beforeGoals.count)）",
                        subtitle: "空转 \(Int(cohort.beforeReworkPct.rounded()))%",
                        goals: beforeGoals,
                        tone: .neutral
                    )
                    cohortLaneColumn(
                        title: "升级后样本 · \(cohort.currentVersion)（\(afterGoals.count)）",
                        subtitle: "空转 \(Int(cohort.afterReworkPct.rounded()))%",
                        goals: afterGoals,
                        tone: cohort.postFixRecurrenceCount > 0 ? .warning : .success
                    )
                }
            }
        }
        .padding(12)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.primary.primary.opacity(0.32), lineWidth: 1)
        )
        .captureDashboardGeometry(id: "work-cohort-focus-matrix", role: "cohortMatrix")
    }

    private func cohortLaneColumn(
        title: String,
        subtitle: String,
        goals: [WorkStatusGoalRow],
        tone: GoalBadgeTone
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Text(subtitle)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(color(for: tone))
            }
            if goals.isEmpty {
                Text(DashboardL10n.tr("dashboard.work_status.cohort_lane_empty", "当前时间窗口无对应版本 Goal 样本"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(goals.prefix(8)) { goal in
                    goalRowView(goal)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.neutrals.inner.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    private func threeTierDeflattenedStream(
        snap: WorkStatusWorkbenchSnapshot,
        filteredGoals: [WorkStatusGoalRow]
    ) -> some View {
        let focusGoals = filteredGoals.filter { !$0.isUnassignedBucket && $0.isFocusAnomaly }
        let steadyGoals = filteredGoals.filter { !$0.isUnassignedBucket && !$0.isFocusAnomaly }
        let unassignedGoals = filteredGoals.filter(\.isUnassignedBucket)

        let repoGroups: [WorkStatusRepoDeliveredGroup] = {
            if selectedFilter == .all && !snap.repoDeliveredGroups.isEmpty {
                return snap.repoDeliveredGroups
            }
            return WorkStatusDerivationHelper.deriveRepoDeliveredGroups(from: steadyGoals)
        }()
        let steadyByID = Dictionary(uniqueKeysWithValues: steadyGoals.map { ($0.goalID, $0) })

        VStack(alignment: .leading, spacing: 14) {
            // Tier 1: Pinned Focus Anomalies (Active/Blocked + Post-Fix Collision / Multi-Round Rework)
            if selectedFilter != .delivered || !focusGoals.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeaderRow(
                        icon: "bolt.trianglebadge.exclamationmark.fill",
                        title: DashboardL10n.tr("dashboard.work_status.tier_focus_title", "焦点跟进（在跑 / 阻塞 / 升级后仍返工）"),
                        badgeText: "\(focusGoals.count)",
                        tint: focusGoals.isEmpty ? theme.success : theme.warning
                    )
                    if focusGoals.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(theme.success)
                                .accessibilityHidden(true)
                            Text(DashboardL10n.tr(
                                "dashboard.work_status.tier_focus_calm",
                                "当前无阻塞或新版复发撞墙 Goal，已完结交付已按仓库折叠收纳。"
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    } else {
                        ForEach(Array(focusGoals.prefix(16))) { goal in
                            goalRowView(goal)
                        }
                    }
                }
                .captureDashboardGeometry(id: "work-tier-focus-anomalies", role: "focusSection")
            }

            // Tier 2: Steady First-Pass Delivered Goals Folded by Repository
            if !repoGroups.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeaderRow(
                        icon: "shippingbox.fill",
                        title: DashboardL10n.tr("dashboard.work_status.tier_steady_repo_title", "平稳一次过审交付（按项目仓库折叠）"),
                        badgeText: DashboardL10n.format(
                            "dashboard.work_status.tier_steady_repo_cnt",
                            "%lld 仓库 · %lld Goal",
                            repoGroups.count,
                            steadyGoals.count
                        ),
                        tint: theme.success
                    )
                    ForEach(repoGroups) { group in
                        repoFoldedAccordionCard(group: group, steadyByID: steadyByID)
                    }
                }
                .captureDashboardGeometry(id: "work-tier-repo-folded", role: "repoFoldSection")
            }

            // Tier 3: Unassigned Daily Standalone Sessions (Secondary Bottom Disclosure)
            if !unassignedGoals.isEmpty {
                ForEach(unassignedGoals) { bucket in
                    unassignedDailyDisclosureBar(bucket)
                }
            }
        }
    }

    private func sectionHeaderRow(icon: String, title: String, badgeText: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(badgeText)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint.opacity(0.15), in: Capsule())
                .foregroundStyle(tint == theme.warning ? theme.warningOnSubtle : theme.successOnSubtle)
            Spacer(minLength: 4)
        }
    }
}

@MainActor
private extension GoalWorkStreamWorkbenchView {
    private func repoFoldedAccordionCard(
        group: WorkStatusRepoDeliveredGroup,
        steadyByID: [String: WorkStatusGoalRow]
    ) -> some View {
        let isRepoExpanded = expandedRepos.contains(group.repo)
        let repoGoals = group.goalIDs.compactMap { steadyByID[$0] }
        let fpText = group.firstPassRatePct.map { "\(Int($0.rounded()))% 一次过审" } ?? "平稳完结"
        let medText = group.medianDurationSec.map { "中位 \(WorkStatusFormatter.durationText($0))" }
            ?? "累计 \(WorkStatusFormatter.durationText(group.totalDurationSec))"

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleRepo(group.repo)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.success)
                        .accessibilityHidden(true)
                    Text(group.repo)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(DashboardL10n.format(
                        "dashboard.work_status.repo_goals_prs",
                        "完结 %lld Goal · %lld PR",
                        group.goalsCount,
                        group.prsCount
                    ))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.success.opacity(0.14), in: Capsule())
                    .foregroundStyle(theme.successOnSubtle)

                    Text(fpText)
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("· \(medText)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(DashboardL10n.format(
                        "dashboard.work_status.repo_files_commits",
                        "改 %lld 文件 · %lld 提交",
                        group.filesChangedCount,
                        group.commitsCount
                    ))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    Image(systemName: isRepoExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(minHeight: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

            if isRepoExpanded && !repoGoals.isEmpty {
                Divider()
                    .padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(repoGoals) { goal in
                        goalRowView(goal)
                    }
                }
                .padding(10)
            }
        }
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.neutrals.border.opacity(0.12), lineWidth: 1)
        )
        .captureDashboardGeometry(id: "repo-group-\(group.repo)", role: "repoAccordion")
    }

    private func unassignedDailyDisclosureBar(_ bucket: WorkStatusGoalRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleUnassigned()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tray.2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(bucket.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(DashboardL10n.format(
                        "dashboard.work_status.unassigned_summary",
                        "%lld 个独立会话 · 累计 %@",
                        bucket.outputs.sessionCount,
                        WorkStatusFormatter.durationText(bucket.durationSec)
                    ))
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(theme.neutrals.inner, in: Capsule())
                    .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(
                        isUnassignedExpanded
                            ? DashboardL10n.tr("dashboard.work_status.collapse_daily", "收起日常会话")
                            : DashboardL10n.tr("dashboard.work_status.expand_daily", "按需展开")
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    Image(systemName: isUnassignedExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

            if isUnassignedExpanded {
                Divider()
                    .padding(.horizontal, 12)
                GoalWorkStreamExpandableRow(
                    goal: bucket,
                    isExpanded: true,
                    diagnosticVariant: diagnosticVariant,
                    locale: locale,
                    reduceMotion: reduceMotion,
                    onToggleExpand: { toggleUnassigned() },
                    onOpenSessionReceipt: { session in
                        activeReceipt = SessionReceiptPresentation(
                            goalTitle: bucket.title,
                            goalRepo: bucket.repo,
                            session: session
                        )
                    }
                )
                .padding(8)
            }
        }
        .background(theme.neutrals.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(theme.neutrals.border.opacity(0.1), lineWidth: 1)
        )
        .captureDashboardGeometry(id: "unassigned-daily-disclosure", role: "secondaryDisclosure")
    }

    private func goalRowView(_ goal: WorkStatusGoalRow) -> some View {
        GoalWorkStreamExpandableRow(
            goal: goal,
            isExpanded: expandedGoalIDs.contains(goal.goalID),
            diagnosticVariant: diagnosticVariant,
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

    private func toggleRepo(_ repo: String) {
        let update = {
            if expandedRepos.contains(repo) {
                expandedRepos.remove(repo)
            } else {
                expandedRepos.insert(repo)
            }
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) { update() }
        }
    }

    private func toggleUnassigned() {
        if reduceMotion {
            isUnassignedExpanded.toggle()
        } else {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                isUnassignedExpanded.toggle()
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
            withAnimation(nil) { update() }
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
    let diagnosticVariant: GoalExpandedDiagnosticVariant
    let locale: Locale
    let reduceMotion: Bool
    let onToggleExpand: () -> Void
    let onOpenSessionReceipt: (WorkStatusSessionReceipt) -> Void
    private let theme = Theme.system

    init(
        goal: WorkStatusGoalRow,
        isExpanded: Bool,
        diagnosticVariant: GoalExpandedDiagnosticVariant = .watermarkPillsPlusRoleRelayBar,
        locale: Locale,
        reduceMotion: Bool,
        onToggleExpand: @escaping () -> Void,
        onOpenSessionReceipt: @escaping (WorkStatusSessionReceipt) -> Void
    ) {
        self.goal = goal
        self.isExpanded = isExpanded
        self.diagnosticVariant = diagnosticVariant
        self.locale = locale
        self.reduceMotion = reduceMotion
        self.onToggleExpand = onToggleExpand
        self.onOpenSessionReceipt = onOpenSessionReceipt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggleExpand) {
                goalSummaryHeader
            }
            .buttonStyle(.plain)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
            .accessibilityLabel(goalAccessibilitySummary)

            if isExpanded {
                expandedChildSessionsSection
                    .padding(.top, 8)
            }
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
                    .frame(minWidth: 130, maxWidth: 210)
                Text(splitCompactText(goal.actionSplit))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                HStack(spacing: 5) {
                    ForEach(goal.skillWatermarks.prefix(2)) { wm in
                        watermarkChip(wm, compact: true)
                    }
                    ForEach(goal.skillsUsed.prefix(goal.skillWatermarks.isEmpty ? 3 : 1)) { sk in
                        skillChip(sk)
                    }
                }
                Spacer(minLength: 4)
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

    private func watermarkChip(_ wm: WorkStatusGoalSkillWatermark, compact: Bool = false) -> some View {
        let isZh = locale.language.languageCode?.identifier.hasPrefix("zh") ?? true
        let tone: GoalBadgeTone = {
            switch wm.watermarkState {
            case "post_fix_recurring": return .warning
            case "pre_fix_legacy": return .neutral
            default: return .success
            }
        }()
        let iconName: String = {
            switch wm.watermarkState {
            case "post_fix_recurring": return "exclamationmark.triangle.fill"
            case "pre_fix_legacy": return "clock.arrow.circlepath"
            default: return "checkmark.circle.fill"
            }
        }()
        let rawLabel = compact
            ? "\(wm.skill) · \(isZh ? wm.summaryZh : wm.summaryEn)"
            : (isZh ? wm.labelZh : wm.labelEn)
        let text = WorkStatusFormatter.sanitizedSummary(rawLabel) ?? rawLabel
        return HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(bgColor(tone), in: Capsule())
        .foregroundStyle(fgColor(tone))
    }

    private var expandedChildSessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            if !goal.skillWatermarks.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(DashboardL10n.tr("dashboard.work_status.watermark_section_title", "命中的技能版本水位（区分旧版遗留与新版复发）"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(goal.skillWatermarks.prefix(4)) { wm in
                            watermarkChip(wm, compact: false)
                        }
                    }
                }
                .captureDashboardGeometry(id: "goal-watermarks-\(goal.goalID)", role: "watermarkStrip")
            }

            if !goal.roleRelay.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(DashboardL10n.tr("dashboard.work_status.role_relay_title", "角色接力耗时条"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if diagnosticVariant == .watermarkPillsPlusRoleRelayBar {
                        RoleRelayDurationBar(items: goal.roleRelay, locale: locale, height: 8)
                    } else {
                        timelineStepRelayList
                    }
                }
                .padding(8)
                .background(theme.neutrals.inner.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .captureDashboardGeometry(id: "goal-role-relay-\(goal.goalID)", role: "roleRelay")
            }

            if !goal.aiSignals.isEmpty {
                HStack(spacing: 6) {
                    ForEach(goal.aiSignals.prefix(2)) { sig in
                        let isZh = locale.language.languageCode?.identifier.hasPrefix("zh") ?? true
                        let tone: GoalBadgeTone = sig.severity == "positive" ? .success : (sig.severity == "warning" ? .warning : .primary)
                        let rawSig = isZh ? sig.labelZh : sig.labelEn
                        let cleanSig = WorkStatusFormatter.sanitizedSummary(rawSig) ?? rawSig
                        HStack(spacing: 4) {
                            Image(systemName: sig.severity == "positive" ? "checkmark.seal.fill" : "sparkles")
                                .font(.caption2)
                                .accessibilityHidden(true)
                            Text(cleanSig)
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

    private var timelineStepRelayList: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(goal.roleRelay) { item in
                let roleTitle = WorkStatusFormatter.plainRoleBadge(
                    roleKey: item.roleKey,
                    zh: item.roleLabelZh,
                    en: item.roleLabelEn,
                    locale: locale
                )
                HStack(spacing: 8) {
                    Text(roleTitle)
                        .font(.caption2.weight(.bold))
                        .frame(width: 68, alignment: .leading)
                    Canvas { context, size in
                        let rect = CGRect(origin: .zero, size: size)
                        context.fill(Capsule().path(in: rect), with: .color(theme.neutrals.card))
                        let ratio = CGFloat(min(max(item.sharePct / 100.0, 0.04), 1.0))
                        let fillRect = CGRect(x: 0, y: 0, width: max(4, size.width * ratio), height: size.height)
                        context.fill(
                            Capsule().path(in: fillRect),
                            with: .color(item.reworkCalls > 0 ? theme.warning : theme.primary.primary)
                        )
                    }
                    .frame(height: 6)
                    .accessibilityHidden(true)
                    Text("\(WorkStatusFormatter.durationText(item.durationSec)) · \(Int(item.sharePct.rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .trailing)
                }
            }
        }
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
