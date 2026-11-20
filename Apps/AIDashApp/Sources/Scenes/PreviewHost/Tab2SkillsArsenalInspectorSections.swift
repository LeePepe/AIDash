#if os(macOS)
import SwiftUI

private enum Tab2InstrumentMode: String, CaseIterable {
    case northstar, directory, funnel, practice, escapes, reader, scripts, evals, channels, action
}

@MainActor
public enum Tab2SkillsArsenalInspectorSections {
    public static let descriptors: [PreviewVariantDescriptor] = [
        PreviewVariantDescriptor(id: "tab2-v01", tab: .agentEfficiency, badgeCode: "V01", title: "Skills 军火库北极星总览", metricTags: ["Managed Skills", "Contract Pass", "Unpracticed %"], symbolName: "sparkles.rectangle.stack", topologySignature: "tab2-v01:arsenal-four-up+top3-alert-drawer"),
        PreviewVariantDescriptor(id: "tab2-v02", tab: .agentEfficiency, badgeCode: "V02", title: "技能分类主从名录", metricTags: ["Orchestration", "Product Design", "Engineering Delivery"], symbolName: "list.bullet.rectangle", topologySignature: "tab2-v02:grouped-skill-directory+dual-badges+skill-detail-drawer"),
        PreviewVariantDescriptor(id: "tab2-v03", tab: .agentEfficiency, badgeCode: "V03", title: "静态体积与渐进式披露漏斗", metricTags: ["L0 / L1 Tokens", "0-Hit References", "Progressive Disclosure"], symbolName: "filter", topologySignature: "tab2-v03:disclosure-funnel+zombie-reference-highlight+hit-drawer"),
        PreviewVariantDescriptor(id: "tab2-v04", tab: .agentEfficiency, badgeCode: "V04", title: "光读不练率与脚本触发排行", metricTags: ["Loads vs Script Calls", "Unpracticed %", "30d"], symbolName: "figure.run", topologySignature: "tab2-v04:butterfly-load-script-bars+practice-filter+script-drawer"),
        PreviewVariantDescriptor(id: "tab2-v05", tab: .agentEfficiency, badgeCode: "V05", title: "技能返工擦写与逃逸归因", metricTags: ["Edit Churn", "Implementation Escape", "Specification Gap"], symbolName: "arrow.left.and.right", topologySignature: "tab2-v05:diverging-churn-bars+escape-attribution+diagnostic-drawer"),
        PreviewVariantDescriptor(id: "tab2-v06", tab: .agentEfficiency, badgeCode: "V06", title: "L1 / L2 文件树与原文阅读器", metricTags: ["SKILL.md", "references/*", "Four-level Fallback"], symbolName: "doc.text.magnifyingglass", topologySignature: "tab2-v06:file-tree+markdown-reader+copy-path-drawer"),
        PreviewVariantDescriptor(id: "tab2-v07", tab: .agentEfficiency, badgeCode: "V07", title: "确定性脚本执行账本", metricTags: ["30d Calls", "Success Rate", "P95 ms"], symbolName: "terminal", topologySignature: "tab2-v07:script-ledger+success-progress+latency-drawer"),
        PreviewVariantDescriptor(id: "tab2-v08", tab: .agentEfficiency, badgeCode: "V08", title: "Eval 门禁抽屉检视器", metricTags: ["Caught vs Escaped", "CLI / Contract", "Strict Command"], symbolName: "checkmark.shield", topologySignature: "tab2-v08:eval-matrix+caught-escaped-counters+command-drawer"),
        PreviewVariantDescriptor(id: "tab2-v09", tab: .agentEfficiency, badgeCode: "V09", title: "跨渠道技能调用热力矩阵", metricTags: ["Copilot", "Claude", "Codex", "GTT"], symbolName: "square.grid.3x3", topologySignature: "tab2-v09:channel-heat-matrix+column-sort+usage-drawer"),
        PreviewVariantDescriptor(id: "tab2-v10", tab: .agentEfficiency, badgeCode: "V10", title: "技能瘦身与门禁下沉动作台", metricTags: ["Current → Target", "0-Hit Cleanup", "Gate Downshift"], symbolName: "scissors", topologySignature: "tab2-v10:optimization-workbench+before-after-bars+action-drawer")
    ]

