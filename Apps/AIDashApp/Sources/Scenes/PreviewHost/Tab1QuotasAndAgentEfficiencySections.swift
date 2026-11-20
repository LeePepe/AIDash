#if os(macOS)
import SwiftUI

private enum Tab1InstrumentMode: String, CaseIterable {
    case quota, tokenRiver, roleMatrix, modelArena, rounds, duration, unblock, routes, throughput, northstar
}

@MainActor
public enum Tab1QuotasAndAgentEfficiencySections {
    public static let descriptors: [PreviewVariantDescriptor] = [
        PreviewVariantDescriptor(id: "tab1-v01", tab: .overview, badgeCode: "V01", title: "五大 CLI 实时配额燃烧与重置倒计时舱", metricTags: ["5 CLIs", "5h / 7d Dual Window", "OAuth & Reset Ledger"], symbolName: "gauge.with.dots.needle.67percent", topologySignature: "tab1-v01:5col-dual-ring-quota-gauges+countdown-pills+auth-health-drawer"),
        PreviewVariantDescriptor(id: "tab1-v02", tab: .overview, badgeCode: "V02", title: "Token 消耗与 KV Cache 命中节省双层河流图", metricTags: ["7D ⇄ 30D Horizon", "Input+Output vs KV Cache", "Cost Saved Breakdown"], symbolName: "water.waves", topologySignature: "tab1-v02:dual-layer-area-river-chart+cli-filter-pills+daily-cache-ledger-drawer"),
        PreviewVariantDescriptor(id: "tab1-v03", tab: .overview, badgeCode: "V03", title: "四大角色 Token 占比与 R1 一次通过率双环矩阵", metricTags: ["Steering / Designer / Writer / Reviewer", "Token Share vs R1 %", "Role ROI"], symbolName: "circle.hexagongrid.fill", topologySignature: "tab1-v03:concentric-dual-ring-role-matrix+4role-efficiency-tiles+repo-breakdown-drawer"),
        PreviewVariantDescriptor(id: "tab1-v04", tab: .overview, badgeCode: "V04", title: "多模型竞技场 PK 榜：胜率、擦写与 Token 效率", metricTags: ["Gemini 4 Argon / Claude / GPT / Grok", "R1 Pass %", "Edit Churn & Token/Task"], symbolName: "trophy.fill", topologySignature: "tab1-v04:model-arena-leaderboard+4way-sort-pills+r1-r2-r3-microbars+model-attribution-drawer"),
        PreviewVariantDescriptor(id: "tab1-v05", tab: .overview, badgeCode: "V05", title: "返工轮次分布与高返工 Goal 明细", metricTags: ["R1 / R2 / R3+", "Daily Evolution", "Goal Drilldown"], symbolName: "chart.bar.xaxis", topologySignature: "tab1-v05:stacked-round-bars+target-line+goal-drilldown-drawer"),
        PreviewVariantDescriptor(id: "tab1-v06", tab: .overview, badgeCode: "V06", title: "角色耗时分位卡尺：P50 对比 P90 尾部", metricTags: ["P50 / P90", "5 Roles", "SLA Tail Alerts"], symbolName: "ruler", topologySignature: "tab1-v06:percentile-dumbbell-rulers+log-scale-toggle+slow-task-drawer"),
        PreviewVariantDescriptor(id: "tab1-v07", tab: .overview, badgeCode: "V07", title: "解卡与阻塞热力流", metricTags: ["Blocked Events", "Auto Unblock", "Owner Decisions"], symbolName: "arrow.triangle.branch", topologySignature: "tab1-v07:blocker-heat-flow+auto-vs-owner-ratio+latency-drawer"),
        PreviewVariantDescriptor(id: "tab1-v08", tab: .overview, badgeCode: "V08", title: "模型路由组配额与性价比雷达卡", metricTags: ["4 Route Groups", "Fallback Chains", "Output / 1K Tokens"], symbolName: "dot.radiowaves.left.and.right", topologySignature: "tab1-v08:route-group-radar+quota-health-pods+fallback-history-drawer"),
        PreviewVariantDescriptor(id: "tab1-v09", tab: .overview, badgeCode: "V09", title: "每日 Goal / Task 吞吐与单目标 Token 成本", metricTags: ["Goals / Tasks", "Token Cost Ladder", "Throughput"], symbolName: "chart.xyaxis.line", topologySignature: "tab1-v09:throughput-columns+cost-step-line+goal-task-scope-drawer"),
        PreviewVariantDescriptor(id: "tab1-v10", tab: .overview, badgeCode: "V10", title: "北极星总览：今日 Token、缓存与全栈 R1", metricTags: ["Today Tokens", "KV Hit Rate", "R1 First Pass"], symbolName: "star.circle.fill", topologySignature: "tab1-v10:northstar-hero-four-up+sparkline+diagnostic-summary-drawer")
    ]

