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

struct SkillsEvidence: Identifiable {
    let title: String
    let value: String
    let metadata: SkillsObservationMetadata
    var id: String { title }
}

public struct SkillsRoiDiagnosticsCardView: View {
    let summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?
    @State private var lens: SkillsRoiLens
    @State private var evidence: [SkillsEvidence] = []
    @State private var showingEvidence = false
    @Environment(\.theme) private var theme

    public init(summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?, initialLens: SkillsRoiLens = .usage) {
        self.summary = summary
        _lens = State(initialValue: initialLens)
    }

    public var body: some View {
        SolidModularCardContainer(title: skillsText("title", "Skills 效能与上下文 ROI 诊断 (S1–S12)"),
                                  subtitle: summary.map { _ in skillsText("read_only", "Personal observations · read-only") } ?? skillsText("coverage_unknown", "Coverage: unknown"),
                                  symbolName: "sparkles.square.filled.on.square") {
            VStack(alignment: .leading, spacing: Space.gap) {
                if let roi = summary?.skillsROI {
                    observationSummary(roi.metadata)
                    healthPills(roi.diagnostics)
                    Picker(skillsText("lens", "分析视角"), selection: $lens) {
                        ForEach(SkillsRoiLens.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 480, minHeight: 28)
                    if roi.metadata.coverage == "error" {
                        Label(skillsText("error_state", "Source error · retained observations are not current health"), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(theme.dangerOnSubtle)
                    } else if roi.metadata.coverage == "partial" {
                        Label(skillsText("loading_state", "Collecting observations · incomplete coverage"), systemImage: "hourglass")
                            .foregroundStyle(theme.warningOnSubtle)
                    }
                    switch lens {
                    case .usage: usage(roi)
                    case .disclosure: disclosure(roi.diagnostics)
                    case .context: context(roi.diagnostics)
                    }
                } else {
                    Label(skillsText("missing", "Unknown / missing · no Skills observations yet"), systemImage: "questionmark.circle")
                        .foregroundStyle(theme.neutrals.text(.body))
                }
            }
        }
        .popover(isPresented: $showingEvidence) { evidenceDrawer }
    }

    private func observationSummary(_ metadata: SkillsObservationMetadata) -> some View {
        HStack(alignment: .top, spacing: Space.gap) {
            Text(metadataLine(metadata)).font(.caption).foregroundStyle(theme.neutrals.text(.body))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            infoButton([.init(title: skillsText("observation", "Observation"), value: coverage(metadata.coverage), metadata: metadata)], id: "report")
        }
    }

    private func healthPills(_ d: SkillsRoiDiagnostics) -> some View {
        DashboardResponsiveGrid(wideColumns: 4, compactColumns: 2) {
            healthPill("pins", title: skillsText("pins", "S1 · Shared pins"), value: pinText(d.pins),
                       detail: skillsText("inspected", "Inspected") + " · " + number(d.pins?.metadata.sample),
                       facts: [fact(skillsText("behind", "Pins behind"), d.pins?.behind), fact(skillsText("synchronized", "Synchronized"), d.pins?.synchronized)])
            healthPill("gates", title: skillsText("gates", "S2 · CI catch / noise"), value: rate(d.gates?.catchRate) + " / " + rate(d.gates?.noiseRate),
                       detail: skillsText("runs", "Runs") + " · " + integer(d.gates?.runs),
                       facts: [fact(skillsText("catch", "Catch ratio"), d.gates?.catchRate), fact(skillsText("noise", "Noise ratio"), d.gates?.noiseRate), fact(skillsText("runs", "Runs"), d.gates?.runs)])
            healthPill("audit", title: skillsText("audit", "S3 · Audit / Evals"), value: integer(d.audit?.passed) + " / " + integer(d.audit?.total),
                       detail: skillsText("evals", "Evals") + " " + integer(d.audit?.evals) + " (+" + integer(d.audit?.evalDelta) + ")",
                       facts: [fact(skillsText("passed", "Audit passes"), d.audit?.passed), fact(skillsText("total", "Skills inspected"), d.audit?.total), fact(skillsText("evals", "Evals"), d.audit?.evals), fact(skillsText("eval_delta", "Weekly Eval change"), d.audit?.evalDelta)])
            healthPill("cache", title: skillsText("cache", "S11 · KV cache"), value: percent(d.context?.cacheHitPercent),
                       detail: skillsText("saved", "Saved") + " · " + decimal(d.context?.savedTokens) + " tok",
                       facts: [fact(skillsText("cache_hit", "KV hit (%)"), d.context?.cacheHitPercent), fact(skillsText("saved", "Saved tokens"), d.context?.savedTokens)])
        }
        .captureDashboardGeometry(id: "skills-health", role: "skillsHealthGrid")
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
                if facts.compactMap({ $0 }).contains(where: { $0.metadata.estimated == true }) {
                    Text(skillsText("estimated", "Estimated")).font(.caption2).foregroundStyle(theme.warningOnSubtle)
                }
            }
            .padding(Space.gap)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain).frame(minHeight: 28)
        .captureDashboardGeometry(id: "skills-\(id)", role: "skillsHealthPill")
    }

