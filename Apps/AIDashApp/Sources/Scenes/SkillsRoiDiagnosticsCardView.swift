#if os(macOS)
import SwiftUI
import AIDashUI
import DesignKit

private func skillsText(_ key: String, _ fallback: String) -> String { DashboardL10n.tr("dashboard.skills_roi.\(key)", fallback) }

public enum SkillsRoiLens: String, CaseIterable, Identifiable {
    case usage, evolution, flywheel
    public var id: String { rawValue }
    var title: String { switch self { case .usage: skillsText("usage", "活跃与通过率"); case .evolution: skillsText("evolution_lens", "版本进步"); case .flywheel: skillsText("flywheel", "自演进飞轮") } }
}
public enum SkillVersionEvolutionFilter: String, CaseIterable, Identifiable, Sendable { case meaningful, improved, regressed, all; public var id: String { rawValue }; var title: String { rawValue } }
public enum SkillRetroPillar: String, CaseIterable, Identifiable, Sendable { case l0,l1,l2,l3; public var id: String { rawValue } }
public enum SkillInspectorFilter: String, CaseIterable, Identifiable, Sendable { case all, active, needsOptimization, idle30d, repoBound, archivedGhosts; public var id: String { rawValue }; func matches(_ d: SkillInspectorDetail) -> Bool { switch self { case .all: !d.isGhost; case .active: !d.isGhost && d.loads30d > 0 && d.statusLabel != "needs_optimization"; case .needsOptimization: !d.isGhost && d.statusLabel == "needs_optimization"; case .idle30d: !d.isGhost && d.loads30d == 0; case .repoBound: !d.isGhost && d.scope == "repo_bound"; case .archivedGhosts: d.isGhost } } }
public enum SkillInspectorSubTab: String, CaseIterable, Identifiable, Sendable { case definition, scripts, evals, evolution; public var id: String { rawValue } }

public struct DashboardResponsiveGrid<Content: View>: View {
    private let content: Content
    public init(wideColumns: Int = 4, compactColumns: Int = 2, @ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View { ViewThatFits(in: .horizontal) { LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) { content }; VStack(spacing: 12) { content } } }
}

