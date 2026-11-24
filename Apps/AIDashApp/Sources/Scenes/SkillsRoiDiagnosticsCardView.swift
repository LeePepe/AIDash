#if os(macOS)
// swiftlint:disable file_length
    import AIDashUI
    import DesignKit
    import SwiftUI

    private func skillsText(_ key: String, _ fallback: String) -> String { DashboardL10n.tr("dashboard.skills_roi.\(key)", fallback) }

    public enum SkillsRoiLens: String, CaseIterable, Identifiable {
        case usage, evolution, flywheel
        public var id: String { rawValue }
        var title: String {
            switch self {
            case .usage: skillsText("usage", "主力与健康")
            case .evolution: skillsText("evolution_lens", "版本进步")
            case .flywheel: skillsText("flywheel", "自演进飞轮")
            }
        }
    }

    private enum SkillsVitalDimension: String, CaseIterable, Identifiable {
        case adoption, efficiency, quality, evolution

        var id: String { rawValue }

        var title: String {
            switch self {
            case .adoption: skillsText("vital_adoption_title", "规模与活跃")
            case .efficiency: skillsText("vital_efficiency_title", "效率与耗时")
            case .quality: skillsText("vital_quality_title", "质量与稳定")
            case .evolution: skillsText("vital_evolution_title", "质检与演进")
            }
        }
    }

    public enum SkillsRoiObjectLens: String, CaseIterable, Identifiable {
        case overview, scripts, documents, quality

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: skillsText("object_overview", "分 Skill 总览")
            case .scripts: skillsText("object_scripts", "内部脚本")
            case .documents: skillsText("object_documents", "文档本身")
            case .quality: skillsText("object_quality", "质检与 Eval")
            }
        }
    }

    public enum SkillsRoiScriptFilter: String, CaseIterable, Identifiable, Sendable {
        case all, highError, slowestP95, unpracticed

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .all: skillsText("script_filter_all", "全部脚本")
            case .highError: skillsText("script_filter_error", "高报错")
            case .slowestP95: skillsText("script_filter_slowest", "最慢 P95")
            case .unpracticed: skillsText("script_filter_unpracticed", "未触发")
            }
        }

        func matches(_ script: SkillScriptDetail) -> Bool {
            switch self {
            case .all: true
            case .highError: (script.successRate ?? 1) < 0.9
            case .slowestP95: (script.p95Ms ?? 0) > 0
            case .unpracticed: script.isUnpracticed || (script.calls30d ?? 0) == 0
            }
        }
    }

    public enum SkillsRoiQualityView: String, CaseIterable, Identifiable, Sendable {
        case changes, pending, coverage

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .changes: skillsText("quality_view_changes", "版本变动")
            case .pending: skillsText("quality_view_pending", "待优化与修复")
            case .coverage: skillsText("quality_view_coverage", "Eval 覆盖")
            }
        }
    }

    public enum SkillUsageSemanticTier: String, Sendable, Equatable {
        case mainstay, stable, needsBoost, idle30d

        var label: String {
            switch self {
            case .mainstay: "🔥 " + skillsText("status_mainstay", "高频主力")
            case .stable: "🟢 " + skillsText("status_stable", "稳定健康")
            case .needsBoost: "🟡 " + skillsText("status_needs_boost", "待提效")
            case .idle30d: "💤 " + skillsText("status_idle_30d", "30天闲置")
            }
        }

        func tint(using theme: Theme) -> Color {
            switch self {
            case .mainstay: theme.primary.primary
            case .stable: theme.success
            case .needsBoost: theme.warning
            case .idle30d: theme.text(.meta)
            }
        }
    }

    public enum SkillEvolutionSemanticVerdict: String, Sendable, Equatable {
        case converged, improved, attention, stable

        var label: String {
            switch self {
            case .converged: "🟢 " + skillsText("evo_verdict_converged", "报错收敛")
            case .improved: "🟢 " + skillsText("evo_verdict_improved", "有效进化")
            case .attention: "🟠 " + skillsText("evo_verdict_attention", "报错增加")
            case .stable: "🔵 " + skillsText("evo_verdict_stable", "平稳迭代")
            }
        }

        func tint(using theme: Theme) -> Color {
            switch self {
            case .converged, .improved: theme.success
            case .attention: theme.warning
            case .stable: theme.classificationTint(.metric)
            }
        }
    }

    public enum SkillVersionEvolutionFilter: String, CaseIterable, Identifiable, Sendable { case meaningful, improved, regressed, all
        public var id: String { rawValue }
        var localizationKey: String { "filter_evolution_\(rawValue)" }
    }

    public enum SkillRetroPillar: String, CaseIterable, Identifiable, Sendable { case l0, l1, l2, l3
        public var id: String { rawValue }
    }

    public enum SkillInspectorFilter: String, CaseIterable, Identifiable, Sendable {
        case all, active, needsOptimization, idle30d, repoBound
        public var id: String { rawValue }
        var localizationKey: String {
            switch self {
            case .all: "filter_all"
            case .active: "filter_active"
            case .needsOptimization: "filter_needs_opt"
            case .idle30d: "filter_idle_30d"
            case .repoBound: "filter_repo_bound"
            }
        }

        func matches(_ detail: SkillInspectorDetail) -> Bool {
            switch self {
            case .all: !detail.isGhost
            case .active: !detail.isGhost && detail.loads30d > 0 && SkillsRoiDiagnosticsCardView.semanticUsageTier(for: detail) != .needsBoost
            case .needsOptimization: !detail.isGhost && (detail.statusLabel == "needs_optimization" || SkillsRoiDiagnosticsCardView.semanticUsageTier(for: detail) == .needsBoost)
            case .idle30d: !detail.isGhost && detail.loads30d == 0
            case .repoBound: !detail.isGhost && detail.scope == "repo_bound"
            }
        }
    }

    public enum SkillInspectorSubTab: String, CaseIterable, Identifiable, Sendable { case definition, scripts, evals, evolution
        public var id: String { rawValue }
    }

    public struct DashboardResponsiveGrid: Layout {
        public var wideColumns: Int
        public var compactColumns: Int
        public init(wideColumns: Int = 4, compactColumns: Int = 2) { self.wideColumns = wideColumns
            self.compactColumns = compactColumns
        }

        private func columns(for width: CGFloat) -> Int { width >= 960 ? wideColumns : (width >= 640 ? compactColumns : 1) }
        public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize { let width = proposal.width ?? 640
            let count = columns(for: width)
            let gap: CGFloat = 12
            let cellWidth = max(0, (width - CGFloat(count - 1) * gap) / CGFloat(count))
            var rowHeights: [CGFloat] = []
            for index in subviews.indices {
                let row = index / count
                if row >= rowHeights.count {
                    rowHeights.append(0)
                }
                rowHeights[row] = max(rowHeights[row], subviews[index].sizeThatFits(.init(width: cellWidth, height: nil)).height)
            }
            return CGSize(width: width, height: rowHeights.reduce(0, +) + CGFloat(max(0, rowHeights.count - 1)) * gap)
        }

        public func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) { let count = columns(for: bounds.width)
            let gap: CGFloat = 12
            let cellWidth = max(0, (bounds.width - CGFloat(count - 1) * gap) / CGFloat(count))
            var rowHeights: [CGFloat] = []
            for index in subviews.indices {
                let row = index / count
                if row >= rowHeights.count {
                    rowHeights.append(0)
                }
                rowHeights[row] = max(rowHeights[row], subviews[index].sizeThatFits(.init(width: cellWidth, height: nil)).height)
            }
            var y = bounds.minY
            for index in subviews.indices {
                let row = index / count
                let column = index % count
                subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(column) * (cellWidth + gap), y: y), proposal: .init(width: cellWidth, height: rowHeights[row]))
                if column == count - 1 || index == subviews.count - 1 {
                    y += rowHeights[row] + gap
                }
            }
        }
    }

    public struct SkillsRoiDiagnosticsCardView: View {
        let summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?
        @State private var lens: SkillsRoiLens
        @State private var showingMetadata = false
        @Environment(\.theme) private var theme
        @State private var inspectorFilter: SkillInspectorFilter
        @State private var evolutionFilter: SkillVersionEvolutionFilter
        @State private var showAllUsageSkills = false
        @State private var vitalDimension: SkillsVitalDimension = .adoption
        @State private var objectLens: SkillsRoiObjectLens
        @State private var scriptFilter: SkillsRoiScriptFilter = .all
        @State private var qualityView: SkillsRoiQualityView = .coverage
        @State private var selectedSkillDetail: SkillInspectorDetail?
        public init(
            summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?,
            initialLens: SkillsRoiLens = .usage,
            showDailyPopulations _: Bool = false,
            initialSelectedSkill _: String? = nil,
            initialSelectedPillar _: SkillRetroPillar? = nil,
            initialEvolutionFilter: SkillVersionEvolutionFilter = .meaningful,
            initialFilter: SkillInspectorFilter = .all,
            initialSubTab _: SkillInspectorSubTab = .definition,
            initialPreviewRelativePath _: String? = nil,
            previewHomeURL _: URL? = nil,
            initialObjectLens: SkillsRoiObjectLens = .overview
        ) {
            self.summary = summary
            _lens = State(initialValue: initialLens)
            _inspectorFilter = State(initialValue: initialFilter)
            _evolutionFilter = State(initialValue: initialEvolutionFilter)
            _objectLens = State(initialValue: initialObjectLens)
        }

        public var body: some View {
            SolidModularCardContainer(title: skillsText("title", "Skills 状态"), subtitle: nil, symbolName: "sparkles") {
                if let report = summary?.skillsROI {
                    VStack(alignment: .leading, spacing: 16) {
                        fourByFourStage(report)
                    }
                } else {
                    Text(skillsText("missing", "暂无 Skills 状态数据")).foregroundStyle(.secondary)
                }
            }
            .sheet(item: $selectedSkillDetail) { detail in
                SkillHealthSheet(detail: detail, report: summary?.skillsROI)
            }
        }

        @ViewBuilder private func fourByFourStage(_ report: SkillsRoiReport) -> some View {
            DashboardResponsiveGrid(wideColumns: 4, compactColumns: 2) {
                ForEach(SkillsVitalDimension.allCases) { dimension in
                    Button {
                        vitalDimension = dimension
                    } label: {
                        vitalCard(dimension, report: report)
                    }
                    .buttonStyle(.plain)
                    .captureDashboardGeometry(id: "skills-vital-\(dimension.id)", role: "vital")
                }
            }
            .padding(10)
            .captureDashboardGeometry(id: "skills-p0-vitals", role: "vitals")

            HStack(spacing: 8) {
                Picker(skillsText("object_lens", "对象切面"), selection: $objectLens) {
                    ForEach(SkillsRoiObjectLens.allCases) { lens in
                        Text(lens.title).tag(lens)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 28)
                .captureDashboardGeometry(id: "skills-lens", role: "segmented")

                Button { showingMetadata = true } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .frame(minWidth: 28, minHeight: 28)
                .accessibilityLabel(skillsText("metadata", "数据窗口"))
                .popover(isPresented: $showingMetadata) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(skillsText("metadata", "数据窗口"))
                        Text(report.metadata.window ?? skillsText("window_unknown", "未知窗口"))
                        Text(report.metadata.asOf ?? skillsText("as_of_unknown", "更新时间未知"))
                        Text(skillsText("sample", "样本"))
                        Text(report.metadata.sample.map(String.init) ?? skillsText("unknown", "未知"))
                        Text(skillsText("coverage", "覆盖情况"))
                        Text(report.metadata.coverage ?? skillsText("unknown", "未知"))
                    }
                    .padding(16)
                }
            }

            objectStage(report)
        }

        @ViewBuilder private func objectStage(_ report: SkillsRoiReport) -> some View {
            switch objectLens {
            case .overview:
                overviewStage(report)
            case .scripts:
                scriptsStage(report)
            case .documents:
                documentsStage(report)
            case .quality:
                qualityStage(report)
            }
        }

        private func vitalCard(_ dimension: SkillsVitalDimension, report: SkillsRoiReport) -> some View {
            let active = Self.activeVsTotalCounts(in: report)
            let details = managedDetails(report).filter { !$0.isGhost }
            let calls = details.reduce(0) { $0 + $1.loads7d }
            let scriptMedian = Self.aggregateScriptMedian(details.flatMap(\.scripts))
            let behavior = Self.aggregateActiveDurationMedian(report.qualityBehavior ?? [])
            let satisfaction = Self.aggregateSatisfactionRate(report.qualityBehavior ?? [])
            let noError = Self.aggregateNoErrorRate(report: report, details: details)
            let judgeMean = Self.aggregateJudgeMean(report.qualityJudge)
            let eval = Self.aggregateEvalSummary(report: report, details: details)
            let value: String
            let subtitle: String
            let tint: Color
            switch dimension {
            case .adoption:
                value = active.map { "\($0.active) / \($0.total)" } ?? skillsText("unknown", "未知")
                let month = Self.monthlyAdoptionComparison(details: details)
                let empty = Self.emptyInvocationCount(report.qualityBehavior)
                subtitle = "\(skillsText("calls_7d", "本周")) \(calls) \(skillsText("unit_times", "次"))"
                    + (month.map { " · \($0)" } ?? "")
                    + " · \(skillsText("empty_invocations", "空唤起")) \(empty.map(String.init) ?? skillsText("unknown", "未知"))"
                tint = theme.primary.primary
            case .efficiency:
                value = behavior.map { String(format: "%.1fm", $0 / 60) } ?? scriptMedian.map { "\(Int($0))ms" } ?? skillsText("unknown", "未知")
                subtitle = scriptMedian.map { "\(skillsText("script_median", "脚本中位")) \(Int($0))ms" } ?? skillsText("no_duration", "暂无耗时数据")
                tint = theme.classificationTint(.relationship)
            case .quality:
                value = satisfaction.map { "\(Int($0 * 100))%" } ?? Self.overallPassValueForReport(report).map { "\(Int($0 * 100))%" } ?? skillsText("unknown", "未知")
                subtitle = "\(skillsText("no_error_rate", "无错率")) \(Self.percentText(noError))"
                    + " · \(skillsText("judge_mean", "抽检均分")) \(judgeMean.map { String(format: "%.1f", $0) } ?? skillsText("unknown", "未知"))"
                tint = theme.success
            case .evolution:
                value = "\(skillsText("eval", "Eval")) \(eval.population)/\(eval.totalSkills)"
                subtitle = "\(eval.totalCases) \(skillsText("eval_cases", "条用例")) · \(skillsText("coverage", "覆盖")) \(Self.percentText(eval.coverage)) · \(skillsText("evolution_fixed", "已修")) \(Self.curedRoadblocks(in: report).count)"
                tint = theme.warning
            }
            return VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                    Text(dimension.title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(tint.opacity(vitalDimension == dimension ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(vitalDimension == dimension ? 0.48 : 0.18), lineWidth: vitalDimension == dimension ? 1.5 : 1))
        }

        @ViewBuilder private func overviewStage(_ report: SkillsRoiReport) -> some View {
            let details = sortedDetails(report)
            let visible = showAllUsageSkills ? details : Array(details.prefix(10))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(skillsText("overview_header", "分 Skill 健康状态"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if details.count > 10 {
                        Button(showAllUsageSkills ? skillsText("collapse_top10", "收起至 Top 10") : skillsText("expand_all", "展开全部")) {
                            showAllUsageSkills.toggle()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .frame(minWidth: 28, minHeight: 28)
                    }
                }
                DashboardResponsiveGrid(wideColumns: 2, compactColumns: 2) {
                    ForEach(visible) { detail in
                        Button { selectedSkillDetail = detail } label: {
                            skillOverviewCard(detail, report: report)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        private func skillOverviewCard(_ detail: SkillInspectorDetail, report: SkillsRoiReport) -> some View {
            let evolution = report.versionEvolution.first { $0.skill == detail.skill }
            let tier = Self.semanticUsageTier(for: detail, evolution: evolution)
            return VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(detail.skill).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(Self.cleanVersionLabel(evolution?.combinedVersion ?? "v1")).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    statusBadge(tier.label, tint: tier.tint(using: theme))
                }
                HStack(spacing: 10) {
                    compactMetric("\(detail.loads7d)", skillsText("calls_7d", "调用"))
                    if let p95 = detail.scripts.compactMap(\.p95Ms).min() {
                        compactMetric("\(Int(p95))ms", skillsText("script", "脚本"))
                    }
                    if let rate = Self.validPassRate(detail.r1PassRate) {
                        compactMetric("\(Int(rate * 100))%", skillsText("quality", "质量"))
                    }
                    if detail.editChurn > 0 {
                        compactMetric("\(detail.editChurn)", skillsText("changes", "变动"))
                    }
                }
                Text(diagnosisText(detail, evolution: evolution))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(tier.tint(using: theme).opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier("skills-row-\(detail.skill)")
            .accessibilityElement(children: .combine)
        }

        private func compactMetric(_ value: String, _ label: String) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.caption.monospacedDigit().weight(.medium))
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }

        private func diagnosisText(_ detail: SkillInspectorDetail, evolution: SkillVersionEvolutionRow?) -> String {
            if detail.implBugEscapes + detail.specGapEscapes > 0 {
                return skillsText("diagnosis_quality", "有质量信号需要排查")
            }
            if let p95 = detail.scripts.compactMap(\.p95Ms).max(), p95 > 4000 {
                return skillsText("diagnosis_slow", "脚本耗时偏高，建议关注")
            }
            if detail.loads30d == 0 {
                return skillsText("diagnosis_idle", "近 30 天没有调用")
            }
            if evolution?.status == "improved" {
                return skillsText("diagnosis_improved", "版本进步带来更稳定的结果")
            }
            return skillsText("diagnosis_healthy", "当前运行状态稳定")
        }

        @ViewBuilder private func scriptsStage(_ report: SkillsRoiReport) -> some View {
            let filteredScripts = managedDetails(report).flatMap { detail in
                detail.scripts.map { (detail.skill, $0) }
            }.filter { scriptFilter.matches($0.1) }
            let scripts = scriptFilter == .slowestP95
                ? filteredScripts.sorted { ($0.1.p95Ms ?? 0) > ($1.1.p95Ms ?? 0) }
                : filteredScripts
            VStack(alignment: .leading, spacing: 8) {
                Picker(skillsText("script_filter", "脚本筛选"), selection: $scriptFilter) {
                    ForEach(SkillsRoiScriptFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 28)
                DashboardResponsiveGrid(wideColumns: 2, compactColumns: 2) {
                    ForEach(Array(scripts.enumerated()), id: \.offset) { _, item in
                        let (skill, script) = item
                        detailCard(title: script.relPath.split(separator: "/").last.map(String.init) ?? script.relPath, subtitle: skill) {
                            HStack {
                                compactMetric("\(script.calls30d ?? 0)", skillsText("calls_30d", "30天调用"))
                                compactMetric(script.successRate.map { "\(Int($0 * 100))%" } ?? skillsText("unknown", "未知"), skillsText("success", "成功率"))
                                compactMetric(script.p95Ms.map { "\(Int($0))ms" } ?? skillsText("unknown", "未知"), skillsText("p95", "P95"))
                            }
                        }
                        .captureDashboardGeometry(id: "skills-row-\(skill)-script", role: "cell")
                    }
                }
            }
        }

        @ViewBuilder private func documentsStage(_ report: SkillsRoiReport) -> some View {
            let details = managedDetails(report).sorted { $0.skillMdLines > $1.skillMdLines }
            let totalLines = details.reduce(0) { $0 + $1.skillMdLines }
            let totalWords = details.reduce(0) { $0 + $1.bodyTokensEst }
            let totalReferences = details.reduce(0) { $0 + $1.references.count }
            let unhitReferences = details.reduce(0) { $0 + $1.unhitRefsCount }
            VStack(alignment: .leading, spacing: 8) {
                Text("\(skillsText("document_summary", "说明文档")) \(totalLines) \(skillsText("lines", "行")) / \(totalWords) \(skillsText("words", "词")) · \(skillsText("references_hit", "参考命中")) \(max(0, totalReferences - unhitReferences))/\(totalReferences) · \(skillsText("redundancy", "冗余")) \(unhitReferences)")
                    .font(.caption)
                    .foregroundStyle(theme.text(.body))
                DashboardResponsiveGrid(wideColumns: 2, compactColumns: 2) {
                    ForEach(details) { detail in
                        detailCard(title: detail.skill, subtitle: skillsText("document_size", "说明体量")) {
                            HStack {
                                compactMetric("\(detail.skillMdLines)", skillsText("lines", "行"))
                                compactMetric("\(detail.bodyTokensEst)", skillsText("words", "词"))
                                compactMetric("\(detail.references.count - detail.unhitRefsCount)/\(detail.references.count)", skillsText("reference_hit", "参考命中"))
                            }
                        }
                        .captureDashboardGeometry(id: "skills-row-\(detail.skill)-document", role: "cell")
                    }
                }
            }
        }

        @ViewBuilder private func qualityStage(_ report: SkillsRoiReport) -> some View {
            Picker(skillsText("quality_view", "质检视图"), selection: $qualityView) {
                ForEach(SkillsRoiQualityView.allCases) { view in
                    Text(view.title).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 28)
            switch qualityView {
            case .changes:
                versionQualityStage(report)
            case .pending:
                pendingQualityStage(report)
            case .coverage:
                let rows = report.qualityJudge?.skills ?? []
                if rows.isEmpty {
                    Text(skillsText("no_quality_rows", "暂无质检明细")).font(.caption).foregroundStyle(theme.text(.body))
                } else {
                    DashboardResponsiveGrid(wideColumns: 2, compactColumns: 2) {
                        ForEach(rows) { row in
                            detailCard(title: row.skill, subtitle: row.coverageStatus ?? skillsText("quality", "质量")) {
                                HStack {
                                    compactMetric("\(row.judged ?? 0)", skillsText("judged", "抽检"))
                                    compactMetric(row.scoreMean.map { String(format: "%.1f", $0) } ?? skillsText("unknown", "未知"), skillsText("score", "评分"))
                                    compactMetric(row.coveragePct.map { "\(Int($0 * 100))%" } ?? skillsText("unknown", "未知"), skillsText("coverage", "覆盖"))
                                }
                            }
                        }
                    }
                }
            }
        }

        @ViewBuilder private func versionQualityStage(_ report: SkillsRoiReport) -> some View {
            let rows = report.versionEvolution.filter { $0.beforeVersion != nil }
            DashboardResponsiveGrid(wideColumns: 2, compactColumns: 2) {
                ForEach(rows) { row in
                    detailCard(title: row.skill, subtitle: Self.formatVersionComparison(before: row.beforeVersion?.combinedVersion, current: row.combinedVersion)) {
                        Text(evolutionSignalsText(row, theme: theme).text).font(.caption).foregroundStyle(theme.text(.body))
                    }
                }
            }
        }

        @ViewBuilder private func pendingQualityStage(_ report: SkillsRoiReport) -> some View {
            let proposals = report.resolvedSkillRetro.proposals
            let fixed = Self.curedRoadblocks(in: report)
            DashboardResponsiveGrid(wideColumns: 2, compactColumns: 2) {
                detailCard(title: skillsText("pending", "待优化"), subtitle: "\(proposals.count)") {
                    Text(proposals.first?.displayReason ?? skillsText("no_pending", "暂无待优化项"))
                        .font(.caption)
                        .foregroundStyle(theme.text(.body))
                }
                detailCard(title: skillsText("fixed", "已修复"), subtitle: "\(fixed.count)") {
                    Text(fixed.first.map { "\($0.skill) · \($0.preFixCount) → \($0.postFixCount)" } ?? skillsText("no_fixed", "暂无已修复项"))
                        .font(.caption)
                        .foregroundStyle(theme.text(.body))
                }
            }
        }

        private func detailCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(theme.neutrals.inner.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        }

        private func sortedDetails(_ report: SkillsRoiReport) -> [SkillInspectorDetail] {
            managedDetails(report).filter { inspectorFilter.matches($0) }.sorted { lhs, rhs in
                switch vitalDimension {
                case .adoption: return lhs.loads7d != rhs.loads7d ? lhs.loads7d > rhs.loads7d : lhs.skill < rhs.skill
                case .efficiency:
                    let l = lhs.scripts.compactMap(\.p95Ms).max() ?? 0
                    let r = rhs.scripts.compactMap(\.p95Ms).max() ?? 0
                    return l != r ? l > r : lhs.skill < rhs.skill
                case .quality:
                    return (lhs.r1PassRate ?? 0) < (rhs.r1PassRate ?? 0)
                case .evolution: return lhs.editChurn != rhs.editChurn ? lhs.editChurn > rhs.editChurn : lhs.skill < rhs.skill
                }
            }
        }

        private static func overallPassValueForReport(_ report: SkillsRoiReport) -> Double? {
            let rates = report.skillDetails.compactMap { validPassRate($0.r1PassRate) }
            return rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count)
        }

        public static func medianValue(_ values: [Double]) -> Double? {
            let sorted = values.filter(\.isFinite).sorted()
            guard !sorted.isEmpty else { return nil }
            let middle = sorted.count / 2
            if sorted.count.isMultiple(of: 2) {
                return (sorted[middle - 1] + sorted[middle]) / 2
            }
            return sorted[middle]
        }

        public static func aggregateScriptP95(_ scripts: [SkillScriptDetail]) -> Double? {
            medianValue(scripts.compactMap(\.p95Ms))
        }

        public static func aggregateScriptMedian(_ scripts: [SkillScriptDetail]) -> Double? {
            let p50 = scripts.compactMap(\.p50Ms)
            return medianValue(p50.isEmpty ? scripts.compactMap(\.p95Ms) : p50)
        }

        public static func aggregateActiveDurationMedian(_ rows: [SkillQualityBehaviorRow]) -> Double? {
            let weighted = rows.compactMap { row -> (Double, Int)? in
                guard let value = row.activeDurationMedianSec, value.isFinite else { return nil }
                return (value, max(1, row.eligibleInvocations ?? row.observedInvocations ?? 1))
            }
            return weightedMedian(weighted)
        }

        public static func aggregateSatisfactionRate(_ rows: [SkillQualityBehaviorRow]) -> Double? {
            let weighted = rows.compactMap { row -> (Double, Int)? in
                guard let value = row.firstPassSatisfactionRate, value.isFinite, (0 ... 1).contains(value) else { return nil }
                return (value, max(1, row.satisfactionEligibleInvocations ?? row.eligibleInvocations ?? row.observedInvocations ?? 1))
            }
            guard !weighted.isEmpty else { return nil }
            let totalWeight = weighted.reduce(0) { $0 + $1.1 }
            return weighted.reduce(0.0) { $0 + $1.0 * Double($1.1) } / Double(totalWeight)
        }

        public static func emptyInvocationCount(_ rows: [SkillQualityBehaviorRow]?) -> Int? {
            guard let rows, !rows.isEmpty else { return nil }
            return rows.reduce(0) { total, row in
                if let explicit = row.emptyInvocationCount {
                    return total + max(0, explicit)
                }
                if let observed = row.observedInvocations, let eligible = row.eligibleInvocations {
                    return total + max(0, observed - eligible)
                }
                if let observed = row.observedInvocations, let rate = row.emptyInvocationRate, rate.isFinite, (0 ... 1).contains(rate) {
                    return total + Int((Double(observed) * rate).rounded())
                }
                return total
            }
        }

        public static func monthlyAdoptionComparison(details: [SkillInspectorDetail]) -> String? {
            let weekly = details.reduce(0) { $0 + $1.loads7d }
            let monthly = details.reduce(0) { $0 + $1.loads30d }
            guard monthly > 0 else { return nil }
            let delta = Double(weekly) / (Double(monthly) / 4.0) - 1.0
            guard delta.isFinite else { return nil }
            return String(format: "%@ %+.0f%%", skillsText("monthly_comparison", "vs monthly avg"), delta * 100)
        }

        public static func aggregateNoErrorRate(report: SkillsRoiReport, details: [SkillInspectorDetail]) -> Double? {
            let scriptCalls = details.flatMap(\.scripts).compactMap { script -> (Double, Int)? in
                guard let rate = validPassRate(script.successRate), let calls = script.calls30d, calls > 0 else { return nil }
                return (rate, calls)
            }
            if !scriptCalls.isEmpty {
                let weight = scriptCalls.reduce(0) { $0 + $1.1 }
                return scriptCalls.reduce(0) { $0 + $1.0 * Double($1.1) } / Double(weight)
            }
            let rows = report.versionEvolution.compactMap { row -> (Double, Int)? in
                let invocations = row.currentVersion.invocations
                guard invocations > 0, row.currentVersion.exit2Count >= 0 else { return nil }
                return (1.0 - min(1.0, Double(row.currentVersion.exit2Count) / Double(invocations)), invocations)
            }
            guard !rows.isEmpty else { return nil }
            let weight = rows.reduce(0) { $0 + $1.1 }
            return rows.reduce(0) { $0 + $1.0 * Double($1.1) } / Double(weight)
        }

        public static func aggregateJudgeMean(_ summary: SkillQualityJudgeSummary?) -> Double? {
            guard let summary else { return nil }
            let rows = summary.skills.compactMap { row -> (Double, Int)? in
                guard let score = row.scoreMean, score.isFinite, let judged = row.judged, judged > 0 else { return nil }
                return (score, judged)
            }
            guard !rows.isEmpty else { return nil }
            let weight = rows.reduce(0) { $0 + $1.1 }
            return rows.reduce(0) { $0 + $1.0 * Double($1.1) } / Double(weight)
        }

        public static func aggregateEvalSummary(report: SkillsRoiReport, details: [SkillInspectorDetail]) -> (population: Int, totalSkills: Int, totalCases: Int, coverage: Double?) {
            let totalSkills = details.count
            let population = details.filter { !$0.evalCases.isEmpty }.count
            let totalCases = details.reduce(0) { $0 + $1.evalCases.count }
            let coverage: Double? = {
                if let eligible = report.qualityJudge?.eligibleSkillCount, eligible > 0, let judged = report.qualityJudge?.judgedSkillCount {
                    return min(1, max(0, Double(judged) / Double(eligible)))
                }
                guard totalSkills > 0 else { return nil }
                return Double(population) / Double(totalSkills)
            }()
            return (population, totalSkills, totalCases, coverage)
        }

        public static func filteredScripts(_ scripts: [SkillScriptDetail], filter: SkillsRoiScriptFilter) -> [SkillScriptDetail] {
            scripts.filter(filter.matches)
        }

        private static func weightedMedian(_ values: [(Double, Int)]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted { $0.0 < $1.0 }
            let target = Double(sorted.reduce(0) { $0 + $1.1 }) / 2
            var cumulative = 0
            for value in sorted {
                cumulative += value.1
                if Double(cumulative) >= target { return value.0 }
            }
            return sorted.last?.0
        }

        private func managedDetails(_ report: SkillsRoiReport) -> [SkillInspectorDetail] {
            report.skillDetails.isEmpty ? report.diagnostics.resolvedSkillDetails : report.skillDetails
        }

        public static func activeVsTotalCounts(in report: SkillsRoiReport) -> (active: Int, total: Int)? {
            let managed = (report.skillDetails.isEmpty ? report.diagnostics.resolvedSkillDetails : report.skillDetails).filter { !$0.isGhost }
            let usage = report.diagnostics.usageRows
            let reportCurrent = currentObservationAvailable(metadata: report.metadata, reportCoverage: report.metadata.coverage)
            let managedCurrent = reportCurrent && !managed.isEmpty && managed.allSatisfy { $0.metadata.hasSamples && $0.metadata.coverage != "error" }
            let usageCurrent = reportCurrent && !usage.isEmpty && usage.allSatisfy { $0.metadata.hasSamples && $0.loads7d.metadata.hasSamples && $0.loads30d.metadata.hasSamples }
            guard managedCurrent || usageCurrent else { return nil }
            if managedCurrent {
                let active = managed.filter { $0.loads30d > 0 || $0.loads7d > 0 }.count
                return (active, managed.count)
            }
            let total = report.diagnostics.audit.flatMap { $0.metadata.hasSamples ? $0.total.value : nil } ?? usage.count
            let active = report.diagnostics.usage.flatMap { $0.metadata.hasSamples ? $0.active.value : nil }
                ?? usage.filter { ($0.loads30d.value ?? 0) > 0 || ($0.loads7d.value ?? 0) > 0 }.count
            return (min(active, total), total)
        }

        public static func curedRoadblocks(in report: SkillsRoiReport) -> [SkillRetroRoadblockItem] {
            let explicit = report.resolvedSkillRetro.watermarkedResolvedRoadblocks
            var seen = Set(explicit.map(\.skill))
            var merged = explicit
            for row in report.versionEvolution {
                guard let before = row.beforeVersion, before.exit2Count > row.currentVersion.exit2Count, !seen.contains(row.skill) else { continue }
                seen.insert(row.skill)
                merged.append(
                    SkillRetroRoadblockItem(
                        skill: row.skill,
                        script: "scripts/*.py",
                        skillVersion: cleanVersionLabel(row.combinedVersion),
                        calls: row.currentVersion.scriptCallCount,
                        totalExit2Count: before.exit2Count,
                        preFixCount: before.exit2Count,
                        postFixCount: row.currentVersion.exit2Count,
                        watermarkStatus: "converged"
                    )
                )
            }
            return merged
        }

        private func vitals(_ report: SkillsRoiReport) -> some View {
            let managed = managedDetails(report).filter { !$0.isGhost }
            let usage = report.diagnostics.usageRows
            let reportCurrent = Self.currentObservationAvailable(metadata: report.metadata, reportCoverage: report.metadata.coverage)
            let managedCurrent = reportCurrent && !managed.isEmpty && managed.allSatisfy { $0.metadata.hasSamples && $0.metadata.coverage != "error" }
            let usageCurrent = reportCurrent && !usage.isEmpty && usage.allSatisfy { $0.metadata.hasSamples && $0.loads7d.metadata.hasSamples && $0.loads30d.metadata.hasSamples }
            let current = managed.isEmpty ? usageCurrent : managedCurrent
            let counts = Self.activeVsTotalCounts(in: report)
            let calls: Int? = current ? (managed.isEmpty ? usage.reduce(0) { $0 + ($1.loads7d.value ?? 0) } : managed.reduce(0) { $0 + $1.loads7d }) : nil
            let month: Int? = current ? (managed.isEmpty ? usage.reduce(0) { $0 + ($1.loads30d.value ?? 0) } : managed.reduce(0) { $0 + $1.loads30d }) : nil
            let direction: String = calls.flatMap { callsValue in
                month.map { monthValue in
                    guard monthValue > 0 else { return "→" }
                    return Double(callsValue) > Double(monthValue) / 4 * 1.05 ? "↑" : (Double(callsValue) < Double(monthValue) / 4 * 0.95 ? "↓" : "→")
                }
            } ?? "→"
            let highPassCount = managedCurrent ? managed.filter { (Self.validPassRate($0.r1PassRate) ?? 0) >= 0.80 }.count : 0
            let cacheHit = report.diagnostics.context?.cacheHitPercent.value ?? managed.compactMap(\.kvCacheHitPct).first
            let cacheSummary = cacheHit.map { "\(Int($0.rounded()))%" } ?? "—"
            let retro = report.resolvedSkillRetro
            let curedItems = Self.curedRoadblocks(in: report)
            let sampleSize = retro.sampleSize > 0 ? retro.sampleSize : (report.metadata.sample ?? 0)

            let activeValueText = counts.map { "\($0.active) / \($0.total)" } ?? "—"
            let callsSubtitleText: String = {
                guard let calls else { return "—" }
                let callsPart = skillsText("calls_7d", "7d") + " \(calls) " + skillsText("unit_times", "次") + " \(direction)"
                if let month {
                    return callsPart + " · " + skillsText("calls_30d", "30d") + " \(month) " + skillsText("unit_times", "次")
                }
                return callsPart
            }()
            let passSubtitleText = skillsText("high_pass_count", "高通过(≥80%)") + " \(highPassCount) " + skillsText("unit_skills", "个") + " · KV " + cacheSummary
            let flywheelValueText = skillsText("cured", "已治愈") + " \(curedItems.count) · " + skillsText("optimizing", "待演进") + " \(retro.proposals.count)"
            let flywheelSubtitleText = (retro.slowFlywheelReady ? skillsText("slow_ready", "慢飞轮就绪") : skillsText("fast_converging", "快飞轮收敛中")) + " · " + skillsText("sample", "样本") + " \(sampleSize)"

            return DashboardResponsiveGrid(wideColumns: 3, compactColumns: 1) {
                p0VitalCard(
                    title: skillsText("vital_active_title", "活跃家底"),
                    value: activeValueText,
                    subtitle: callsSubtitleText,
                    tint: theme.primary.primary,
                    valueID: "skills-vital-healthy",
                    subtitleID: "skills-vital-calls-7d"
                )
                p0VitalCard(
                    title: skillsText("vital_pass_title", "一次通过率与质量"),
                    value: passRateSummary(report, managed: managedCurrent ? managed : []),
                    subtitle: passSubtitleText,
                    tint: theme.success,
                    valueID: "skills-vital-pass-rate",
                    subtitleID: nil
                )
                p0VitalCard(
                    title: skillsText("vital_flywheel_title", "自演进飞轮"),
                    value: flywheelValueText,
                    subtitle: flywheelSubtitleText,
                    tint: theme.warning,
                    valueID: "skills-vital-flywheel",
                    subtitleID: nil
                )
            }
            .captureDashboardGeometry(id: "skills-p0-vitals", role: "vitals")
        }

        private func p0VitalCard(
            title: String,
            value: String,
            subtitle: String,
            tint: Color,
            valueID: String,
            subtitleID: String?
        ) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                    Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .accessibilityIdentifier(valueID)
                if let subtitleID {
                    Text(subtitle)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .accessibilityIdentifier(subtitleID)
                } else {
                    Text(subtitle)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.22), lineWidth: 1))
        }

        private func passRateSummary(_ report: SkillsRoiReport, managed: [SkillInspectorDetail]) -> String {
            guard let current = overallPassValue(report, managed: managed) else { return "—" }
            let paired = report.versionEvolution.compactMap { row -> (Double, Double)? in
                guard let before = row.beforeVersion, before.r1Total > 0, row.currentVersion.r1Total > 0 else { return nil }
                return (Double(before.r1Pass) / Double(before.r1Total), Double(row.currentVersion.r1Pass) / Double(row.currentVersion.r1Total))
            }
            guard !paired.isEmpty else { return Self.percentText(current) }
            let beforeTotal = paired.reduce(0.0) { $0 + $1.0 }
            let currentTotal = paired.reduce(0.0) { $0 + $1.1 }
            let delta = currentTotal / Double(paired.count) - beforeTotal / Double(paired.count)
            return Self.percentText(current) + " " + Self.deltaText(delta)
        }

        private func overallPassValue(_ report: SkillsRoiReport, managed: [SkillInspectorDetail]) -> Double? {
            let activeWithRate = managed.filter { ($0.loads30d > 0 || $0.loads7d > 0) && Self.validPassRate($0.r1PassRate) != nil }
            if !activeWithRate.isEmpty {
                let weightedNum = activeWithRate.reduce(0.0) { acc, item in
                    acc + (Self.validPassRate(item.r1PassRate) ?? 0) * Double(max(1, item.loads30d))
                }
                let weightedDen = activeWithRate.reduce(0.0) { acc, item in
                    acc + Double(max(1, item.loads30d))
                }
                if weightedDen > 0 { return weightedNum / weightedDen }
            }
            let values = managed.compactMap(\.r1PassRate).compactMap(Self.validPassRate)
            if !values.isEmpty {
                return values.reduce(0, +) / Double(values.count)
            }
            let evo = report.versionEvolution.filter { $0.currentVersion.r1Total > 0 }
            if !evo.isEmpty {
                let total = evo.reduce(0) { $0 + $1.currentVersion.r1Total }
                return total == 0 ? nil : Double(evo.reduce(0) { $0 + $1.currentVersion.r1Pass }) / Double(total)
            }
            return nil
        }

        @ViewBuilder private func stage(_ report: SkillsRoiReport) -> some View {
            switch lens {
            case .usage:
                usageStageView(report)
            case .evolution:
                evolutionStageView(report)
            case .flywheel:
                flywheelStageView(report)
            }
        }

        public static func semanticUsageTier(for detail: SkillInspectorDetail, evolution: SkillVersionEvolutionRow? = nil) -> SkillUsageSemanticTier {
            if detail.loads30d == 0 && detail.loads7d == 0 {
                return .idle30d
            }
            let passRate = validPassRate(detail.r1PassRate) ?? validPassRate(evolution.flatMap { r1PassRate(for: $0.currentVersion) })
            let postFixErrors = evolution?.currentVersion.postFixErrors ?? 0
            let totalEscapes = detail.implBugEscapes + detail.specGapEscapes + detail.evalEscapes
            if detail.loads7d >= 25, (passRate ?? 0.8) >= 0.75, postFixErrors == 0 {
                return .mainstay
            }
            if let passRate, passRate < 0.70 {
                return .needsBoost
            }
            if postFixErrors > 0 || totalEscapes >= 3 {
                return .needsBoost
            }
            if detail.loads7d >= 20, (passRate ?? 0.8) >= 0.70 {
                return .mainstay
            }
            return .stable
        }

        public static func semanticEvolutionVerdict(for row: SkillVersionEvolutionRow) -> SkillEvolutionSemanticVerdict {
            let beforeExit2 = row.beforeVersion?.exit2Count ?? 0
            let currentExit2 = row.currentVersion.exit2Count
            if beforeExit2 > currentExit2 {
                return .converged
            }
            if currentExit2 > beforeExit2 && currentExit2 > 0 {
                return .attention
            }
            if row.status == "improved" {
                return .improved
            }
            if let bP50 = row.beforeVersion?.scriptP50Ms, let cP50 = row.currentVersion.scriptP50Ms, cP50 < bP50 * 0.85 {
                return .improved
            }
            if let bR1 = evolutionRateValue(row, before: true), let cR1 = evolutionRateValue(row, before: false), cR1 > bR1 + 0.02 {
                return .improved
            }
            if row.status == "regressed" && currentExit2 > 0 {
                return .attention
            }
            return .stable
        }

        private func sortedUsageDetails(_ report: SkillsRoiReport) -> [SkillInspectorDetail] {
            managedDetails(report)
                .filter { inspectorFilter.matches($0) }
                .sorted { lhs, rhs in
                    if lhs.loads7d != rhs.loads7d { return lhs.loads7d > rhs.loads7d }
                    if lhs.loads30d != rhs.loads30d { return lhs.loads30d > rhs.loads30d }
                    return lhs.skill < rhs.skill
                }
        }

        @ViewBuilder private func usageStageView(_ report: SkillsRoiReport) -> some View {
            let allFiltered = sortedUsageDetails(report)
            let visible = (showAllUsageSkills || inspectorFilter != .all || allFiltered.count <= 10)
                ? allFiltered
                : Array(allFiltered.prefix(10))
            let maxCalls7d = max(1, allFiltered.map(\.loads7d).max() ?? 1)
            let evoMap = Dictionary(uniqueKeysWithValues: report.versionEvolution.map { ($0.skill, $0) })

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(showAllUsageSkills || allFiltered.count <= 10
                        ? skillsText("all_skills_header", "全部 Skill 健康状态") + " (\(allFiltered.count))"
                        : skillsText("top_active_header", "Top 10 主力与健康状态"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if allFiltered.count > 10 && inspectorFilter == .all {
                        Button {
                            showAllUsageSkills.toggle()
                        } label: {
                            Text(showAllUsageSkills
                                ? skillsText("collapse_top10", "收起至 Top 10")
                                : skillsText("expand_all", "展开全部") + " \(allFiltered.count) " + skillsText("unit_skills", "个"))
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(theme.primary.primary.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(minWidth: 28, minHeight: 28)
                        .accessibilityIdentifier("skills-usage-expand-toggle")
                    }
                }
                ViewThatFits(in: .horizontal) {
                    wideUsageTable(visible, evoMap: evoMap, maxCalls7d: maxCalls7d)
                        .frame(minWidth: 680, alignment: .leading)
                    compactUsageList(visible, evoMap: evoMap, maxCalls7d: maxCalls7d)
                }
            }
        }

        @ViewBuilder private func wideUsageTable(
            _ details: [SkillInspectorDetail],
            evoMap: [String: SkillVersionEvolutionRow],
            maxCalls7d: Int
        ) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text(skillsText("skill", "Skill")).frame(maxWidth: .infinity, alignment: .leading).captureDashboardGeometry(id: "skills-table-header-skill", role: "header")
                    Text(skillsText("calls_7d", "7d calls")).frame(width: 124, alignment: .trailing).captureDashboardGeometry(id: "skills-table-header-calls", role: "header")
                    Text(skillsText("pass_rate", "Pass rate")).frame(width: 176, alignment: .trailing).captureDashboardGeometry(id: "skills-table-header-pass", role: "header")
                    Text(skillsText("status", "Status")).frame(width: 132, alignment: .trailing).captureDashboardGeometry(id: "skills-table-header-status", role: "header")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

                ForEach(details) { detail in
                    usageRowWide(detail, evolution: evoMap[detail.skill], maxCalls7d: maxCalls7d)
                }
            }
        }

        @ViewBuilder private func compactUsageList(
            _ details: [SkillInspectorDetail],
            evoMap: [String: SkillVersionEvolutionRow],
            maxCalls7d: Int
        ) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(details) { detail in
                    usageRowCompact(detail, evolution: evoMap[detail.skill], maxCalls7d: maxCalls7d)
                }
            }
        }

        private func usageRowWide(
            _ detail: SkillInspectorDetail,
            evolution: SkillVersionEvolutionRow?,
            maxCalls7d: Int
        ) -> some View {
            let tier = Self.semanticUsageTier(for: detail, evolution: evolution)
            let passRate = Self.validPassRate(detail.r1PassRate) ?? evolution.flatMap { Self.r1PassRate(for: $0.currentVersion) }
            let beforeRate = evolution.flatMap { $0.beforeVersion.flatMap(Self.r1PassRate) }
            let heatRatio = min(1.0, max(0.06, Double(detail.loads7d) / Double(max(1, maxCalls7d))))
            return HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text(detail.skill)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .captureDashboardGeometry(id: "skills-row-\(detail.skill)-skill", role: "cell")
                    Text(evolution.map { Self.cleanVersionLabel($0.combinedVersion) } ?? "v1")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.4), in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Text("\(detail.loads7d)")
                        .font(.caption.monospacedDigit().weight(.medium))
                    bar(detail.loads7d > 0 ? heatRatio : 0, tier.tint(using: theme), width: 44)
                }
                .frame(width: 124, alignment: .trailing)
                .captureDashboardGeometry(id: "skills-row-\(detail.skill)-calls", role: "cell")

                rateCell(passRate, before: beforeRate)
                    .captureDashboardGeometry(id: "skills-row-\(detail.skill)-pass", role: "cell")

                statusBadge(tier.label, tint: tier.tint(using: theme))
                    .captureDashboardGeometry(id: "skills-row-\(detail.skill)-status", role: "cell")
                    .frame(width: 132, alignment: .trailing)
            }
            .padding(.vertical, 7)
            .accessibilityIdentifier("skills-row-\(detail.skill)")
            .accessibilityElement(children: .combine)
        }

        private func usageRowCompact(
            _ detail: SkillInspectorDetail,
            evolution: SkillVersionEvolutionRow?,
            maxCalls7d: Int
        ) -> some View {
            let tier = Self.semanticUsageTier(for: detail, evolution: evolution)
            let passRate = Self.validPassRate(detail.r1PassRate) ?? evolution.flatMap { Self.r1PassRate(for: $0.currentVersion) }
            let beforeRate = evolution.flatMap { $0.beforeVersion.flatMap(Self.r1PassRate) }
            let heatRatio = min(1.0, max(0.06, Double(detail.loads7d) / Double(max(1, maxCalls7d))))
            return VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(detail.skill)
                        .font(.subheadline.weight(.medium))
                        .captureDashboardGeometry(id: "skills-row-\(detail.skill)-skill", role: "cell")
                    Text(Self.cleanVersionLabel(evolution?.combinedVersion ?? "v1"))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    statusBadge(tier.label, tint: tier.tint(using: theme))
                        .captureDashboardGeometry(id: "skills-row-\(detail.skill)-status", role: "cell")
                }
                HStack {
                    HStack(spacing: 6) {
                        Text("\(detail.loads7d)")
                            .font(.caption.monospacedDigit())
                        bar(detail.loads7d > 0 ? heatRatio : 0, tier.tint(using: theme), width: 44)
                    }
                    .captureDashboardGeometry(id: "skills-row-\(detail.skill)-calls", role: "cell")
                    Spacer()
                    rateCell(passRate, before: beforeRate)
                        .captureDashboardGeometry(id: "skills-row-\(detail.skill)-pass", role: "cell")
                }
            }
            .padding(.vertical, 8)
            .accessibilityIdentifier("skills-row-\(detail.skill)")
            .accessibilityElement(children: .combine)
        }

        private struct FlywheelDisplayEntry: Identifiable {
            let skill: String
            let subtitle: String
            let metricText: String
            let passRate: Double?
            let statusLabel: String
            let tint: Color
            var id: String { skill }
        }
    }

    extension SkillsRoiDiagnosticsCardView {
        @ViewBuilder private func evolutionStageView(_ report: SkillsRoiReport) -> some View {
            let filtered = Self.filterEvolutionRows(
                report.versionEvolution,
                filter: evolutionFilter,
                watermarkedSkills: Set(report.resolvedSkillRetro.watermarkedResolvedRoadblocks.map(\.skill))
            )
            let rowsToShow = filtered.isEmpty ? report.versionEvolution : filtered
            let detailMap = Dictionary(uniqueKeysWithValues: managedDetails(report).map { ($0.skill, $0) })

            VStack(alignment: .leading, spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            Text(skillsText("evo_header_transition", "版本演进")).frame(maxWidth: .infinity, alignment: .leading).captureDashboardGeometry(id: "skills-table-header-skill", role: "header")
                            Text(skillsText("evo_header_signals", "关键变化信号 (vN-1 → vN)")).frame(width: 224, alignment: .trailing).captureDashboardGeometry(id: "skills-table-header-calls", role: "header")
                            Text(skillsText("evo_r1_30d", "30d R1")).frame(width: 152, alignment: .trailing).captureDashboardGeometry(id: "skills-table-header-pass", role: "header")
                            Text(skillsText("status", "Status")).frame(width: 132, alignment: .trailing).captureDashboardGeometry(id: "skills-table-header-status", role: "header")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                        ForEach(rowsToShow) { row in
                            evolutionRowWide(row, detail: detailMap[row.skill])
                        }
                    }
                    .frame(minWidth: 680, alignment: .leading)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rowsToShow) { row in
                            evolutionRowCompact(row, detail: detailMap[row.skill])
                        }
                    }
                }
            }
        }

        private func evolutionSignalsText(_ row: SkillVersionEvolutionRow, theme: Theme) -> (text: String, tint: Color) {
            let beforeExit2 = row.beforeVersion?.exit2Count ?? 0
            let currentExit2 = row.currentVersion.exit2Count
            var parts: [String] = []
            var tint: Color = theme.text(.body)

            if beforeExit2 != currentExit2 || beforeExit2 > 0 || currentExit2 > 0 {
                let delta = currentExit2 - beforeExit2
                let deltaStr = delta != 0 ? "(\(delta > 0 ? "+" : "")\(delta))" : ""
                parts.append(skillsText("evo_script_errors", "报错") + " \(beforeExit2)→\(currentExit2)\(deltaStr)")
                tint = delta < 0 ? theme.success : (delta > 0 ? theme.warning : theme.text(.body))
            }
            if let bP50 = row.beforeVersion?.scriptP50Ms, let cP50 = row.currentVersion.scriptP50Ms {
                parts.append(String(format: "P50 %.1fs→%.1fs", bP50 / 1000.0, cP50 / 1000.0))
                if cP50 < bP50 { tint = theme.success }
            } else if let bSessions = row.beforeVersion?.sessions {
                parts.append(skillsText("evo_sessions", "会话") + " \(bSessions)→\(row.currentVersion.sessions)")
            }
            if parts.isEmpty {
                let bInv = row.beforeVersion?.invocations ?? 0
                parts.append(skillsText("evo_sessions", "会话") + " \(bInv)→\(row.currentVersion.invocations)")
            }
            return (parts.joined(separator: " · "), tint)
        }

        private func resolvedEvolutionPassRate(_ row: SkillVersionEvolutionRow, detail: SkillInspectorDetail?) -> (current: Double?, before: Double?) {
            let cur = Self.r1PassRate(for: row.currentVersion) ?? Self.validPassRate(detail?.r1PassRate) ?? row.beforeVersion.flatMap(Self.r1PassRate)
            let bef = row.beforeVersion.flatMap(Self.r1PassRate)
            return (cur, bef)
        }

        private func evolutionRowWide(_ row: SkillVersionEvolutionRow, detail: SkillInspectorDetail?) -> some View {
            let verdict = Self.semanticEvolutionVerdict(for: row)
            let signals = evolutionSignalsText(row, theme: theme)
            let rates = resolvedEvolutionPassRate(row, detail: detail)
            return HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text(row.skill)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .captureDashboardGeometry(id: "skills-row-\(row.skill)-skill", role: "cell")
                    Text(Self.cleanVersionLabel(row.versionTransitionLabel))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.45), in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(signals.text)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(signals.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: 224, alignment: .trailing)
                    .captureDashboardGeometry(id: "skills-row-\(row.skill)-calls", role: "cell")

                rateCell(rates.current, before: rates.before, width: 152)
                    .captureDashboardGeometry(id: "skills-row-\(row.skill)-pass", role: "cell")

                statusBadge(verdict.label, tint: verdict.tint(using: theme))
                    .captureDashboardGeometry(id: "skills-row-\(row.skill)-status", role: "cell")
                    .frame(width: 132, alignment: .trailing)
            }
            .padding(.vertical, 7)
            .accessibilityIdentifier("skills-row-\(row.skill)")
            .accessibilityElement(children: .combine)
        }

        private func evolutionRowCompact(_ row: SkillVersionEvolutionRow, detail: SkillInspectorDetail?) -> some View {
            let verdict = Self.semanticEvolutionVerdict(for: row)
            let signals = evolutionSignalsText(row, theme: theme)
            let rates = resolvedEvolutionPassRate(row, detail: detail)
            return VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(row.skill)
                        .font(.subheadline.weight(.medium))
                        .captureDashboardGeometry(id: "skills-row-\(row.skill)-skill", role: "cell")
                    Text(Self.cleanVersionLabel(row.versionTransitionLabel))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    statusBadge(verdict.label, tint: verdict.tint(using: theme))
                        .captureDashboardGeometry(id: "skills-row-\(row.skill)-status", role: "cell")
                }
                HStack {
                    Text(signals.text)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(signals.tint)
                        .lineLimit(1)
                        .captureDashboardGeometry(id: "skills-row-\(row.skill)-calls", role: "cell")
                    Spacer()
                    rateCell(rates.current, before: rates.before, width: 152)
                        .captureDashboardGeometry(id: "skills-row-\(row.skill)-pass", role: "cell")
                }
            }
            .padding(.vertical, 8)
            .accessibilityIdentifier("skills-row-\(row.skill)")
            .accessibilityElement(children: .combine)
        }

        private func buildFlywheelEntries(_ report: SkillsRoiReport) -> [FlywheelDisplayEntry] {
            let detailMap = Dictionary(uniqueKeysWithValues: managedDetails(report).map { ($0.skill, $0) })
            let evoMap = Dictionary(uniqueKeysWithValues: report.versionEvolution.map { ($0.skill, $0) })
            let curedList = Self.curedRoadblocks(in: report)
            let proposals = report.resolvedSkillRetro.proposals

            var entries: [FlywheelDisplayEntry] = []
            var seen: Set<String> = []

            for item in curedList where !seen.contains(item.skill) {
                seen.insert(item.skill)
                let detail = detailMap[item.skill]
                let evo = evoMap[item.skill]
                let pass = Self.validPassRate(detail?.r1PassRate) ?? evo.flatMap { Self.r1PassRate(for: $0.currentVersion) }
                let versionStr = !item.skillVersion.isEmpty ? Self.cleanVersionLabel(item.skillVersion) : (evo.map { Self.cleanVersionLabel($0.combinedVersion) } ?? "v1")
                entries.append(
                    FlywheelDisplayEntry(
                        skill: item.skill,
                        subtitle: versionStr + " · " + skillsText("cured_section_title", "已自动治愈路障成果"),
                        metricText: skillsText("evo_script_errors", "脚本报错") + " \(item.preFixCount) → \(item.postFixCount) " + skillsText("unit_times", "次"),
                        passRate: pass,
                        statusLabel: "✅ " + skillsText("flywheel_status_cured", "已清零治愈"),
                        tint: theme.success
                    )
                )
            }

            for prop in proposals where !seen.contains(prop.skill) {
                seen.insert(prop.skill)
                let detail = detailMap[prop.skill]
                let evo = evoMap[prop.skill]
                let pass = Self.validPassRate(detail?.r1PassRate) ?? evo.flatMap { Self.r1PassRate(for: $0.currentVersion) }
                entries.append(
                    FlywheelDisplayEntry(
                        skill: prop.skill,
                        subtitle: prop.displayTitle,
                        metricText: skillsText("calls_7d", "7d") + " \(detail?.loads7d ?? 0) " + skillsText("unit_times", "次"),
                        passRate: pass,
                        statusLabel: "⏳ " + skillsText("flywheel_status_queued", "慢飞轮排队中"),
                        tint: theme.warning
                    )
                )
            }

            if entries.isEmpty {
                for detail in managedDetails(report).filter({ !$0.isGhost }).prefix(6) {
                    let evo = evoMap[detail.skill]
                    entries.append(
                        FlywheelDisplayEntry(
                            skill: detail.skill,
                            subtitle: evo.map { Self.cleanVersionLabel($0.combinedVersion) } ?? "v1",
                            metricText: skillsText("calls_7d", "7d") + " \(detail.loads7d) " + skillsText("unit_times", "次"),
                            passRate: Self.validPassRate(detail.r1PassRate),
                            statusLabel: "🔄 " + skillsText("flywheel_status_converging", "自动收敛中"),
                            tint: theme.primary.primary
                        )
                    )
                }
            }
            return entries
        }

        @ViewBuilder private func flywheelStageView(_ report: SkillsRoiReport) -> some View {
            let retro = report.resolvedSkillRetro
            let curedList = Self.curedRoadblocks(in: report)
            let entries = buildFlywheelEntries(report)
            let gateHealthy = retro.crossRepoGateHealth?.healthyReposCount ?? 0
            let gateScanned = retro.crossRepoGateHealth?.reposScanned ?? 0

            VStack(alignment: .leading, spacing: 14) {
                DashboardResponsiveGrid(wideColumns: 4, compactColumns: 2) {
                    flywheelPillarCard(
                        title: skillsText("pillar_trigger_title", "触发命中"),
                        value: "\(retro.triggerMissSkills) 漏 · \(retro.zeroActionLoadSkills) 空载",
                        subtitle: skillsText("pillar_trigger_sub", "漏触发与空载收敛"),
                        tint: retro.triggerMissSkills == 0 ? theme.success : theme.warning
                    )
                    flywheelPillarCard(
                        title: skillsText("pillar_drawer_title", "知识库精简"),
                        value: "\(retro.hotDrawers.count) 热 · \(retro.trueDeadwoodDrawersCount) 冗余",
                        subtitle: skillsText("pillar_drawer_sub", "热抽屉与零命中清理"),
                        tint: retro.trueDeadwoodDrawersCount <= 4 ? theme.success : theme.warning
                    )
                    flywheelPillarCard(
                        title: skillsText("pillar_script_title", "脚本稳定度"),
                        value: "\(curedList.count) 已治愈 · \(retro.rigidRoadblockScriptsCount) 待清",
                        subtitle: skillsText("pillar_script_sub", "有效拦截与路障清零"),
                        tint: !curedList.isEmpty ? theme.success : theme.warning
                    )
                    flywheelPillarCard(
                        title: skillsText("pillar_gate_title", "跨仓门禁与收编"),
                        value: gateScanned > 0 ? "\(gateHealthy)/\(gateScanned) 仓健康" : "\(retro.wildPatternsCount) 待收编",
                        subtitle: skillsText("pillar_gate_sub", "野生模式收编与仓库健康"),
                        tint: retro.wildPatternsCount == 0 ? theme.success : theme.warning
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(skillsText("cured_section_title", "已自动治愈路障成果") + " · " + skillsText("queued_section_title", "排队进化中状态项"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    ForEach(entries) { entry in
                        flywheelEntryRow(entry)
                    }
                }
            }
        }

        private func flywheelPillarCard(title: String, value: String, subtitle: String, tint: Color) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 6, height: 6)
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.2), lineWidth: 1))
        }

        private func flywheelEntryRow(_ entry: FlywheelDisplayEntry) -> some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.skill)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .captureDashboardGeometry(id: "skills-row-\(entry.skill)-skill", role: "cell")
                        Text(entry.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(entry.metricText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(entry.tint)
                        .frame(width: 148, alignment: .trailing)
                        .captureDashboardGeometry(id: "skills-row-\(entry.skill)-calls", role: "cell")

                    rateCell(entry.passRate, before: nil, width: 136)
                        .captureDashboardGeometry(id: "skills-row-\(entry.skill)-pass", role: "cell")

                    statusBadge(entry.statusLabel, tint: entry.tint)
                        .captureDashboardGeometry(id: "skills-row-\(entry.skill)-status", role: "cell")
                        .frame(width: 140, alignment: .trailing)
                }
                .frame(minWidth: 680, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.skill)
                            .font(.subheadline.weight(.medium))
                            .captureDashboardGeometry(id: "skills-row-\(entry.skill)-skill", role: "cell")
                        Spacer()
                        statusBadge(entry.statusLabel, tint: entry.tint)
                            .captureDashboardGeometry(id: "skills-row-\(entry.skill)-status", role: "cell")
                    }
                    HStack {
                        Text(entry.metricText)
                            .font(.caption.monospacedDigit())
                            .captureDashboardGeometry(id: "skills-row-\(entry.skill)-calls", role: "cell")
                        Spacer()
                        rateCell(entry.passRate, before: nil, width: 136)
                            .captureDashboardGeometry(id: "skills-row-\(entry.skill)-pass", role: "cell")
                    }
                }
            }
            .padding(.vertical, 7)
            .accessibilityIdentifier("skills-row-\(entry.skill)")
            .accessibilityElement(children: .combine)
        }

        private func statusBadge(_ label: String, tint: Color) -> some View {
            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.14), in: Capsule())
        }

        private func rateCell(_ current: Double?, before: Double?, width: CGFloat = 176) -> some View {
            let safeCurrent = Self.validPassRate(current)
            let safeBefore = Self.validPassRate(before)
            let barTint: Color = {
                guard let safeCurrent else { return theme.text(.meta) }
                return safeCurrent >= 0.80 ? theme.success : (safeCurrent >= 0.60 ? theme.warning : theme.danger)
            }()
            return HStack(spacing: 6) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Self.percentText(safeCurrent)).font(.caption.monospacedDigit().weight(.medium))
                    if let safeCurrent, let safeBefore, abs(safeCurrent - safeBefore) >= 0.01 {
                        Text(Self.deltaText(safeCurrent - safeBefore)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }.frame(width: max(64, width - 60), alignment: .trailing)
                VStack(spacing: 2) {
                    bar(safeBefore ?? safeCurrent, theme.text(.meta))
                    bar(safeCurrent, barTint)
                }.frame(width: 48)
            }.frame(width: width, alignment: .trailing)
        }

        private static func validPassRate(_ value: Double?) -> Double? {
            guard let value, value.isFinite, (0 ... 1).contains(value) else { return nil }
            return value
        }

        private static func percentText(_ value: Double?) -> String {
            guard let value = validPassRate(value) else { return "—" }
            return "\(Int(value * 100))%"
        }

        private static func deltaText(_ value: Double) -> String {
            guard value.isFinite, abs(value) <= 1 else { return "—" }
            let points = Int(value * 100)
            return "\(points >= 0 ? "+" : "")\(points)pp"
        }

        private func bar(_ value: Double?, _ color: Color, width: CGFloat = 48) -> some View {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.65))
                    .frame(width: max(0, min(proxy.size.width, proxy.size.width * (value ?? 0))), height: 4)
            }
            .frame(width: width, height: 4)
        }

        public static func cleanVersionLabel(_ raw: String) -> String { raw.split(separator: "→", omittingEmptySubsequences: false).map { part in let text = part.trimmingCharacters(in: .whitespaces); let v = text.split(separator: "@").first.map(String.init) ?? text; if let range = v.range(of: "+v") { return String(v[v.index(after: range.lowerBound)...]).split(separator: "@").first.map(String.init) ?? v }; return v }.joined(separator: " → ") }
        public static func activeSkillRow(in diagnostics: SkillsRoiDiagnostics, selectedSkill: String?) -> SkillsUsageRow? { diagnostics.usageRows.first { $0.skill == selectedSkill } ?? diagnostics.usageRows.first }
        public static func activeSkillDetail(in report: SkillsRoiReport, selectedSkill: String?, filter: SkillInspectorFilter = .all) -> SkillInspectorDetail? {
            let pool = (report.skillDetails.isEmpty ? report.diagnostics.resolvedSkillDetails : report.skillDetails).filter { filter.matches($0) }
            if let selectedSkill {
                return pool.first { $0.skill == selectedSkill }
            }
            return pool.first
        }
        public static func currentObservationAvailable(metadata: SkillsObservationMetadata, reportCoverage: String?) -> Bool {
            metadata.hasSamples && metadata.coverage != "error" && reportCoverage != "error"
        }

        public static func r1PassRate(for snapshot: SkillVersionMetricsSnapshot) -> Double? {
            validPassRate(snapshot.r1Total > 0 ? Double(snapshot.r1Pass) / Double(snapshot.r1Total) : snapshot.r1PassRate)
        }

        private static func evolutionRateValue(_ row: SkillVersionEvolutionRow, before: Bool) -> Double? {
            guard let snapshot = before ? row.beforeVersion : Optional(row.currentVersion) else {
                return nil
            }
            return r1PassRate(for: snapshot)
        }

        public static func filterEvolutionRows(_ rows: [SkillVersionEvolutionRow], filter: SkillVersionEvolutionFilter, watermarkedSkills: Set<String> = []) -> [SkillVersionEvolutionRow] {
            rows.filter { row in
                let exit2Changed = (row.beforeVersion?.exit2Count ?? 0) != row.currentVersion.exit2Count
                let p50Changed = row.beforeVersion?.scriptP50Ms != nil && row.currentVersion.scriptP50Ms != nil && row.beforeVersion?.scriptP50Ms != row.currentVersion.scriptP50Ms
                switch filter {
                case .all:
                    return true
                case .meaningful:
                    guard row.beforeVersion != nil else { return false }
                    if exit2Changed || watermarkedSkills.contains(row.skill) { return true }
                    return row.status != "observing" && (Self.evolutionRateValue(row, before: true) != Self.evolutionRateValue(row, before: false) || row.beforeVersion?.invocations != row.currentVersion.invocations || p50Changed)
                case .improved:
                    return semanticEvolutionVerdict(for: row) == .converged || semanticEvolutionVerdict(for: row) == .improved
                case .regressed:
                    return semanticEvolutionVerdict(for: row) == .attention
                }
            }
        }

        public static func formatVersionComparison(before: String?, current: String, status _: String = "") -> String { cleanVersionLabel((before.map { "\($0) → " } ?? "") + current) }
    }

    private struct SkillHealthSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.theme) private var theme
        let detail: SkillInspectorDetail
        let report: SkillsRoiReport?

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        healthSection(skillsText("health_summary", "四维体检概览")) {
                            let behavior = report?.qualityBehavior?.first(where: { $0.skill == detail.skill })
                            HStack {
                                healthMetric("\(detail.loads30d)", skillsText("calls_30d", "30天调用"))
                                healthMetric(SkillsRoiDiagnosticsCardView.aggregateScriptMedian(detail.scripts).map { "\(Int($0))ms" } ?? skillsText("unknown", "未知"), skillsText("script_median", "脚本中位"))
                                healthMetric(behavior?.firstPassSatisfactionRate.map { "\(Int($0 * 100))%" } ?? detail.r1PassRate.map { "\(Int($0 * 100))%" } ?? skillsText("unknown", "未知"), skillsText("first_pass", "一次满意"))
                                healthMetric(behavior?.normalizedEditChurn.map { String(format: "%.2f", $0) } ?? (detail.editChurn > 0 ? String(format: "%.2f", Double(detail.editChurn)) : skillsText("unknown", "未知")), skillsText("normalized_churn", "归一化擦写"))
                            }
                            if let behavior {
                                Text("\(skillsText("observed", "观测调用")) \(behavior.observedInvocations ?? 0) · \(skillsText("corrections", "纠正")) \(behavior.correctionCount ?? 0) · \(skillsText("active_duration", "活跃耗时")) \(behavior.activeDurationMedianSec.map { String(format: "%.1fm", $0 / 60) } ?? skillsText("unknown", "未知"))")
                                    .font(.caption)
                                    .foregroundStyle(theme.text(.body))
                            }
                            if let evolution = report?.versionEvolution.first(where: { $0.skill == detail.skill }) {
                                Text(skillsText("version_comparison", "版本对比") + " " + SkillsRoiDiagnosticsCardView.formatVersionComparison(before: evolution.beforeVersion?.combinedVersion, current: evolution.combinedVersion))
                                    .font(.caption)
                                    .foregroundStyle(theme.text(.body))
                            }
                        }
                        healthSection(skillsText("health_scripts", "名下脚本")) {
                            ForEach(detail.scripts) { script in
                                HStack {
                                    Text(script.relPath.split(separator: "/").last.map(String.init) ?? script.relPath)
                                    Spacer()
                                    Text("\(script.calls30d ?? 0) · " + (script.successRate.map { "\(Int($0 * 100))%" } ?? skillsText("unknown", "未知")) + " · " + (script.p95Ms.map { "\(Int($0))ms" } ?? skillsText("unknown", "未知")))
                                        .foregroundStyle(theme.text(.body))
                                }
                            }
                        }
                        healthSection(skillsText("health_documents", "说明与参考文档")) {
                            Text("\(detail.skillMdLines) " + skillsText("lines", "行") + " · \(detail.bodyTokensEst) " + skillsText("words", "词"))
                            Text("\(detail.references.count - detail.unhitRefsCount)/\(detail.references.count) " + skillsText("reference_hit", "参考命中") + " · \(detail.unhitRefsCount) " + skillsText("redundancy", "冗余"))
                                .foregroundStyle(theme.text(.body))
                            ForEach(detail.references) { reference in
                                Text((reference.isUnhit ? skillsText("reference_unhit", "未命中") : skillsText("reference_hit_status", "已命中")) + " · " + (reference.relPath.split(separator: "/").last.map(String.init) ?? reference.relPath))
                                    .font(.caption2)
                                    .foregroundStyle(theme.text(.body))
                            }
                        }
                        healthSection(skillsText("health_quality", "Eval 与优化建议")) {
                            Text("\(detail.evalCases.count) " + skillsText("eval_cases", "条用例") + " · \(detail.evalInterceptions) " + skillsText("interceptions", "拦截") + " · \(detail.evalEscapes) " + skillsText("escapes", "漏检"))
                                .foregroundStyle(theme.text(.body))
                            ForEach(detail.evalCases) { evalCase in
                                Text("\(evalCase.title) · \(evalCase.status) · \(evalCase.interceptions30d)/\(evalCase.escapes30d)")
                                    .font(.caption)
                                    .foregroundStyle(theme.text(.body))
                            }
                            Text(optimizationGuidance(detail: detail))
                                .foregroundStyle(theme.text(.body))
                            if let judge = report?.qualityJudge?.skills.first(where: { $0.skill == detail.skill }),
                               let score = judge.scoreMean {
                                Text(skillsText("score", "评分") + " \(String(format: "%.1f", score))")
                                    .foregroundStyle(theme.text(.body))
                            }
                        }
                    }
                    .padding(20)
                }
                .navigationTitle(detail.skill)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(skillsText("done", "完成")) { dismiss() }
                    }
                }
            }
            .frame(minWidth: 520, minHeight: 520)
        }

        private func healthSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.neutrals.inner.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        }

        private func healthMetric(_ value: String, _ label: String) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.subheadline.monospacedDigit().weight(.medium))
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func optimizationGuidance(detail: SkillInspectorDetail) -> String {
            if detail.evalEscapes > 0 || detail.implBugEscapes + detail.specGapEscapes > 0 {
                return skillsText("guidance_quality", "先补齐失败用例，再复核最近的质量信号。")
            }
            if detail.scripts.contains(where: { ($0.successRate ?? 1) < 0.9 }) {
                return skillsText("guidance_script", "优先检查失败率较高的脚本，并补一条回归用例。")
            }
            if detail.unhitRefsCount > 0 {
                return skillsText("guidance_references", "优先清理长期未命中的参考文档，保留常用内容。")
            }
            return skillsText("guidance_healthy", "当前没有明显风险，保持现有检查节奏。")
        }
    }

    public struct SkillsObservationMetadata: Decodable, Sendable, Equatable {
        public let window: String?, start: String?, end: String?, asOf: String?, sample: Int?, coverage: String?, estimated: Bool?, method: String?
        private let present: Set<String>

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: SkillsKey.self); present = Set(c.allKeys.map(\.stringValue))
            window = try c.decodeIfPresent(String.self, forKey: .init("window_cst")); start = try c.decodeIfPresent(String.self, forKey: .init("window_start"))
            end = try c.decodeIfPresent(String.self, forKey: .init("window_end")); asOf = try c.decodeIfPresent(String.self, forKey: .init("source_as_of"))
            sample = try c.decodeIfPresent(Int.self, forKey: .init("sample_size")); coverage = try c.decodeIfPresent(String.self, forKey: .init("coverage_status"))
            estimated = try c.decodeIfPresent(Bool.self, forKey: .init("estimated")); method = try c.decodeIfPresent(String.self, forKey: .init("estimation_method"))
        }

        private init(window: String?, start: String?, end: String?, asOf: String?, sample: Int?, coverage: String?, estimated: Bool?, method: String?, present: Set<String>) {
            self.window = window; self.start = start; self.end = end; self.asOf = asOf
            self.sample = sample; self.coverage = coverage; self.estimated = estimated; self.method = method; self.present = present
        }

        func inheriting(_ parent: Self) -> Self {
            .init(window: present.contains("window_cst") ? window : parent.window, start: present.contains("window_start") ? start : parent.start,
                  end: present.contains("window_end") ? end : parent.end, asOf: present.contains("source_as_of") ? asOf : parent.asOf,
                  sample: present.contains("sample_size") ? sample : parent.sample, coverage: present.contains("coverage_status") ? coverage : parent.coverage,
                  estimated: present.contains("estimated") ? estimated : parent.estimated, method: present.contains("estimation_method") ? method : parent.method,
                  present: present.union(parent.present))
        }

        var hasSamples: Bool { (sample ?? 0) > 0 && !["missing", "unknown", "error"].contains(coverage ?? "unknown") }
    }

    public struct SkillsMetric<Value: Decodable & Sendable & Equatable>: Sendable, Equatable { public let value: Value?, metadata: SkillsObservationMetadata }

    public struct SkillQualityBehaviorRow: Decodable, Sendable, Equatable, Identifiable {
        public let skill: String
        public let registered: Bool?, observedInvocations: Int?, eligibleInvocations: Int?, eligible: Bool?
        public let emptyInvocationCount: Int?, emptyInvocationRate: Double?
        public let correctionCount: Int?, maxTokensInvocations: Int?, satisfactionEligibleInvocations: Int?
        public let firstPassSatisfactionRate: Double?, implicitCorrectionRate: Double?, editToolCalls: Int?
        public let assistantTurnCount: Int?, normalizedEditChurn: Double?, activeDurationMedianSec: Double?
        public let activeDurationP90Sec: Double?, sourceAsOf: String?, windowCst: String?, coverageStatus: String?, estimated: Bool?
        public var id: String { skill }

        enum CodingKeys: String, CodingKey {
            case skill, registered, eligible, estimated
            case observedInvocations = "observed_invocations"
            case eligibleInvocations = "eligible_invocations"
            case emptyInvocationCount = "empty_invocation_count"
            case emptyInvocationRate = "empty_invocation_rate"
            case correctionCount = "correction_count"
            case maxTokensInvocations = "max_tokens_invocations"
            case satisfactionEligibleInvocations = "satisfaction_eligible_invocations"
            case firstPassSatisfactionRate = "first_pass_satisfaction_rate"
            case implicitCorrectionRate = "implicit_correction_rate"
            case editToolCalls = "edit_tool_calls"
            case assistantTurnCount = "assistant_turn_count"
            case normalizedEditChurn = "normalized_edit_churn"
            case activeDurationMedianSec = "active_duration_median_sec"
            case activeDurationP90Sec = "active_duration_p90_sec"
            case sourceAsOf = "source_as_of"
            case windowCst = "window_cst"
            case coverageStatus = "coverage_status"
        }
    }

    public struct SkillQualityJudgeRow: Decodable, Sendable, Equatable, Identifiable {
        public let skill: String
        public let eligible: Bool?, eligibleInvocations: Int?, sampled: Int?, judged: Int?, validJudgements: Int?
        public let coverageStatus: String?, coveragePct: Double?, scoreMean: Double?
        public let sourceAsOf: String?, rubricVersion: String?, judgeModel: String?
        public var id: String { skill }

        enum CodingKeys: String, CodingKey {
            case skill, eligible, sampled, judged
            case eligibleInvocations = "eligible_invocations"
            case validJudgements = "valid_judgements"
            case coverageStatus = "coverage_status"
            case coveragePct = "coverage_pct"
            case scoreMean = "score_mean"
            case sourceAsOf = "source_as_of"
            case rubricVersion = "rubric_version"
            case judgeModel = "judge_model"
        }
    }

    public struct SkillQualityJudgeSummary: Decodable, Sendable, Equatable {
        public let eligibleSkillCount: Int?, judgedSkillCount: Int?, coverageLabel: String?, coveragePct: Double?
        public let sourceAsOf: String?, windowCst: String?, rubricVersion: String?, estimated: Bool?
        public let skills: [SkillQualityJudgeRow]

        enum CodingKeys: String, CodingKey {
            case eligibleSkillCount = "eligible_skill_count"
            case judgedSkillCount = "judged_skill_count"
            case coverageLabel = "coverage_label"
            case coveragePct = "coverage_pct"
            case sourceAsOf = "source_as_of"
            case windowCst = "window_cst"
            case rubricVersion = "rubric_version"
            case estimated, skills
        }
    }

    private struct SkillsKey: CodingKey {
        let stringValue: String; var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue _: Int) { return nil }
    }

    private protocol SkillsObjectPopulation: Decodable {}

    private struct SkillsObserved<Value: Decodable>: Decodable {
        let value: Value?, metadata: SkillsObservationMetadata?
        init(from decoder: Decoder) throws {
            if let c = try? decoder.container(keyedBy: SkillsKey.self), c.contains(.init("value")) {
                value = Value.self is any SkillsObjectPopulation.Type ? try Value(from: decoder) : try c.decodeIfPresent(Value.self, forKey: .init("value"))
                metadata = try SkillsObservationMetadata(from: decoder)
            } else {
                value = try decoder.singleValueContainer().decode(Value?.self); metadata = nil
            }
        }
    }

    private struct SkillsFields {
        let container: KeyedDecodingContainer<SkillsKey>, metadata: SkillsObservationMetadata
        init(_ decoder: Decoder) throws {
            let outer = try decoder.container(keyedBy: SkillsKey.self), parent = try SkillsObservationMetadata(from: decoder)
            if outer.contains(.init("value")), let nested = try? outer.superDecoder(forKey: .init("value")), let inner = try? nested.container(keyedBy: SkillsKey.self) {
                container = inner; metadata = try SkillsObservationMetadata(from: nested).inheriting(parent)
            } else {
                container = outer; metadata = parent
            }
        }

        func metric<T: Decodable & Sendable & Equatable>(_ key: String) throws -> SkillsMetric<T> {
            let observed = try container.decodeIfPresent(SkillsObserved<T>.self, forKey: .init(key))
            return SkillsMetric(value: observed?.value, metadata: observed?.metadata?.inheriting(metadata) ?? metadata)
        }

        func value<T: Decodable>(_ key: String, as _: T.Type = T.self) throws -> T? { try container.decodeIfPresent(SkillsObserved<T>.self, forKey: .init(key))?.value }
    }

    public struct SkillsPinHealth: Decodable, Sendable, Equatable {
        public let metadata: SkillsObservationMetadata, behind: SkillsMetric<Int>, synchronized: SkillsMetric<Bool>, consumers: [SkillsPinConsumer]
        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata
            behind = try f.metric("outdated_pin_count"); synchronized = try f.metric("all_up_to_date"); consumers = try f.value("consumers") ?? []
        }
    }

    public struct SkillsPinConsumer: Decodable, Sendable, Equatable { public let repo: String?, outdated: Bool? }

    public struct SkillsGateHealth: Decodable, Sendable, Equatable {
        public let metadata: SkillsObservationMetadata, runs: SkillsMetric<Int>, catches: SkillsMetric<Int>, noise: SkillsMetric<Int>, catchRate: SkillsMetric<Double>, noiseRate: SkillsMetric<Double>
        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata
            runs = try f.metric("total_runs_7d"); catches = try f.metric("true_positive_catches_7d"); noise = try f.metric("config_or_rerun_noise_7d")
            catchRate = try f.metric("gate_catch_rate"); noiseRate = try f.metric("noise_rate")
        }
    }

    public struct SkillsAuditHealth: Decodable, Sendable, Equatable {
        public let metadata: SkillsObservationMetadata, total: SkillsMetric<Int>, passed: SkillsMetric<Int>, evals: SkillsMetric<Int>, evalDelta: SkillsMetric<Int>
        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata
            total = try f.metric("total_skills"); passed = try f.metric("audit_pass_count"); evals = try f.metric("eval_case_total"); evalDelta = try f.metric("eval_case_weekly_delta")
        }
    }

    public struct SkillsUsageRow: Decodable, Sendable, Equatable {
        public let skill: String, metadata: SkillsObservationMetadata, loads7d: SkillsMetric<Int>, loads30d: SkillsMetric<Int>, roi: SkillsMetric<Double>
        public let r1Total: SkillsMetric<Int>, r1Pass: SkillsMetric<Double>, touch: SkillsMetric<Double>, unpracticed: SkillsMetric<Double>, scriptExecs: SkillsMetric<Int>, diagnosis: String?
        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata; skill = try f.container.decode(String.self, forKey: .init("skill"))
            loads7d = try f.metric("loads_7d"); loads30d = try f.metric("loads_30d"); roi = try f.metric("roi_score")
            let reviews = try f.value("r1_freshness", as: SkillsObservationMetadata.self)
            let total: SkillsMetric<Int> = try f.metric("r1_total"), pass: SkillsMetric<Double> = try f.metric("r1_pass_rate")
            r1Total = SkillsMetric(value: total.value, metadata: reviews ?? total.metadata); r1Pass = SkillsMetric(value: pass.value, metadata: reviews ?? pass.metadata)
            touch = try f.metric("script_touch_rate"); unpracticed = try f.metric("unpracticed_rate"); scriptExecs = try f.metric("script_execs"); diagnosis = try f.value("diagnosis")
        }
    }

    public struct SkillsUsagePopulation: Decodable, Sendable, Equatable {
        public let metadata: SkillsObservationMetadata, active: SkillsMetric<Int>, idle: [String], top: [SkillsUsageRow]
        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata
            active = try f.metric("active_skills_count"); idle = try f.value("idle_skills_30d") ?? []; top = try f.value("top_used_skills") ?? []
        }
    }

    public struct SkillsDisclosureRow: Decodable, Sendable, Equatable {
        public let skill: String, metadata: SkillsObservationMetadata, l0: SkillsMetric<Double>, l1: SkillsMetric<Double>, greedy: SkillsMetric<Double>, contextTokens: SkillsMetric<Double>
        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata; skill = try f.container.decode(String.self, forKey: .init("skill"))
            l0 = try f.metric("l0_only_rate"); l1 = try f.metric("l1_selective_rate"); greedy = try f.metric("l1_greedy_violation_rate"); contextTokens = try f.metric("avg_context_tokens")
        }
    }

    public struct SkillsChurnRow: Decodable, Sendable, Equatable {
        public let skill: String, metadata: SkillsObservationMetadata, edits: SkillsMetric<Int>, retries: SkillsMetric<Int>
        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata; skill = try f.container.decode(String.self, forKey: .init("skill"))
            edits = try f.metric("edit_churn_count"); retries = try f.metric("retry_commands")
        }
    }

    public struct SkillsEscapeRow: Decodable, Sendable, Equatable {
        public let skill: String, metadata: SkillsObservationMetadata, implementation: SkillsMetric<Int>, specification: SkillsMetric<Int>
        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata; skill = try f.container.decode(String.self, forKey: .init("skill"))
            implementation = try f.metric("impl_bug_escapes"); specification = try f.metric("spec_gap_escapes")
        }
    }

    public struct SkillsContextSlice: Decodable, Sendable, Equatable {
        public let key: String, metadata: SkillsObservationMetadata, tokens: SkillsMetric<Double>, share: SkillsMetric<Double>
        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata; key = try f.container.decode(String.self, forKey: .init("slice_key"))
            tokens = try f.metric("tokens"); share = try f.metric("share_pct")
        }
    }

    public struct SkillsContextHealth: Decodable, Sendable, Equatable {
        public let metadata: SkillsObservationMetadata, slices: [SkillsContextSlice], total: SkillsMetric<Double>, cacheHitPercent: SkillsMetric<Double>, savedTokens: SkillsMetric<Double>
        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata; slices = try f.value("slices") ?? []; total = try f.metric("total_context_tokens")
            let hit: SkillsMetric<Double> = try f.metric("kv_cache_hit_pct"), cacheMetadata = try f.value("kv_cache_freshness", as: SkillsObservationMetadata.self)
            cacheHitPercent = SkillsMetric(value: hit.value, metadata: cacheMetadata ?? hit.metadata); savedTokens = try f.metric("compressed_saved_tokens")
        }
    }

    public struct SkillsToolBurnRow: Decodable, Sendable, Equatable {
        public let tool: String, metadata: SkillsObservationMetadata, calls: SkillsMetric<Int>, total: SkillsMetric<Double>, p95: SkillsMetric<Double>, bloated: SkillsMetric<Int>, share: SkillsMetric<Double>, dominantSkill: String?
        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata; tool = try f.container.decode(String.self, forKey: .init("tool_name"))
            calls = try f.metric("call_count"); total = try f.metric("total_tokens"); p95 = try f.metric("p95_tokens")
            bloated = try f.metric("bloated_call_count"); share = try f.metric("share_pct"); dominantSkill = try f.value("dominant_skill")
        }
    }

    public struct SkillsDailyObservation: Decodable, Sendable, Equatable {
        public let day: String, source: String, skill: String, count: Int?, sessions: Int?, metadata: SkillsObservationMetadata
        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata; day = try f.container.decode(String.self, forKey: .init("day"))
            source = try f.container.decode(String.self, forKey: .init("source")); skill = try f.container.decode(String.self, forKey: .init("skill"))
            count = try f.value("n"); sessions = try f.value("sessions")
        }
    }

    public struct SkillReferenceDetail: Decodable, Sendable, Equatable, Identifiable {
        public let relPath: String, docPreview: String?, lineCount: Int, tokensEst: Int, hits30d: Int?, sessions30d: Int?, isUnhit: Bool
        public var id: String { relPath }

        public init(relPath: String, docPreview: String? = nil, lineCount: Int = 0, tokensEst: Int = 0, hits30d: Int? = nil, sessions30d: Int? = nil, isUnhit: Bool = false) {
            self.relPath = relPath; self.docPreview = docPreview; self.lineCount = lineCount; self.tokensEst = tokensEst
            self.hits30d = hits30d; self.sessions30d = sessions30d; self.isUnhit = isUnhit
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            relPath = try f.container.decode(String.self, forKey: .init("rel_path"))
            docPreview = try f.value("doc_preview")
            lineCount = try f.value("line_count") ?? 0
            tokensEst = try f.value("tokens_est") ?? 0
            hits30d = try f.value("hits_30d")
            sessions30d = try f.value("sessions_30d")
            isUnhit = try f.value("is_unhit") ?? (hits30d == 0)
        }
    }

    public struct SkillScriptDetail: Decodable, Sendable, Equatable, Identifiable {
        public let relPath: String, calls30d: Int?, successRate: Double?, p50Ms: Double?, p95Ms: Double?, isUnpracticed: Bool
        public var id: String { relPath }

        public init(relPath: String, calls30d: Int? = nil, successRate: Double? = nil, p50Ms: Double? = nil, p95Ms: Double? = nil, isUnpracticed: Bool = false) {
            self.relPath = relPath; self.calls30d = calls30d; self.successRate = successRate
            self.p50Ms = p50Ms; self.p95Ms = p95Ms; self.isUnpracticed = isUnpracticed
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            relPath = try f.container.decode(String.self, forKey: .init("rel_path"))
            calls30d = try f.value("calls_30d")
            successRate = try f.value("success_rate")
            p50Ms = try f.value("p50_ms") ?? f.value("script_p50_ms")
            p95Ms = try f.value("p95_ms")
            isUnpracticed = try f.value("is_unpracticed") ?? (calls30d == 0)
        }
    }

    public struct SkillEvalCaseDetail: Decodable, Sendable, Equatable, Identifiable {
        public let id: String, title: String, kind: String, assertionSummary: String, status: String, interceptions30d: Int, escapes30d: Int

        public init(id: String, title: String, kind: String = "contract", assertionSummary: String = "", status: String = "active", interceptions30d: Int = 0, escapes30d: Int = 0) {
            self.id = id; self.title = title; self.kind = kind; self.assertionSummary = assertionSummary
            self.status = status; self.interceptions30d = interceptions30d; self.escapes30d = escapes30d
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            id = try f.container.decode(String.self, forKey: .init("id"))
            title = try f.value("title") ?? id
            kind = try f.value("kind") ?? "contract"
            assertionSummary = try f.value("assertion_summary") ?? ""
            status = try f.value("status") ?? "active"
            interceptions30d = try f.value("interceptions_30d") ?? 0
            escapes30d = try f.value("escapes_30d") ?? 0
        }
    }

    public struct SkillInspectorDetail: Decodable, Sendable, Equatable, Identifiable {
        public let metadata: SkillsObservationMetadata
        public let skill: String, docPreview: String?, scope: String, repo: String, skillDir: String, skillMdPath: String
        public let skillMdLines: Int, frontmatterTokensEst: Int, bodyTokensEst: Int
        public let bundleKb: Double?, refsKb: Double?, refsTokensEst: Int?
        public let loads7d: Int, loads30d: Int, emptyLoadRate: Double?, unpracticedRate: Double?, roiScore: Double?, r1PassRate: Double?
        public let unhitRefsCount: Int, unhitRefsRatio: Double?, isGhost: Bool
        public let avgContextTokens: Double?, kvCacheHitPct: Double?, editChurn: Int, retryChurn: Int
        public let implBugEscapes: Int, specGapEscapes: Int, evalInterceptions: Int, evalEscapes: Int
        public let statusLabel: String, sourceBreakdown: [String: Int]
        public let references: [SkillReferenceDetail], scripts: [SkillScriptDetail], evalCases: [SkillEvalCaseDetail]
        public var id: String { skill }

        public init(
            metadata: SkillsObservationMetadata, skill: String, docPreview: String? = nil, scope: String = "global", repo: String = "user-skills",
            skillDir: String, skillMdPath: String = "SKILL.md", skillMdLines: Int = 0, frontmatterTokensEst: Int = 0, bodyTokensEst: Int = 0,
            bundleKb: Double? = nil, refsKb: Double? = nil, refsTokensEst: Int? = nil,
            loads7d: Int = 0, loads30d: Int = 0, emptyLoadRate: Double? = nil, unpracticedRate: Double? = nil, roiScore: Double? = nil, r1PassRate: Double? = nil,
            unhitRefsCount: Int? = nil, unhitRefsRatio: Double? = nil, isGhost: Bool? = nil,
            avgContextTokens: Double? = nil, kvCacheHitPct: Double? = nil, editChurn: Int = 0, retryChurn: Int = 0,
            implBugEscapes: Int = 0, specGapEscapes: Int = 0, evalInterceptions: Int = 0, evalEscapes: Int = 0,
            statusLabel: String = "active", sourceBreakdown: [String: Int] = [:],
            references: [SkillReferenceDetail] = [], scripts: [SkillScriptDetail] = [], evalCases: [SkillEvalCaseDetail] = []
        ) {
            let computedUnhit = unhitRefsCount ?? references.filter(\.isUnhit).count
            let computedRatio = unhitRefsRatio ?? (references.isEmpty ? nil : Double(computedUnhit) / Double(references.count))
            self.metadata = metadata; self.skill = skill; self.docPreview = docPreview; self.scope = scope; self.repo = repo
            self.skillDir = skillDir; self.skillMdPath = skillMdPath; self.skillMdLines = skillMdLines
            self.frontmatterTokensEst = frontmatterTokensEst; self.bodyTokensEst = bodyTokensEst
            self.bundleKb = bundleKb; self.refsKb = refsKb; self.refsTokensEst = refsTokensEst
            self.loads7d = loads7d; self.loads30d = loads30d; self.emptyLoadRate = emptyLoadRate
            self.unpracticedRate = unpracticedRate; self.roiScore = roiScore; self.r1PassRate = r1PassRate
            self.unhitRefsCount = computedUnhit; self.unhitRefsRatio = computedRatio
            self.isGhost = isGhost ?? (statusLabel == "ghost")
            self.avgContextTokens = avgContextTokens
            self.kvCacheHitPct = kvCacheHitPct; self.editChurn = editChurn; self.retryChurn = retryChurn
            self.implBugEscapes = implBugEscapes; self.specGapEscapes = specGapEscapes
            self.evalInterceptions = evalInterceptions; self.evalEscapes = evalEscapes
            self.statusLabel = statusLabel; self.sourceBreakdown = sourceBreakdown
            self.references = references; self.scripts = scripts; self.evalCases = evalCases
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata
            skill = try f.container.decode(String.self, forKey: .init("skill"))
            docPreview = try f.value("doc_preview")
            scope = try f.value("scope") ?? "global"
            repo = try f.value("repo") ?? (scope == "repo_bound" ? "repo" : "user-skills")
            skillDir = try f.value("skill_dir") ?? "~/Development/user-skills/skills/\(skill)"
            skillMdPath = try f.value("skill_md_path") ?? "SKILL.md"
            skillMdLines = try f.value("skill_md_lines") ?? 0
            frontmatterTokensEst = try f.value("frontmatter_tokens_est") ?? 0
            bodyTokensEst = try f.value("body_tokens_est") ?? 0
            bundleKb = try f.value("bundle_kb")
            refsKb = try f.value("refs_kb")
            refsTokensEst = try f.value("refs_tokens_est")
            loads7d = try f.value("loads_7d") ?? 0
            loads30d = try f.value("loads_30d") ?? 0
            emptyLoadRate = try f.value("empty_load_rate")
            unpracticedRate = try f.value("unpracticed_rate")
            roiScore = try f.value("roi_score")
            r1PassRate = try f.value("r1_pass_rate")
            avgContextTokens = try f.value("avg_context_tokens")
            kvCacheHitPct = try f.value("kv_cache_hit_pct")
            editChurn = try f.value("edit_churn") ?? 0
            retryChurn = try f.value("retry_churn") ?? 0
            implBugEscapes = try f.value("impl_bug_escapes") ?? 0
            specGapEscapes = try f.value("spec_gap_escapes") ?? 0
            evalInterceptions = try f.value("eval_interceptions") ?? 0
            evalEscapes = try f.value("eval_escapes") ?? 0
            let decodedStatus: String = try f.value("status_label") ?? (loads30d == 0 ? "zombie_30d" : "active")
            statusLabel = decodedStatus
            isGhost = try f.value("is_ghost") ?? (decodedStatus == "ghost")
            sourceBreakdown = try f.value("source_breakdown") ?? [:]
            let decodedRefs: [SkillReferenceDetail] = try f.value("references") ?? []
            references = decodedRefs
            let fallbackUnhit = decodedRefs.filter(\.isUnhit).count
            unhitRefsCount = try f.value("unhit_refs_count") ?? fallbackUnhit
            unhitRefsRatio = try f.value("unhit_refs_ratio") ?? (decodedRefs.isEmpty ? nil : Double(fallbackUnhit) / Double(decodedRefs.count))
            scripts = try f.value("scripts") ?? []
            evalCases = try f.value("eval_cases") ?? []
        }
    }

    public enum SkillsPseudoSkillGuard {
        public static let forbiddenSlugs: Set<String> = [
            "tests", "leepepe", "pull", "main", "scripts", "skills",
            "head", "origin", "pr", "issue", "issues", "master", "refs", "tags",
        ]

        public static func isPseudoSkill(_ raw: String) -> Bool {
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !cleaned.isEmpty else {
                return true
            }
            return forbiddenSlugs.contains(cleaned)
        }

        public static func scrubAcademicCodes(_ raw: String) -> String {
            guard let regex = try? NSRegularExpression(pattern: #"\bS(?:1[0-2]|[1-9])\b"#) else { return raw }
            let range = NSRange(raw.startIndex ..< raw.endIndex, in: raw)
            return regex.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public struct SkillVersionMetricsSnapshot: Decodable, Sendable, Equatable, Identifiable {
        public let skillVersion: String
        public let semver: String
        public let combinedVersion: String
        public let commitCount: Int
        public let subtreeSha: String
        public let sessions: Int
        public let invocations: Int
        public let scriptCallCount: Int
        public let exit2Count: Int
        public let exit1Count: Int
        public let postFixErrors: Int
        public let exit2ErrorRate: Double?
        public let brokenDrawerCount: Int
        public let scriptP50Ms: Double?
        public let uptakeRate: Double?
        public let r1Total: Int
        public let r1Pass: Int
        public let r1PassRate: Double?

        public var id: String { combinedVersion }

        public init(
            skillVersion: String,
            semver: String = "1.0.0",
            combinedVersion: String? = nil,
            commitCount: Int = 1,
            subtreeSha: String = "",
            sessions: Int = 0,
            invocations: Int = 0,
            scriptCallCount: Int = 0,
            exit2Count: Int = 0,
            exit1Count: Int = 0,
            postFixErrors: Int? = nil,
            exit2ErrorRate: Double? = nil,
            brokenDrawerCount: Int = 0,
            scriptP50Ms: Double? = nil,
            uptakeRate: Double? = nil,
            r1Total: Int = 0,
            r1Pass: Int = 0,
            r1PassRate: Double? = nil
        ) {
            self.skillVersion = skillVersion
            self.semver = semver
            self.combinedVersion = combinedVersion ?? "\(semver)+\(skillVersion)"
            self.commitCount = commitCount
            self.subtreeSha = subtreeSha
            self.sessions = sessions
            self.invocations = invocations
            self.scriptCallCount = scriptCallCount
            self.exit2Count = exit2Count
            self.exit1Count = exit1Count
            self.postFixErrors = postFixErrors ?? exit2Count
            self.exit2ErrorRate = exit2ErrorRate
            self.brokenDrawerCount = brokenDrawerCount
            self.scriptP50Ms = scriptP50Ms
            self.uptakeRate = uptakeRate
            self.r1Total = r1Total
            self.r1Pass = r1Pass
            self.r1PassRate = r1PassRate
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            let sv = try f.value("skill_version", as: String.self) ?? "v1@head"
            let sem = try f.value("semver", as: String.self) ?? (f.value("plugin_version", as: String.self)) ?? "1.0.0"
            skillVersion = sv
            semver = sem
            combinedVersion = try f.value("combined_version", as: String.self) ?? "\(sem)+\(sv)"
            commitCount = try f.value("commit_count", as: Int.self) ?? 1
            subtreeSha = try f.value("subtree_sha", as: String.self) ?? ""
            sessions = try f.value("sessions", as: Int.self) ?? 0
            invocations = try f.value("invocations", as: Int.self) ?? sessions
            scriptCallCount = try f.value("script_call_count", as: Int.self) ?? 0
            let e2 = try f.value("exit2_count", as: Int.self) ?? 0
            exit2Count = e2
            exit1Count = try f.value("exit1_count", as: Int.self) ?? 0
            postFixErrors = try f.value("post_fix_errors", as: Int.self) ?? e2
            exit2ErrorRate = try f.value("exit2_error_rate", as: Double.self)
            brokenDrawerCount = try f.value("broken_drawer_count", as: Int.self) ?? 0
            scriptP50Ms = try f.value("script_p50_ms", as: Double.self)
            uptakeRate = try f.value("uptake_rate", as: Double.self)
            let rt = try f.value("r1_total", as: Int.self) ?? 0
            let rp = try f.value("r1_pass", as: Int.self) ?? 0
            r1Total = rt
            r1Pass = rp
            r1PassRate = try f.value("r1_pass_rate", as: Double.self) ?? (rt > 0 ? Double(rp) / Double(rt) : nil)
        }
    }

    public struct SkillVersionDeltaSummary: Decodable, Sendable, Equatable {
        public let exit2ErrorRateDelta: Double?
        public let exit2CountDelta: Int?
        public let brokenDrawerDelta: Int?
        public let scriptP50MsDelta: Double?
        public let uptakeRateDelta: Double?
        public let r1PassRateDelta: Double?
        public let postFixErrors: Int
        public let improvedDimensions: [String]
        public let regressedDimensions: [String]

        public init(
            exit2ErrorRateDelta: Double? = nil,
            exit2CountDelta: Int? = nil,
            brokenDrawerDelta: Int? = nil,
            scriptP50MsDelta: Double? = nil,
            uptakeRateDelta: Double? = nil,
            r1PassRateDelta: Double? = nil,
            postFixErrors: Int = 0,
            improvedDimensions: [String] = [],
            regressedDimensions: [String] = []
        ) {
            self.exit2ErrorRateDelta = exit2ErrorRateDelta
            self.exit2CountDelta = exit2CountDelta
            self.brokenDrawerDelta = brokenDrawerDelta
            self.scriptP50MsDelta = scriptP50MsDelta
            self.uptakeRateDelta = uptakeRateDelta
            self.r1PassRateDelta = r1PassRateDelta
            self.postFixErrors = postFixErrors
            self.improvedDimensions = improvedDimensions
            self.regressedDimensions = regressedDimensions
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            exit2ErrorRateDelta = try f.value("exit2_error_rate_delta", as: Double.self)
            exit2CountDelta = try f.value("exit2_count_delta", as: Int.self)
            brokenDrawerDelta = try f.value("broken_drawer_delta", as: Int.self)
            scriptP50MsDelta = try f.value("script_p50_ms_delta", as: Double.self)
            uptakeRateDelta = try f.value("uptake_rate_delta", as: Double.self)
            r1PassRateDelta = try f.value("r1_pass_rate_delta", as: Double.self)
            postFixErrors = try f.value("post_fix_errors", as: Int.self) ?? 0
            improvedDimensions = try f.value("improved_dimensions", as: [String].self) ?? []
            regressedDimensions = try f.value("regressed_dimensions", as: [String].self) ?? []
        }
    }

    public struct SkillVersionEvolutionRow: Decodable, Sendable, Equatable, Identifiable {
        public let metadata: SkillsObservationMetadata
        public let skill: String
        public let semver: String
        public let skillVersion: String
        public let combinedVersion: String
        public let subtreeSha: String
        public let commitCount: Int
        public let status: String
        public let statusLabel: String
        public let beforeVersion: SkillVersionMetricsSnapshot?
        public let currentVersion: SkillVersionMetricsSnapshot
        public let delta: SkillVersionDeltaSummary
        public let versions: [SkillVersionMetricsSnapshot]

        public var id: String { skill }

        public var resolvedStatusLabel: String {
            if !statusLabel.isEmpty {
                return SkillsPseudoSkillGuard.scrubAcademicCodes(statusLabel)
            }
            switch status {
            case "improved": return "✅ 有效演进"
            case "regressed": return "⚠️ 退化告警"
            case "observing": return "⏳ 样本积累中"
            default: return "🕰️ 基准版本"
            }
        }

        public var versionTransitionLabel: String {
            if let beforeVersion {
                return "\(beforeVersion.skillVersion) → \(combinedVersion)"
            }
            return combinedVersion
        }

        public init(
            metadata: SkillsObservationMetadata,
            skill: String,
            semver: String = "1.0.0",
            skillVersion: String = "v1@head",
            combinedVersion: String? = nil,
            subtreeSha: String = "",
            commitCount: Int = 1,
            status: String = "baseline",
            statusLabel: String = "",
            beforeVersion: SkillVersionMetricsSnapshot? = nil,
            currentVersion: SkillVersionMetricsSnapshot,
            delta: SkillVersionDeltaSummary = SkillVersionDeltaSummary(),
            versions: [SkillVersionMetricsSnapshot] = []
        ) {
            self.metadata = metadata
            self.skill = skill
            self.semver = semver
            self.skillVersion = skillVersion
            self.combinedVersion = combinedVersion ?? "\(semver)+\(skillVersion)"
            self.subtreeSha = subtreeSha
            self.commitCount = commitCount
            self.status = status
            self.statusLabel = statusLabel
            self.beforeVersion = beforeVersion
            self.currentVersion = currentVersion
            self.delta = delta
            self.versions = versions.isEmpty ? ([beforeVersion, currentVersion].compactMap { $0 }) : versions
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            metadata = f.metadata
            skill = try f.container.decode(String.self, forKey: .init("skill"))
            let cur = try f.value("current_version", as: SkillVersionMetricsSnapshot.self)
                ?? SkillVersionMetricsSnapshot(skillVersion: (try? f.value("skill_version", as: String.self)) ?? "v1@head")
            currentVersion = cur
            let sem = try f.value("semver", as: String.self) ?? cur.semver
            let sv = try f.value("skill_version", as: String.self) ?? cur.skillVersion
            semver = sem
            skillVersion = sv
            combinedVersion = try f.value("combined_version", as: String.self) ?? "\(sem)+\(sv)"
            subtreeSha = try f.value("subtree_sha", as: String.self) ?? cur.subtreeSha
            commitCount = try f.value("commit_count", as: Int.self) ?? cur.commitCount
            status = try f.value("status", as: String.self) ?? "baseline"
            statusLabel = try f.value("status_label", as: String.self) ?? ""
            beforeVersion = try f.value("before_version", as: SkillVersionMetricsSnapshot.self)
            delta = try f.value("delta", as: SkillVersionDeltaSummary.self) ?? SkillVersionDeltaSummary(postFixErrors: cur.postFixErrors)
            let decodedVersions = try f.value("versions", as: [SkillVersionMetricsSnapshot].self) ?? []
            versions = decodedVersions.isEmpty ? ([beforeVersion, cur].compactMap { $0 }) : decodedVersions
        }
    }

    public struct SkillRetroTriggerMissSample: Decodable, Sendable, Equatable, Identifiable {
        public let sessionId: String
        public let evidenceFiles: [String]
        public var id: String { sessionId }

        public init(sessionId: String, evidenceFiles: [String] = []) {
            self.sessionId = sessionId
            self.evidenceFiles = evidenceFiles
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            sessionId = (try? f.value("session_id", as: String.self)) ?? "unknown"
            evidenceFiles = (try? f.value("evidence_files", as: [String].self)) ?? []
        }
    }

    public struct SkillRetroTriggerMissItem: Decodable, Sendable, Equatable, Identifiable {
        public let skill: String
        public let missedSessions: Int
        public let domainSessions: Int
        public let missRate: Double
        public let samples: [SkillRetroTriggerMissSample]
        public var id: String { skill }

        public init(
            skill: String,
            missedSessions: Int = 0,
            domainSessions: Int = 0,
            missRate: Double = 0,
            samples: [SkillRetroTriggerMissSample] = []
        ) {
            self.skill = skill
            self.missedSessions = missedSessions
            self.domainSessions = domainSessions
            self.missRate = missRate
            self.samples = samples
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            skill = (try? f.value("skill", as: String.self)) ?? "unknown"
            missedSessions = (try? f.value("missed_sessions", as: Int.self)) ?? 0
            domainSessions = (try? f.value("domain_sessions", as: Int.self)) ?? 0
            missRate = (try? f.value("miss_rate", as: Double.self))
                ?? (domainSessions > 0 ? Double(missedSessions) / Double(domainSessions) : 0)
            samples = (try? f.value("samples", as: [SkillRetroTriggerMissSample].self)) ?? []
        }
    }

    public struct SkillRetroZeroActionItem: Decodable, Sendable, Equatable, Identifiable {
        public let skill: String
        public let loads: Int
        public let zeroActionSessions: Int
        public let zeroActionRate: Double
        public var id: String { skill }

        public init(skill: String, loads: Int = 0, zeroActionSessions: Int = 0, zeroActionRate: Double = 0) {
            self.skill = skill
            self.loads = loads
            self.zeroActionSessions = zeroActionSessions
            self.zeroActionRate = zeroActionRate
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            skill = (try? f.value("skill", as: String.self)) ?? "unknown"
            loads = (try? f.value("loads", as: Int.self)) ?? 0
            zeroActionSessions = (try? f.value("zero_action_sessions", as: Int.self)) ?? 0
            zeroActionRate = (try? f.value("zero_action_rate", as: Double.self))
                ?? (loads > 0 ? Double(zeroActionSessions) / Double(loads) : 0)
        }
    }

    public struct SkillRetroDirectionalDriftItem: Decodable, Sendable, Equatable, Identifiable {
        public let goalId: String
        public let taskId: String
        public let event: String
        public let skills: [String]
        public var id: String { "\(goalId)-\(taskId)-\(event)" }

        public init(goalId: String, taskId: String = "", event: String = "CHANGE_REQUEST", skills: [String] = []) {
            self.goalId = goalId
            self.taskId = taskId
            self.event = event
            self.skills = skills
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            goalId = (try? f.value("goal_id", as: String.self)) ?? "unknown"
            taskId = (try? f.value("task_id", as: String.self)) ?? ""
            event = (try? f.value("event", as: String.self)) ?? "CHANGE_REQUEST"
            skills = (try? f.value("skills", as: [String].self)) ?? []
        }
    }

    public struct SkillRetroDrawerItem: Decodable, Sendable, Equatable, Identifiable {
        public let skill: String
        public let drawer: String
        public let hits: Int
        public let hitSessions: Int
        public let scenarioSessions: Int
        public let scenarioHitRate: Double
        public let lineCount: Int
        public let tokensEst: Int
        public let classification: String
        public let evolutionAction: String
        public var id: String { "\(skill)/\(drawer)" }

        public init(
            skill: String,
            drawer: String,
            hits: Int = 0,
            hitSessions: Int = 0,
            scenarioSessions: Int = 0,
            scenarioHitRate: Double = 0,
            lineCount: Int = 0,
            tokensEst: Int = 0,
            classification: String = "",
            evolutionAction: String = ""
        ) {
            self.skill = skill
            self.drawer = drawer
            self.hits = hits
            self.hitSessions = hitSessions
            self.scenarioSessions = scenarioSessions
            self.scenarioHitRate = scenarioHitRate
            self.lineCount = lineCount
            self.tokensEst = tokensEst
            self.classification = classification
            self.evolutionAction = evolutionAction
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            skill = (try? f.value("skill", as: String.self)) ?? "unknown"
            drawer = (try? f.value("drawer", as: String.self)) ?? "references/unknown.md"
            hits = (try? f.value("hits", as: Int.self)) ?? 0
            hitSessions = (try? f.value("hit_sessions", as: Int.self)) ?? hits
            scenarioSessions = (try? f.value("scenario_sessions", as: Int.self)) ?? 0
            scenarioHitRate = (try? f.value("scenario_hit_rate", as: Double.self)) ?? 0
            lineCount = (try? f.value("line_count", as: Int.self)) ?? 0
            tokensEst = (try? f.value("tokens_est", as: Int.self)) ?? 0
            classification = (try? f.value("classification", as: String.self)) ?? ""
            evolutionAction = (try? f.value("evolution_action", as: String.self)) ?? ""
        }
    }

    public struct SkillRetroRoadblockItem: Decodable, Sendable, Equatable, Identifiable {
        public let skill: String
        public let script: String
        public let skillVersion: String
        public let calls: Int
        public let totalExit2Count: Int
        public let preFixCount: Int
        public let postFixCount: Int
        public let exit2Sessions: Int
        public let failingCommandSamples: [String]
        public let watermarkStatus: String
        public let evolutionAction: String
        public var id: String { "\(skill)/\(script)" }

        public init(
            skill: String,
            script: String,
            skillVersion: String = "",
            calls: Int = 0,
            totalExit2Count: Int? = nil,
            preFixCount: Int = 0,
            postFixCount: Int = 0,
            exit2Sessions: Int = 0,
            failingCommandSamples: [String] = [],
            watermarkStatus: String = "",
            evolutionAction: String = ""
        ) {
            self.skill = skill
            self.script = script
            self.skillVersion = skillVersion
            self.calls = calls
            self.preFixCount = preFixCount
            self.postFixCount = postFixCount
            self.totalExit2Count = totalExit2Count ?? (preFixCount + postFixCount)
            self.exit2Sessions = exit2Sessions
            self.failingCommandSamples = failingCommandSamples
            self.watermarkStatus = watermarkStatus
            self.evolutionAction = evolutionAction
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            skill = (try? f.value("skill", as: String.self)) ?? "unknown"
            script = (try? f.value("script", as: String.self)) ?? "scripts/unknown.py"
            skillVersion = (try? f.value("skill_version", as: String.self)) ?? ""
            calls = (try? f.value("calls", as: Int.self)) ?? 0
            let pre = (try? f.value("pre_fix_count", as: Int.self))
                ?? (try? f.value("pre_fix", as: Int.self))
                ?? 0
            let post = (try? f.value("post_fix_count", as: Int.self))
                ?? (try? f.value("post_fix", as: Int.self))
                ?? (try? f.value("exit_2_count", as: Int.self))
                ?? 0
            let total = (try? f.value("total_exit_2_count", as: Int.self))
                ?? (try? f.value("exit_2_count", as: Int.self))
                ?? (pre + post)
            preFixCount = pre
            postFixCount = post
            totalExit2Count = max(total, pre + post)
            exit2Sessions = (try? f.value("exit_2_sessions", as: Int.self)) ?? 0
            failingCommandSamples = (try? f.value("failing_command_samples", as: [String].self)) ?? []
            watermarkStatus = (try? f.value("watermark_status", as: String.self)) ?? ""
            evolutionAction = (try? f.value("evolution_action", as: String.self)) ?? ""
        }
    }

    public struct SkillRetroRubberStampItem: Decodable, Sendable, Equatable, Identifiable {
        public let skill: String
        public let script: String
        public let calls: Int
        public let coOccurringSkillEscapes: Int
        public let p50Ms: Double?
        public let evolutionAction: String
        public var id: String { "\(skill)/\(script)" }

        public init(
            skill: String,
            script: String,
            calls: Int = 0,
            coOccurringSkillEscapes: Int = 0,
            p50Ms: Double? = nil,
            evolutionAction: String = ""
        ) {
            self.skill = skill
            self.script = script
            self.calls = calls
            self.coOccurringSkillEscapes = coOccurringSkillEscapes
            self.p50Ms = p50Ms
            self.evolutionAction = evolutionAction
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            skill = (try? f.value("skill", as: String.self)) ?? "unknown"
            script = (try? f.value("script", as: String.self)) ?? "scripts/unknown.py"
            calls = (try? f.value("calls", as: Int.self)) ?? 0
            coOccurringSkillEscapes = (try? f.value("co_occurring_skill_escapes", as: Int.self)) ?? 0
            p50Ms = try? f.value("p50_ms", as: Double.self)
            evolutionAction = (try? f.value("evolution_action", as: String.self)) ?? ""
        }
    }

    public struct SkillRetroLatencySinkItem: Decodable, Sendable, Equatable, Identifiable {
        public let skill: String
        public let script: String
        public let calls: Int
        public let primaryBottleneck: String
        public let p50Ms: Double?
        public let p95Ms: Double?
        public var id: String { "\(skill)/\(script)" }

        public init(
            skill: String,
            script: String,
            calls: Int = 0,
            primaryBottleneck: String = "external_wait",
            p50Ms: Double? = nil,
            p95Ms: Double? = nil
        ) {
            self.skill = skill
            self.script = script
            self.calls = calls
            self.primaryBottleneck = primaryBottleneck
            self.p50Ms = p50Ms
            self.p95Ms = p95Ms
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            skill = (try? f.value("skill", as: String.self)) ?? "unknown"
            script = (try? f.value("script", as: String.self)) ?? "scripts/unknown.py"
            calls = (try? f.value("calls", as: Int.self)) ?? 0
            primaryBottleneck = (try? f.value("primary_bottleneck", as: String.self)) ?? "external_wait"
            p50Ms = try? f.value("p50_ms", as: Double.self)
            p95Ms = try? f.value("p95_ms", as: Double.self)
        }
    }

    public struct SkillRetroCrossRepoGateSummary: Decodable, Sendable, Equatable {
        public let reposScanned: Int
        public let healthyReposCount: Int
        public let driftedReposCount: Int
        public let averageGateHealthScore: Double
        public let totalFindings: Int

        public init(
            reposScanned: Int = 0,
            healthyReposCount: Int = 0,
            driftedReposCount: Int = 0,
            averageGateHealthScore: Double = 100.0,
            totalFindings: Int = 0
        ) {
            self.reposScanned = reposScanned
            self.healthyReposCount = healthyReposCount
            self.driftedReposCount = driftedReposCount
            self.averageGateHealthScore = averageGateHealthScore
            self.totalFindings = totalFindings
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            reposScanned = (try? f.value("repos_scanned", as: Int.self)) ?? 0
            healthyReposCount = (try? f.value("healthy_repos_count", as: Int.self)) ?? 0
            driftedReposCount = (try? f.value("drifted_repos_count", as: Int.self)) ?? 0
            averageGateHealthScore = (try? f.value("average_gate_health_score", as: Double.self)) ?? 100.0
            totalFindings = (try? f.value("total_findings", as: Int.self)) ?? 0
        }
    }

    public struct SkillRetroWildPatternItem: Decodable, Sendable, Equatable, Identifiable {
        public let patternSignature: String
        public let occurrences: Int
        public let sessionCount: Int
        public let candidateSkill: String
        public let examples: [String]
        public var id: String { patternSignature }

        public init(
            patternSignature: String,
            occurrences: Int = 0,
            sessionCount: Int = 0,
            candidateSkill: String = "team-lead",
            examples: [String] = []
        ) {
            self.patternSignature = patternSignature
            self.occurrences = occurrences
            self.sessionCount = sessionCount
            self.candidateSkill = candidateSkill
            self.examples = examples
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            patternSignature = (try? f.value("pattern_signature", as: String.self)) ?? "unknown"
            occurrences = (try? f.value("occurrences", as: Int.self)) ?? 0
            sessionCount = (try? f.value("session_count", as: Int.self)) ?? 0
            candidateSkill = (try? f.value("candidate_skill", as: String.self)) ?? "team-lead"
            examples = (try? f.value("examples", as: [String].self)) ?? []
        }
    }

    public struct SkillRetroProposalItem: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let skill: String
        public let layer: String
        public let category: String
        public let priority: String
        public let ruleId: String?
        public let title: String
        public let plainReason: String
        public let detail: String?
        public let action: String?
        public let humanWhat: String?
        public let humanWhy: String?
        public let affectedRepos: [String]
        public let remediationCommands: [String]

        public var displayTitle: String {
            let raw = (humanWhat?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? title
            let stripped = raw.replacingOccurrences(of: #"(?i)\[Skill Retro\s+L[0-3]\]\s*"#, with: "", options: .regularExpression)
            return SkillsPseudoSkillGuard.scrubAcademicCodes(stripped)
        }

        public var displayReason: String {
            let raw = (humanWhy?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? (!plainReason.isEmpty ? plainReason : (action ?? title))
            return SkillsPseudoSkillGuard.scrubAcademicCodes(raw)
        }

        public var primaryRemediationCommand: String {
            if let first = remediationCommands.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return first
            }
            if let actionText = action?.trimmingCharacters(in: .whitespacesAndNewlines), !actionText.isEmpty {
                return actionText
            }
            return action ?? ""
        }

        public init(
            id: String,
            skill: String,
            layer: String = "L0",
            category: String = "",
            priority: String = "P2",
            ruleId: String? = nil,
            title: String,
            plainReason: String = "",
            detail: String? = nil,
            action: String? = nil,
            humanWhat: String? = nil,
            humanWhy: String? = nil,
            affectedRepos: [String] = [],
            remediationCommands: [String] = []
        ) {
            self.id = id
            self.skill = skill
            self.layer = layer
            self.category = category
            self.priority = priority
            self.ruleId = ruleId
            self.title = title
            self.plainReason = plainReason
            self.detail = detail
            self.action = action
            self.humanWhat = humanWhat
            self.humanWhy = humanWhy
            self.affectedRepos = affectedRepos
            self.remediationCommands = remediationCommands
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            let sk = (try? f.value("skill", as: String.self)) ?? "team-lead"
            let ly = (try? f.value("layer", as: String.self)) ?? "L0"
            let cat = (try? f.value("category", as: String.self)) ?? ""
            id = (try? f.value("id", as: String.self)) ?? "skill-retro-\(ly.lowercased())-\(sk)"
            skill = sk
            layer = ly
            category = cat
            priority = (try? f.value("priority", as: String.self)) ?? "P2"
            ruleId = try? f.value("rule_id", as: String.self)
            let t = (try? f.value("title", as: String.self)) ?? sk
            title = t
            plainReason = (try? f.value("plain_reason", as: String.self)) ?? ""
            detail = try? f.value("detail", as: String.self)
            action = try? f.value("action", as: String.self)
            humanWhat = try? f.value("human_what", as: String.self)
            humanWhy = try? f.value("human_why", as: String.self)
            affectedRepos = (try? f.value("affected_repos", as: [String].self)) ?? []
            remediationCommands = (try? f.value("remediation_commands", as: [String].self)) ?? []
        }
    }

    public struct SkillRetroFourLayerSummary: Decodable, Sendable, Equatable {
        public let sampleSize: Int
        public let slowFlywheelReady: Bool
        public let triggerMissSkills: Int
        public let zeroActionLoadSkills: Int
        public let directionalDrifts: Int
        public let unwiredDrawersCount: Int
        public let trueDeadwoodDrawersCount: Int
        public let trueCatcherScriptsCount: Int
        public let ceremonialScriptsCount: Int
        public let rigidRoadblockScriptsCount: Int
        public let exit2RoadblockTotalCount: Int
        public let latencySinkScriptsCount: Int
        public let wildPatternsCount: Int
        public let triggerMisses: [SkillRetroTriggerMissItem]
        public let zeroActionLoads: [SkillRetroZeroActionItem]
        public let directionalDriftItems: [SkillRetroDirectionalDriftItem]
        public let hotDrawers: [SkillRetroDrawerItem]
        public let onDemandDrawers: [SkillRetroDrawerItem]
        public let unwiredDrawers: [SkillRetroDrawerItem]
        public let trueZeroHitDeadwood: [SkillRetroDrawerItem]
        public let rigidRoadblocks: [SkillRetroRoadblockItem]
        public let watermarkedResolvedRoadblocks: [SkillRetroRoadblockItem]
        public let ceremonialRubberStamps: [SkillRetroRubberStampItem]
        public let latencySinks: [SkillRetroLatencySinkItem]
        public let crossRepoGateHealth: SkillRetroCrossRepoGateSummary?
        public let wildPatterns: [SkillRetroWildPatternItem]
        public let proposals: [SkillRetroProposalItem]

        private struct Layer0Section: Decodable {
            let triggerMisses: [SkillRetroTriggerMissItem]?
            let zeroActionLoads: [SkillRetroZeroActionItem]?
            let directionalDrifts: [SkillRetroDirectionalDriftItem]?
            let directionalDriftCount: Int?
            enum CodingKeys: String, CodingKey {
                case triggerMisses = "trigger_misses"
                case zeroActionLoads = "zero_action_loads"
                case directionalDrifts = "directional_drifts"
                case directionalDriftCount = "directional_drift_count"
            }
        }

        private struct Layer1Section: Decodable {
            let hotDrawers: [SkillRetroDrawerItem]?
            let onDemandCorrectionDrawers: [SkillRetroDrawerItem]?
            let unwiredDisconnectedDrawers: [SkillRetroDrawerItem]?
            let trueZeroHitDeadwood: [SkillRetroDrawerItem]?
            enum CodingKeys: String, CodingKey {
                case hotDrawers = "hot_drawers"
                case onDemandCorrectionDrawers = "on_demand_correction_drawers"
                case unwiredDisconnectedDrawers = "unwired_disconnected_drawers"
                case trueZeroHitDeadwood = "true_zero_hit_deadwood"
            }
        }

        private struct Layer2Section: Decodable {
            let rigidRoadblocks: [SkillRetroRoadblockItem]?
            let watermarkedResolvedRoadblocks: [SkillRetroRoadblockItem]?
            let ceremonialRubberStamps: [SkillRetroRubberStampItem]?
            let latencySinks: [SkillRetroLatencySinkItem]?
            let crossRepoGateHealth: SkillRetroCrossRepoGateSummary?
            enum CodingKeys: String, CodingKey {
                case rigidRoadblocks = "rigid_roadblocks"
                case watermarkedResolvedRoadblocks = "watermarked_resolved_roadblocks"
                case ceremonialRubberStamps = "ceremonial_rubber_stamps"
                case latencySinks = "latency_sinks"
                case crossRepoGateHealth = "cross_repo_gate_health"
            }
        }

        private struct Layer3Section: Decodable {
            let wildPatterns: [SkillRetroWildPatternItem]?
            enum CodingKeys: String, CodingKey {
                case wildPatterns = "wild_patterns"
            }
        }

        private struct SummaryNested: Decodable {
            let triggerMissSkills: Int?
            let zeroActionLoadSkills: Int?
            let directionalDrifts: Int?
            let unwiredDrawersCount: Int?
            let trueDeadwoodDrawersCount: Int?
            let trueCatcherScriptsCount: Int?
            let ceremonialScriptsCount: Int?
            let rigidRoadblockScriptsCount: Int?
            let exit2RoadblockTotalCount: Int?
            let latencySinkScriptsCount: Int?
            let wildPatternsCount: Int?
            let slowFlywheelReady: Bool?

            enum CodingKeys: String, CodingKey {
                case triggerMissSkills = "trigger_miss_skills"
                case zeroActionLoadSkills = "zero_action_load_skills"
                case directionalDrifts = "directional_drifts"
                case unwiredDrawersCount = "unwired_drawers_count"
                case trueDeadwoodDrawersCount = "true_deadwood_drawers_count"
                case trueCatcherScriptsCount = "true_catcher_scripts_count"
                case ceremonialScriptsCount = "ceremonial_scripts_count"
                case rigidRoadblockScriptsCount = "rigid_roadblock_scripts_count"
                case exit2RoadblockTotalCount = "exit2_roadblock_total_count"
                case latencySinkScriptsCount = "latency_sink_scripts_count"
                case wildPatternsCount = "wild_patterns_count"
                case slowFlywheelReady = "slow_flywheel_ready"
            }
        }

        public init(
            sampleSize: Int = 0,
            slowFlywheelReady: Bool = false,
            triggerMissSkills: Int = 0,
            zeroActionLoadSkills: Int = 0,
            directionalDrifts: Int = 0,
            unwiredDrawersCount: Int = 0,
            trueDeadwoodDrawersCount: Int = 0,
            trueCatcherScriptsCount: Int = 0,
            ceremonialScriptsCount: Int = 0,
            rigidRoadblockScriptsCount: Int = 0,
            exit2RoadblockTotalCount: Int? = nil,
            latencySinkScriptsCount: Int = 0,
            wildPatternsCount: Int = 0,
            triggerMisses: [SkillRetroTriggerMissItem] = [],
            zeroActionLoads: [SkillRetroZeroActionItem] = [],
            directionalDriftItems: [SkillRetroDirectionalDriftItem] = [],
            hotDrawers: [SkillRetroDrawerItem] = [],
            onDemandDrawers: [SkillRetroDrawerItem] = [],
            unwiredDrawers: [SkillRetroDrawerItem] = [],
            trueZeroHitDeadwood: [SkillRetroDrawerItem] = [],
            rigidRoadblocks: [SkillRetroRoadblockItem] = [],
            watermarkedResolvedRoadblocks: [SkillRetroRoadblockItem] = [],
            ceremonialRubberStamps: [SkillRetroRubberStampItem] = [],
            latencySinks: [SkillRetroLatencySinkItem] = [],
            crossRepoGateHealth: SkillRetroCrossRepoGateSummary? = nil,
            wildPatterns: [SkillRetroWildPatternItem] = [],
            proposals: [SkillRetroProposalItem] = []
        ) {
            self.sampleSize = sampleSize
            self.slowFlywheelReady = slowFlywheelReady
            self.triggerMissSkills = triggerMissSkills
            self.zeroActionLoadSkills = zeroActionLoadSkills
            self.directionalDrifts = directionalDrifts
            self.unwiredDrawersCount = unwiredDrawersCount
            self.trueDeadwoodDrawersCount = trueDeadwoodDrawersCount
            self.trueCatcherScriptsCount = trueCatcherScriptsCount
            self.ceremonialScriptsCount = ceremonialScriptsCount
            self.rigidRoadblockScriptsCount = rigidRoadblockScriptsCount
            self.exit2RoadblockTotalCount = exit2RoadblockTotalCount ?? rigidRoadblockScriptsCount
            self.latencySinkScriptsCount = latencySinkScriptsCount
            self.wildPatternsCount = wildPatternsCount
            self.triggerMisses = triggerMisses.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            self.zeroActionLoads = zeroActionLoads.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            self.directionalDriftItems = directionalDriftItems
            self.hotDrawers = hotDrawers.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            self.onDemandDrawers = onDemandDrawers.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            self.unwiredDrawers = unwiredDrawers.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            self.trueZeroHitDeadwood = trueZeroHitDeadwood.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            self.rigidRoadblocks = rigidRoadblocks.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            self.watermarkedResolvedRoadblocks = watermarkedResolvedRoadblocks.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            self.ceremonialRubberStamps = ceremonialRubberStamps.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            self.latencySinks = latencySinks.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            self.crossRepoGateHealth = crossRepoGateHealth
            self.wildPatterns = wildPatterns
            self.proposals = proposals.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder)
            let nested = try? f.value("summary", as: SummaryNested.self)
            let l0 = try? f.value("layer0_direction_and_triggers", as: Layer0Section.self)
            let l1 = try? f.value("layer1_drawer_metabolism", as: Layer1Section.self)
            let l2 = try? f.value("layer2_script_efficacy_and_speed", as: Layer2Section.self)
            let l3 = try? f.value("layer3_wild_patterns_and_eval", as: Layer3Section.self)
            let topGateHealth = try? f.value("cross_repo_gate_health", as: SkillRetroCrossRepoGateSummary.self)

            let decodedTriggerMisses = (l0?.triggerMisses ?? []).filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            let decodedZeroActions = (l0?.zeroActionLoads ?? []).filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            let decodedDrifts = l0?.directionalDrifts ?? []
            let decodedHotDrawers = (l1?.hotDrawers ?? []).filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            let decodedOnDemandDrawers = (l1?.onDemandCorrectionDrawers ?? []).filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            let decodedUnwiredDrawers = (l1?.unwiredDisconnectedDrawers ?? []).filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            let decodedDeadwood = (l1?.trueZeroHitDeadwood ?? []).filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            let decodedRigidRoadblocks = (l2?.rigidRoadblocks ?? []).filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            let decodedWatermarked = (l2?.watermarkedResolvedRoadblocks ?? []).filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            let decodedRubberStamps = (l2?.ceremonialRubberStamps ?? []).filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            let decodedLatencySinks = (l2?.latencySinks ?? []).filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            let decodedWildPatterns = l3?.wildPatterns ?? []

            triggerMisses = decodedTriggerMisses
            zeroActionLoads = decodedZeroActions
            directionalDriftItems = decodedDrifts
            hotDrawers = decodedHotDrawers
            onDemandDrawers = decodedOnDemandDrawers
            unwiredDrawers = decodedUnwiredDrawers
            trueZeroHitDeadwood = decodedDeadwood
            rigidRoadblocks = decodedRigidRoadblocks
            watermarkedResolvedRoadblocks = decodedWatermarked
            ceremonialRubberStamps = decodedRubberStamps
            latencySinks = decodedLatencySinks
            crossRepoGateHealth = topGateHealth ?? l2?.crossRepoGateHealth
            wildPatterns = decodedWildPatterns

            let roadblockPostFixSum: Int? = decodedRigidRoadblocks.isEmpty
                ? nil
                : decodedRigidRoadblocks.reduce(0) { $0 + ($1.postFixCount > 0 ? $1.postFixCount : $1.totalExit2Count) }

            sampleSize = (try? f.value("sample_size", as: Int.self)) ?? f.metadata.sample ?? 0
            slowFlywheelReady = (try? f.value("slow_flywheel_ready", as: Bool.self)) ?? nested?.slowFlywheelReady ?? (sampleSize >= 50)
            triggerMissSkills = (try? f.value("trigger_miss_skills", as: Int.self)) ?? nested?.triggerMissSkills ?? decodedTriggerMisses.count
            zeroActionLoadSkills = (try? f.value("zero_action_load_skills", as: Int.self)) ?? nested?.zeroActionLoadSkills ?? decodedZeroActions.count
            directionalDrifts = (try? f.value("directional_drifts", as: Int.self)) ?? nested?.directionalDrifts ?? l0?.directionalDriftCount ?? decodedDrifts.count
            unwiredDrawersCount = (try? f.value("unwired_drawers_count", as: Int.self)) ?? nested?.unwiredDrawersCount ?? decodedUnwiredDrawers.count
            trueDeadwoodDrawersCount = (try? f.value("true_deadwood_drawers_count", as: Int.self)) ?? nested?.trueDeadwoodDrawersCount ?? decodedDeadwood.count
            trueCatcherScriptsCount = (try? f.value("true_catcher_scripts_count", as: Int.self)) ?? nested?.trueCatcherScriptsCount ?? 0
            ceremonialScriptsCount = (try? f.value("ceremonial_scripts_count", as: Int.self)) ?? nested?.ceremonialScriptsCount ?? decodedRubberStamps.count
            let rbScripts = (try? f.value("rigid_roadblock_scripts_count", as: Int.self)) ?? nested?.rigidRoadblockScriptsCount ?? decodedRigidRoadblocks.count
            rigidRoadblockScriptsCount = rbScripts
            exit2RoadblockTotalCount = (try? f.value("exit2_roadblock_total_count", as: Int.self))
                ?? nested?.exit2RoadblockTotalCount
                ?? roadblockPostFixSum
                ?? rbScripts
            latencySinkScriptsCount = (try? f.value("latency_sink_scripts_count", as: Int.self)) ?? nested?.latencySinkScriptsCount ?? decodedLatencySinks.count
            wildPatternsCount = (try? f.value("wild_patterns_count", as: Int.self)) ?? nested?.wildPatternsCount ?? decodedWildPatterns.count
            let decodedProposals = (try? f.value("proposals", as: [SkillRetroProposalItem].self)) ?? []
            proposals = decodedProposals.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
        }
    }

    public typealias SkillRetroWorkbenchSummary = SkillRetroFourLayerSummary

    private struct RemovedSkillsPrimaryDetailSplitLayout: Layout {
        var primaryFraction: CGFloat = 0.34, minPrimaryWidth: CGFloat = 240, maxPrimaryWidth: CGFloat = 340, spacing: CGFloat = Space.gap
        private func isSplit(_ width: CGFloat) -> Bool { width >= 760 }
        private func primaryWidth(_ width: CGFloat) -> CGFloat { min(maxPrimaryWidth, max(minPrimaryWidth, floor(width * primaryFraction))) }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
            let width = proposal.width ?? 760
            guard subviews.count >= 2 else {
                return subviews.first?.sizeThatFits(.init(width: width, height: nil)) ?? .zero
            }
            if isSplit(width) {
                let pw = primaryWidth(width), dw = max(0, width - pw - spacing)
                let ph = subviews[0].sizeThatFits(.init(width: pw, height: nil)).height
                let dh = subviews[1].sizeThatFits(.init(width: dw, height: nil)).height
                return .init(width: width, height: max(ph, dh))
            }
            let ph = subviews[0].sizeThatFits(.init(width: width, height: nil)).height
            let dh = subviews[1].sizeThatFits(.init(width: width, height: nil)).height
            return .init(width: width, height: ph + dh + spacing)
        }

        func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
            guard subviews.count >= 2 else {
                subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: bounds.width, height: bounds.height))
                return
            }
            if isSplit(bounds.width) {
                let pw = primaryWidth(bounds.width), dw = max(0, bounds.width - pw - spacing)
                let ph = subviews[0].sizeThatFits(.init(width: pw, height: nil)).height
                let dh = subviews[1].sizeThatFits(.init(width: dw, height: nil)).height
                let rowH = max(ph, dh)
                subviews[0].place(at: .init(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: .init(width: pw, height: rowH))
                subviews[1].place(at: .init(x: bounds.minX + pw + spacing, y: bounds.minY), anchor: .topLeading, proposal: .init(width: dw, height: rowH))
            } else {
                let ph = subviews[0].sizeThatFits(.init(width: bounds.width, height: nil)).height
                let dh = subviews[1].sizeThatFits(.init(width: bounds.width, height: nil)).height
                subviews[0].place(at: .init(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: .init(width: bounds.width, height: ph))
                subviews[1].place(at: .init(x: bounds.minX, y: bounds.minY + ph + spacing), anchor: .topLeading, proposal: .init(width: bounds.width, height: dh))
            }
        }
    }

    public struct SkillsRoiDiagnostics: Decodable, Sendable, Equatable {
        public let metadata: SkillsObservationMetadata
        public let pins: SkillsPinHealth?, gates: SkillsGateHealth?, audit: SkillsAuditHealth?, usage: SkillsUsagePopulation?
        public let scripts: [SkillsUsageRow], disclosure: [SkillsDisclosureRow], churn: [SkillsChurnRow], escapes: [SkillsEscapeRow], ranking: [SkillsUsageRow], context: SkillsContextHealth?, tools: [SkillsToolBurnRow]
        public let skillDetails: [SkillInspectorDetail]
        public let versionEvolution: [SkillVersionEvolutionRow]
        public let skillRetro: SkillRetroFourLayerSummary?
        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata
            pins = try f.value("S1_pin_drift"); gates = try f.value("S2_gate_catch"); audit = try f.value("S3_skill_health"); usage = try f.value("S4_usage_and_r1")
            let rawScripts: [SkillsUsageRow] = try f.value("S6_load_vs_script") ?? []
            let rawDisclosure: [SkillsDisclosureRow] = try f.value("S7_disclosure_funnel") ?? []
            let rawChurn: [SkillsChurnRow] = try f.value("S8_post_skill_churn") ?? []
            let rawEscapes: [SkillsEscapeRow] = try f.value("S9_escape_attribution") ?? []
            let rawRanking: [SkillsUsageRow] = try f.value("S10_skill_roi_ranking") ?? []
            scripts = rawScripts.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            disclosure = rawDisclosure.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            churn = rawChurn.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            escapes = rawEscapes.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            ranking = rawRanking.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            context = try f.value("S11_context_composition"); tools = try f.value("S12_tool_context_burn") ?? []
            let rawDetails: [SkillInspectorDetail] = try f.value("skill_details") ?? []
            skillDetails = rawDetails.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            let rawEvo: [SkillVersionEvolutionRow] = try f.value("skill_version_evolution") ?? []
            versionEvolution = rawEvo.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            skillRetro = try? f.value("skill_retro", as: SkillRetroFourLayerSummary.self)
        }

        public var usageRows: [SkillsUsageRow] {
            let topFiltered = (usage?.top ?? []).filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            let ranked = ranking.isEmpty ? topFiltered : ranking
            let names = Set(ranked.map(\.skill))
            return ranked + scripts.filter { !names.contains($0.skill) }
        }

        public var resolvedSkillDetails: [SkillInspectorDetail] {
            if !skillDetails.isEmpty {
                return skillDetails
            }
            var synthesized: [SkillInspectorDetail] = []
            var seen: Set<String> = []
            for row in usageRows where !SkillsPseudoSkillGuard.isPseudoSkill(row.skill) {
                seen.insert(row.skill)
                let disc = disclosure.first { $0.skill == row.skill }
                let ch = churn.first { $0.skill == row.skill }
                let esc = escapes.first { $0.skill == row.skill }
                let scRow = scripts.first { $0.skill == row.skill }
                let calls = row.scriptExecs.value ?? scRow?.scriptExecs.value
                let unprac = (row.unpracticed.value ?? scRow?.unpracticed.value ?? 0) >= 0.5 && (calls ?? 0) == 0
                let fallbackScripts: [SkillScriptDetail] = (calls != nil || scRow != nil)
                    ? [SkillScriptDetail(relPath: "scripts/*.py", calls30d: calls, successRate: nil, p95Ms: nil, isUnpracticed: calls == 0 || unprac)]
                    : []
                let l30 = row.loads30d.value ?? 0
                let implEsc = esc?.implementation.value ?? 0, specEsc = esc?.specification.value ?? 0
                let status: String = l30 == 0 ? "zombie_30d" : ((implEsc + specEsc > 0 || (ch?.edits.value ?? 0) >= 4 || ((row.roi.value ?? 1.0) < 0.8 && row.roi.value != nil)) ? "needs_optimization" : "active")
                synthesized.append(SkillInspectorDetail(
                    metadata: row.metadata, skill: row.skill, scope: "global", repo: "user-skills",
                    skillDir: "~/Development/user-skills/skills/\(row.skill)", skillMdPath: "SKILL.md",
                    loads7d: row.loads7d.value ?? 0, loads30d: l30, roiScore: row.roi.value, r1PassRate: row.r1Pass.value,
                    avgContextTokens: disc?.contextTokens.value, kvCacheHitPct: context?.cacheHitPercent.value,
                    editChurn: ch?.edits.value ?? 0, retryChurn: ch?.retries.value ?? 0,
                    implBugEscapes: implEsc, specGapEscapes: specEsc, statusLabel: status, scripts: fallbackScripts
                ))
            }
            for idleSkill in (usage?.idle ?? []) where !seen.contains(idleSkill) && !SkillsPseudoSkillGuard.isPseudoSkill(idleSkill) {
                seen.insert(idleSkill)
                synthesized.append(SkillInspectorDetail(
                    metadata: usage?.metadata ?? metadata, skill: idleSkill, scope: "global", repo: "user-skills",
                    skillDir: "~/Development/user-skills/skills/\(idleSkill)", skillMdPath: "SKILL.md", statusLabel: "zombie_30d"
                ))
            }
            return synthesized
        }
    }

    public struct SkillsRoiReport: Decodable, Sendable, Equatable {
        public let metadata: SkillsObservationMetadata
        public let diagnostics: SkillsRoiDiagnostics
        public let skillsDaily: [SkillsDailyObservation]
        public let skillDetails: [SkillInspectorDetail]
        public let versionEvolution: [SkillVersionEvolutionRow]
        public let skillRetro: SkillRetroFourLayerSummary?
        public let qualityBehavior: [SkillQualityBehaviorRow]?
        public let qualityJudge: SkillQualityJudgeSummary?
        public let errors: [String]

        public var resolvedSkillRetro: SkillRetroFourLayerSummary {
            if let skillRetro {
                return skillRetro
            }
            let nonGhost = skillDetails.filter { !$0.isGhost }
            let zeroActionCount = nonGhost.filter { ($0.emptyLoadRate ?? 0) >= 0.3 }.count
            let deadwoodCount = nonGhost.reduce(0) { $0 + $1.unhitRefsCount }
            let unwiredCount = versionEvolution.reduce(0) { $0 + $1.currentVersion.brokenDrawerCount }
            let catcherCount = nonGhost.reduce(0) { acc, item in
                acc + item.scripts.filter { ($0.calls30d ?? 0) > 0 && !$0.isUnpracticed }.count
            }
            let roadblockScriptsCount = versionEvolution.filter { $0.currentVersion.exit2Count > 0 }.count
            let exit2Total = versionEvolution.reduce(0) { $0 + $1.currentVersion.exit2Count }
            let slowScriptsCount = nonGhost.reduce(0) { acc, item in
                acc + item.scripts.filter { ($0.p95Ms ?? 0) >= 10000 }.count
            }
            let sample = metadata.sample ?? diagnostics.metadata.sample ?? 0
            return SkillRetroFourLayerSummary(
                sampleSize: sample,
                slowFlywheelReady: sample >= 50,
                triggerMissSkills: 0,
                zeroActionLoadSkills: zeroActionCount,
                directionalDrifts: nonGhost.reduce(0) { $0 + $1.specGapEscapes },
                unwiredDrawersCount: unwiredCount,
                trueDeadwoodDrawersCount: deadwoodCount,
                trueCatcherScriptsCount: catcherCount,
                ceremonialScriptsCount: 0,
                rigidRoadblockScriptsCount: roadblockScriptsCount,
                exit2RoadblockTotalCount: exit2Total,
                latencySinkScriptsCount: slowScriptsCount,
                wildPatternsCount: 0,
                proposals: []
            )
        }

        public init(from decoder: Decoder) throws {
            let f = try SkillsFields(decoder); metadata = f.metadata
            let diag = try f.value("diagnostics") ?? SkillsRoiDiagnostics(from: decoder)
            diagnostics = diag
            let rawDaily: [SkillsDailyObservation] = try f.value("skills_daily") ?? []
            skillsDaily = rawDaily.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            let topLevelDetails: [SkillInspectorDetail]? = try f.value("skill_details")
            let filteredTopDetails = (topLevelDetails ?? []).filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            skillDetails = !filteredTopDetails.isEmpty ? filteredTopDetails : diag.resolvedSkillDetails
            let topLevelEvo: [SkillVersionEvolutionRow]? = try f.value("skill_version_evolution")
            let filteredTopEvo = (topLevelEvo ?? []).filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
            versionEvolution = !filteredTopEvo.isEmpty ? filteredTopEvo : diag.versionEvolution
            skillRetro = (try? f.value("skill_retro", as: SkillRetroFourLayerSummary.self)) ?? diag.skillRetro
            qualityBehavior = try f.value("quality_behavior")
            qualityJudge = try f.value("quality_judge")
            errors = try f.value("errors") ?? []
        }
    }

    extension SkillsPinHealth: SkillsObjectPopulation {}
    extension SkillsGateHealth: SkillsObjectPopulation {}
    extension SkillsAuditHealth: SkillsObjectPopulation {}
    extension SkillsUsagePopulation: SkillsObjectPopulation {}
    extension SkillsContextHealth: SkillsObjectPopulation {}
    extension SkillsUsageRow: SkillsObjectPopulation {}
    extension SkillsDisclosureRow: SkillsObjectPopulation {}
    extension SkillsChurnRow: SkillsObjectPopulation {}
    extension SkillsEscapeRow: SkillsObjectPopulation {}
    extension SkillsContextSlice: SkillsObjectPopulation {}
    extension SkillsToolBurnRow: SkillsObjectPopulation {}
    extension SkillReferenceDetail: SkillsObjectPopulation {}
    extension SkillScriptDetail: SkillsObjectPopulation {}
    extension SkillEvalCaseDetail: SkillsObjectPopulation {}
    extension SkillInspectorDetail: SkillsObjectPopulation {}
    extension SkillVersionMetricsSnapshot: SkillsObjectPopulation {}
    extension SkillVersionDeltaSummary: SkillsObjectPopulation {}
    extension SkillVersionEvolutionRow: SkillsObjectPopulation {}
    extension SkillRetroTriggerMissSample: SkillsObjectPopulation {}
    extension SkillRetroTriggerMissItem: SkillsObjectPopulation {}
    extension SkillRetroZeroActionItem: SkillsObjectPopulation {}
    extension SkillRetroDirectionalDriftItem: SkillsObjectPopulation {}
    extension SkillRetroDrawerItem: SkillsObjectPopulation {}
    extension SkillRetroRoadblockItem: SkillsObjectPopulation {}
    extension SkillRetroRubberStampItem: SkillsObjectPopulation {}
    extension SkillRetroLatencySinkItem: SkillsObjectPopulation {}
    extension SkillRetroCrossRepoGateSummary: SkillsObjectPopulation {}
    extension SkillRetroWildPatternItem: SkillsObjectPopulation {}
    extension SkillRetroProposalItem: SkillsObjectPopulation {}
    extension SkillRetroFourLayerSummary: SkillsObjectPopulation {}
    extension SkillQualityBehaviorRow: SkillsObjectPopulation {}
    extension SkillQualityJudgeRow: SkillsObjectPopulation {}
    extension SkillQualityJudgeSummary: SkillsObjectPopulation {}
#endif
