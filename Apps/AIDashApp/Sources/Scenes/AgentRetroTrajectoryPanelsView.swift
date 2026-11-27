#if os(macOS)
import AppKit
import DesignKit
import SwiftUI

public enum AgentRetroWatermarkFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case unconverged

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            return DashboardL10n.tr("dashboard.agent_retro.filter_all", "All Layers")
        case .unconverged:
            return DashboardL10n.tr("dashboard.agent_retro.filter_unconverged", "Unconverged Only")
        }
    }
}

@MainActor
public struct AgentRetroTrajectoryPanelsView: View {
    public let retro: AgentRetroWorkbenchSummary?
    @State private var retroFilter: AgentRetroWatermarkFilter = .all
    private let theme = Theme.system
    @Environment(\.locale) private var locale

    public init(retro: AgentRetroWorkbenchSummary?) {
        self.retro = retro
    }

    public var body: some View {
        let status = retro?.coverageStatus ?? "missing"
        switch status {
        case "missing", "error":
            degradedBanner(status: status)
        case "unknown":
            emptySamplesCard
        default:
            if let retro, retro.sampleSize > 0 || retro.preFixTotal > 0 || retro.postFixTotal > 0 || !retro.horizonWaste.items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    if status == "partial" {
                        partialCoverageStrip(retro: retro)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            AgentRetroSixLayerPanelView(retro: retro, filter: $retroFilter, locale: locale)
                            AgentHorizonWastePanelView(retro: retro, locale: locale)
                        }
                        .frame(minWidth: 760)
                        VStack(alignment: .leading, spacing: 14) {
                            AgentRetroSixLayerPanelView(retro: retro, filter: $retroFilter, locale: locale)
                            AgentHorizonWastePanelView(retro: retro, locale: locale)
                        }
                    }
                }
            } else {
                emptySamplesCard
            }
        }
    }

    private func partialCoverageStrip(retro: AgentRetroWorkbenchSummary) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(DashboardL10n.tr("dashboard.agent_retro.coverage_partial", "Partial Sample Coverage"))
                    .font(.caption2.weight(.semibold))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(theme.warning.opacity(0.14), in: Capsule())
            .foregroundStyle(theme.warningOnSubtle)

            Text(DashboardL10n.format(
                "dashboard.agent_retro.partial_detail_format",
                "Observed %lld sessions in %@ window",
                retro.sampleSize,
                retro.windowCST
            ))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Spacer(minLength: 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptySamplesCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(DashboardL10n.tr("dashboard.agent_retro.empty_title", "No Trajectory Diagnostic Samples Yet"))
                    .font(.subheadline.weight(.semibold))
                Text(DashboardL10n.tr(
                    "dashboard.agent_retro.empty_desc",
                    "Trajectory health and long-horizon waste panels appear once session diagnostics are collected."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.neutrals.inner)
        )
        .accessibilityIdentifier("dashboard.agentRetroEmptyCard")
        .accessibilityElement(children: .combine)
    }

    private func degradedBanner(status: String) -> some View {
        let isError = status == "error"
        let tint = isError ? theme.danger : theme.warning
        let textTint = isError ? theme.dangerOnSubtle : theme.warningOnSubtle
        let badgeLabel = isError
            ? DashboardL10n.tr("dashboard.agent_retro.status_degraded", "Diagnostics Degraded")
            : DashboardL10n.tr("dashboard.agent_retro.status_missing", "Trajectory Source Uncollected")
        let descLabel = isError
            ? DashboardL10n.tr(
                "dashboard.agent_retro.degraded_error_desc",
                "Trajectory diagnostic query encountered a read error; zero values are withheld to preserve metric honesty."
            )
            : DashboardL10n.tr(
                "dashboard.agent_retro.degraded_missing_desc",
                "Trajectory diagnostic warehouse table is not yet initialized; zero values are withheld."
            )
        return HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.octagon.fill" : "tray")
                .font(.subheadline)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(DashboardL10n.tr("dashboard.agent_retro.six_layer_title", "6-Layer Trajectory Health & Watermarks"))
                        .font(.subheadline.weight(.semibold))
                    Text(badgeLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.14), in: Capsule())
                        .foregroundStyle(textTint)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(descLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.neutrals.inner)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        )
        .accessibilityIdentifier("dashboard.agentRetroDegradedBanner")
        .accessibilityElement(children: .combine)
    }
}

