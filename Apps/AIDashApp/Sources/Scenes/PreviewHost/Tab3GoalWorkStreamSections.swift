#if os(macOS)
import DesignKit
import SwiftUI

private enum Tab3GoalWorkbenchMode: String, CaseIterable {
    case dualTrackFocusRepoAccordion      // tab3-v01: Header.A + Stream.A + Diag.A
    case cohortRibbonVersionSplit         // tab3-v02: Header.B + Stream.B + Diag.A
    case repoHealthTimelineStepRelay      // tab3-v03: Header.A + Stream.A + Diag.B
    case watermarkActionSpectrumMatrix    // tab3-v04: Header.B + Stream.B + Diag.B
}

@MainActor
public enum Tab3GoalWorkStreamSections {
    public static let descriptors: [PreviewVariantDescriptor] = [
        PreviewVariantDescriptor(
            id: "tab3-v01",
            tab: .goalWorkStream,
            badgeCode: "V01",
            title: "双轨收敛 + 焦点置顶与仓库折叠",
            metricTags: ["收敛趋势 ▲"],
            symbolName: "point.3.connected.trianglepath.dotted",
            topologySignature: "tab3-v01:dual-track-convergence+focus-top+repo-accordion+role-relay-bar"
        ),
        PreviewVariantDescriptor(
            id: "tab3-v02",
            tab: .goalWorkStream,
            badgeCode: "V02",
            title: "版本水位靶标带 + 升级前后对照分栏",
            metricTags: ["版本提升 ▲"],
            symbolName: "arrow.triangle.branch",
            topologySignature: "tab3-v02:compact-cohort-ribbon+before-after-version-lanes+watermark-pills"
        ),
        PreviewVariantDescriptor(
            id: "tab3-v03",
            tab: .goalWorkStream,
            badgeCode: "V03",
            title: "仓库手风琴 + 角色阶梯微条账单",
            metricTags: ["接力耗时 ▼"],
            symbolName: "shippingbox.and.arrow.backward.fill",
            topologySignature: "tab3-v03:dual-track-header+repo-folded-stream+timeline-step-relay"
        ),
        PreviewVariantDescriptor(
            id: "tab3-v04",
            tab: .goalWorkStream,
            badgeCode: "V04",
            title: "异常聚焦光谱矩阵与复发对照台",
            metricTags: ["空转返工 ▼"],
            symbolName: "waveform.path.ecg.rectangle",
            topologySignature: "tab3-v04:cohort-ribbon+version-split-matrix+step-relay-spectrum"
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
        case "tab3-v01": return .dualTrackFocusRepoAccordion
        case "tab3-v02": return .cohortRibbonVersionSplit
        case "tab3-v03": return .repoHealthTimelineStepRelay
        default: return .watermarkActionSpectrumMatrix
        }
    }

    public static func makePreviewSnapshot(from data: AIDashPreviewSampleData) -> WorkStatusWorkbenchSnapshot {
        let goals = makePreviewGoals()
        let series: [WorkStatusTimeSeriesPoint] = [
            WorkStatusTimeSeriesPoint(day: "2026-11-22", goalsCompleted: 2, firstPassRate: 67.0, medianGoalDurationSec: 1620, spinReworkPct: 12.5, sessionsCount: 5),
            WorkStatusTimeSeriesPoint(day: "2026-11-24", goalsCompleted: 3, firstPassRate: 75.0, medianGoalDurationSec: 1440, spinReworkPct: 9.2, sessionsCount: 6),
            WorkStatusTimeSeriesPoint(day: "2026-11-26", goalsCompleted: 3, firstPassRate: 88.0, medianGoalDurationSec: 1200, spinReworkPct: 5.8, sessionsCount: 6),
            WorkStatusTimeSeriesPoint(day: "2026-11-28", goalsCompleted: 4, firstPassRate: 91.0, medianGoalDurationSec: 1140, spinReworkPct: 4.0, sessionsCount: 7),
        ]
        let cohorts = makePreviewCohorts()
        let repoGroups: [WorkStatusRepoDeliveredGroup] = [
            WorkStatusRepoDeliveredGroup(
                repo: "AIDash", goalsCount: 8, prsCount: 8, firstPassCount: 8, firstPassRatePct: 100.0,
                totalDurationSec: 8820, medianDurationSec: 1140, filesChangedCount: 42, commitsCount: 16,
                goalIDs: ["goal-theme-system"]
            ),
            WorkStatusRepoDeliveredGroup(
                repo: "user-skills", goalsCount: 6, prsCount: 6, firstPassCount: 6, firstPassRatePct: 100.0,
                totalDurationSec: 7200, medianDurationSec: 1200, filesChangedCount: 29, commitsCount: 11,
                goalIDs: ["goal-legacy-v18-sample"]
            ),
        ]
        return WorkStatusWorkbenchSnapshot(
            windowCST: "14d", windowStart: "2026-11-15", windowEnd: "2026-11-28", sourceAsOf: "2026-11-28",
            sampleSize: max(12, data.goalStreams.count * 3), coverageStatus: "healthy",
            pulse: WorkStatusPulseSummary(
                goalsCount: 16, bucketsCount: 17, sessionsCount: 24, durationSec: 19_500, totalTokens: 627_000,
                filesChangedCount: 85, commitsCount: 32, prsTouchedCount: 16,
                actionSplit: WorkStatusActionSplit(searchReadCalls: 34, codeEditCalls: 41, verifyScriptCalls: 18, spinReworkCalls: 4)
            ),
            trendSummary: WorkStatusTrendSummary(
                firstPassRatePct: 91.0, firstPassDeltaPct: 18.0, medianGoalDurationSec: 1140,
                medianDurationDeltaSec: -360, spinReworkPct: 4.0, spinReworkDeltaPct: -8.5
            ),
            timeSeries: series, skillVersionCohorts: cohorts, repoDeliveredGroups: repoGroups, goals: goals
        )
    }