    private func usage(_ roi: SkillsRoiReport) -> some View {
        VStack(alignment: .leading, spacing: Space.gap) {
            Text(skillsText("usage_title", "Skill use, ROI and practice")).font(.headline)
            if let active = roi.diagnostics.usage {
                Text(activeSummary(active))
                    .font(.caption).foregroundStyle(theme.neutrals.text(.body))
            }
            usageTable(roi.diagnostics)
            dailyObservations(roi.skillsDaily)
        }
    }

    private func activeSummary(_ population: SkillsUsagePopulation) -> String {
        let count = integer(population.active)
        let idle = population.idle.isEmpty ? unknown : population.idle.joined(separator: ", ")
        return [skillsText("active", "Active skills"), count, skillsText("idle", "Idle (30d)"), idle].joined(separator: " · ")
    }

    private func usageTable(_ diagnostics: SkillsRoiDiagnostics) -> some View {
        Group {
            if diagnostics.usageRows.isEmpty { missingPopulation } else {
                Grid(alignment: .leading, horizontalSpacing: Space.gap, verticalSpacing: Space.gap) {
                    GridRow {
                        columnHeader(skillsText("skill", "Skill"), "skill")
                        columnHeader(skillsText("loads", "Loads\n7d / 30d"), "loads")
                        columnHeader("ROI", "roi")
                        columnHeader(skillsText("r1", "R1 pass"), "r1")
                        columnHeader(skillsText("touch", "Script\ntouch"), "touch")
                        columnHeader(skillsText("unpracticed", "Unpracticed"), "unpracticed")
                        columnHeader(skillsText("evidence", "Evidence"), "evidence")
                    }
                    ForEach(diagnostics.usageRows, id: \.skill) { row in
                        usageRow(row, script: diagnostics.scripts.first { $0.skill == row.skill })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func dailyObservations(_ rows: [SkillsDailyObservation]) -> some View {
        Group {
            DisclosureGroup(skillsText("daily_title", "Daily populations · day / source / skill (not additive)")) {
                VStack(alignment: .leading, spacing: Space.gap) {
                    Text(skillsText("daily_notice", "Attribution, tool and slash populations may overlap. No cross-source sum.")).font(.caption)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text("\(row.day) · \(row.source) · \(row.skill)").font(.caption)
                            Spacer()
                            Text(number(row.count) + " / " + number(row.sessions)).font(.caption.monospacedDigit()).fixedSize()
                            infoButton([.init(title: skillsText("daily_population", "Calls / sessions"), value: number(row.count) + " / " + number(row.sessions), metadata: row.metadata)], id: "daily-\(row.day)-\(row.source)-\(row.skill)")
                        }
                    }
                    if rows.isEmpty { missingPopulation }
                }
                .padding(.top, Space.gap)
            }
            .font(.caption).frame(minHeight: 28)
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
        ScrollView {
            VStack(alignment: .leading, spacing: Space.gap) {
                Text(skillsText("evidence", "Evidence")).font(.headline)
                if evidence.isEmpty { missingPopulation }
                ForEach(evidence) { item in
                    VStack(alignment: .leading, spacing: Space.gap / 2) {
                        Text(item.title + " · " + item.value).font(.caption.weight(.semibold))
                        Text(metadataLine(item.metadata)).font(.caption)
                        Text((item.metadata.start ?? unknown) + " → " + (item.metadata.end ?? unknown)).font(.caption)
                        if let method = item.metadata.method { Text(method).font(.caption).foregroundStyle(theme.neutrals.text(.body)) }
                    }
                }
            }.padding(Space.cardPadding)
        }.frame(width: 440).frame(maxHeight: 500)
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
    private func metadataLine(_ m: SkillsObservationMetadata) -> String {
        "\(m.window ?? unknown) CST · " + skillsText("as_of", "As of") + " \(m.asOf ?? unknown) · " + skillsText("sample", "Sample") + " \(number(m.sample)) · \(coverage(m.coverage))" + (m.estimated == true ? " · " + skillsText("estimated", "Estimated") : "")
    }
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
#endif
