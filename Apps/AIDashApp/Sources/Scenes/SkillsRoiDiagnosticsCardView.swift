#if os(macOS)
import SwiftUI
import AIDashUI
import DesignKit

private func skillsText(_ key: String, _ fallback: String) -> String {
    DashboardL10n.tr("dashboard.skills_roi.\(key)", fallback)
}

public enum SkillsRoiLens: String, CaseIterable, Identifiable {
    case usage, disclosure, context
    public var id: String { rawValue }
    var title: String {
        switch self {
        case .usage: return skillsText("usage", "Usage")
        case .disclosure: return skillsText("disclosure", "Disclosure / Escapes")
        case .context: return skillsText("context", "Context")
        }
    }
}

struct SkillsEvidence: Identifiable { let title: String, value: String, metadata: SkillsObservationMetadata; var id: String { title } }

public struct SkillsRoiDiagnosticsCardView: View {
    let summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?
    @State private var lens: SkillsRoiLens
    @State private var evidence: [SkillsEvidence] = []
    @State private var showingEvidence = false
    @State private var dailyExpanded: Bool
    @Environment(\.theme) private var theme

    public init(summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?, initialLens: SkillsRoiLens = .usage, showDailyPopulations: Bool = false) {
        self.summary = summary; _lens = State(initialValue: initialLens); _dailyExpanded = State(initialValue: showDailyPopulations)
    }