    @ViewBuilder
    public static func view(for descriptor: PreviewVariantDescriptor, data: AIDashPreviewSampleData, globalExpandAll: Bool, speed: PreviewSpeedMultiplier) -> some View {
        PreviewInstrumentSection(descriptor: descriptor, mode: mode(for: descriptor), data: data, globalExpandAll: globalExpandAll, speed: speed)
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

    private static func mode(for descriptor: PreviewVariantDescriptor) -> Tab1InstrumentMode {
        switch descriptor.id {
        case "tab1-v01": return .quota
        case "tab1-v02": return .tokenRiver
        case "tab1-v03": return .roleMatrix
        case "tab1-v04": return .modelArena
        case "tab1-v05": return .rounds
        case "tab1-v06": return .duration
        case "tab1-v07": return .unblock
        case "tab1-v08": return .routes
        case "tab1-v09": return .throughput
        default: return .northstar
        }
    }
}

private struct PreviewInstrumentSection: View {
    let descriptor: PreviewVariantDescriptor
    let mode: Tab1InstrumentMode
    let data: AIDashPreviewSampleData
    let globalExpandAll: Bool
    let speed: PreviewSpeedMultiplier
    @State private var drawerExpanded = false
    @State private var selectedIndex = 0
    @State private var alternateMode = false

    private var expanded: Bool { globalExpandAll || drawerExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: descriptor.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.title).font(.headline.weight(.semibold))
                    Text(descriptor.metricTags.joined(separator: "  ·  "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
            mainInstrument
            ClippedRevealLayout(progress: expanded ? 1 : 0) {
                drawer
                    .padding(.top, 8)
            }
            .clipped()
            .allowsHitTesting(expanded)
            .opacity(expanded ? 1 : 0)
            .animation(speed.spring(), value: expanded)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.secondary.opacity(0.18)))
    }

    @ViewBuilder
    private var mainInstrument: some View {
        switch mode {
        case .quota: quotaInstrument
        case .tokenRiver: tokenRiverInstrument
        case .roleMatrix: roleMatrixInstrument
        case .modelArena: modelArenaInstrument
        case .rounds: roundsInstrument
        case .duration: durationInstrument
        case .unblock: unblockInstrument
        case .routes: routesInstrument
        case .throughput: throughputInstrument
        case .northstar: northstarInstrument
        }
    }