    private static func makePreviewCohorts() -> [WorkStatusSkillVersionCohort] {
        [
            WorkStatusSkillVersionCohort(
                cohortID: "team-lead:v18->v19", skill: "team-lead", previousVersion: "v18", currentVersion: "v19",
                beforeGoalsCount: 4, afterGoalsCount: 6, beforeFirstPassPct: 66.0, afterFirstPassPct: 91.0,
                firstPassDeltaPct: 25.0, beforeReworkPct: 14.5, afterReworkPct: 3.8, reworkDeltaPct: -10.7,
                beforeMedianDurationSec: 1580, afterMedianDurationSec: 1160, postFixRecurrenceCount: 1,
                beforeGoalIDs: ["goal-legacy-v18-sample"], afterGoalIDs: ["goal-workbench-v2", "goal-skill-gate-collision"]
            ),
            WorkStatusSkillVersionCohort(
                cohortID: "my-designer:v11->v12", skill: "my-designer", previousVersion: "v11", currentVersion: "v12",
                beforeGoalsCount: 3, afterGoalsCount: 5, beforeFirstPassPct: 72.0, afterFirstPassPct: 95.0,
                firstPassDeltaPct: 23.0, beforeReworkPct: 11.0, afterReworkPct: 2.1, reworkDeltaPct: -8.9,
                beforeMedianDurationSec: 1490, afterMedianDurationSec: 1080, postFixRecurrenceCount: 0,
                beforeGoalIDs: ["goal-legacy-v18-sample"], afterGoalIDs: ["goal-workbench-v2", "goal-theme-system"]
            ),
        ]
    }