    @ViewBuilder
    public static func view(for descriptor: PreviewVariantDescriptor, data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View {
        PreviewSkillsInstrumentSection(descriptor: descriptor, mode: mode(for: descriptor), data: data, globalExpandAll: globalExpandAll, speed: speed)
    }

    public static func v01(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View { view(for: descriptors[0], data: data, globalExpandAll: globalExpandAll, speed: speed) }
    public static func v02(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View { view(for: descriptors[1], data: data, globalExpandAll: globalExpandAll, speed: speed) }
    public static func v03(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View { view(for: descriptors[2], data: data, globalExpandAll: globalExpandAll, speed: speed) }
    public static func v04(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View { view(for: descriptors[3], data: data, globalExpandAll: globalExpandAll, speed: speed) }
    public static func v05(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View { view(for: descriptors[4], data: data, globalExpandAll: globalExpandAll, speed: speed) }
    public static func v06(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View { view(for: descriptors[5], data: data, globalExpandAll: globalExpandAll, speed: speed) }
    public static func v07(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View { view(for: descriptors[6], data: data, globalExpandAll: globalExpandAll, speed: speed) }
    public static func v08(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View { view(for: descriptors[7], data: data, globalExpandAll: globalExpandAll, speed: speed) }
    public static func v09(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View { view(for: descriptors[8], data: data, globalExpandAll: globalExpandAll, speed: speed) }
    public static func v10(data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View { view(for: descriptors[9], data: data, globalExpandAll: globalExpandAll, speed: speed) }

    private static func mode(for descriptor: PreviewVariantDescriptor) -> Tab2InstrumentMode {
        switch descriptor.id {
        case "tab2-v01": return .northstar
        case "tab2-v02": return .directory
        case "tab2-v03": return .funnel
        case "tab2-v04": return .practice
        case "tab2-v05": return .escapes
        case "tab2-v06": return .reader
        case "tab2-v07": return .scripts
        case "tab2-v08": return .evals
        case "tab2-v09": return .channels
        default: return .action
        }
    }
}

private struct PreviewSkillsInstrumentSection: View {
    let descriptor: PreviewVariantDescriptor
    let mode: Tab2InstrumentMode
    let data: AIDashPreviewSampleData
    let globalExpandAll: Bool
    let speed: PreviewSpeedMultiplier
    @State private var drawerExpanded = false
    @State private var selectedIndex = 0
    @State private var filterMode = 0

    private var expanded: Bool { globalExpandAll || drawerExpanded }
    private var activeSkill: PreviewSkillMetric { data.skills[selectedIndex % data.skills.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: descriptor.symbolName).font(.title3.weight(.semibold)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.title).font(.headline.weight(.semibold))
                    Text(descriptor.metricTags.joined(separator: "  ·  ")).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { withAnimation(speed.spring()) { drawerExpanded.toggle() } } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down").frame(width: 28, height: 28) }.buttonStyle(.bordered).controlSize(.small)
            }
            mainInstrument
            ClippedRevealLayout(progress: expanded ? 1 : 0) {
                PreviewSurface { drawer }
            }
            .clipped().allowsHitTesting(expanded).opacity(expanded ? 1 : 0).animation(speed.spring(), value: expanded)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.secondary.opacity(0.18)))
    }

    @ViewBuilder
    private var mainInstrument: some View {
        switch mode {
        case .northstar: northstar
        case .directory: directory
        case .funnel: funnel
        case .practice: practice
        case .escapes: escapes
        case .reader: reader
        case .scripts: scripts
        case .evals: evals
        case .channels: channels
        case .action: action
        }
    }

    private var northstar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) { stat("Managed", "\(data.skills.count)", .blue); stat("Audit pass", "94%", .green); stat("Static", "\(Int(data.skills.map(\.bundleKB).reduce(0, +))) KB", .purple); stat("Unpracticed", "34%", .orange) }
            HStack { Text("Top attention").font(.caption.weight(.semibold)); Spacer(); PreviewPill("3 signals", tint: .orange) }
            ForEach(data.skills.sorted { $0.unpracticedRate > $1.unpracticedRate }.prefix(3)) { skill in
                HStack { Text(skill.name).font(.caption); Spacer(); Text("\(Int(skill.unpracticedRate * 100))% unpracticed · ROI \(skill.roiScore, specifier: "%.1f")").font(.caption2.monospacedDigit()).foregroundStyle(.orange) }
            }
        }
    }

    private var directory: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { PreviewPill(filterMode == 0 ? "Active managed" : "Category: \(data.skills[selectedIndex % data.skills.count].category)", tint: .blue); Spacer(); Button("Group") { filterMode = (filterMode + 1) % 2 }.buttonStyle(.bordered).controlSize(.small) }
            ForEach(Array(data.skills.enumerated()), id: \.element.id) { index, skill in
                Button { selectedIndex = index } label: {
                    HStack(spacing: 8) { Image(systemName: index == selectedIndex ? "circle.inset.filled" : "circle").foregroundStyle(.blue); Text(skill.name).font(.caption.weight(.medium)); Spacer(); PreviewPill("\(Int(skill.bundleKB)) KB", tint: .purple); PreviewPill("R1 \(Int(skill.r1Rate * 100))%", tint: .green) }
                        .padding(7).background(index == selectedIndex ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
            }
        }
    }

    private var funnel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(data.skills.enumerated()), id: \.element.id) { index, skill in
                Button { selectedIndex = index } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(skill.name).font(.caption.weight(.semibold)); Spacer(); Text("0-Hit \(skill.unhitRefsCount)").font(.caption2.monospacedDigit()).foregroundStyle(skill.unhitRefsCount > 0 ? .orange : .green) }
                        PreviewMetricBar(label: "L0 contract", value: max(0.2, 1 - skill.refsKB / max(skill.bundleKB, 1)), valueText: "\(Int(skill.bundleKB - skill.refsKB)) KB", tint: .teal)
                        PreviewMetricBar(label: "L1 references", value: skill.refsKB / max(skill.bundleKB, 1), valueText: "\(Int(skill.refsKB)) KB", tint: .orange)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(filterMode == 0 ? "All script skills" : "Unpracticed ≥ 50%").font(.caption.weight(.semibold)); Spacer(); Button("Filter") { filterMode = (filterMode + 1) % 2 }.buttonStyle(.bordered).controlSize(.small) }
            ForEach(data.skills.filter { filterMode == 0 || $0.unpracticedRate >= 0.5 }) { skill in
                HStack(spacing: 7) { Text(skill.name).font(.caption).frame(width: 100, alignment: .leading); PreviewMetricBar(label: "loads", value: min(Double(skill.scriptCalls) / 45, 1), valueText: "\(skill.scriptCalls)", tint: .blue); PreviewMetricBar(label: "scripts", value: min(Double(skill.scripts) / 8, 1), valueText: "\(skill.scripts)", tint: .green); Text("\(Int(skill.unpracticedRate * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(.orange) }
            }
        }
    }

    private var escapes: some View {
        VStack(spacing: 8) {
            ForEach(Array(data.skills.enumerated()), id: \.element.id) { index, skill in
                Button { selectedIndex = index } label: {
                    HStack(spacing: 6) { Text(skill.name).font(.caption).frame(width: 100, alignment: .leading); Capsule().fill(Color.red.opacity(0.7)).frame(width: CGFloat(12 + skill.implBugEscapes * 20), height: 11); Text("implementation \(skill.implBugEscapes)").font(.caption2); Spacer(); Capsule().fill(Color.orange.opacity(0.8)).frame(width: CGFloat(12 + skill.specGapEscapes * 20), height: 11); Text("specification \(skill.specGapEscapes)").font(.caption2) }
                }.buttonStyle(.plain)
            }
        }
    }

    private var reader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("FILES").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                ForEach(Array(data.skills.enumerated()), id: \.element.id) { index, skill in
                    Button { selectedIndex = index } label: {
                        HStack(spacing: 5) {
                            Image(systemName: skill.name == activeSkill.name ? "doc.text" : "doc.plaintext")
                            Text(skill.name == activeSkill.name ? "SKILL.md" : "references/overview.md")
                        }
                        .font(.caption)
                        .foregroundStyle(index == selectedIndex ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }.frame(width: 130, alignment: .leading)
            Divider()
            ScrollView { Text(activeSkill.docPreview).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .topLeading).textSelection(.enabled) }.frame(minHeight: 100)
        }
    }

    private var scripts: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("30-day deterministic execution").font(.caption.weight(.semibold)); Spacer(); PreviewPill("__pycache__ excluded", tint: .secondary) }
            ForEach(Array(data.skills.flatMap { skill in (0..<skill.scripts).map { (skill, $0) } }.enumerated()), id: \.offset) { _, pair in
                HStack { Text("\(pair.0.name)/scripts/check-\(pair.1 + 1).py").font(.caption2.monospaced()).frame(width: 210, alignment: .leading); PreviewMetricBar(label: "success", value: 0.92 - Double(pair.1 % 3) * 0.08, valueText: "\(Int((0.92 - Double(pair.1 % 3) * 0.08) * 100))%", tint: .green); Text("P95 \(280 + pair.1 * 43)ms").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
            }
        }
    }

