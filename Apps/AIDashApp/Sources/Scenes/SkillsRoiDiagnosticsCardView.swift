#if os(macOS)
// swiftlint:disable file_length
import AppKit
import SwiftUI
import AIDashUI
import DesignKit

private func skillsText(_ key: String, _ fallback: String) -> String {
    DashboardL10n.tr("dashboard.skills_roi.\(key)", fallback)
}

public enum SkillsRoiLens: String, CaseIterable, Identifiable {
    case usage, evolution, disclosure, context
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .usage: return skillsText("usage", "Usage")
        case .evolution: return skillsText("evolution_lens", "版本演进与复盘")
        case .disclosure: return skillsText("disclosure", "Disclosure / Escapes")
        case .context: return skillsText("context", "Context")
        }
    }
}

struct SkillsEvidence: Identifiable { let title: String, value: String, metadata: SkillsObservationMetadata; var id: String { title } }

// swiftlint:disable:next type_body_length
public struct SkillsRoiDiagnosticsCardView: View {
    let summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?
    let previewHomeURL: URL?
    @State private var lens: SkillsRoiLens
    @State private var selectedSkill: String?
    @State private var inspectorFilter: SkillInspectorFilter
    @State private var inspectorSubTab: SkillInspectorSubTab
    @State private var previewRelativePath: String?
    @State private var showAllDirectorySkills = false
    @State private var copiedFeedback: String?
    @State private var evidence: [SkillsEvidence] = []
    @State private var showingEvidence = false
    @State private var dailyExpanded: Bool
    @Environment(\.theme) private var theme

    public init(
        summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?,
        initialLens: SkillsRoiLens = .usage,
        showDailyPopulations: Bool = false,
        initialSelectedSkill: String? = nil,
        initialFilter: SkillInspectorFilter = .all,
        initialSubTab: SkillInspectorSubTab = .definition,
        initialPreviewRelativePath: String? = nil,
        previewHomeURL: URL? = nil
    ) {
        self.summary = summary
        self.previewHomeURL = previewHomeURL
        _lens = State(initialValue: initialLens)
        _selectedSkill = State(initialValue: initialSelectedSkill)
        _inspectorFilter = State(initialValue: initialFilter)
        _inspectorSubTab = State(initialValue: initialSubTab)
        _previewRelativePath = State(initialValue: initialPreviewRelativePath)
        _dailyExpanded = State(initialValue: showDailyPopulations)
    }