public struct SkillsRoiDiagnosticsCardView: View {
    let summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?
    @State private var lens: SkillsRoiLens
    @State private var showingMetadata = false
    @State private var inspectorFilter: SkillInspectorFilter
    @State private var evolutionFilter: SkillVersionEvolutionFilter
    public init(summary: LiveDashboardTelemetryReader.LiveEfficiencySummary?, initialLens: SkillsRoiLens = .usage, showDailyPopulations: Bool = false, initialSelectedSkill: String? = nil, initialSelectedPillar: SkillRetroPillar? = nil, initialEvolutionFilter: SkillVersionEvolutionFilter = .meaningful, initialFilter: SkillInspectorFilter = .all, initialSubTab: SkillInspectorSubTab = .definition, initialPreviewRelativePath: String? = nil, previewHomeURL: URL? = nil) { self.summary=summary; _lens=State(initialValue: initialLens); _inspectorFilter=State(initialValue: initialFilter); _evolutionFilter=State(initialValue: initialEvolutionFilter) }
    public var body: some View { SolidModularCardContainer(title: skillsText("title", "Skills 状态"), subtitle: nil, symbolName: "sparkles") { if let report=summary?.skillsROI { VStack(alignment:.leading,spacing:16) { HStack { Spacer(); Button { showingMetadata = true } label: { Image(systemName: "info.circle") }.buttonStyle(.plain).frame(minWidth:28,minHeight:28).accessibilityLabel(skillsText("metadata", "数据窗口")) }.popover(isPresented: $showingMetadata) { VStack(alignment:.leading,spacing:8) { Text(skillsText("metadata", "数据窗口")); Text(report.metadata.window ?? skillsText("window_unknown", "未知窗口")); Text(report.metadata.asOf ?? skillsText("as_of_unknown", "更新时间未知")) }.padding(16) }; vitals(report); Picker(skillsText("lens", "状态切面"), selection:$lens) { ForEach(SkillsRoiLens.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).frame(minHeight:28).captureDashboardGeometry(id:"skills-lens",role:"segmented"); if let coverage=report.metadata.coverage, coverage == "partial" || coverage == "error" { Text(coverage == "partial" ? skillsText("loading_state", "数据覆盖不完整") : skillsText("error_state", "数据源暂不可用")).font(.caption) }; stage(report) } } else { Text(skillsText("missing", "暂无 Skills 状态数据")).foregroundStyle(.secondary) } } }
    private func managedDetails(_ report: SkillsRoiReport) -> [SkillInspectorDetail] { report.skillDetails.isEmpty ? report.diagnostics.resolvedSkillDetails : report.skillDetails }
    private func vitals(_ report: SkillsRoiReport) -> some View {
        let managed = managedDetails(report).filter { !$0.isGhost }
        let usage = report.diagnostics.usageRows
        let total = managed.isEmpty ? (report.diagnostics.audit?.total.value ?? usage.count) : managed.count
        let healthy = managed.isEmpty ? (report.diagnostics.audit?.passed.value ?? 0) : managed.filter { $0.statusLabel != "needs_optimization" && !Set(report.versionEvolution.filter { $0.status == "regressed" }.map(\.skill)).contains($0.skill) }.count
        let improved = report.versionEvolution.filter { $0.status == "improved" }.count
        let regressed = report.versionEvolution.filter { $0.status == "regressed" }.count
        let calls = managed.isEmpty ? usage.reduce(0) { $0 + ($1.loads7d.value ?? 0) } : managed.reduce(0) { $0 + $1.loads7d }
        let month = managed.isEmpty ? usage.reduce(0) { $0 + ($1.loads30d.value ?? 0) } : managed.reduce(0) { $0 + $1.loads30d }
        let active = managed.filter { $0.loads30d > 0 }.count
        let idle = managed.filter { $0.loads30d == 0 }.count
        let direction = month == 0 ? "→" : (Double(calls) > Double(month) / 4 * 1.05 ? "↑" : (Double(calls) < Double(month) / 4 * 0.95 ? "↓" : "→"))
        let retro = report.resolvedSkillRetro
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(total == 0 ? "—" : "\(healthy) / \(total)").font(.system(size: 28, weight: .bold, design: .monospaced)).accessibilityIdentifier("skills-vital-healthy")
                Spacer()
                Text(improved + regressed == 0 ? skillsText("active_idle", "活跃 \(active) · 闲置 \(idle)") : skillsText("trend", "↑\(improved) 变好 · ↓\(regressed) 退化")).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                vital("pass_rate", passRateSummary(report, managed: managed), "skills-vital-pass-rate")
                vital("calls_7d", "\(calls) \(direction)", "skills-vital-calls-7d", detail: skillsText("calls_30d", "近 30 天 \(month) 次"))
                vital("flywheel", skillsText("flywheel_summary", "已治愈 \(retro.watermarkedResolvedRoadblocks.count) · 优化中 \(retro.proposals.count)"), "skills-vital-flywheel", detail: skillsText("flywheel_cadence", retro.slowFlywheelReady ? "慢飞轮就绪 · 评测用例 \(report.diagnostics.audit?.evals.value ?? 0)" : "快飞轮收敛中 · 评测用例 \(report.diagnostics.audit?.evals.value ?? 0)"))
            }.captureDashboardGeometry(id: "skills-p0-vitals", role: "vitals")
        }.padding(16).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
    private func vital(_ key: String, _ value: String, _ id: String, detail: String? = nil) -> some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(.system(size: 16, weight: .semibold, design: .monospaced)).lineLimit(1); Text(skillsText(key, key)).font(.caption).foregroundStyle(.secondary); if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) } }.accessibilityIdentifier(id) }
    private func passRateSummary(_ report: SkillsRoiReport, managed: [SkillInspectorDetail]) -> String { let current = overallPassValue(report, managed: managed); guard let current else { return "—" }; let before = report.versionEvolution.compactMap { $0.beforeVersion }.filter { $0.r1Total > 0 }; let beforeRate = before.isEmpty ? nil : Double(before.reduce(0) { $0 + $1.r1Pass }) / Double(before.reduce(0) { $0 + $1.r1Total }); let delta = beforeRate.map { current - $0 }; return delta.map { "\(Int(current * 100))% \($0 >= 0 ? "+" : "")\(Int($0 * 100))pp" } ?? "\(Int(current * 100))%" }
    private func overallPassValue(_ report: SkillsRoiReport, managed: [SkillInspectorDetail]) -> Double? { let evo = report.versionEvolution.filter { $0.currentVersion.r1Total > 0 }; if !evo.isEmpty { let total = evo.reduce(0) { $0 + $1.currentVersion.r1Total }; return total == 0 ? nil : Double(evo.reduce(0) { $0 + $1.currentVersion.r1Pass }) / Double(total) }; let values = managed.compactMap(\.r1PassRate); return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    private func overallPassRate(_ report:SkillsRoiReport, managed:[SkillInspectorDetail])->String { let evo=report.versionEvolution.filter{$0.currentVersion.r1Total>0}; let current:Double? = evo.isEmpty ? (managed.isEmpty ? nil : { let values=managed.compactMap(\.r1PassRate); return values.isEmpty ? nil : values.reduce(0,+)/Double(values.count) }()) : { let p=evo.reduce(0){$0+$1.currentVersion.r1Pass}, t=evo.reduce(0){$0+$1.currentVersion.r1Total}; return t == 0 ? nil : Double(p)/Double(t) }(); guard let current else { return "—" }; return "\(Int(current*100))%" }
    @ViewBuilder private func stage(_ report:SkillsRoiReport)->some View { switch lens { case .usage: rows(report, details: managedDetails(report).filter{ inspectorFilter.matches($0) }); case .evolution: rows(report, evolution: Self.filterEvolutionRows(report.versionEvolution, filter: evolutionFilter)); case .flywheel: let names=Set(report.resolvedSkillRetro.watermarkedResolvedRoadblocks.map(\.skill)+report.resolvedSkillRetro.proposals.map(\.skill)); rows(report, evolution: report.versionEvolution.filter { names.contains($0.skill) }, flywheel:true) } }
    private func rows(_ report: SkillsRoiReport, details: [SkillInspectorDetail] = [], evolution: [SkillVersionEvolutionRow] = [], flywheel: Bool = false) -> some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                if proxy.size.width < 680 {
                    if !details.isEmpty { ForEach(details) { detail in compactRow(detail, evolution: report.versionEvolution.first { $0.skill == detail.skill }, flywheel: flywheel) } }
                    else { ForEach(evolution) { compactEvolutionRow($0, flywheel: flywheel) } }
                } else {
                    HStack(spacing: 12) { Text(skillsText("skill", "Skill")).frame(maxWidth: .infinity, alignment: .leading); Text(skillsText("calls_7d", "7d 调用")).frame(width: 96, alignment: .trailing); Text(skillsText("pass_rate", "通过率")).frame(width: 176, alignment: .trailing); Text(skillsText("status", "状态")).frame(width: 88, alignment: .trailing) }.font(.caption).foregroundStyle(.secondary)
                    if !details.isEmpty { ForEach(details) { detail in statusRow(detail, evolution: report.versionEvolution.first { $0.skill == detail.skill }, flywheel: flywheel) } }
                    else { ForEach(evolution) { evoRow($0, flywheel: flywheel) } }
                }
            }
            .captureDashboardGeometry(id: "skills-table-header", role: "header")
            .captureDashboardGeometry(id: "skills-status-stage", role: "stage")
        }
        .frame(minHeight: details.isEmpty && evolution.isEmpty ? 44 : CGFloat(max(details.count, evolution.count) * 58 + 28))
    }
    private func compactRow(_ detail: SkillInspectorDetail, evolution: SkillVersionEvolutionRow?, flywheel: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) { HStack { Text(detail.skill).font(.subheadline); Text(Self.cleanVersionLabel(evolution?.combinedVersion ?? "—")).font(.caption).foregroundStyle(.secondary); Spacer(); Text(statusText(detail.statusLabel)).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(.secondary.opacity(0.14), in: Capsule()) }; HStack { Text("\(detail.loads7d) ").font(.caption.monospacedDigit()); Spacer(); rateCell(detail.r1PassRate ?? evolution?.currentVersion.r1PassRate, before: evolution?.beforeVersion?.r1PassRate) } }.padding(.vertical, 8).accessibilityIdentifier("skills-row-\(detail.skill)")
    }
    private func compactEvolutionRow(_ row: SkillVersionEvolutionRow, flywheel: Bool) -> some View { VStack(alignment: .leading, spacing: 6) { HStack { Text(row.skill); Text(Self.cleanVersionLabel(row.versionTransitionLabel)).font(.caption).foregroundStyle(.secondary); Spacer(); Text(flywheel ? (row.status == "improved" ? skillsText("cured", "已治愈") : skillsText("optimizing", "优化中")) : statusText(row.status)).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(.secondary.opacity(0.14), in: Capsule()) }; HStack { Text("\(row.currentVersion.invocations) ").font(.caption.monospacedDigit()); Spacer(); rateCell(row.currentVersion.r1PassRate ?? (row.currentVersion.exit2ErrorRate.map { 1 - $0 } ?? (row.currentVersion.r1Total > 0 ? Double(row.currentVersion.r1Pass) / Double(row.currentVersion.r1Total) : nil)), before: row.beforeVersion?.r1PassRate) } }.padding(.vertical, 8).accessibilityIdentifier("skills-row-\(row.skill)")
    }
    private func statusRow(_ detail:SkillInspectorDetail,evolution:SkillVersionEvolutionRow?,flywheel:Bool)->some View { HStack(spacing:12) { VStack(alignment:.leading) { Text(detail.skill).font(.subheadline); Text(evolution.map { Self.cleanVersionLabel($0.combinedVersion) } ?? "—").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading); Text("\(detail.loads7d)").font(.caption.monospacedDigit()).frame(width:96,alignment:.trailing); rateCell(detail.r1PassRate ?? evolution?.currentVersion.r1PassRate, before:evolution?.beforeVersion?.r1PassRate); Text(flywheel ? (detail.statusLabel == "needs_optimization" ? skillsText("optimizing", "优化中") : skillsText("cured", "已治愈")) : statusText(detail.statusLabel)).font(.caption).padding(.horizontal,8).padding(.vertical,4).background(.secondary.opacity(0.14),in:Capsule()).frame(width:88,alignment:.trailing) }.padding(.vertical,8).accessibilityIdentifier("skills-row-\(detail.skill)") }
    private func evoRow(_ row:SkillVersionEvolutionRow, flywheel: Bool)->some View { HStack(spacing:12) { VStack(alignment:.leading) { Text(row.skill); Text(Self.cleanVersionLabel(row.versionTransitionLabel)).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading); Text("\(row.currentVersion.invocations)").font(.caption.monospacedDigit()).frame(width:96,alignment:.trailing); rateCell(row.currentVersion.r1PassRate ?? (row.currentVersion.exit2ErrorRate.map { 1 - $0 } ?? (row.currentVersion.r1Total > 0 ? Double(row.currentVersion.r1Pass) / Double(row.currentVersion.r1Total) : nil)), before:row.beforeVersion?.r1PassRate); Text(flywheel ? (row.status == "improved" ? skillsText("cured", "已治愈") : skillsText("optimizing", "优化中")) : statusText(row.status)).font(.caption).padding(.horizontal,8).padding(.vertical,4).background(.secondary.opacity(0.14),in:Capsule()).frame(width:88,alignment:.trailing) }.padding(.vertical,8).accessibilityIdentifier("skills-row-\(row.skill)") }
    private func rateCell(_ current:Double?,before:Double?)->some View { HStack(spacing:6) { Text(current.map{"\(Int($0*100))%"} ?? "—").font(.caption.monospacedDigit()); VStack(spacing:2) { bar(before ?? current, .secondary); bar(current, .accentColor) }.frame(width:48) }.frame(width:176,alignment:.trailing) }
    private func bar(_ value:Double?,_ color:Color)->some View { GeometryReader { proxy in RoundedRectangle(cornerRadius:2).fill(color.opacity(0.55)).frame(width:max(0,min(proxy.size.width,proxy.size.width*(value ?? 0))),height:3) }.frame(width:48,height:3) }
    private func statusText(_ raw:String)->String { switch raw { case "improved":skillsText("improved","变好"); case "regressed":skillsText("regressed","退化"); case "needs_optimization":skillsText("observing","观察中"); case "zombie_30d":skillsText("idle","闲置"); case "baseline":skillsText("baseline","基准"); default:skillsText("healthy","健康") } }
    public static func cleanVersionLabel(_ raw:String)->String { raw.split(separator:"→",omittingEmptySubsequences:false).map { part in let text=part.trimmingCharacters(in:.whitespaces); let v=text.split(separator:"@").first.map(String.init) ?? text; if let range=v.range(of:"+v") { return String(v[v.index(after: range.lowerBound)...]).split(separator:"@").first.map(String.init) ?? v }; return v }.joined(separator:" → ") }
    public static func activeSkillRow(in diagnostics:SkillsRoiDiagnostics,selectedSkill:String?)->SkillsUsageRow? { diagnostics.usageRows.first{$0.skill==selectedSkill} ?? diagnostics.usageRows.first }
    public static func activeSkillDetail(in report:SkillsRoiReport,selectedSkill:String?,filter: SkillInspectorFilter = .all)->SkillInspectorDetail? { let pool=managedDetails(report).filter{filter.matches($0)}; return pool.first{$0.skill==selectedSkill} ?? pool.first }
    public static func filterEvolutionRows(_ rows:[SkillVersionEvolutionRow],filter:SkillVersionEvolutionFilter,watermarkedSkills: Set<String> = [])->[SkillVersionEvolutionRow] { rows.filter { switch filter { case .all:true; case .meaningful:$0.status != "observing" || $0.beforeVersion != nil; case .improved:$0.status=="improved"; case .regressed:$0.status=="regressed" } } }
    public static func formatVersionComparison(before:String?,current:String,status:String="")->String { cleanVersionLabel((before.map{"\($0) → "} ?? "")+current) }
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
        versionEvolution = !filteredTopEvo.isEmpty ? filteredTopEvo : diag.versionEvolution
        skillRetro = (try? f.value("skill_retro", as: SkillRetroFourLayerSummary.self)) ?? diag.skillRetro
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
#endif