    private var evals: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Active gate cases").font(.caption.weight(.semibold)); Spacer(); PreviewPill("Caught 31", tint: .green); PreviewPill("Escaped 3", tint: .red) }
            ForEach(Array(data.skills.enumerated()), id: \.element.id) { index, skill in
                Button { selectedIndex = index } label: { HStack { Text("Case \(index + 1) · \(skill.name) contract boundary").font(.caption); Spacer(); PreviewPill(index % 2 == 0 ? "Contract" : "CLI", tint: .blue); Text("strict").font(.caption2.monospaced()).foregroundStyle(.secondary) } }.buttonStyle(.plain)
            }
        }
    }

    private var channels: some View {
        let channels = ["Copilot", "Claude", "Codex", "Hermes", "GTT"]
        return VStack(alignment: .leading, spacing: 7) {
            HStack { Text("Calls by channel").font(.caption.weight(.semibold)); Spacer(); Button("Sort channel") { filterMode = (filterMode + 1) % channels.count }.buttonStyle(.bordered).controlSize(.small) }
            HStack(alignment: .top, spacing: 5) {
                Text("skill").font(.caption2).frame(width: 90, alignment: .leading)
                ForEach(channels, id: \.self) { Text($0).font(.caption2).frame(maxWidth: .infinity) }
            }
            ForEach(data.skills) { skill in
                HStack(spacing: 5) { Text(skill.name).font(.caption2).frame(width: 90, alignment: .leading); ForEach(0..<5, id: \.self) { channel in RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.18 + Double((channel + skill.name.count) % 5) * 0.14)).frame(maxWidth: .infinity, minHeight: 18) } }
            }
        }
    }

    private var action: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Priority queue").font(.caption.weight(.semibold))
            ForEach(Array(data.skills.sorted { $0.bundleKB > $1.bundleKB }.enumerated()), id: \.element.id) { _, skill in
                Button { selectedIndex = data.skills.firstIndex(of: skill) ?? 0 } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(skill.name).font(.caption.weight(.medium)); Spacer(); Text("\(Int(skill.bundleKB)) KB → \(Int(skill.bundleKB * 0.68)) KB").font(.caption2.monospacedDigit()).foregroundStyle(.purple) }
                        PreviewMetricBar(label: "current → target", value: 0.68, valueText: "save \(Int(skill.bundleKB * 0.32)) KB", tint: .purple)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View { VStack(alignment: .leading, spacing: 3) { Text(value).font(.headline.monospacedDigit()).foregroundStyle(tint); Text(label).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(8).background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8)) }

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(drawerTitle).font(.subheadline.weight(.semibold)); Spacer(); PreviewPill("SOURCE READY", tint: .green) }
            Text(activeSkill.docPreview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            Divider()
            HStack { Text("bundle \(Int(activeSkill.bundleKB)) KB · refs \(Int(activeSkill.refsKB)) KB"); Spacer(); Text("scripts \(activeSkill.scripts) · eval \(activeSkill.evalCases)") }.font(.caption2.monospaced())
            HStack { Text("unpracticed \(Int(activeSkill.unpracticedRate * 100))%"); Spacer(); Text("R1 \(Int(activeSkill.r1Rate * 100))% · ROI \(activeSkill.roiScore, specifier: "%.1f")") }.font(.caption2.monospaced())
        }
    }

    private var drawerTitle: String {
        switch mode {
        case .northstar: return "Top 3 volume and rework alerts"
        case .directory: return "Skill detail and channel footprint"
        case .funnel: return "Reference hit ledger"
        case .practice: return "Under-practiced script inventory"
        case .escapes: return "Escape diagnosis"
        case .reader: return "Four-level document fallback"
        case .scripts: return "Script invocation and latency"
        case .evals: return "Readable gate assertion"
        case .channels: return "Channel share and cache"
        case .action: return "Executable slimming actions"
        }
    }
}
#endif