    public var body: some View {
        SolidModularCardContainer(title: skillsText("title", "Skills 效能与上下文 ROI 诊断 (S1–S12)"),
                                  subtitle: summary.map { _ in skillsText("read_only", "Personal observations · read-only") } ?? skillsText("coverage_unknown", "Coverage: unknown"),
                                  symbolName: "sparkles.square.filled.on.square") {
            VStack(alignment: .leading, spacing: Space.gap) {
                if let roi = summary?.skillsROI {
                    observationSummary(roi.metadata); healthPills(roi.diagnostics)
                    HStack(spacing: Space.gap / 2) {
                        ForEach(SkillsRoiLens.allCases) { option in
                            Button(option.title) { lens = option }
                                .buttonStyle(.bordered).controlSize(.small)
                                .tint(lens == option ? theme.primary.primary : theme.neutrals.text(.body))
                                .frame(minWidth: 28, minHeight: 28).accessibilityAddTraits(lens == option ? .isSelected : [])
                                .captureDashboardGeometry(id: "skills-lens-\(option.id)", role: "button")
                        }
                    }
                    if roi.metadata.coverage == "error" {
                        Label(skillsText("error_state", "Source error · retained observations are not current health"), systemImage: "exclamationmark.triangle").foregroundStyle(theme.dangerOnSubtle)
                    } else if roi.metadata.coverage == "partial" {
                        Label(skillsText("loading_state", "Collecting observations · incomplete coverage"), systemImage: "hourglass").foregroundStyle(theme.warningOnSubtle)
                    }
                    switch lens {
                    case .usage: usage(roi)
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
            healthPill("pins", title: skillsText("pins", "S1 · Shared pins"), value: pinText(d.pins), detail: skillsText("inspected", "Inspected") + " · " + number(d.pins?.metadata.sample),
                       facts: [fact(skillsText("behind", "Pins behind"), d.pins?.behind), fact(skillsText("synchronized", "Synchronized"), d.pins?.synchronized)])
            healthPill("gates", title: skillsText("gates", "S2 · CI catch / noise"), value: rate(d.gates?.catchRate) + " / " + rate(d.gates?.noiseRate), detail: skillsText("runs", "Runs") + " · " + integer(d.gates?.runs),
                       facts: [fact(skillsText("catch", "Catch ratio"), d.gates?.catchRate), fact(skillsText("noise", "Noise ratio"), d.gates?.noiseRate), fact(skillsText("runs", "Runs"), d.gates?.runs)])
            healthPill("audit", title: skillsText("audit", "S3 · Audit / Evals"), value: integer(d.audit?.passed) + " / " + integer(d.audit?.total), detail: skillsText("evals", "Evals") + " " + integer(d.audit?.evals) + " (+" + integer(d.audit?.evalDelta) + ")",
                       facts: [fact(skillsText("passed", "Audit passes"), d.audit?.passed), fact(skillsText("total", "Skills inspected"), d.audit?.total), fact(skillsText("evals", "Evals"), d.audit?.evals), fact(skillsText("eval_delta", "Weekly Eval change"), d.audit?.evalDelta)])
            healthPill("cache", title: skillsText("cache", "S11 · KV cache"), value: percent(d.context?.cacheHitPercent), detail: skillsText("saved", "Saved") + " · " + decimal(d.context?.savedTokens) + " tok",
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

    private func usage(_ roi: SkillsRoiReport) -> some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            Text(skillsText("usage_title", "Skill use, ROI and practice")).font(.headline)
            if let active = roi.diagnostics.usage { Text(activeSummary(active)).font(.caption).foregroundStyle(theme.neutrals.text(.body)) }
            usageTable(roi.diagnostics); dailyObservations(roi.skillsDaily)
        }
    }

    private func activeSummary(_ population: SkillsUsagePopulation) -> String {
        let count = integer(population.active), idle = population.idle.isEmpty ? unknown : population.idle.joined(separator: ", ")
        return [skillsText("active", "Active skills"), count, skillsText("idle", "Idle (30d)"), idle].joined(separator: " · ")
    }

    private func usageTable(_ diagnostics: SkillsRoiDiagnostics) -> some View {
        Group {
            if diagnostics.usageRows.isEmpty { missingPopulation } else {
                Grid(alignment: .leading, horizontalSpacing: Space.gap, verticalSpacing: Space.gap) {
                    GridRow {
                        columnHeader(skillsText("skill", "Skill"), "skill"); columnHeader(skillsText("loads", "Loads") + "\n7d / 30d", "loads"); columnHeader("ROI", "roi")
                        columnHeader(skillsText("r1", "R1 pass"), "r1"); columnHeader(skillsText("touch", "Script\ntouch"), "touch"); columnHeader(skillsText("unpracticed", "Unpracticed"), "unpracticed"); columnHeader(skillsText("evidence", "Evidence"), "evidence")
                    }
                    ForEach(diagnostics.usageRows, id: \.skill) { row in usageRow(row, script: diagnostics.scripts.first { $0.skill == row.skill }) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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

    private func usageRow(_ row: SkillsUsageRow, script: SkillsUsageRow?) -> some View {
        let touch = row.touch.value == nil ? script?.touch : row.touch
        let unpracticed = row.unpracticed.value == nil ? script?.unpracticed : row.unpracticed
        let facts: [SkillsEvidence?] = [
            fact("7d " + skillsText("loads", "Loads"), row.loads7d),
            fact("30d " + skillsText("loads", "Loads"), row.loads30d), fact("ROI", row.roi),
            fact(skillsText("r1", "R1 pass"), row.r1Pass), fact(skillsText("r1_sample", "R1 reviews"), row.r1Total),
            fact(skillsText("touch", "Script touch"), touch), fact(skillsText("unpracticed", "Unpracticed"), unpracticed),
            .init(title: skillsText("diagnosis", "Diagnosis"), value: row.diagnosis ?? unknown, metadata: row.metadata)
        ]
        return GridRow {
            VStack(alignment: .leading, spacing: Space.gap / 2) {
                Text(row.skill).font(.caption.weight(.semibold))
                Text(row.diagnosis ?? unknown).font(.caption2).foregroundStyle(theme.neutrals.text(.body))
            }
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: Space.gap * 12, alignment: .leading)
            .captureDashboardGeometry(id: "usage-\(row.skill)-skill", role: "skillsTableCell")
            tableValue(integer(row.loads7d) + " / " + integer(row.loads30d), row.skill, "loads")
            tableValue(decimal(row.roi), row.skill, "roi")
            tableValue((row.r1Total.value ?? 0) > 0 ? rate(row.r1Pass) : unknown, row.skill, "r1")
            tableValue(rate(touch), row.skill, "touch")
            tableValue(rate(unpracticed), row.skill, "unpracticed")
            infoButton(facts, id: row.skill).frame(maxWidth: .infinity, alignment: .leading)
                .captureDashboardGeometry(id: "usage-\(row.skill)-evidence", role: "skillsTableCell")
        }
    }

    private func disclosure(_ d: SkillsRoiDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            Text(skillsText("funnel_title", "S7 · L0 → L1 disclosure")).font(.headline)
            Text(skillsText("funnel_notice", "Deep-read violations are observed separately; no measured L2 completion count.")).font(.caption).foregroundStyle(theme.neutrals.text(.body))
            if d.disclosure.isEmpty { missingPopulation }
            ForEach(d.disclosure, id: \.skill) { row in
                HStack(alignment: .top) {
                    Text(row.skill).font(.caption.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: Space.gap / 2) {
                        Text("L0 " + rate(row.l0) + " · L1 " + rate(row.l1)).font(.caption.monospacedDigit())
                        Text(skillsText("greedy", "Deep-read violations") + " " + rate(row.greedy)).font(.caption.monospacedDigit())
                        proportionalBar([row.l0.value, row.l1.value, row.greedy.value])
                    }.frame(maxWidth: .infinity)
                    infoButton([fact("L0", row.l0), fact("L1", row.l1), fact(skillsText("greedy", "Deep-read violations"), row.greedy), fact(skillsText("context_tokens", "Context tokens"), row.contextTokens)], id: "funnel-\(row.skill)")
                }.captureDashboardGeometry(id: "funnel-\(row.skill)", role: "skillsDiagnosticRow")
            }
            Text(skillsText("churn_title", "S8 · Post-skill churn")).font(.headline)
            if d.churn.isEmpty { missingPopulation }
            ForEach(d.churn, id: \.skill) { row in
                metricRow(row.skill, value: skillsText("edits", "Edits") + " " + integer(row.edits) + " · " + skillsText("retries", "Retries") + " " + integer(row.retries), facts: [fact(skillsText("edits", "Edits"), row.edits), fact(skillsText("retries", "Retries"), row.retries)], id: "churn-\(row.skill)")
            }
            Text(skillsText("escape_title", "S9 · Escapes by attribution")).font(.headline)
            if d.escapes.isEmpty { missingPopulation }
            ForEach(d.escapes, id: \.skill) { row in
                metricRow(row.skill, value: "IMPL_BUG " + integer(row.implementation) + " · SPEC_GAP " + integer(row.specification), facts: [fact("IMPL_BUG", row.implementation), fact("SPEC_GAP", row.specification)], id: "escapes-\(row.skill)")
            }
        }
    }

    private func context(_ d: SkillsRoiDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            Text(skillsText("composition_title", "S11 · Context composition")).font(.headline)
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
            Text(skillsText("burn_title", "S12 · Tool calls above 10k tokens")).font(.headline)
            let tools = d.tools.filter { ($0.bloated.value ?? 0) > 0 }
            if tools.isEmpty { missingPopulation }
            ForEach(tools, id: \.tool) { tool in
                metricRow(tool.tool, value: integer(tool.bloated) + " / " + integer(tool.calls) + " · p95 " + decimal(tool.p95) + " tok", facts: [fact(skillsText("bloated", "Calls >10k"), tool.bloated), fact(skillsText("calls", "Calls"), tool.calls), fact(skillsText("total_tokens", "Total tokens"), tool.total), fact("p95 tok", tool.p95), fact(skillsText("share", "Share (%)"), tool.share)], id: "tool-\(tool.tool)")
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

public struct SkillsRoiDiagnostics: Decodable, Sendable, Equatable {
    public let pins: SkillsPinHealth?, gates: SkillsGateHealth?, audit: SkillsAuditHealth?, usage: SkillsUsagePopulation?
    public let scripts: [SkillsUsageRow], disclosure: [SkillsDisclosureRow], churn: [SkillsChurnRow], escapes: [SkillsEscapeRow], ranking: [SkillsUsageRow], context: SkillsContextHealth?, tools: [SkillsToolBurnRow]
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder)
        pins = try f.value("S1_pin_drift"); gates = try f.value("S2_gate_catch"); audit = try f.value("S3_skill_health"); usage = try f.value("S4_usage_and_r1")
        scripts = try f.value("S6_load_vs_script") ?? []; disclosure = try f.value("S7_disclosure_funnel") ?? []; churn = try f.value("S8_post_skill_churn") ?? []
        escapes = try f.value("S9_escape_attribution") ?? []; ranking = try f.value("S10_skill_roi_ranking") ?? []; context = try f.value("S11_context_composition"); tools = try f.value("S12_tool_context_burn") ?? []
    }
    public var usageRows: [SkillsUsageRow] {
        let ranked = ranking.isEmpty ? (usage?.top ?? []) : ranking, names = Set(ranked.map(\.skill))
        return ranked + scripts.filter { !names.contains($0.skill) }
    }
}

public struct SkillsRoiReport: Decodable, Sendable, Equatable {
    public let metadata: SkillsObservationMetadata, diagnostics: SkillsRoiDiagnostics, skillsDaily: [SkillsDailyObservation], errors: [String]
    public init(from decoder: Decoder) throws {
        let f = try SkillsFields(decoder); metadata = f.metadata
        diagnostics = try f.value("diagnostics") ?? SkillsRoiDiagnostics(from: decoder); skillsDaily = try f.value("skills_daily") ?? []; errors = try f.value("errors") ?? []
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
#endif