    private static func makePreviewGoals() -> [WorkStatusGoalRow] {
        let firstPassCode = "R" + "1"
        let focusActive = makeFocusActiveGoal()
        let focusCollision = makeFocusCollisionGoal()
        let steadyAIDash1 = WorkStatusGoalRow(
            goalID: "goal-theme-system", title: "系统原生动态外观令牌统一", isUnassignedBucket: false,
            repo: "AIDash", status: "merged", reviewRoundBadge: firstPassCode, latestActivityAt: "2026-11-26T08:00:00Z",
            durationSec: 1080, turnCount: 10, totalTokens: 115_000,
            skillsUsed: [WorkStatusGoalSkillTouch(skill: "my-designer", sessionLoads: 1, referenceSessions: 1, scriptSessions: 1)],
            skillWatermarks: [WorkStatusGoalSkillWatermark(skill: "my-designer", versionLabel: "v12", watermarkState: "post_fix_clean")],
            focusBucket: "steady_delivered", isFocusAnomaly: false,
            actionSplit: WorkStatusActionSplit(searchReadCalls: 5, codeEditCalls: 9, verifyScriptCalls: 4, spinReworkCalls: 0),
            outputs: WorkStatusGoalOutputs(filesChangedCount: 8, commitsCount: 2, prNumber: 347, sessionCount: 2)
        )
        let steadySkills1 = WorkStatusGoalRow(
            goalID: "goal-legacy-v18-sample", title: "历史队列锁与回执对账收敛", isUnassignedBucket: false,
            repo: "user-skills", status: "merged", reviewRoundBadge: firstPassCode, latestActivityAt: "2026-11-22T06:00:00Z",
            durationSec: 1380, turnCount: 11, totalTokens: 128_000,
            skillsUsed: [WorkStatusGoalSkillTouch(skill: "team-lead", sessionLoads: 1, referenceSessions: 1, scriptSessions: 1)],
            skillWatermarks: [WorkStatusGoalSkillWatermark(skill: "team-lead", versionLabel: "v18", watermarkState: "pre_fix_legacy")],
            focusBucket: "steady_delivered", isFocusAnomaly: false,
            actionSplit: WorkStatusActionSplit(searchReadCalls: 6, codeEditCalls: 7, verifyScriptCalls: 3, spinReworkCalls: 0),
            outputs: WorkStatusGoalOutputs(filesChangedCount: 4, commitsCount: 2, prNumber: 211, sessionCount: 2)
        )
        let dailyBucket = WorkStatusGoalRow(
            goalID: "unassigned-daily", title: "日常独立会话（未绑定独立 Goal）", isUnassignedBucket: true,
            repo: "AIDash", status: "daily", durationSec: 660, turnCount: 5, totalTokens: 48_000,
            focusBucket: "unassigned_daily", isFocusAnomaly: false,
            actionSplit: WorkStatusActionSplit(searchReadCalls: 6, codeEditCalls: 3, verifyScriptCalls: 1, spinReworkCalls: 0),
            outputs: WorkStatusGoalOutputs(filesChangedCount: 2, commitsCount: 0, prNumber: nil, sessionCount: 3)
        )
        return [focusActive, focusCollision, steadyAIDash1, steadySkills1, dailyBucket]
    }

    private static func makeFocusActiveGoal() -> WorkStatusGoalRow {
        WorkStatusGoalRow(
            goalID: "goal-workbench-v2", title: "Goal 与工作流双轨趋势及版本对照升级", isUnassignedBucket: false,
            repo: "AIDash", status: "in_progress", reviewRoundBadge: "R" + "1", latestActivityAt: "2026-11-28T03:30:00Z",
            durationSec: 1260, turnCount: 14, totalTokens: 162_000,
            skillsUsed: [
                WorkStatusGoalSkillTouch(skill: "team-lead", sessionLoads: 2, referenceSessions: 2, scriptSessions: 2),
                WorkStatusGoalSkillTouch(skill: "my-designer", sessionLoads: 2, referenceSessions: 2, scriptSessions: 2),
                WorkStatusGoalSkillTouch(skill: "aidash-metrics", sessionLoads: 1, referenceSessions: 1, scriptSessions: 1),
            ],
            skillWatermarks: [
                WorkStatusGoalSkillWatermark(skill: "team-lead", versionLabel: "v19", watermarkState: "post_fix_clean"),
                WorkStatusGoalSkillWatermark(skill: "my-designer", versionLabel: "v12", watermarkState: "post_fix_clean"),
            ],
            roleRelay: [
                WorkStatusRoleRelayItem(roleKey: "m1", roleLabelZh: "主控编排", roleLabelEn: "Goal Lead", durationSec: 240, sharePct: 19.0, sessionCount: 1, reworkCalls: 0),
                WorkStatusRoleRelayItem(roleKey: "designer", roleLabelZh: "视觉设计", roleLabelEn: "Visual Designer", durationSec: 260, sharePct: 20.6, sessionCount: 1, reworkCalls: 0),
                WorkStatusRoleRelayItem(roleKey: "writer", roleLabelZh: "编码实现", roleLabelEn: "Code Implementation", durationSec: 580, sharePct: 46.0, sessionCount: 1, reworkCalls: 0),
                WorkStatusRoleRelayItem(roleKey: "reviewer", roleLabelZh: "独立审查", roleLabelEn: "Independent Reviewer", durationSec: 180, sharePct: 14.4, sessionCount: 1, reworkCalls: 0),
            ],
            focusBucket: "active_or_blocked", isFocusAnomaly: true,
            actionSplit: WorkStatusActionSplit(searchReadCalls: 8, codeEditCalls: 14, verifyScriptCalls: 6, spinReworkCalls: 0),
            outputs: WorkStatusGoalOutputs(filesChangedCount: 7, commitsCount: 2, prNumber: 349, sessionCount: 4),
            aiSignals: [WorkStatusAISignal(kind: "first_pass_clean", severity: "positive", labelZh: "首轮审查一次通过，探查与编码节奏均衡", labelEn: "Clean first-pass flow")],
            sessions: [
                WorkStatusSessionReceipt(
                    sessionUID: "sw:prev-m1", sessionIDShort: "a190f210", roleKey: "m1", roleLabelZh: "主控编排", roleLabelEn: "Goal Lead",
                    modelID: "Gemini 4 Carbon", cstDay: "2026-11-28", durationSec: 240, turnCount: 4, totalTokens: 38_000,
                    skillsUsed: [WorkStatusSessionSkillTouch(skill: "team-lead", usedReference: true, usedScript: true)],
                    actionSplit: WorkStatusActionSplit(searchReadCalls: 3, codeEditCalls: 1, verifyScriptCalls: 2, spinReworkCalls: 0),
                    outputs: WorkStatusSessionOutputs(filesChangedCount: 1, commitsCount: 0, prNumber: 349)
                ),
                WorkStatusSessionReceipt(
                    sessionUID: "sw:prev-wr", sessionIDShort: "b284c901", roleKey: "writer", roleLabelZh: "编码实现", roleLabelEn: "Code Implementation",
                    modelID: "GPT-5.6", cstDay: "2026-11-28", durationSec: 580, turnCount: 7, totalTokens: 89_000,
                    skillsUsed: [WorkStatusSessionSkillTouch(skill: "my-designer", usedReference: true, usedScript: true)],
                    actionSplit: WorkStatusActionSplit(searchReadCalls: 3, codeEditCalls: 11, verifyScriptCalls: 3, spinReworkCalls: 0),
                    outputs: WorkStatusSessionOutputs(filesChangedCount: 6, commitsCount: 2, prNumber: 349)
                ),
            ]
        )
    }