@MainActor
public struct AgentRetroSixLayerPanelView: View {
    public let retro: AgentRetroWorkbenchSummary
    @Binding public var filter: AgentRetroWatermarkFilter
    public let locale: Locale
    private let theme = Theme.system

    public init(
        retro: AgentRetroWorkbenchSummary,
        filter: Binding<AgentRetroWatermarkFilter>,
        locale: Locale = .current
    ) {
        self.retro = retro
        self._filter = filter
        self.locale = locale
    }

    private var visibleLayers: [AgentRetroLayerRow] {
        let base = retro.layers.isEmpty ? Self.defaultLayers : retro.layers
        switch filter {
        case .all:
            return base
        case .unconverged:
            return base.filter { $0.postFixCount > 0 }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(DashboardL10n.tr(
                        "dashboard.agent_retro.six_layer_title",
                        "6-Layer Trajectory Health & Watermarks"
                    ))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    Picker(
                        DashboardL10n.tr("dashboard.agent_retro.filter_picker", "Layer Filter"),
                        selection: $filter
                    ) {
                        ForEach(AgentRetroWatermarkFilter.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minHeight: 28)
                }
                Text(DashboardL10n.format(
                    "dashboard.agent_retro.six_layer_subtitle_format",
                    "Pre-fix baseline %lld vs current-version new anomalies %lld",
                    retro.preFixTotal,
                    retro.postFixTotal
                ))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            if visibleLayers.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(theme.success)
                        .accessibilityHidden(true)
                    Text(DashboardL10n.tr(
                        "dashboard.agent_retro.all_converged_note",
                        "All 6 trajectory layers have zero new anomalies in the current version."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleLayers) { row in
                        layerRowView(row)
                    }
                }
            }

            if !retro.skillWatermarks.isEmpty {
                Divider()
                watermarkStripView
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.neutrals.inner)
        )
        .accessibilityIdentifier("dashboard.agentRetroSixLayerPanel")
    }

    private func layerRowView(_ row: AgentRetroLayerRow) -> some View {
        let title = Self.localizedLayerTitle(row, locale: locale)
        let postTint: Color = {
            if row.postFixCount == 0 { return theme.success }
            if row.postFixCount <= 2 { return theme.warning }
            return theme.danger
        }()
        let postTextTint: Color = {
            if row.postFixCount == 0 { return theme.successOnSubtle }
            if row.postFixCount <= 2 { return theme.warningOnSubtle }
            return theme.dangerOnSubtle
        }()

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let sub = layerAttributionText(row) {
                    Text(sub)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(DashboardL10n.format(
                "dashboard.agent_retro.pre_fix_badge_format",
                "Pre-fix %lld",
                row.preFixCount
            ))
            .font(.caption2.monospacedDigit().weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(theme.neutrals.inner, in: Capsule())
            .foregroundStyle(theme.text(.meta))
            .fixedSize(horizontal: true, vertical: false)

            Text(DashboardL10n.format(
                "dashboard.agent_retro.post_fix_badge_format",
                "New %lld",
                row.postFixCount
            ))
            .font(.caption2.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(postTint.opacity(0.15), in: Capsule())
            .foregroundStyle(postTextTint)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func layerAttributionText(_ row: AgentRetroLayerRow) -> String? {
        var parts: [String] = []
        if let skill = row.topSkill, !skill.isEmpty, !SkillsPseudoSkillGuard.isPseudoSkill(skill) {
            if let ver = row.topSkillVersion, !ver.isEmpty {
                parts.append("\(skill) \(ver)")
            } else {
                parts.append(skill)
            }
        }
        if row.affectedSessions > 0 {
            parts.append(DashboardL10n.format(
                "dashboard.agent_retro.sessions_count_format",
                "%lld sessions",
                row.affectedSessions
            ))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var watermarkStripView: some View {
        let topWatermarks = Array(retro.skillWatermarks.prefix(4))
        return VStack(alignment: .leading, spacing: 6) {
            Text(DashboardL10n.tr("dashboard.agent_retro.watermarks_title", "Skill Post-Fix Watermarks"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.flexible(minimum: 150), spacing: 6), GridItem(.flexible(minimum: 150), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(topWatermarks) { wm in
                    watermarkChip(wm)
                }
            }
        }
    }

    private func watermarkChip(_ wm: AgentRetroSkillWatermark) -> some View {
        let isClean = wm.postFixCount == 0
        let tint = isClean ? theme.success : theme.warning
        let textTint = isClean ? theme.successOnSubtle : theme.warningOnSubtle
        let verText = wm.skillVersion ?? "v1"
            let statText = DashboardL10n.format("dashboard.agent_retro.watermark_chip_stat_format", "%@ · New %lld", verText, wm.postFixCount)
            return HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(wm.skill).font(.caption2.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: 2)
                Text(statText).font(.caption2.monospacedDigit().weight(.medium)).foregroundStyle(textTint).fixedSize(horizontal: true, vertical: false)
            }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    static func localizedLayerTitle(_ row: AgentRetroLayerRow, locale: Locale) -> String {
        switch row.layerKey {
        case "role": return DashboardL10n.tr("dashboard.agent_retro.layer.role", "Role Boundaries")
        case "handoff": return DashboardL10n.tr("dashboard.agent_retro.layer.handoff", "Handoff Completeness")
        case "invoke": return DashboardL10n.tr("dashboard.agent_retro.layer.invoke", "Tool & Reference Invocation")
        case "exec": return DashboardL10n.tr("dashboard.agent_retro.layer.exec", "Execution & Rework Convergence")
        case "friction": return DashboardL10n.tr("dashboard.agent_retro.layer.friction", "Human-Agent Collaboration Friction")
        case "horizon": return DashboardL10n.tr("dashboard.agent_retro.layer.horizon", "Long-Horizon Context Waste")
        default:
            let isZh = locale.language.languageCode?.identifier.hasPrefix("zh") == true
            return SkillsPseudoSkillGuard.scrubAcademicCodes(isZh ? row.labelZh : row.labelEn)
        }
    }

    private static let defaultLayers: [AgentRetroLayerRow] = [
        AgentRetroLayerRow(layerKey: "role", labelZh: "角色边界", labelEn: "Role Boundaries"),
        AgentRetroLayerRow(layerKey: "handoff", labelZh: "交接完整度", labelEn: "Handoff Completeness"),
        AgentRetroLayerRow(layerKey: "invoke", labelZh: "工具与参考调用", labelEn: "Tool & Reference Invocation"),
        AgentRetroLayerRow(layerKey: "exec", labelZh: "执行与返工收敛", labelEn: "Execution & Rework Convergence"),
        AgentRetroLayerRow(layerKey: "friction", labelZh: "人机协作摩擦", labelEn: "Human-Agent Collaboration Friction"),
        AgentRetroLayerRow(layerKey: "horizon", labelZh: "长程上下文损耗", labelEn: "Long-Horizon Context Waste"),
    ]
}

@MainActor
public struct AgentHorizonWastePanelView: View {
    public let retro: AgentRetroWorkbenchSummary
    public let locale: Locale
    private let theme = Theme.system

    public init(retro: AgentRetroWorkbenchSummary, locale: Locale = .current) {
        self.retro = retro
        self.locale = locale
    }

    public var body: some View {
        let waste = retro.horizonWaste
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DashboardL10n.tr(
                    "dashboard.agent_retro.horizon_title",
                    "Long-Horizon Waste & Optimization"
                ))
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                Text(DashboardL10n.tr(
                    "dashboard.agent_retro.horizon_subtitle",
                    "Avoidable turns and context tokens across extended execution chains"
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                wasteKPIChip(
                    title: DashboardL10n.tr("dashboard.agent_retro.savable_turns", "Savable Turns"),
                    value: "\(waste.wastedTurnsTotal)",
                    tint: waste.wastedTurnsTotal > 0 ? theme.warning : theme.success
                )
                wasteKPIChip(
                    title: DashboardL10n.tr("dashboard.agent_retro.savable_tokens", "Savable Context Spend"),
                    value: DashboardTokenFormatter.compact(waste.wastedTokensTotal),
                    tint: waste.wastedTokensTotal > 0 ? theme.primary.primary : theme.success
                )
            }

            if waste.items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(theme.success)
                        .accessibilityHidden(true)
                    Text(DashboardL10n.tr(
                        "dashboard.agent_retro.horizon_empty",
                        "No significant long-horizon context waste observed in current window."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(waste.items.prefix(4))) { item in
                        horizonCategoryRow(item)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.neutrals.inner)
        )
        .accessibilityIdentifier("dashboard.agentHorizonWastePanel")
    }

    private func wasteKPIChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(.callout, design: .rounded, weight: .bold)).monospacedDigit().foregroundStyle(tint).fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func horizonCategoryRow(_ item: AgentHorizonWasteItem) -> some View {
        let title = Self.localizedWasteCategoryTitle(item, locale: locale)
        let shareClamped = min(max(item.tokenSharePct / 100.0, 0.04), 1.0)
        let cleanSkill = SkillsPseudoSkillGuard.isPseudoSkill(item.skill) ? nil : item.skill
        let roleText = Self.localizedRoleLabel(item, locale: locale)
        let metaText = [roleText, cleanSkill].compactMap { val -> String? in
            guard let val, !val.isEmpty, val != "unmeasured" else { return nil }
            return val
        }.joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(DashboardL10n.format(
                    "dashboard.agent_retro.waste_row_stat_format",
                    "%lld turns · %@",
                    item.wastedTurns,
                    DashboardTokenFormatter.compact(item.wastedTokens)
                ))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(theme.warningOnSubtle)
                .fixedSize(horizontal: true, vertical: false)
            }
            HStack(spacing: 8) {
                if !metaText.isEmpty {
                    Text(metaText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.neutrals.inner)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.warning.opacity(0.75))
                            .frame(width: max(6, proxy.size.width * shareClamped))
                    }
                }
                .frame(width: 64, height: 4)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    static func localizedWasteCategoryTitle(_ item: AgentHorizonWasteItem, locale: Locale) -> String {
        switch item.categoryKey {
        case "context_carry":
            return DashboardL10n.tr("dashboard.agent_retro.waste.context_carry", "Read-Only Status Polling Scriptable")
        case "fatigue_inflection":
            return DashboardL10n.tr("dashboard.agent_retro.waste.fatigue_inflection", "Repeated Full Re-Reads Replaceable by Delta")
        case "steering_overkill":
            return DashboardL10n.tr("dashboard.agent_retro.waste.steering_overkill", "High-Tier Model Mechanical Work Downgradable")
        case "rework_verify":
            return DashboardL10n.tr("dashboard.agent_retro.waste.rework_verify", "Outer-Loop Rework Missing Fast Check")
        case "wakeup_parallelism":
            return DashboardL10n.tr("dashboard.agent_retro.waste.wakeup_parallelism", "Wakeup Lag & Serial Queueing")
        default:
            let isZh = locale.language.languageCode?.identifier.hasPrefix("zh") == true
            return SkillsPseudoSkillGuard.scrubAcademicCodes(isZh ? item.labelZh : item.labelEn)
        }
    }

    private static func localizedRoleLabel(_ item: AgentHorizonWasteItem, locale: Locale) -> String {
        switch item.roleKey {
        case "m3": return DashboardL10n.tr("dashboard.agent_efficiency.role.top_coordinator", "Top-Level Coordinator")
        case "m2": return DashboardL10n.tr("dashboard.agent_efficiency.role.topic_dispatcher", "Topic Dispatcher")
        case "m1": return DashboardL10n.tr("dashboard.agent_efficiency.role.goal_lead", "Goal Lead (TL)")
        case "designer": return DashboardL10n.tr("dashboard.agent_efficiency.role.designer", "Visual Design (Designer)")
        case "writer": return DashboardL10n.tr("dashboard.agent_efficiency.role.writer", "Code Implementation (Writer)")
        case "reviewer": return DashboardL10n.tr("dashboard.agent_efficiency.role.reviewer", "Independent Review (Reviewer)")
        case "explorer": return DashboardL10n.tr("dashboard.agent_efficiency.role.explorer", "Code Exploration (Explorer)")
        case "pr_monitor": return DashboardL10n.tr("dashboard.agent_efficiency.role.pr_monitor", "Delivery Monitor (PR Monitor)")
        default:
            let isZh = locale.language.languageCode?.identifier.hasPrefix("zh") == true
            return SkillsPseudoSkillGuard.scrubAcademicCodes(isZh ? item.roleLabelZh : item.roleLabelEn)
        }
    }
}
#endif