    public var body: some View {
        SolidModularCardContainer(title: skillsText("title", "Skills 效能与上下文 ROI 工作台"),
                                  subtitle: summary.map { _ in skillsText("read_only", "Personal observations · read-only") } ?? skillsText("coverage_unknown", "Coverage: unknown"),
                                  symbolName: "sparkles.square.filled.on.square") {
            VStack(alignment: .leading, spacing: Space.gap) {
                if let roi = summary?.skillsROI {
                    observationSummary(roi.metadata); healthPills(roi.diagnostics)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.gap / 2) {
                            ForEach(SkillsRoiLens.allCases) { option in
                                Button(option.title) { lens = option }
                                    .buttonStyle(.bordered).controlSize(.small)
                                    .tint(lens == option ? theme.primary.primary : theme.neutrals.text(.body))
                                    .frame(minWidth: 28, minHeight: 28).accessibilityAddTraits(lens == option ? .isSelected : [])
                                    .captureDashboardGeometry(id: "skills-lens-\(option.id)", role: "button")
                            }
                        }
                    }
                    if roi.metadata.coverage == "error" {
                        Label(skillsText("error_state", "Source error · retained observations are not current health"), systemImage: "exclamationmark.triangle").foregroundStyle(theme.dangerOnSubtle)
                    } else if roi.metadata.coverage == "partial" {
                        Label(skillsText("loading_state", "Collecting observations · incomplete coverage"), systemImage: "hourglass").foregroundStyle(theme.warningOnSubtle)
                    }
                    switch lens {
                    case .usage: usage(roi)
                    case .evolution: evolutionWorkbench(roi)
                    case .disclosure: disclosure(roi.diagnostics)
                    case .context: context(roi.diagnostics)
                    }
                } else {
                    Label(skillsText("missing", "Unknown / missing · no Skills observations yet"), systemImage: "questionmark.circle").foregroundStyle(theme.neutrals.text(.body))
                }
            }
        }
        .popover(isPresented: $showingEvidence) { evidenceDrawer }
    }

    private func observationSummary(_ metadata: SkillsObservationMetadata) -> some View {
        HStack(alignment: .top, spacing: Space.gap) {
            Text(metadataLine(metadata)).font(.caption).foregroundStyle(theme.neutrals.text(.body)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            infoButton([.init(title: skillsText("observation", "Observation"), value: coverage(metadata.coverage), metadata: metadata)], id: "report")
        }
    }

    private func healthPills(_ d: SkillsRoiDiagnostics) -> some View {
        DashboardResponsiveGrid(wideColumns: 4, compactColumns: 2) {
            healthPill("pins", title: skillsText("pins", "共享底座版本同步"), value: pinText(d.pins), detail: skillsText("inspected", "Inspected") + " · " + number(d.pins?.metadata.sample),
                       facts: [fact(skillsText("behind", "Pins behind"), d.pins?.behind), fact(skillsText("synchronized", "Synchronized"), d.pins?.synchronized)])
            healthPill("gates", title: skillsText("gates", "CI 门禁拦截与噪音"), value: rate(d.gates?.catchRate) + " / " + rate(d.gates?.noiseRate), detail: skillsText("runs", "Runs") + " · " + integer(d.gates?.runs),
                       facts: [fact(skillsText("catch", "Catch ratio"), d.gates?.catchRate), fact(skillsText("noise", "Noise ratio"), d.gates?.noiseRate), fact(skillsText("runs", "Runs"), d.gates?.runs)])
            healthPill("audit", title: skillsText("audit", "契约审计与回归用例"), value: integer(d.audit?.passed) + " / " + integer(d.audit?.total), detail: skillsText("evals", "Evals") + " " + integer(d.audit?.evals) + " (+" + integer(d.audit?.evalDelta) + ")",
                       facts: [fact(skillsText("passed", "Audit passes"), d.audit?.passed), fact(skillsText("total", "Skills inspected"), d.audit?.total), fact(skillsText("evals", "Evals"), d.audit?.evals), fact(skillsText("eval_delta", "Weekly Eval change"), d.audit?.evalDelta)])
            healthPill("cache", title: skillsText("cache", "KV 缓存命中"), value: percent(d.context?.cacheHitPercent), detail: skillsText("saved", "Saved") + " · " + decimal(d.context?.savedTokens) + " tok",
                       facts: [fact(skillsText("cache_hit", "KV hit (%)"), d.context?.cacheHitPercent), fact(skillsText("saved", "Saved tokens"), d.context?.savedTokens)])
        }.captureDashboardGeometry(id: "skills-health", role: "skillsHealthGrid")
    }

    private func pinText(_ pins: SkillsPinHealth?) -> String {
        guard let pins, pins.behind.metadata.hasSamples, let behind = pins.behind.value else { return unknown }
        if behind > 0 { return "\(behind) " + skillsText("behind", "Pins behind") }
        guard pins.synchronized.value == true, pins.synchronized.metadata.hasSamples else { return unknown }
        return skillsText("in_sync", "Synchronized")
    }

    private func healthPill(_ id: String, title: String, value: String, detail: String, facts: [SkillsEvidence?]) -> some View {
        Button { show(facts) } label: {
            VStack(alignment: .leading, spacing: Space.gap / 2) {
                HStack { Text(title).font(.caption.weight(.semibold)); Spacer(minLength: 0); Image(systemName: "info.circle") }
                Text(value).font(.headline.monospacedDigit()).fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.caption).fixedSize(horizontal: false, vertical: true)
                if facts.compactMap({ $0 }).contains(where: { $0.metadata.estimated == true }) { Text(skillsText("estimated", "Estimated")).font(.caption2).foregroundStyle(theme.warningOnSubtle) }
            }
            .padding(Space.gap).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: Radius.card))
        }.buttonStyle(.plain).frame(minHeight: 28).captureDashboardGeometry(id: "skills-\(id)", role: "skillsHealthPill")
    }

    public static func activeSkillRow(in diagnostics: SkillsRoiDiagnostics, selectedSkill: String?) -> SkillsUsageRow? {
        diagnostics.usageRows.first { $0.skill == selectedSkill } ?? diagnostics.usageRows.first
    }

    public static func activeSkillDetail(
        in report: SkillsRoiReport,
        selectedSkill: String?,
        filter: SkillInspectorFilter = .all
    ) -> SkillInspectorDetail? {
        let filtered = report.skillDetails.filter { filter.matches($0) }
        let nonGhostFallback = report.skillDetails.filter { !$0.isGhost }
        let pool = !filtered.isEmpty ? filtered : (!nonGhostFallback.isEmpty ? nonGhostFallback : report.skillDetails)
        return pool.first { $0.skill == selectedSkill } ?? pool.first
    }

    private func usage(_ roi: SkillsRoiReport) -> some View {
        let allDetails = roi.skillDetails
        let filtered = allDetails.filter { inspectorFilter.matches($0) }
        let activeDetail = Self.activeSkillDetail(in: roi, selectedSkill: selectedSkill, filter: inspectorFilter)
        return VStack(alignment: .leading, spacing: Space.gap) {
            Text(skillsText("usage_title", "Skill use, ROI and practice")).font(.headline)
            if let active = roi.diagnostics.usage {
                Text(activeSummary(active)).font(.caption).foregroundStyle(theme.neutrals.text(.body))
            }
            fourLayerPulseStrip(roi.resolvedSkillRetro)
            versionEvolutionTableSection(roi: roi, selectedSkill: activeDetail?.skill)
            retroProposalsSection(roi.resolvedSkillRetro)
            filterPillsBar(allDetails: allDetails)
            if allDetails.isEmpty {
                missingPopulation
            } else {
                SkillsPrimaryDetailSplitLayout {
                    primarySkillListPane(filtered: filtered, selected: activeDetail?.skill)
                    inspectorDetailPane(detail: activeDetail, roi: roi)
                }
                .captureDashboardGeometry(id: "skills-primary-detail", role: "skillsWorkbench")
            }
            dailyObservations(roi.skillsDaily)
        }
    }

    private func evolutionWorkbench(_ roi: SkillsRoiReport) -> some View {
        let activeDetail = Self.activeSkillDetail(in: roi, selectedSkill: selectedSkill, filter: inspectorFilter)
        return VStack(alignment: .leading, spacing: Space.gap) {
            fourLayerPulseStrip(roi.resolvedSkillRetro)
            versionEvolutionTableSection(roi: roi, selectedSkill: activeDetail?.skill)
            retroProposalsSection(roi.resolvedSkillRetro)
            if let activeDetail {
                inspectorDetailPane(detail: activeDetail, roi: roi)
            }
        }
    }

    @ViewBuilder
    private func fourLayerPulseStrip(_ retro: SkillRetroFourLayerSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(skillsText("four_layer_pulse_title", "L0–L3 四层自演进健康度脉冲条")).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(retro.slowFlywheelReady
                     ? skillsText("flywheel_slow_ready", "慢飞轮就绪 · 样本 \(retro.sampleSize)")
                     : skillsText("flywheel_fast_scoped", "快飞轮收敛中 · 样本 \(retro.sampleSize)"))
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .foregroundStyle(retro.slowFlywheelReady ? theme.successOnSubtle : theme.primary.onPrimarySubtle)
                    .background((retro.slowFlywheelReady ? theme.success : theme.primary.primary).opacity(0.14), in: Capsule())
            }
            DashboardResponsiveGrid(wideColumns: 4, compactColumns: 2, spacing: 8) {
                retroPulseTile(
                    id: "l0-direction",
                    layerTag: "L0",
                    title: skillsText("pulse_l0_title", "L0 触发与方向"),
                    headline: "漏触发 \(retro.triggerMissSkills) · 零动作 \(retro.zeroActionLoadSkills)",
                    subtitle: "方向漂移 \(retro.directionalDrifts) 次",
                    isWarning: retro.triggerMissSkills > 0 || retro.directionalDrifts > 0
                )
                retroPulseTile(
                    id: "l1-drawers",
                    layerTag: "L1",
                    title: skillsText("pulse_l1_title", "L1 知识抽屉代谢"),
                    headline: "未接线 \(retro.unwiredDrawersCount) · 30d 死木 \(retro.trueDeadwoodDrawersCount)",
                    subtitle: "按需渐进披露与断连巡检",
                    isWarning: retro.unwiredDrawersCount > 0 || retro.trueDeadwoodDrawersCount > 0
                )
                retroPulseTile(
                    id: "l2-scripts",
                    layerTag: "L2",
                    title: skillsText("pulse_l2_title", "L2 脚本路障与耗时"),
                    headline: "真拦截 \(retro.trueCatcherScriptsCount) · 路障 \(retro.rigidRoadblockScriptsCount)",
                    subtitle: "exit=2 参数撞墙 \(retro.exit2RoadblockTotalCount) 次 · 慢脚本 \(retro.latencySinkScriptsCount)",
                    isWarning: retro.rigidRoadblockScriptsCount > 0 || retro.exit2RoadblockTotalCount > 0
                )
                retroPulseTile(
                    id: "l3-wild-eval",
                    layerTag: "L3",
                    title: skillsText("pulse_l3_title", "L3 野生模式与评测"),
                    headline: "高频探针 \(retro.wildPatternsCount) · 提案 \(retro.proposals.count)",
                    subtitle: retro.slowFlywheelReady ? "3 层评测门禁已激活" : "快飞轮局部防呆收敛",
                    isWarning: !retro.proposals.isEmpty
                )
            }
        }
        .padding(10)
        .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .captureDashboardGeometry(id: "skills-four-layer-pulse", role: "skillsRetroPulse")
    }

    private func retroPulseTile(
        id: String,
        layerTag: String,
        title: String,
        headline: String,
        subtitle: String,
        isWarning: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(layerTag)
                    .font(.caption2.monospaced().weight(.bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .foregroundStyle(isWarning ? theme.warningOnSubtle : theme.successOnSubtle)
                    .background((isWarning ? theme.warning : theme.success).opacity(0.16), in: Capsule())
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(headline)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(theme.neutrals.text(.heading))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(theme.neutrals.text(.meta))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .captureDashboardGeometry(id: "skills-pulse-\(id)", role: "skillsRetroPulseTile")
    }

    @ViewBuilder
    private func versionEvolutionTableSection(roi: SkillsRoiReport, selectedSkill: String?) -> some View {
        let rows = roi.versionEvolution
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(skillsText("version_evolution_title", "单技能 vN-1 → vN 演进成效对比表")).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(skillsText("version_evolution_subtitle", "参数路障率 (exit=2) · 断链抽屉 · 脚本 P50 耗时 · 规则吸收 / 一次通过率"))
                    .font(.caption2)
                    .foregroundStyle(theme.neutrals.text(.meta))
                    .lineLimit(1)
            }
            if rows.isEmpty {
                Text(skillsText("version_evolution_empty", "暂无单技能版本演进对比样本"))
                    .font(.caption)
                    .foregroundStyle(theme.neutrals.text(.meta))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows.prefix(12)) { row in
                        versionEvolutionRowView(row, isSelected: row.skill == selectedSkill)
                    }
                }
            }
        }
        .padding(10)
        .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .captureDashboardGeometry(id: "skills-version-evolution-table", role: "skillsEvolutionTable")
    }

    private func versionEvolutionRowView(_ row: SkillVersionEvolutionRow, isSelected: Bool) -> some View {
        Button {
            selectedSkill = row.skill
            inspectorFilter = .all
            previewRelativePath = nil
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.skill)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.neutrals.text(.heading))
                        .lineLimit(1)
                    Text(row.versionTransitionLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.neutrals.text(.meta))
                        .lineLimit(1)
                    evolutionStatusBadge(row)
                    Spacer(minLength: 4)
                    Text("会话 \(row.beforeVersion?.sessions ?? 0) → \(row.currentVersion.sessions)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.neutrals.text(.meta))
                        .layoutPriority(1)
                }
                DashboardResponsiveGrid(wideColumns: 4, compactColumns: 2, spacing: 6) {
                    evolutionMetricCell(
                        label: skillsText("evo_col_exit2", "参数路障 (exit=2)"),
                        value: Self.formatVersionComparison(
                            before: row.beforeVersion?.exit2ErrorRate,
                            current: row.currentVersion.exit2ErrorRate,
                            delta: row.delta.exit2ErrorRateDelta,
                            isRate: true,
                            lowerIsBetter: true
                        )
                    )
                    evolutionMetricCell(
                        label: skillsText("evo_col_drawers", "断链抽屉数"),
                        value: Self.formatCountComparison(
                            before: row.beforeVersion?.brokenDrawerCount,
                            current: row.currentVersion.brokenDrawerCount,
                            delta: row.delta.brokenDrawerDelta
                        )
                    )
                    evolutionMetricCell(
                        label: skillsText("evo_col_p50", "脚本 P50 耗时"),
                        value: Self.formatLatencyComparison(
                            beforeMs: row.beforeVersion?.scriptP50Ms,
                            currentMs: row.currentVersion.scriptP50Ms,
                            deltaMs: row.delta.scriptP50MsDelta
                        )
                    )
                    evolutionMetricCell(
                        label: skillsText("evo_col_uptake_r1", "规则吸收 / 一次通过"),
                        value: Self.formatUptakeAndR1Comparison(row: row)
                    )
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.primary.primary.opacity(0.14) : theme.neutrals.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? theme.primary.primary.opacity(0.55) : theme.neutrals.border.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .captureDashboardGeometry(id: "skills-evo-row-\(row.skill)", role: "skillsEvolutionRow")
    }

    private func evolutionMetricCell(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(theme.neutrals.text(.meta)).lineLimit(1)
            Spacer(minLength: 4)
            Text(value).font(.caption2.monospacedDigit().weight(.medium)).foregroundStyle(theme.neutrals.text(.heading)).lineLimit(1).layoutPriority(1)
        }
    }

    private func evolutionStatusBadge(_ row: SkillVersionEvolutionRow) -> some View {
        let (fg, bg): (Color, Color) = {
            switch row.status {
            case "improved": return (theme.successOnSubtle, theme.success.opacity(0.15))
            case "regressed": return (theme.dangerOnSubtle, theme.danger.opacity(0.15))
            case "observing": return (theme.warningOnSubtle, theme.warning.opacity(0.15))
            default: return (theme.neutrals.text(.meta), theme.neutrals.inner)
            }
        }()
        return Text(row.resolvedStatusLabel)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
    }

    @ViewBuilder
    private func retroProposalsSection(_ retro: SkillRetroFourLayerSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(skillsText("retro_proposals_title", "今日高信号待演进提案卡")).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text("\(retro.proposals.count) 项待办")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(theme.neutrals.text(.meta))
            }
            if retro.proposals.isEmpty {
                Text(skillsText("retro_proposals_empty", "当前周期无高信号待演进提案 · 各技能运行平稳"))
                    .font(.caption)
                    .foregroundStyle(theme.neutrals.text(.meta))
            } else {
                ForEach(retro.proposals.prefix(6)) { proposal in
                    retroProposalCardRow(proposal)
                }
            }
        }
        .padding(10)
        .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .captureDashboardGeometry(id: "skills-retro-proposals", role: "skillsRetroProposals")
    }

    private func retroProposalCardRow(_ proposal: SkillRetroProposalItem) -> some View {
        let cmd = proposal.primaryRemediationCommand
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("[\(proposal.layer)]")
                    .font(.caption2.monospaced().weight(.bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .foregroundStyle(theme.primary.onPrimarySubtle)
                    .background(theme.primary.primary.opacity(0.14), in: Capsule())
                Text(proposal.priority)
                    .font(.caption2.monospaced().weight(.bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .foregroundStyle(proposal.priority == "P0" || proposal.priority == "P1" ? theme.warningOnSubtle : theme.neutrals.text(.meta))
                    .background((proposal.priority == "P0" || proposal.priority == "P1" ? theme.warning : theme.neutrals.border).opacity(0.16), in: Capsule())
                Button {
                    selectedSkill = proposal.skill
                    inspectorFilter = .all
                } label: {
                    Text("\(proposal.skill) — \(proposal.displayTitle)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.neutrals.text(.heading))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 6)
                Button(skillsText("copy_remediation_cmd", "复制演进命令")) {
                    copyToPasteboard(cmd)
                }
                .buttonStyle(.bordered).controlSize(.mini)
                .frame(minWidth: 28, minHeight: 24)
                .captureDashboardGeometry(id: "proposal-copy-\(proposal.id)", role: "button")
            }
            Text(proposal.displayReason)
                .font(.caption2)
                .foregroundStyle(theme.neutrals.text(.body))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .captureDashboardGeometry(id: "skills-proposal-\(proposal.id)", role: "skillsProposalRow")
    }

    public static func formatVersionComparison(
        before: Double?,
        current: Double?,
        delta: Double?,
        isRate: Bool = true,
        lowerIsBetter: Bool = false
    ) -> String {
        func fmt(_ v: Double?) -> String {
            guard let v else { return "—" }
            if isRate {
                return (v * 100).formatted(.number.precision(.fractionLength(0...1))) + "%"
            }
            return v.formatted(.number.precision(.fractionLength(0...1)))
        }
        let arrow: String = {
            guard let d = delta, abs(d) > 0.0001 else { return "" }
            let improved = lowerIsBetter ? (d < 0) : (d > 0)
            return improved ? " ▼" : " ▲"
        }()
        return "\(fmt(before)) → \(fmt(current))\(arrow)"
    }

    public static func formatCountComparison(before: Int?, current: Int, delta: Int?) -> String {
        let befText = before.map(String.init) ?? "—"
        let suffix: String = {
            guard let d = delta, d != 0 else { return "" }
            return d < 0 ? " (\(d))" : " (+\(d))"
        }()
        return "\(befText) → \(current)\(suffix)"
    }

    public static func formatLatencyComparison(beforeMs: Double?, currentMs: Double?, deltaMs: Double?) -> String {
        func fmt(_ ms: Double?) -> String {
            guard let ms else { return "—" }
            if ms >= 1000 {
                return (ms / 1000.0).formatted(.number.precision(.fractionLength(0...1))) + "s"
            }
            return ms.formatted(.number.precision(.fractionLength(0...0))) + "ms"
        }
        let suffix: String = {
            guard let d = deltaMs, abs(d) >= 1 else { return "" }
            return d < 0 ? " ▼" : " ▲"
        }()
        return "\(fmt(beforeMs)) → \(fmt(currentMs))\(suffix)"
    }

    public static func formatUptakeAndR1Comparison(row: SkillVersionEvolutionRow) -> String {
        let uptakeCur = row.currentVersion.uptakeRate.map { ($0 * 100).formatted(.number.precision(.fractionLength(0...0))) + "%" } ?? "—"
        let r1Bef = row.beforeVersion?.r1PassRate.map { ($0 * 100).formatted(.number.precision(.fractionLength(0...0))) + "%" } ?? "—"
        let r1Cur = row.currentVersion.r1PassRate.map { ($0 * 100).formatted(.number.precision(.fractionLength(0...0))) + "%" } ?? "—"
        return "吸收 \(uptakeCur) · R1 \(r1Bef)→\(r1Cur)"
    }

    private func filterPillsBar(allDetails: [SkillInspectorDetail]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.gap / 2) {
                ForEach(SkillInspectorFilter.allCases) { option in
                    let count = allDetails.filter { option.matches($0) }.count
                    Button("\(option.title) (\(count))") {
                        inspectorFilter = option
                        previewRelativePath = nil
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .tint(inspectorFilter == option ? theme.primary.primary : theme.neutrals.text(.body))
                    .frame(minWidth: 28, minHeight: 28)
                    .accessibilityAddTraits(inspectorFilter == option ? .isSelected : [])
                    .captureDashboardGeometry(id: "skills-filter-\(option.id)", role: "button")
                }
            }
        }
    }

    public static func shellQuotedSingleArgument(_ raw: String) -> String {
        let stripped = raw.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "'" + stripped.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func evalCommandString(forSkill skill: String) -> String {
        "python3 ~/Development/user-skills/skills/skill-contract/scripts/skill_contract.py eval --skill \(shellQuotedSingleArgument(skill)) --strict"
    }

    private func primarySkillListPane(filtered: [SkillInspectorDetail], selected: String?) -> some View {
        let visibleItems = showAllDirectorySkills ? filtered : Array(filtered.prefix(18))
        return VStack(alignment: .leading, spacing: 6) {
            Text(skillsText("directory_list_title", "Skill Directory")).font(.caption.weight(.semibold)).foregroundStyle(theme.neutrals.text(.meta))
            if filtered.isEmpty {
                Text(skillsText("filter_empty", "No matching skills in this filter")).font(.caption).foregroundStyle(theme.neutrals.text(.body)).padding(.vertical, 8)
            } else {
                ForEach(visibleItems) { item in
                    primarySkillRow(item, isSelected: item.skill == selected)
                }
                if filtered.count > 18 {
                    Button(showAllDirectorySkills ? skillsText("collapse_directory", "Collapse") : "\(skillsText("filter_all", "All")) (\(filtered.count))") {
                        showAllDirectorySkills.toggle()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .frame(minWidth: 28, minHeight: 28)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .captureDashboardGeometry(id: "skills-primary-list", role: "skillsPrimaryPane")
    }

    private func primarySkillRow(_ item: SkillInspectorDetail, isSelected: Bool) -> some View {
        Button {
            selectedSkill = item.skill
            previewRelativePath = nil
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.skill).font(.caption.weight(.semibold)).foregroundStyle(theme.neutrals.text(.heading)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.roiScore.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? unknown)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(theme.neutrals.text(.heading))
                        .layoutPriority(1)
                }
                HStack(spacing: 6) {
                    scopeBadge(item)
                    statusBadge(item)
                    Spacer(minLength: 4)
                    Text("\(item.loads7d) / \(item.loads30d)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.neutrals.text(.meta))
                        .layoutPriority(1)
                }
                HStack(spacing: 6) {
                    Text(primaryRowMetricsSubtitle(item))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(theme.neutrals.text(.meta))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(isSelected ? theme.primary.primary.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? theme.primary.primary.opacity(0.55) : theme.neutrals.border.opacity(0.5), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .captureDashboardGeometry(id: "primary-skill-\(item.skill)", role: "skillsPrimaryRow")
    }

    private func primaryRowMetricsSubtitle(_ item: SkillInspectorDetail) -> String {
        var segments: [String] = []
        if let kb = item.bundleKb {
            segments.append("\(formatDecimal(kb, digits: 1)) KB")
        }
        segments.append("\(skillsText("r1_short", "Pass")) \(formatRatio(item.r1PassRate))")
        if !item.scripts.isEmpty {
            segments.append("\(skillsText("unpracticed", "Unpracticed")) \(formatRatio(item.unpracticedRate))")
        }
        return segments.joined(separator: " · ")
    }

    private func scopeBadge(_ item: SkillInspectorDetail) -> some View {
        let label = item.scope == "repo_bound"
            ? skillsText("scope_repo_bound", "Repo-Bound") + " (\(item.repo))"
            : skillsText("scope_global", "Global")
        return Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(item.scope == "repo_bound" ? theme.warningOnSubtle : theme.primary.onPrimarySubtle)
            .background((item.scope == "repo_bound" ? theme.warning : theme.primary.primary).opacity(0.14), in: Capsule())
    }

    private func statusBadge(_ item: SkillInspectorDetail) -> some View {
        let (label, fg, bg): (String, Color, Color) = {
            if item.isGhost || item.statusLabel == "ghost" {
                return (skillsText("health_ghost", "Archived Ghost"), theme.neutrals.text(.meta), theme.neutrals.card)
            }
            if item.loads30d == 0 || item.statusLabel == "zombie_30d" {
                return (skillsText("health_zombie", "30d Idle"), theme.neutrals.text(.meta), theme.neutrals.card)
            }
            if item.statusLabel == "needs_optimization" || item.implBugEscapes > 0 || item.specGapEscapes > 0 {
                return (skillsText("health_optimize", "Needs Optimization"), theme.warningOnSubtle, theme.warning.opacity(0.14))
            }
            return (skillsText("health_healthy", "Active"), theme.successOnSubtle, theme.success.opacity(0.14))
        }()
        return Text(label).font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(fg).background(bg, in: Capsule())
    }

    private func inspectorDetailPane(detail: SkillInspectorDetail?, roi: SkillsRoiReport) -> some View {
        let diagnostics = roi.diagnostics
        let evoRow = roi.versionEvolution.first { $0.skill == detail?.skill }
        return VStack(alignment: .leading, spacing: 12) {
            if let detail {
                inspectorHeaderCard(detail, diagnostics: diagnostics, evolutionRow: evoRow)
                inspectorSubTabBar(detail, evolutionRow: evoRow)
                switch inspectorSubTab {
                case .definition: inspectorDefinitionTreeSection(detail)
                case .scripts: inspectorScriptsLedgerSection(detail)
                case .evals: inspectorEvalCasesSection(detail)
                case .evolution: inspectorVersionEvolutionSection(detail: detail, evolutionRow: evoRow)
                }
            } else {
                missingPopulation
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.neutrals.border, lineWidth: 1) }
        .captureDashboardGeometry(id: "skills-inspector-detail", role: "skillsInspectorPane")
    }

    private func inspectorHeaderCard(
        _ detail: SkillInspectorDetail,
        diagnostics: SkillsRoiDiagnostics,
        evolutionRow: SkillVersionEvolutionRow? = nil
    ) -> some View {
        let diagRow = diagnostics.usageRows.first { $0.skill == detail.skill }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(detail.skill).font(.headline)
                        scopeBadge(detail)
                        statusBadge(detail)
                        if let evolutionRow {
                            evolutionStatusBadge(evolutionRow)
                        }
                    }
                    Text(diagRow?.diagnosis ?? detail.skillDir)
                        .font(.caption)
                        .foregroundStyle(theme.neutrals.text(.body))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Button(skillsText("copy_path", "Copy Path")) {
                        copyToPasteboard("\(detail.skillDir)/\(detail.skillMdPath)")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .frame(minWidth: 28, minHeight: 28)
                    .captureDashboardGeometry(id: "inspector-copy-path", role: "button")

                    Button(skillsText("copy_eval_cmd", "Copy Eval Command")) {
                        copyToPasteboard(Self.evalCommandString(forSkill: detail.skill))
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .frame(minWidth: 28, minHeight: 28)
                    .captureDashboardGeometry(id: "inspector-copy-eval", role: "button")
                }
            }
            if let feedback = copiedFeedback {
                Text(feedback).font(.caption2).foregroundStyle(theme.successOnSubtle)
            }
            if let evolutionRow {
                inspectorVersionEvolutionBanner(evolutionRow)
            }
            DashboardResponsiveGrid(wideColumns: 3, compactColumns: 2, spacing: 8) {
                skillsOverviewPane(0, title: skillsText("header_calls_channels", "Calls & Channels")) {
                    metricPair(skillsText("loads_7d_30d", "7d / 30d"), "\(detail.loads7d) / \(detail.loads30d)")
                    metricPair(skillsText("unpracticed_rate", "Unpracticed rate"), formatRatio(detail.unpracticedRate))
                    metricPair(skillsText("empty_load_rate", "Empty-load rate"), formatRatio(detail.emptyLoadRate))
                    metricPair(skillsText("channels_summary", "Channels (30d)"), channelSummary(detail.sourceBreakdown))
                }
                skillsOverviewPane(1, title: skillsText("header_roi_context", "ROI & Context")) {
                    metricPair(skillsText("roi_score", "ROI"), formatDecimal(detail.roiScore, digits: 2))
                    metricPair(skillsText("r1_pass_rate", "R1 pass rate"), formatRatio(detail.r1PassRate))
                    metricPair(skillsText("bundle_size", "Bundle size"), formatBundleSize(detail))
                    metricPair(skillsText("avg_context_tokens", "Average context tokens"), formatTokens(detail.avgContextTokens))
                    metricPair(skillsText("kv_cache", "KV Cache"), detail.kvCacheHitPct.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? unknown)
                }
                skillsOverviewPane(2, title: skillsText("header_churn_escapes", "Churn & Gate Signals")) {
                    metricPair(skillsText("unhit_refs", "0-Hit references"), formatUnhitReferences(detail))
                    metricPair(skillsText("churn", "Edit / retry churn"), "\(detail.editChurn) / \(detail.retryChurn)")
                    metricPair(skillsText("interceptions_30d", "Gate interceptions"), "\(detail.evalInterceptions)")
                    metricPair(skillsText("escape_attribution", "IMPL_BUG / SPEC_GAP"), "\(detail.implBugEscapes) / \(detail.specGapEscapes)")
                }
            }
        }
    }

    private func inspectorVersionEvolutionBanner(_ row: SkillVersionEvolutionRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(skillsText("inspector_evo_banner_title", "单技能版本演进对比"))
                    .font(.caption.weight(.semibold))
                Text(row.versionTransitionLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.neutrals.text(.meta))
                Spacer(minLength: 4)
                Text("升级后参数撞墙 \(row.delta.postFixErrors) 次")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(row.delta.postFixErrors > 0 ? theme.dangerOnSubtle : theme.successOnSubtle)
            }
            DashboardResponsiveGrid(wideColumns: 4, compactColumns: 2, spacing: 6) {
                evolutionMetricCell(
                    label: "参数路障率",
                    value: Self.formatVersionComparison(
                        before: row.beforeVersion?.exit2ErrorRate,
                        current: row.currentVersion.exit2ErrorRate,
                        delta: row.delta.exit2ErrorRateDelta,
                        isRate: true,
                        lowerIsBetter: true
                    )
                )
                evolutionMetricCell(
                    label: "断链抽屉",
                    value: Self.formatCountComparison(
                        before: row.beforeVersion?.brokenDrawerCount,
                        current: row.currentVersion.brokenDrawerCount,
                        delta: row.delta.brokenDrawerDelta
                    )
                )
                evolutionMetricCell(
                    label: "脚本 P50 耗时",
                    value: Self.formatLatencyComparison(
                        beforeMs: row.beforeVersion?.scriptP50Ms,
                        currentMs: row.currentVersion.scriptP50Ms,
                        deltaMs: row.delta.scriptP50MsDelta
                    )
                )
                evolutionMetricCell(
                    label: "吸收 / 一次通过",
                    value: Self.formatUptakeAndR1Comparison(row: row)
                )
            }
        }
        .padding(8)
        .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .captureDashboardGeometry(id: "inspector-evo-banner-\(row.skill)", role: "skillsInspectorEvolutionCard")
    }

    private func inspectorSubTabBar(_ detail: SkillInspectorDetail, evolutionRow: SkillVersionEvolutionRow?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SkillInspectorSubTab.allCases) { tab in
                    let badge: String = {
                        switch tab {
                        case .definition: return "\(detail.references.count + 1)"
                        case .scripts: return "\(detail.scripts.count)"
                        case .evals: return "\(detail.evalCases.count)"
                        case .evolution: return "\(evolutionRow?.versions.count ?? (evolutionRow != nil ? 1 : 0))"
                        }
                    }()
                    Button("\(tab.title) (\(badge))") { inspectorSubTab = tab }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tint(inspectorSubTab == tab ? theme.primary.primary : theme.neutrals.text(.body))
                        .frame(minWidth: 28, minHeight: 28)
                        .accessibilityAddTraits(inspectorSubTab == tab ? .isSelected : [])
                        .captureDashboardGeometry(id: "inspector-tab-\(tab.id)", role: "button")
                }
            }
        }
    }

    private func inspectorVersionEvolutionSection(
        detail: SkillInspectorDetail,
        evolutionRow: SkillVersionEvolutionRow?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(skillsText("inspector_evo_section_title", "历史版本链与 vN-1 → vN 归因明细")).font(.subheadline.weight(.semibold))
            if let row = evolutionRow {
                ForEach(row.versions.isEmpty ? [row.currentVersion] : row.versions) { ver in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ver.combinedVersion)
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(theme.neutrals.text(.heading))
                        Spacer(minLength: 4)
                        Text("会话 \(ver.sessions) · 脚本 \(ver.scriptCallCount) · exit=2 \(ver.exit2Count) · 断链 \(ver.brokenDrawerCount) · P50 \(Self.formatLatencyComparison(beforeMs: nil, currentMs: ver.scriptP50Ms, deltaMs: nil).replacingOccurrences(of: "— → ", with: ""))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(theme.neutrals.text(.meta))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .captureDashboardGeometry(id: "inspector-ver-\(detail.skill)-\(ver.skillVersion)", role: "skillsVersionHistoryRow")
                }
            } else {
                Text(skillsText("no_evolution_history", "当前技能暂无历史版本对比快照"))
                    .font(.caption)
                    .foregroundStyle(theme.neutrals.text(.body))
            }
        }
    }

    private func inspectorDefinitionTreeSection(_ detail: SkillInspectorDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(skillsText("definition_section_title", "Definition & Progressive Disclosure Tree")).font(.subheadline.weight(.semibold))
            definitionFileRow(
                id: "skill-md",
                title: detail.skillMdPath,
                subtitle: skillsText("frontmatter_budget", "Frontmatter") + " ~\(detail.frontmatterTokensEst) tok · \(detail.skillMdLines) " + skillsText("lines_unit", "lines") + " (~\(detail.bodyTokensEst) tok)",
                badgeText: "L0",
                isWarning: detail.skillMdLines > 180,
                relativePath: detail.skillMdPath
            )
            if detail.references.isEmpty {
                Text(skillsText("no_references", "No physical references/ files in this skill bundle"))
                    .font(.caption).foregroundStyle(theme.neutrals.text(.body))
            } else {
                ForEach(detail.references) { ref in
                    let hitLabel = ref.hits30d.map { "\($0) " + skillsText("hits_unit", "hits") } ?? unknown
                    let sessLabel = ref.sessions30d.map { "\($0) " + skillsText("sessions_unit", "sessions") } ?? unknown
                    definitionFileRow(
                        id: "ref-\(ref.relPath)",
                        title: ref.relPath,
                        subtitle: "\(ref.lineCount) " + skillsText("lines_unit", "lines") + " · ~\(ref.tokensEst) tok · \(sessLabel)",
                        badgeText: ref.isUnhit ? skillsText("zero_hits_badge", "0 hits") : hitLabel,
                        isWarning: ref.isUnhit,
                        relativePath: ref.relPath
                    )
                }
            }
            if let relPath = previewRelativePath {
                inlineDocumentPreviewBox(detail: detail, relativePath: relPath)
            }
        }
    }

    private func definitionFileRow(id: String, title: String, subtitle: String, badgeText: String, isWarning: Bool, relativePath: String) -> some View {
        let isOpen = previewRelativePath == relativePath
        return Button {
            previewRelativePath = isOpen ? nil : relativePath
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: isOpen ? "doc.text.magnifyingglass" : "doc.text")
                    .foregroundStyle(theme.primary.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(theme.neutrals.text(.heading))
                    Text(subtitle).font(.caption2.monospacedDigit()).foregroundStyle(theme.neutrals.text(.meta))
                }
                Spacer(minLength: 6)
                Text(badgeText)
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .foregroundStyle(isWarning ? theme.warningOnSubtle : theme.primary.onPrimarySubtle)
                    .background((isWarning ? theme.warning : theme.primary.primary).opacity(0.14), in: Capsule())
                    .layoutPriority(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .captureDashboardGeometry(id: "inspector-file-\(id)", role: "skillsFileRow")
    }

    private func inlineDocumentPreviewBox(detail: SkillInspectorDetail, relativePath: String) -> some View {
        let embeddedPreview = relativePath == detail.skillMdPath
            ? detail.docPreview
            : detail.references.first(where: { $0.relPath == relativePath })?.docPreview
        let content = Self.resolveSkillPreviewContent(
            detail: detail,
            relativePath: relativePath,
            embeddedPreview: embeddedPreview,
            homeURL: previewHomeURL
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(detail.skill)/\(relativePath)").font(.caption.weight(.semibold))
                Spacer()
                Button(skillsText("close_preview", "Close Preview")) { previewRelativePath = nil }
                    .buttonStyle(.bordered).controlSize(.mini)
                    .frame(minWidth: 28, minHeight: 24)
            }
            if let content, !content.isEmpty {
                ScrollView(.vertical) {
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.neutrals.text(.body))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .captureDashboardGeometry(id: "inspector-doc-preview-content:\(relativePath)", role: "skillsPreviewContent")
                }
                .frame(maxHeight: 220)
            } else {
                Text(skillsText("preview_unavailable", "Read-only preview unavailable outside local skill whitelist or missing on disk"))
                    .font(.caption)
                    .foregroundStyle(theme.neutrals.text(.meta))
            }
        }
        .padding(10)
        .background(theme.neutrals.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.neutrals.border, lineWidth: 1) }
        .captureDashboardGeometry(id: "inspector-doc-preview", role: "skillsPreviewBox")
    }

    public static func resolveSkillPreviewContent(
        detail: SkillInspectorDetail,
        relativePath: String,
        embeddedPreview: String? = nil,
        homeURL: URL? = nil
    ) -> String? {
        if detail.skillDir.contains("/Mobile Documents/com~apple~CloudDocs")
            || relativePath.contains("/Mobile Documents/com~apple~CloudDocs") {
            let fallback = (embeddedPreview ?? detail.docPreview)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return fallback.isEmpty ? nil : fallback
        }
        return LiveDashboardTelemetryReader.loadSkillDocumentPreview(
            skillDir: detail.skillDir,
            relativePath: relativePath,
            skillSlug: detail.skill,
            embeddedPreview: embeddedPreview,
            homeURL: homeURL
        )
    }

    private func inspectorScriptsLedgerSection(_ detail: SkillInspectorDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(skillsText("scripts_section_title", "Deterministic Script Execution Ledger")).font(.subheadline.weight(.semibold))
            if detail.scripts.isEmpty {
                Text(skillsText("no_scripts", "No deterministic scripts configured in scripts/"))
                    .font(.caption).foregroundStyle(theme.neutrals.text(.body))
            } else {
                Grid(alignment: .leading, horizontalSpacing: Space.gap, verticalSpacing: 6) {
                    GridRow {
                        columnHeader(skillsText("script_col_path", "Script"), "script-path")
                        columnHeader(skillsText("script_col_calls", "30d Calls"), "script-calls")
                        columnHeader(skillsText("script_col_success", "Success"), "script-success")
                        columnHeader(skillsText("script_col_p95", "P95 (ms)"), "script-p95")
                    }
                    ForEach(detail.scripts) { sc in
                        GridRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sc.relPath).font(.caption.weight(.semibold))
                                if sc.isUnpracticed {
                                    Text(skillsText("unpracticed_badge", "Unpracticed (0 calls)"))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(theme.warningOnSubtle)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            tableValue(sc.calls30d.map(String.init) ?? unknown, detail.skill, "sc-calls-\(sc.relPath)")
                            tableValue(formatRatio(sc.successRate), detail.skill, "sc-succ-\(sc.relPath)")
                            tableValue(sc.p95Ms.map { $0.formatted(.number.precision(.fractionLength(0...0))) + " ms" } ?? unknown, detail.skill, "sc-p95-\(sc.relPath)")
                        }
                    }
                }
                .padding(8)
                .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func inspectorEvalCasesSection(_ detail: SkillInspectorDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(skillsText("evals_section_title", "Eval Cases & Gate Interceptions")).font(.subheadline.weight(.semibold))
            if detail.evalCases.isEmpty {
                Text(skillsText("no_eval_drawer", "No eval-cases.json drawer configured"))
                    .font(.caption).foregroundStyle(theme.neutrals.text(.body))
            } else {
                ForEach(detail.evalCases) { ev in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(ev.id).font(.caption.monospaced().weight(.bold))
                            Text(ev.kind.uppercased())
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .foregroundStyle(theme.primary.onPrimarySubtle)
                                .background(theme.primary.primary.opacity(0.14), in: Capsule())
                            Text(ev.title).font(.caption.weight(.medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(skillsText("intercept_short", "Caught") + " \(ev.interceptions30d) · " + skillsText("escape_short", "Escaped") + " \(ev.escapes30d)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(ev.escapes30d > 0 ? theme.dangerOnSubtle : theme.neutrals.text(.meta))
                                .layoutPriority(1)
                        }
                        if !ev.assertionSummary.isEmpty {
                            Text(ev.assertionSummary)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(theme.neutrals.text(.meta))
                                .lineLimit(2)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .captureDashboardGeometry(id: "inspector-eval-\(ev.id)", role: "skillsEvalRow")
                }
            }
        }
    }

    private func skillsOverviewPane<Content: View>(_ index: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.caption.weight(.semibold)); content() }
            .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .captureDashboardGeometry(id: "skills-overview-pane-\(index)", role: "skillsOverviewPane")
    }

    private func metricPair(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).font(.caption.monospacedDigit()).multilineTextAlignment(.trailing).layoutPriority(1)
        }
    }

    private func channelSummary(_ breakdown: [String: Int]) -> String {
        let ordered = [("claude", "Claude"), ("copilot", "Copilot"), ("codex", "Codex"), ("hermes", "Hermes"), ("gtt", "GTT")]
        let nonZero = ordered.compactMap { key, label -> String? in
            guard let count = breakdown[key], count > 0 else { return nil }
            return "\(label) \(count)"
        }
        return nonZero.isEmpty ? unknown : nonZero.joined(separator: " · ")
    }

    private func formatRatio(_ value: Double?) -> String {
        guard let value else { return unknown }
        return (value * 100).formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    private func formatDecimal(_ value: Double?, digits: Int = 1) -> String {
        guard let value else { return unknown }
        return value.formatted(.number.precision(.fractionLength(0...digits)))
    }

    private func formatTokens(_ value: Double?) -> String {
        guard let value else { return unknown }
        return value.formatted(.number.precision(.fractionLength(0...0))) + " tok"
    }

    private func formatBundleSize(_ detail: SkillInspectorDetail) -> String {
        let estTokens = Double(detail.frontmatterTokensEst + detail.bodyTokensEst + (detail.refsTokensEst ?? detail.references.reduce(0) { $0 + $1.tokensEst }))
        guard let kb = detail.bundleKb else {
            return estTokens > 0 ? "~\(formatTokens(estTokens))" : unknown
        }
        return "\(formatDecimal(kb, digits: 1)) KB (~\(formatTokens(estTokens)))"
    }

    private func formatUnhitReferences(_ detail: SkillInspectorDetail) -> String {
        guard !detail.references.isEmpty else { return "0 / 0" }
        let ratioLabel = formatRatio(detail.unhitRefsRatio ?? (Double(detail.unhitRefsCount) / Double(detail.references.count)))
        return "\(detail.unhitRefsCount) / \(detail.references.count) (\(ratioLabel))"
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        copiedFeedback = skillsText("copied_feedback", "Copied to clipboard")
    }

    private func activeSummary(_ population: SkillsUsagePopulation) -> String {
        let count = integer(population.active), idle = population.idle.isEmpty ? unknown : population.idle.joined(separator: ", ")
        return [skillsText("active", "Active skills"), count, skillsText("idle", "Idle (30d)"), idle].joined(separator: " · ")
    }

    private func dailyObservations(_ rows: [SkillsDailyObservation]) -> some View {
        Group {
            DisclosureGroup(skillsText("daily_title", "Daily populations · day / source / skill (not additive)"), isExpanded: $dailyExpanded) {
                VStack(alignment: .leading, spacing: Space.gap) {
                    Text(skillsText("daily_notice", "Attribution, tool and slash populations may overlap. No cross-source sum.")).font(.caption)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text("\(row.day) · \(row.source) · \(row.skill)").font(.caption); Spacer()
                            Text(number(row.count) + " / " + number(row.sessions)).font(.caption.monospacedDigit()).fixedSize()
                            infoButton([.init(title: skillsText("daily_population", "Calls / sessions"), value: number(row.count) + " / " + number(row.sessions), metadata: row.metadata)], id: "daily-\(row.day)-\(row.source)-\(row.skill)")
                        }
                    }
                    if rows.isEmpty { missingPopulation }
                }.padding(.top, Space.gap)
            }.font(.caption).frame(minHeight: 28)
        }
    }

    private func disclosure(_ d: SkillsRoiDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            Text(skillsText("funnel_title", "渐进披露漏斗 (L0 → L1)")).font(.headline)
            Text(skillsText("funnel_notice", "Deep-read violations are observed separately; no measured L2 completion count.")).font(.caption).foregroundStyle(theme.neutrals.text(.body))
            if d.disclosure.isEmpty { missingPopulation }
            ForEach(d.disclosure, id: \.skill) { row in
                HStack(alignment: .top) {
                    Button {
                        selectedSkill = row.skill
                        inspectorFilter = .all
                        inspectorSubTab = .definition
                        lens = .usage
                    } label: {
                        Text(row.skill).font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: Space.gap / 2) {
                        Text("L0 " + rate(row.l0) + " · L1 " + rate(row.l1)).font(.caption.monospacedDigit())
                        Text(skillsText("greedy", "Deep-read violations") + " " + rate(row.greedy)).font(.caption.monospacedDigit())
                        proportionalBar([row.l0.value, row.l1.value, row.greedy.value])
                    }.frame(maxWidth: .infinity)
                    infoButton([fact("L0", row.l0), fact("L1", row.l1), fact(skillsText("greedy", "Deep-read violations"), row.greedy), fact(skillsText("context_tokens", "Context tokens"), row.contextTokens)], id: "funnel-\(row.skill)")
                }.captureDashboardGeometry(id: "funnel-\(row.skill)", role: "skillsDiagnosticRow")
            }
            Text(skillsText("churn_title", "调用后擦写与重试")).font(.headline)
            if d.churn.isEmpty { missingPopulation }
            ForEach(d.churn, id: \.skill) { row in
                metricRow(row.skill, value: skillsText("edits", "Edits") + " " + integer(row.edits) + " · " + skillsText("retries", "Retries") + " " + integer(row.retries), facts: [fact(skillsText("edits", "Edits"), row.edits), fact(skillsText("retries", "Retries"), row.retries)], id: "churn-\(row.skill)")
            }
            Text(skillsText("escape_title", "漏网缺陷归因")).font(.headline)
            if d.escapes.isEmpty { missingPopulation }
            ForEach(d.escapes, id: \.skill) { row in
                metricRow(row.skill, value: "IMPL_BUG " + integer(row.implementation) + " · SPEC_GAP " + integer(row.specification), facts: [fact("IMPL_BUG", row.implementation), fact("SPEC_GAP", row.specification)], id: "escapes-\(row.skill)")
            }
        }
    }

    private func context(_ d: SkillsRoiDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            Text(skillsText("composition_title", "上下文构成分布")).font(.headline)
            if let context = d.context, !context.slices.isEmpty {
                proportionalBar(context.slices.map { $0.share.metadata.hasSamples ? $0.share.value : nil })
                ForEach(Array(context.slices.enumerated()), id: \.offset) { index, slice in
                    HStack {
                        Circle().fill(theme.chartCategorical(index)).frame(width: Space.gap, height: Space.gap)
                        Text(sliceTitle(slice.key)).font(.caption)
                        Spacer()
                        Text(percent(slice.share) + " · " + decimal(slice.tokens) + " tok").font(.caption.monospacedDigit()).fixedSize()
                        infoButton([fact(skillsText("share", "Share (%)"), slice.share), fact(skillsText("tokens", "Tokens"), slice.tokens)], id: "slice-\(index)")
                    }.captureDashboardGeometry(id: "slice-\(index)", role: "skillsDiagnosticRow")
                }
                Text(skillsText("estimated", "Estimated") + " · " + decimal(context.total) + " tok").font(.caption).foregroundStyle(theme.warningOnSubtle)
            } else { missingPopulation }
            Text(skillsText("burn_title", "高消耗工具调用 (>10k tok)")).font(.headline)
            let tools = d.tools.filter { ($0.bloated.value ?? 0) > 0 }
            if tools.isEmpty { missingPopulation }
            ForEach(tools, id: \.tool) { tool in
                HStack {
                    Button {
                        if let dom = tool.dominantSkill {
                            selectedSkill = dom
                            inspectorFilter = .all
                            lens = .usage
                        }
                    } label: {
                        Text(tool.tool).font(.caption.weight(.semibold)).frame(minHeight: 28, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(integer(tool.bloated) + " / " + integer(tool.calls) + " · p95 " + decimal(tool.p95) + " tok").font(.caption.monospacedDigit()).fixedSize(horizontal: false, vertical: true)
                    infoButton([fact(skillsText("bloated", "Calls >10k"), tool.bloated), fact(skillsText("calls", "Calls"), tool.calls), fact(skillsText("total_tokens", "Total tokens"), tool.total), fact("p95 tok", tool.p95), fact(skillsText("share", "Share (%)"), tool.share)], id: "tool-\(tool.tool)")
                }.captureDashboardGeometry(id: "tool-\(tool.tool)", role: "skillsDiagnosticRow")
            }
        }
    }

    private func sliceTitle(_ key: String) -> String {
        if key.localizedCaseInsensitiveContains("system") || key.contains("AGENTS") { return skillsText("slice_system", "System / AGENTS") }
        if key.localizedCaseInsensitiveContains("skills") { return skillsText("slice_skills", "Skills") }
        if key.localizedCaseInsensitiveContains("schema") { return skillsText("slice_schema", "Tool schemas") }
        if key.localizedCaseInsensitiveContains("result") || key.contains("结果") { return skillsText("slice_results", "Tool results") }
        return skillsText("slice_conversation", "Conversation")
    }

    private func proportionalBar(_ values: [Double?]) -> some View {
        GeometryReader { proxy in
            let total = values.compactMap { $0 }.reduce(0, +)
            HStack(spacing: 0) {
                ForEach(values.indices, id: \.self) { index in
                    if let value = values[index], value > 0, total > 0 {
                        Rectangle().fill(theme.chartCategorical(index))
                            .frame(width: proxy.size.width * value / max(total, 1))
                            .captureDashboardGeometry(id: "\(lens.rawValue)-segment-\(index)", role: "skillsBarSegment")
                    }
                }
            }
        }
        .frame(height: Space.gap).background(theme.neutrals.inner).clipShape(Capsule())
    }

    private func metricRow(_ title: String, value: String, facts: [SkillsEvidence?], id: String) -> some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)); Spacer()
            Text(value).font(.caption.monospacedDigit()).fixedSize(horizontal: false, vertical: true)
            infoButton(facts, id: id)
        }.captureDashboardGeometry(id: id, role: "skillsDiagnosticRow")
    }

    private func columnHeader(_ title: String, _ id: String) -> some View {
        Text(title).font(.caption2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .captureDashboardGeometry(id: "usage-header-\(id)", role: "skillsTableHeader")
    }
    private func tableValue(_ value: String, _ skill: String, _ column: String) -> some View {
        Text(value).font(.caption.monospacedDigit()).fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .captureDashboardGeometry(id: "usage-\(skill)-\(column)", role: "skillsTableCell")
    }
    private func infoButton(_ facts: [SkillsEvidence?], id: String) -> some View {
        Button { show(facts) } label: { Image(systemName: "info.circle").frame(minWidth: 28, minHeight: 28) }
            .buttonStyle(.plain).help(skillsText("show_evidence", "Show freshness, sample and coverage"))
            .captureDashboardGeometry(id: "evidence-\(id)", role: "button")
    }
    private func show(_ facts: [SkillsEvidence?]) { evidence = facts.compactMap { $0 }; showingEvidence = true }
    private var evidenceDrawer: some View {
        ScrollView { SkillsObservationDrawer(evidence: evidence) }.frame(width: 440).frame(maxHeight: 500)
    }
    private var missingPopulation: some View {
        Text(skillsText("no_samples", "Unknown · no observed samples")).font(.caption).foregroundStyle(theme.neutrals.text(.body))
    }
    private var unknown: String { skillsText("metric_unknown", "Unknown") }
    private func coverage(_ raw: String?) -> String {
        switch raw {
        case "healthy": return skillsText("observed", "Observed")
        case "partial": return skillsText("partial", "Partial")
        case "missing": return skillsText("missing_short", "Missing")
        case "error": return skillsText("error_short", "Error")
        default: return unknown
        }
    }
    private func metadataLine(_ m: SkillsObservationMetadata) -> String { SkillsObservationDrawer.metadataLine(m) }
    private func number(_ value: Int?) -> String { value.map(String.init) ?? unknown }
    private func integer(_ metric: SkillsMetric<Int>?) -> String { metric.flatMap { $0.metadata.hasSamples ? $0.value : nil }.map(String.init) ?? unknown }
    private func decimal(_ metric: SkillsMetric<Double>?) -> String { metric.flatMap { $0.metadata.hasSamples ? $0.value : nil }.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? unknown }
    private func rate(_ metric: SkillsMetric<Double>?) -> String { metric.flatMap { $0.metadata.hasSamples ? $0.value : nil }.map { ($0 * 100).formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? unknown }
    private func percent(_ metric: SkillsMetric<Double>?) -> String { metric.flatMap { $0.metadata.hasSamples ? $0.value : nil }.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? unknown }
    private func fact<T: Decodable & Sendable & Equatable>(_ title: String, _ metric: SkillsMetric<T>?) -> SkillsEvidence? {
        guard let metric else { return nil }
        let value: String
        if let number = metric.value as? Double {
            value = number.formatted(.number.precision(.fractionLength(0...2)))
        } else if let number = metric.value as? Int {
            value = String(number)
        } else if let flag = metric.value as? Bool {
            value = flag ? skillsText("yes", "Yes") : skillsText("no", "No")
        } else {
            value = unknown
        }
        return .init(title: title, value: value, metadata: metric.metadata)
    }
}

/// The same evidence content is used by the production popover and the hostless render proof.
struct SkillsObservationDrawer: View {
    let evidence: [SkillsEvidence]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            Text(skillsText("evidence", "Evidence")).font(.headline)
            if evidence.isEmpty { Text(skillsText("no_samples", "Unknown · no observed samples")).font(.caption) }
            ForEach(evidence) { item in
                VStack(alignment: .leading, spacing: Space.gap / 2) {
                    Text(item.title + " · " + item.value).font(.caption.weight(.semibold))
                    Text(Self.metadataLine(item.metadata)).font(.caption)
                    Text((item.metadata.start ?? skillsText("metric_unknown", "Unknown")) + " → " + (item.metadata.end ?? skillsText("metric_unknown", "Unknown"))).font(.caption)
                    if let method = item.metadata.method { Text(method).font(.caption).foregroundStyle(theme.neutrals.text(.body)) }
                }
                .fixedSize(horizontal: false, vertical: true).captureDashboardGeometry(id: "evidence-\(item.id)", role: "skillsEvidence")
            }
        }.padding(Space.cardPadding)
    }

    static func metadataLine(_ metadata: SkillsObservationMetadata) -> String {
        let unknown = skillsText("metric_unknown", "Unknown")
        let status: String
        switch metadata.coverage {
        case "healthy": status = skillsText("observed", "Observed")
        case "partial": status = skillsText("partial", "Partial")
        case "missing": status = skillsText("missing_short", "Missing")
        case "error": status = skillsText("error_short", "Error")
        default: status = unknown
        }
        let window = "\(metadata.window ?? unknown) CST", asOf = skillsText("as_of", "As of") + " " + (metadata.asOf ?? unknown)
        let sample = skillsText("sample", "Sample") + " " + (metadata.sample.map(String.init) ?? unknown)
        let parts = [window, asOf, sample, status] + (metadata.estimated == true ? [skillsText("estimated", "Estimated")] : [])
        return parts.joined(separator: " · ")
    }
}