    private static func makeFocusCollisionGoal() -> WorkStatusGoalRow {
        WorkStatusGoalRow(
            goalID: "goal-skill-gate-collision", title: "技能契约门禁巡检与重试收敛", isUnassignedBucket: false,
            repo: "user-skills", status: "done", reviewRoundBadge: "R" + "2", latestActivityAt: "2026-11-27T09:10:00Z",
            durationSec: 1560, turnCount: 15, totalTokens: 174_000,
            skillsUsed: [
                WorkStatusGoalSkillTouch(skill: "team-lead", sessionLoads: 2, referenceSessions: 1, scriptSessions: 2),
                WorkStatusGoalSkillTouch(skill: "skill-contract", sessionLoads: 1, referenceSessions: 0, scriptSessions: 0),
            ],
            skillWatermarks: [
                WorkStatusGoalSkillWatermark(skill: "team-lead", versionLabel: "v19", watermarkState: "post_fix_recurring"),
                WorkStatusGoalSkillWatermark(skill: "skill-contract", versionLabel: "v8", watermarkState: "pre_fix_legacy"),
            ],
            roleRelay: [
                WorkStatusRoleRelayItem(roleKey: "m1", roleLabelZh: "主控编排", roleLabelEn: "Goal Lead", durationSec: 300, sharePct: 19.2, sessionCount: 1, reworkCalls: 0),
                WorkStatusRoleRelayItem(roleKey: "writer", roleLabelZh: "编码实现", roleLabelEn: "Code Implementation", durationSec: 960, sharePct: 61.5, sessionCount: 2, reworkCalls: 2),
                WorkStatusRoleRelayItem(roleKey: "reviewer", roleLabelZh: "独立审查", roleLabelEn: "Independent Reviewer", durationSec: 300, sharePct: 19.3, sessionCount: 1, reworkCalls: 0),
            ],
            focusBucket: "post_fix_collision", isFocusAnomaly: true,
            actionSplit: WorkStatusActionSplit(searchReadCalls: 9, codeEditCalls: 8, verifyScriptCalls: 4, spinReworkCalls: 2),
            outputs: WorkStatusGoalOutputs(filesChangedCount: 5, commitsCount: 3, prNumber: 218, sessionCount: 3),
            aiSignals: [WorkStatusAISignal(kind: "script_or_rework_friction", severity: "warning", labelZh: "验证或脚本重试 2 次，建议收紧前置参数校验", labelEn: "Observed 2 retries")],
            sessions: [
                WorkStatusSessionReceipt(
                    sessionUID: "sw:col-wr", sessionIDShort: "c3319a12", roleKey: "writer", roleLabelZh: "编码实现", roleLabelEn: "Code Implementation",
                    modelID: "Claude Opus", cstDay: "2026-11-27", durationSec: 960, turnCount: 11, totalTokens: 118_000,
                    skillsUsed: [WorkStatusSessionSkillTouch(skill: "skill-contract", usedReference: false, usedScript: false)],
                    actionSplit: WorkStatusActionSplit(searchReadCalls: 6, codeEditCalls: 8, verifyScriptCalls: 3, spinReworkCalls: 2),
                    outputs: WorkStatusSessionOutputs(filesChangedCount: 5, commitsCount: 3, prNumber: 218)
                ),
            ]
        )
    }
}