    private var quotaInstrument: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { PreviewPill("Pool remaining \(Int(data.quotas.map(\.remaining).reduce(0, +) / Double(data.quotas.count) * 100))%", tint: .blue); Spacer(); PreviewPill("RESET LEDGER", tint: .secondary) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(Array(data.quotas.enumerated()), id: \.element.id) { index, quota in
                    Button { selectedIndex = index } label: {
                        VStack(spacing: 7) {
                            PreviewRing(value: quota.remaining, tint: selectedIndex == index ? .blue : (quota.remaining < 0.25 ? .orange : .green), label: "\(Int(quota.remaining * 100))%", size: 62)
                            Text(quota.name).font(.caption.weight(.semibold))
                            Text(quota.reset).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(selectedIndex == index ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var tokenRiverInstrument: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { PreviewPill(alternateMode ? "30D" : "7D", tint: .blue); Spacer(); Button("7D / 30D") { alternateMode.toggle() }.buttonStyle(.bordered).controlSize(.small) }
            ForEach(Array(data.tokenPoints.prefix(alternateMode ? 14 : 7).enumerated()), id: \.element.id) { index, point in
                Button { selectedIndex = index } label: {
                    HStack(spacing: 8) {
                        Text(point.label).font(.caption2.monospacedDigit()).frame(width: 40, alignment: .leading)
                        PreviewMetricBar(label: point.cli, value: min(Double(point.activeTokens) / 300_000, 1), valueText: DashboardTokenFormatter.compact(point.activeTokens), tint: .blue)
                        PreviewMetricBar(label: "KV", value: min(Double(point.cacheSaved) / 160_000, 1), valueText: DashboardTokenFormatter.compact(point.cacheSaved), tint: .green)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var roleMatrixInstrument: some View {
        HStack(spacing: 14) {
            ZStack {
                PreviewRing(value: data.roles[selectedIndex % data.roles.count].tokenShare / 0.5, tint: .blue, label: "Token", size: 128)
                PreviewRing(value: data.roles[selectedIndex % data.roles.count].r1Rate, tint: .green, label: "R1", size: 90)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(data.roles.enumerated()), id: \.element.id) { index, role in
                    Button { selectedIndex = index } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(role.name).font(.caption.weight(.semibold))
                            Text("\(Int(role.tokenShare * 100))% · R1 \(Int(role.r1Rate * 100))%").font(.caption2.monospacedDigit())
                            Text("\(role.r1) / \(role.r2) / \(role.r3)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .background(index == selectedIndex ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var modelArenaInstrument: some View {
        VStack(spacing: 7) {
            HStack { Text(alternateMode ? "Token efficiency" : "R1 first-pass").font(.caption.weight(.semibold)); Spacer(); Button("Sort") { alternateMode.toggle() }.buttonStyle(.bordered).controlSize(.small) }
            ForEach(Array(data.models.sorted { alternateMode ? $0.tokensPerTask < $1.tokensPerTask : $0.r1Rate > $1.r1Rate }.enumerated()), id: \.element.id) { index, model in
                HStack(spacing: 8) {
                    Text("#\(index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24)
                    Text(model.name).font(.caption.weight(.medium)).frame(width: 110, alignment: .leading)
                    PreviewMetricBar(label: "R1", value: model.r1Rate, valueText: "\(Int(model.r1Rate * 100))%", tint: .green)
                    Text("churn \(model.churn)").font(.caption2.monospacedDigit()).foregroundStyle(.orange)
                }
            }
        }
    }

    private var roundsInstrument: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(alternateMode ? "Share" : "Task count").font(.caption.weight(.semibold)); Spacer(); Button("Count / %") { alternateMode.toggle() }.buttonStyle(.bordered).controlSize(.small) }
            ForEach(Array(data.tokenPoints.prefix(7).enumerated()), id: \.element.id) { index, point in
                HStack(spacing: 6) {
                    Text(point.label).font(.caption2.monospacedDigit()).frame(width: 42)
                    ForEach(Array([0.72, 0.19, 0.09].enumerated()), id: \.offset) { segmentIndex, ratio in
                        RoundedRectangle(cornerRadius: 3).fill([Color.green, Color.orange, Color.red][segmentIndex]).frame(width: max(10, CGFloat(ratio * Double(145 + index * 6))), height: 18)
                    }
                    Text("R1 \(Int((0.72 + Double(index % 3) * 0.03) * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var durationInstrument: some View {
        VStack(spacing: 8) {
            HStack { Text(alternateMode ? "Log scale" : "Linear scale").font(.caption.weight(.semibold)); Spacer(); Button("Scale") { alternateMode.toggle() }.buttonStyle(.bordered).controlSize(.small) }
            ForEach(data.roles) { role in
                HStack(spacing: 8) {
                    Text(role.name).font(.caption).frame(width: 70, alignment: .leading)
                    PreviewMetricBar(label: "P50", value: min(role.p50 / 600, 1), valueText: "\(Int(role.p50))s", tint: .blue)
                    PreviewMetricBar(label: "P90", value: min(role.p90 / 600, 1), valueText: "\(Int(role.p90))s", tint: .orange)
                }
            }
        }
    }

    private var unblockInstrument: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { PreviewPill("Auto unblock 74%", tint: .green); PreviewPill("Owner decision 26%", tint: .orange); Spacer() }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(data.tokenPoints.prefix(12).enumerated()), id: \.element.id) { index, _ in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3).fill(index % 4 == 0 ? Color.orange : Color.blue).frame(height: CGFloat(12 + (index * 11) % 42))
                        Text(String(index + 1)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }.frame(height: 70)
        }
    }

    private var routesInstrument: some View {
        let groups = ["group/steering", "group/designer", "group/coding", "group/reviewing"]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                Button { selectedIndex = index } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(group).font(.caption.weight(.semibold)); Spacer(); Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.blue) }
                        PreviewMetricBar(label: "quota health", value: 0.84 - Double(index) * 0.08, valueText: "\(84 - index * 8)%", tint: .green)
                        Text("\(42 + index * 8) output / 1K · fallback ready").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }.padding(9).background(index == selectedIndex ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
        }
    }

    private var throughputInstrument: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(alternateMode ? "Task scope" : "Goal scope").font(.caption.weight(.semibold)); Spacer(); Button("Goal / Task") { alternateMode.toggle() }.buttonStyle(.bordered).controlSize(.small) }
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(Array(data.tokenPoints.prefix(10).enumerated()), id: \.element.id) { _, point in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.blue.gradient).frame(height: CGFloat(20 + (point.invocations % 37)))
                        Text("\(point.invocations)").font(.caption2.monospacedDigit())
                        Text(point.label).font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 100)
            PreviewMetricBar(label: "Average token cost", value: 0.58, valueText: "68K / goal", tint: .purple)
        }
    }

    private var northstarInstrument: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(DashboardTokenFormatter.compact(data.tokenPoints.reduce(0) { $0 + $1.activeTokens })).font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                Text("today tokens").font(.caption).foregroundStyle(.secondary)
                Spacer(); PreviewPill("Top 1 · Gemini 4 Argon", tint: .green)
            }
            HStack(spacing: 8) {
                stat("KV cache", "78.4%", .teal)
                stat("Full-stack R1", "88.9%", .green)
                stat("P90 tail", "4m 42s", .orange)
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<14, id: \.self) { index in
                    let opacity = 0.35 + Double(index % 5) * 0.1
                    let height = CGFloat(12 + (index * 13) % 34)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(opacity))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
            .frame(height: 48)
        }
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(value).font(.headline.monospacedDigit()).foregroundStyle(tint); Text(label).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(8).background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }

    private var drawer: some View {
        PreviewSurface {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text(drawerTitle).font(.subheadline.weight(.semibold)); Spacer(); PreviewPill("DETAILS", tint: .secondary) }
                ForEach(Array(drawerRows.enumerated()), id: \.offset) { _, row in
                    HStack { Text(row.0).font(.caption); Spacer(); Text(row.1).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    Divider()
                }
            }
        }
    }

    private var drawerTitle: String {
        switch mode {
        case .quota: return "Credential health & reset ledger"
        case .tokenRiver: return "Daily token and cache savings ledger"
        case .roleMatrix: return "Role delivery and round breakdown"
        case .modelArena: return "Model strengths and attribution"
        case .rounds: return "High-rework Goal detail"
        case .duration: return "Slow task percentile alerts"
        case .unblock: return "Recent unblock signals"
        case .routes: return "Fallback chain history"
        case .throughput: return "High-output / high-cost comparison"
        case .northstar: return "Three executable efficiency signals"
        }
    }

    private var drawerRows: [(String, String)] {
        switch mode {
        case .quota: return data.quotas.map { ($0.name, "\($0.auth) · \($0.reset)") }
        case .tokenRiver: return data.tokenPoints.prefix(5).map { ($0.label, "active \(DashboardTokenFormatter.compact($0.activeTokens)) · saved \(DashboardTokenFormatter.compact($0.cacheSaved))") }
        case .roleMatrix: return data.roles.map { ($0.name, "\($0.r1) R1 · \($0.r2) R2 · \($0.r3) R3+") }
        case .modelArena: return data.models.map { ($0.name, "R1 \(Int($0.r1Rate * 100))% · churn \($0.churn)") }
        case .rounds: return [("High-rework goals", "3"), ("Implementation escapes", "2"), ("Specification gaps", "1")]
        case .duration: return data.roles.map { ($0.name, "P50 \(Int($0.p50))s · P90 \(Int($0.p90))s") }
        case .unblock: return [("Path permissions", "12 auto"), ("Read-only command", "8 auto"), ("Owner ruling", "7 escalated")]
        case .routes: return [("Quota fallback", "Claude → Copilot"), ("Latency guard", "Argon → GPT"), ("Review guard", "Claude → Grok")]
        case .throughput: return [("Highest throughput", "Goal-142 · 9 tasks"), ("Lowest token cost", "Goal-139 · 41K"), ("Needs inspection", "Goal-147 · 122K")]
        case .northstar: return [("Cache opportunity", "18.6% active tokens"), ("R1 opportunity", "Writer tail"), ("Routing signal", "Argon leads by 5pt")]
        }
    }
}
#endif