struct DashboardResponsiveGrid: Layout {
    var wideColumns = 4, compactColumns = 2, spacing = Space.gap
    private func columns(_ width: CGFloat) -> Int { width >= 960 ? wideColumns : (width >= 640 ? compactColumns : 1) }
    private struct Measurement { let width: CGFloat, columns: Int, cellWidth: CGFloat, heights: [CGFloat] }

    private func geometry(_ proposal: ProposedViewSize, _ subviews: Subviews) -> Measurement {
        let width = proposal.width ?? 640, count = columns(width)
        let cellWidth = max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
        let heights = stride(from: 0, to: subviews.count, by: count).map { start in
            (start..<min(start + count, subviews.count)).map { subviews[$0].sizeThatFits(.init(width: cellWidth, height: nil)).height }.max() ?? 0
        }
        return .init(width: width, columns: count, cellWidth: cellWidth, heights: heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let measured = geometry(proposal, subviews)
        return .init(width: measured.width, height: measured.heights.reduce(0, +) + spacing * CGFloat(max(0, measured.heights.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let measured = geometry(.init(width: bounds.width, height: nil), subviews)
        let count = measured.columns, width = measured.cellWidth, heights = measured.heights
        var y = bounds.minY
        for row in heights.indices {
            for column in 0..<count {
                let index = row * count + column
                guard index < subviews.count else { continue }
                subviews[index].place(at: .init(x: bounds.minX + CGFloat(column) * (width + spacing), y: y), anchor: .topLeading, proposal: .init(width: width, height: heights[row]))
            }
            y += heights[row] + spacing
        }
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

private struct SkillsKey: CodingKey {
    let stringValue: String; var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

private protocol SkillsObjectPopulation: Decodable {}

private struct SkillsObserved<Value: Decodable>: Decodable {
    let value: Value?, metadata: SkillsObservationMetadata?
    init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: SkillsKey.self), c.contains(.init("value")) {
            value = Value.self is any SkillsObjectPopulation.Type ? try Value(from: decoder) : try c.decodeIfPresent(Value.self, forKey: .init("value"))
            metadata = try SkillsObservationMetadata(from: decoder)
        } else { value = try decoder.singleValueContainer().decode(Value?.self); metadata = nil }
    }
}

private struct SkillsFields {
    let container: KeyedDecodingContainer<SkillsKey>, metadata: SkillsObservationMetadata
    init(_ decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: SkillsKey.self), parent = try SkillsObservationMetadata(from: decoder)
        if outer.contains(.init("value")), let nested = try? outer.superDecoder(forKey: .init("value")), let inner = try? nested.container(keyedBy: SkillsKey.self) {
            container = inner; metadata = try SkillsObservationMetadata(from: nested).inheriting(parent)
        } else { container = outer; metadata = parent }
    }
    func metric<T: Decodable & Sendable & Equatable>(_ key: String) throws -> SkillsMetric<T> {
        let observed = try container.decodeIfPresent(SkillsObserved<T>.self, forKey: .init(key))
        return SkillsMetric(value: observed?.value, metadata: observed?.metadata?.inheriting(metadata) ?? metadata)
    }
    func value<T: Decodable>(_ key: String, as type: T.Type = T.self) throws -> T? { try container.decodeIfPresent(SkillsObserved<T>.self, forKey: .init(key))?.value }
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
    public let relPath: String, calls30d: Int?, successRate: Double?, p95Ms: Double?, isUnpracticed: Bool
    public var id: String { relPath }

    public init(relPath: String, calls30d: Int? = nil, successRate: Double? = nil, p95Ms: Double? = nil, isUnpracticed: Bool = false) {
        self.relPath = relPath; self.calls30d = calls30d; self.successRate = successRate
        self.p95Ms = p95Ms; self.isUnpracticed = isUnpracticed
    }

    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder)
        relPath = try f.container.decode(String.self, forKey: .init("rel_path"))
        calls30d = try f.value("calls_30d")
        successRate = try f.value("success_rate")
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

public enum SkillInspectorFilter: String, CaseIterable, Identifiable, Sendable {
    case all, active, needsOptimization, idle30d, repoBound, archivedGhosts
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return skillsText("filter_all", "All")
        case .active: return skillsText("filter_active", "Active")
        case .needsOptimization: return skillsText("filter_needs_opt", "Needs Optimization")
        case .idle30d: return skillsText("filter_idle_30d", "30d Idle")
        case .repoBound: return skillsText("filter_repo_bound", "Repo-Bound")
        case .archivedGhosts: return skillsText("filter_ghosts", "Archived Ghosts")
        }
    }
    public func matches(_ detail: SkillInspectorDetail) -> Bool {
        switch self {
        case .all:
            return !detail.isGhost
        case .active:
            return !detail.isGhost && detail.loads30d > 0 && detail.statusLabel != "needs_optimization"
        case .needsOptimization:
            return !detail.isGhost && (detail.statusLabel == "needs_optimization" || detail.implBugEscapes > 0 || detail.specGapEscapes > 0 || detail.editChurn >= 4)
        case .idle30d:
            return !detail.isGhost && (detail.loads30d == 0 || detail.statusLabel == "zombie_30d")
        case .repoBound:
            return !detail.isGhost && detail.scope == "repo_bound"
        case .archivedGhosts:
            return detail.isGhost
        }
    }
}

public enum SkillInspectorSubTab: String, CaseIterable, Identifiable, Sendable {
    case definition, scripts, evals, evolution
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .definition: return skillsText("tab_definition", "Definition & References")
        case .scripts: return skillsText("tab_scripts", "Script Ledger")
        case .evals: return skillsText("tab_evals", "Eval & Interceptions")
        case .evolution: return skillsText("tab_evolution", "版本演进对比")
        }
    }
}