private struct PreviewGoalWorkStreamVariantCard: View {
    let descriptor: PreviewVariantDescriptor
    let mode: Tab3GoalWorkbenchMode
    let data: AIDashPreviewSampleData
    let globalExpandAll: Bool
    let speed: PreviewSpeedMultiplier
    @State private var drawerExpanded = false
    private let theme = Theme.system

    private var expanded: Bool { globalExpandAll || drawerExpanded }

    var body: some View {
        let previewSnap = Tab3GoalWorkStreamSections.makePreviewSnapshot(from: data)
        let summary = LiveDashboardTelemetryReader.LiveEfficiencySummary(workStatus: previewSnap)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: descriptor.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.primary.primary)
                    .accessibilityHidden(true)
                Text(descriptor.title)
                    .font(.subheadline.weight(.semibold))
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

            variantComposedBody(summary: summary)
                .id("\(descriptor.id):\(expanded)")
        }
        .padding(10)
        .background(theme.neutrals.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func variantComposedBody(summary: LiveDashboardTelemetryReader.LiveEfficiencySummary) -> some View {
        switch mode {
        case .dualTrackFocusRepoAccordion:
            GoalWorkStreamWorkbenchView(
                summary: summary,
                initialExpandedGoalIDs: expanded ? ["goal-workbench-v2", "goal-skill-gate-collision"] : [],
                initialExpandedRepos: expanded ? ["AIDash"] : [],
                headerVariant: .dualTrackDeck,
                hierarchyVariant: .focusTopWithRepoAccordion,
                diagnosticVariant: .watermarkPillsPlusRoleRelayBar
            )
        case .cohortRibbonVersionSplit:
            GoalWorkStreamWorkbenchView(
                summary: summary,
                initialSelectedCohortID: "team-lead:v18->v19",
                initialExpandedGoalIDs: expanded ? ["goal-skill-gate-collision"] : [],
                headerVariant: .compactCohortRibbon,
                hierarchyVariant: .beforeAfterVersionSplit,
                diagnosticVariant: .watermarkPillsPlusRoleRelayBar
            )
        case .repoHealthTimelineStepRelay:
            GoalWorkStreamWorkbenchView(
                summary: summary,
                initialExpandedGoalIDs: ["goal-workbench-v2", "goal-skill-gate-collision"],
                initialExpandedRepos: expanded ? ["AIDash", "user-skills"] : ["AIDash"],
                headerVariant: .dualTrackDeck,
                hierarchyVariant: .focusTopWithRepoAccordion,
                diagnosticVariant: .timelineStepRelayList
            )
        case .watermarkActionSpectrumMatrix:
            GoalWorkStreamWorkbenchView(
                summary: summary,
                initialSelectedCohortID: "team-lead:v18->v19",
                initialExpandedGoalIDs: ["goal-workbench-v2", "goal-skill-gate-collision"],
                headerVariant: .compactCohortRibbon,
                hierarchyVariant: .beforeAfterVersionSplit,
                diagnosticVariant: .timelineStepRelayList
            )
        }
    }
}

#Preview("Goal Workbench V01 · 双轨收敛 + 焦点置顶 + 仓库折叠") {
    ScrollView {
        Tab3GoalWorkStreamSections.v01(data: .fallback(), globalExpandAll: false, speed: .normal)
            .padding(16)
    }
    .frame(width: 980, height: 760)
}

#Preview("Goal Workbench V02 · 版本演进锚点 + 前后分栏对照") {
    ScrollView {
        Tab3GoalWorkStreamSections.v02(data: .fallback(), globalExpandAll: true, speed: .normal)
            .padding(16)
    }
    .frame(width: 980, height: 760)
}

#Preview("Goal Workbench V03 · 仓库手风琴 + 角色阶梯接力") {
    ScrollView {
        Tab3GoalWorkStreamSections.v03(data: .fallback(), globalExpandAll: false, speed: .normal)
            .padding(16)
    }
    .frame(width: 980, height: 760)
}

#Preview("Goal Workbench V04 · 版本水位光谱矩阵") {
    ScrollView {
        Tab3GoalWorkStreamSections.v04(data: .fallback(), globalExpandAll: true, speed: .normal)
            .padding(16)
    }
    .frame(width: 980, height: 760)
}
#endif