public enum SkillsPseudoSkillGuard {
    public static let forbiddenSlugs: Set<String> = [
        "tests", "leepepe", "pull", "main", "scripts", "skills",
        "head", "origin", "pr", "issue", "issues", "master", "refs", "tags"
    ]

    public static func isPseudoSkill(_ raw: String) -> Bool {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return true }
        return forbiddenSlugs.contains(cleaned)
    }

    public static func scrubAcademicCodes(_ raw: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\bS(?:1[0-2]|[1-9])\b"#) else { return raw }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
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
        let sem = try f.value("semver", as: String.self) ?? (try f.value("plugin_version", as: String.self)) ?? "1.0.0"
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

public struct SkillRetroProposalItem: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let skill: String
    public let layer: String
    public let category: String
    public let priority: String
    public let title: String
    public let plainReason: String
    public let action: String?
    public let humanWhat: String?
    public let humanWhy: String?
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
        return SkillsRoiDiagnosticsCardView.evalCommandString(forSkill: skill)
    }

    public init(
        id: String,
        skill: String,
        layer: String = "L0",
        category: String = "",
        priority: String = "P2",
        title: String,
        plainReason: String = "",
        action: String? = nil,
        humanWhat: String? = nil,
        humanWhy: String? = nil,
        remediationCommands: [String] = []
    ) {
        self.id = id
        self.skill = skill
        self.layer = layer
        self.category = category
        self.priority = priority
        self.title = title
        self.plainReason = plainReason
        self.action = action
        self.humanWhat = humanWhat
        self.humanWhy = humanWhy
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
        let t = (try? f.value("title", as: String.self)) ?? sk
        title = t
        plainReason = (try? f.value("plain_reason", as: String.self)) ?? ""
        action = try? f.value("action", as: String.self)
        humanWhat = try? f.value("human_what", as: String.self)
        humanWhy = try? f.value("human_why", as: String.self)
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
    public let proposals: [SkillRetroProposalItem]

    private struct RoadblockEntry: Decodable {
        let exit2Count: Int?
        enum CodingKeys: String, CodingKey { case exit2Count = "exit_2_count" }
    }

    private struct Layer2Section: Decodable {
        let rigidRoadblocks: [RoadblockEntry]?
        enum CodingKeys: String, CodingKey { case rigidRoadblocks = "rigid_roadblocks" }
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
        self.proposals = proposals.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
    }

    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder)
        let nested = try? f.value("summary", as: SummaryNested.self)
        let l2 = try? f.value("layer2_script_efficacy_and_speed", as: Layer2Section.self)
        let roadblockExit2Sum = l2?.rigidRoadblocks?.compactMap(\.exit2Count).reduce(0, +)

        sampleSize = (try? f.value("sample_size", as: Int.self)) ?? f.metadata.sample ?? 0
        slowFlywheelReady = (try? f.value("slow_flywheel_ready", as: Bool.self)) ?? nested?.slowFlywheelReady ?? (sampleSize >= 50)
        triggerMissSkills = (try? f.value("trigger_miss_skills", as: Int.self)) ?? nested?.triggerMissSkills ?? 0
        zeroActionLoadSkills = (try? f.value("zero_action_load_skills", as: Int.self)) ?? nested?.zeroActionLoadSkills ?? 0
        directionalDrifts = (try? f.value("directional_drifts", as: Int.self)) ?? nested?.directionalDrifts ?? 0
        unwiredDrawersCount = (try? f.value("unwired_drawers_count", as: Int.self)) ?? nested?.unwiredDrawersCount ?? 0
        trueDeadwoodDrawersCount = (try? f.value("true_deadwood_drawers_count", as: Int.self)) ?? nested?.trueDeadwoodDrawersCount ?? 0
        trueCatcherScriptsCount = (try? f.value("true_catcher_scripts_count", as: Int.self)) ?? nested?.trueCatcherScriptsCount ?? 0
        ceremonialScriptsCount = (try? f.value("ceremonial_scripts_count", as: Int.self)) ?? nested?.ceremonialScriptsCount ?? 0
        let rbScripts = (try? f.value("rigid_roadblock_scripts_count", as: Int.self)) ?? nested?.rigidRoadblockScriptsCount ?? (l2?.rigidRoadblocks?.count ?? 0)
        rigidRoadblockScriptsCount = rbScripts
        exit2RoadblockTotalCount = (try? f.value("exit2_roadblock_total_count", as: Int.self))
            ?? nested?.exit2RoadblockTotalCount
            ?? roadblockExit2Sum
            ?? rbScripts
        latencySinkScriptsCount = (try? f.value("latency_sink_scripts_count", as: Int.self)) ?? nested?.latencySinkScriptsCount ?? 0
        wildPatternsCount = (try? f.value("wild_patterns_count", as: Int.self)) ?? nested?.wildPatternsCount ?? 0
        let decodedProposals = (try? f.value("proposals", as: [SkillRetroProposalItem].self)) ?? []
        proposals = decodedProposals.filter { !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }
    }
}

public typealias SkillRetroWorkbenchSummary = SkillRetroFourLayerSummary

struct SkillsPrimaryDetailSplitLayout: Layout {
    var primaryFraction: CGFloat = 0.34, minPrimaryWidth: CGFloat = 240, maxPrimaryWidth: CGFloat = 340, spacing: CGFloat = Space.gap
    private func isSplit(_ width: CGFloat) -> Bool { width >= 760 }
    private func primaryWidth(_ width: CGFloat) -> CGFloat { min(maxPrimaryWidth, max(minPrimaryWidth, floor(width * primaryFraction))) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
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

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
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
        if !skillDetails.isEmpty { return skillDetails }
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
    public let errors: [String]

    public var resolvedSkillRetro: SkillRetroFourLayerSummary {
        if let skillRetro { return skillRetro }
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
            acc + item.scripts.filter { ($0.p95Ms ?? 0) >= 10_000 }.count
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
        let resolvedEvo = !filteredTopEvo.isEmpty ? filteredTopEvo : diag.versionEvolution
        if !resolvedEvo.isEmpty {
            versionEvolution = resolvedEvo
        } else {
            versionEvolution = Self.synthesizeVersionEvolution(from: skillDetails, fallbackMetadata: metadata)
        }
        skillRetro = (try? f.value("skill_retro", as: SkillRetroFourLayerSummary.self)) ?? diag.skillRetro
        errors = try f.value("errors") ?? []
    }

    private static func synthesizeVersionEvolution(
        from details: [SkillInspectorDetail],
        fallbackMetadata: SkillsObservationMetadata
    ) -> [SkillVersionEvolutionRow] {
        details.filter { !$0.isGhost && !SkillsPseudoSkillGuard.isPseudoSkill($0.skill) }.map { item in
            let scriptCalls = item.scripts.compactMap(\.calls30d).reduce(0, +)
            let p50 = item.scripts.compactMap(\.p95Ms).min()
            let uptake = item.unpracticedRate.map { max(0.0, min(1.0, 1.0 - $0)) }
            let current = SkillVersionMetricsSnapshot(
                skillVersion: "v1@head",
                semver: "1.0.0",
                combinedVersion: "1.0.0+v1@head",
                commitCount: 1,
                subtreeSha: "head",
                sessions: item.loads30d,
                invocations: item.loads30d,
                scriptCallCount: scriptCalls,
                exit2Count: 0,
                exit1Count: 0,
                postFixErrors: 0,
                exit2ErrorRate: scriptCalls > 0 ? 0.0 : nil,
                brokenDrawerCount: item.unhitRefsCount,
                scriptP50Ms: p50,
                uptakeRate: uptake,
                r1Total: item.r1PassRate != nil ? max(1, item.loads7d) : 0,
                r1Pass: item.r1PassRate.map { Int((Double(max(1, item.loads7d)) * $0).rounded()) } ?? 0,
                r1PassRate: item.r1PassRate
            )
            let status = item.loads30d >= 5 ? "improved" : (item.loads30d > 0 ? "observing" : "baseline")
            return SkillVersionEvolutionRow(
                metadata: item.metadata.inheriting(fallbackMetadata),
                skill: item.skill,
                semver: "1.0.0",
                skillVersion: "v1@head",
                combinedVersion: "1.0.0+v1@head",
                subtreeSha: "head",
                commitCount: 1,
                status: status,
                currentVersion: current
            )
        }
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
extension SkillRetroProposalItem: SkillsObjectPopulation {}
extension SkillRetroFourLayerSummary: SkillsObjectPopulation {}
#endif
