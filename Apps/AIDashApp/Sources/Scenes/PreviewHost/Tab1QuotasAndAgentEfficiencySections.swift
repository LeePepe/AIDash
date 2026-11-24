#if os(macOS)
import SwiftUI

private enum Tab1InstrumentMode: String, CaseIterable {
    case baseOverview, dailyRework, cliQuotas, tokenSavings, durationDrop
    case modelCompare, roleWorkload, autoInspections, interruptDrop, repoTrends
}

@MainActor
public enum Tab1QuotasAndAgentEfficiencySections {
    public static let descriptors: [PreviewVariantDescriptor] = [
        PreviewVariantDescriptor(id: "tab1-v01", tab: .overview, badgeCode: "V01", title: "Agent 基本盘与 30 天核心趋势总卡", metricTags: ["42 Goals / 128 Tasks ▲", "一次成功率 88.4% ▲", "单任务均耗 6.4m ▼"], symbolName: "chart.line.uptrend.xyaxis", topologySignature: "tab1-v01:base-4tile-kpis+30d-trend-sparkline+weekly-evolution-drawer"),
        PreviewVariantDescriptor(id: "tab1-v02", tab: .overview, badgeCode: "V02", title: "每日任务量与「一次做对 vs 返工重试」趋势图", metricTags: ["一次做对 ▲ +14%", "返工比例 29% → 11% ▼", "近 14 天走势"], symbolName: "chart.bar.xaxis", topologySignature: "tab1-v02:stacked-firstpass-rework-bars+rework-drop-curve+rework-detail-drawer"),
        PreviewVariantDescriptor(id: "tab1-v03", tab: .overview, badgeCode: "V03", title: "五大 CLI 实时剩余额度与重置倒计时", metricTags: ["5 大主力工具", "剩余额度 % ▲", "今日消耗 ▼ 与重置时间"], symbolName: "gauge.with.dots.needle.67percent", topologySignature: "tab1-v03:5cli-remaining-gauges+reset-countdown-pills+7d-usage-trend-drawer"),
        PreviewVariantDescriptor(id: "tab1-v04", tab: .overview, badgeCode: "V04", title: "每日 Token 消耗与缓存节省趋势图（7D / 30D）", metricTags: ["7D ⇄ 30D 切换", "缓存直接省下 68% ▲", "单日净消耗 ▼ -22%"], symbolName: "water.waves", topologySignature: "tab1-v04:dual-token-savings-bars+7d-30d-horizon+cli-savings-drawer"),
        PreviewVariantDescriptor(id: "tab1-v05", tab: .overview, badgeCode: "V05", title: "任务与测试门禁平均耗时下降曲线", metricTags: ["单任务 11.2m → 6.4m ▼", "门禁 95s → 14s ▼", "持续提速曲线"], symbolName: "timer", topologySignature: "tab1-v05:dual-duration-drop-sparklines+milestone-speedup-drawer"),
        PreviewVariantDescriptor(id: "tab1-v06", tab: .overview, badgeCode: "V06", title: "主力模型使用次数、成功率与速度对比趋势", metricTags: ["4 大主力模型", "一次成功率 ▲", "响应速度与 14 天趋势"], symbolName: "trophy.fill", topologySignature: "tab1-v06:model-usage-success-leaderboard+14d-sparklines+task-fit-drawer"),
        PreviewVariantDescriptor(id: "tab1-v07", tab: .overview, badgeCode: "V07", title: "四大分工角色（总控 / 设计 / 编码 / 审查）调用量与耗时趋势", metricTags: ["总控 · 设计 · 编码 · 审查", "一次成功率 ▲", "平均耗时 ▼ -31%"], symbolName: "person.3.sequence.fill", topologySignature: "tab1-v07:4role-workload-tiles+duration-drop-sparkline+role-handoff-drawer"),
        PreviewVariantDescriptor(id: "tab1-v08", tab: .overview, badgeCode: "V08", title: "每日定时任务（7 大自动巡检）运行记录与自动修复趋势", metricTags: ["7 大自动巡检", "▲ 94% 自动闭环", "14 天自愈趋势"], symbolName: "clock.badge.checkmark", topologySignature: "tab1-v08:7inspection-autofix-rows+closure-rate-sparkline+fix-log-drawer"),
        PreviewVariantDescriptor(id: "tab1-v09", tab: .overview, badgeCode: "V09", title: "人工打断与卡壳等待次数下降趋势", metricTags: ["日均 9.5 次 → 1.2 次 ▼", "自动放行率 93.6% ▲", "14 天下降曲线"], symbolName: "hand.raised.slash.fill", topologySignature: "tab1-v09:interrupt-drop-bars+auto-pass-badge+reason-breakdown-drawer"),
        PreviewVariantDescriptor(id: "tab1-v10", tab: .overview, badgeCode: "V10", title: "各项目仓库每日活跃任务与成功率趋势", metricTags: ["user-skills / AIDash / Financial / VitalStride", "30 天任务量 ▲", "成功率趋势 ▲"], symbolName: "folder.badge.gearshape", topologySignature: "tab1-v10:4repo-activity-cards+14d-sparklines+repo-throughput-drawer")
    ]

    @ViewBuilder
    public static func view(
        for descriptor: PreviewVariantDescriptor,
        data: AIDashPreviewSampleData,
        globalExpandAll: Bool,
        speed: PreviewSpeedMultiplier
    ) -> some View {
        PreviewAgentOverviewSection(
            descriptor: descriptor,
            mode: mode(for: descriptor),
            data: data,
            globalExpandAll: globalExpandAll,
            speed: speed
        )
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
        case "tab1-v01": return .baseOverview
        case "tab1-v02": return .dailyRework
        case "tab1-v03": return .cliQuotas
        case "tab1-v04": return .tokenSavings
        case "tab1-v05": return .durationDrop
        case "tab1-v06": return .modelCompare
        case "tab1-v07": return .roleWorkload
        case "tab1-v08": return .autoInspections
        case "tab1-v09": return .interruptDrop
        default: return .repoTrends
        }
    }
}

private struct PreviewAgentOverviewSection: View {
    let descriptor: PreviewVariantDescriptor
    let mode: Tab1InstrumentMode
    let data: AIDashPreviewSampleData
    let globalExpandAll: Bool
    let speed: PreviewSpeedMultiplier
    @State private var drawerExpanded = false
    @State private var selectedIndex = 0
    @State private var windowIndex = 2
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
                drawer.padding(.top, 8)
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
        case .baseOverview: baseOverviewInstrument
        case .dailyRework: dailyReworkInstrument
        case .cliQuotas: cliQuotasInstrument
        case .tokenSavings: tokenSavingsInstrument
        case .durationDrop: durationDropInstrument
        case .modelCompare: modelCompareInstrument
        case .roleWorkload: roleWorkloadInstrument
        case .autoInspections: autoInspectionsInstrument
        case .interruptDrop: interruptDropInstrument
        case .repoTrends: repoTrendsInstrument
        }
    }

    private var baseOverviewInstrument: some View {
        let windows = ["近 7 天", "近 14 天", "近 30 天"]
        let goalText = ["12 个 Goal / 36 子任务", "24 个 Goal / 74 子任务", "42 个 Goal / 128 子任务"][windowIndex % 3]
        let successSeries: [Double] = [79.5, 81.2, 82.8, 84.1, 85.6, 86.9, 87.8, 88.4]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                PreviewPill("基本盘总览 · \(windows[windowIndex % 3])", tint: .blue)
                Spacer()
                Button("切换 7D / 14D / 30D") { windowIndex = (windowIndex + 1) % 3 }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                kpiTile("完成任务总数", goalText, "▲ +18%", .blue)
                kpiTile("一次成功率", "88.4%", "▲ +6.2%", .green)
                kpiTile("单任务平均耗时", "6.4 分钟", "▼ -28%", .teal)
                kpiTile("单任务均摊消耗", "142K Token", "▼ -22%", .purple)
            }
            HStack(spacing: 10) {
                Text("30 天一次成功率爬升曲线").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                PreviewPill("79.5% → 88.4% ▲", tint: .green)
            }
            PreviewSparkline(values: successSeries, tint: .green, height: 28)
        }
    }

    private var dailyReworkInstrument: some View {
        let slice = Array(data.tokenPoints.suffix(7))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                PreviewPill("返工比例近 14 天：29% → 11% ▼", tint: .green)
                Spacer()
                Button(alternateMode ? "按百分比 %" : "按任务数") { alternateMode.toggle() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ForEach(slice) { point in
                let total = max(point.invocations, 1)
                let passRatio = Double(point.firstPassCount) / Double(total)
                let reworkRatio = Double(point.reworkCount) / Double(total)
                HStack(spacing: 8) {
                    Text(point.label).font(.caption2.monospacedDigit()).frame(width: 40, alignment: .leading)
                    GeometryReader { proxy in
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.green.opacity(0.85))
                                .frame(width: max(12, proxy.size.width * passRatio * 0.86))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange.opacity(0.85))
                                .frame(width: max(6, proxy.size.width * reworkRatio * 0.86))
                        }
                    }
                    .frame(height: 12)
                    Text(
                        alternateMode
                            ? "一次做对 \(Int(passRatio * 100))% · 返工 \(Int(reworkRatio * 100))%"
                            : "做对 \(point.firstPassCount) / 返工 \(point.reworkCount)"
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 142, alignment: .trailing)
                }
            }
        }
    }

    private var cliQuotasInstrument: some View {
        let sorted = alternateMode
            ? data.quotas.sorted { $0.tokens > $1.tokens }
            : data.quotas.sorted { $0.remaining < $1.remaining }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                let avgRem = Int(data.quotas.map(\.remaining).reduce(0, +) / Double(max(data.quotas.count, 1)) * 100)
                PreviewPill("总剩余可用池 \(avgRem)% ▲", tint: .green)
                Spacer()
                Button(alternateMode ? "按今日消耗排序" : "按剩余最少优先") { alternateMode.toggle() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, quota in
                    VStack(spacing: 6) {
                        PreviewRing(
                            value: quota.remaining,
                            tint: quota.remaining < 0.35 ? .orange : .green,
                            label: "\(Int(quota.remaining * 100))%",
                            size: 58
                        )
                        Text(quota.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(quota.reset).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                        Text(quota.deltaText).font(.caption2.monospacedDigit()).foregroundStyle(.green).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(7)
                    .background(
                        selectedIndex == index ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .onTapGesture { selectedIndex = index }
                }
            }
        }
    }

    private var tokenSavingsInstrument: some View {
        let rows = Array((alternateMode ? data.tokenPoints.suffix(8) : data.tokenPoints.prefix(7)))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                PreviewPill("命中缓存直接省下 68% ▲", tint: .green)
                PreviewPill("单日实际消耗 ▼ -22%", tint: .blue)
                Spacer()
                Button(alternateMode ? "近 30 天采样" : "近 7 天明细") { alternateMode.toggle() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ForEach(rows) { point in
                HStack(spacing: 8) {
                    Text(point.label).font(.caption2.monospacedDigit()).frame(width: 40, alignment: .leading)
                    PreviewMetricBar(
                        label: "实际消耗",
                        value: min(Double(point.activeTokens) / 260_000, 1),
                        valueText: DashboardTokenFormatter.compact(point.activeTokens),
                        tint: .blue
                    )
                    PreviewMetricBar(
                        label: "缓存省下",
                        value: min(Double(point.cacheSaved) / 260_000, 1),
                        valueText: DashboardTokenFormatter.compact(point.cacheSaved),
                        tint: .green
                    )
                }
            }
        }
    }

    private var durationDropInstrument: some View {
        let taskCurve: [Double] = [11.2, 10.4, 9.6, 8.7, 7.9, 7.2, 6.8, 6.4]
        let gateCurve: [Double] = [95, 78, 62, 44, 29, 21, 16, 14]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                PreviewPill("单任务 11.2m → 6.4m ▼ -43%", tint: .green)
                PreviewPill("本地门禁 95s → 14s ▼ -85%", tint: .teal)
                Spacer()
                Button(alternateMode ? "看门禁耗时" : "看任务总耗时") { alternateMode.toggle() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("单个任务平均完成耗时（分钟）").font(.caption.weight(.semibold))
                    Spacer()
                    Text("6.4m ▼ 持续变快").font(.caption2.monospacedDigit()).foregroundStyle(.green)
                }
                PreviewSparkline(values: taskCurve, tint: .blue, height: 32)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("本地测试检查平均耗时（秒）").font(.caption.weight(.semibold))
                    Spacer()
                    Text("14s ▼ 迁入 /tmp 提速").font(.caption2.monospacedDigit()).foregroundStyle(.teal)
                }
                PreviewSparkline(values: gateCurve, tint: .teal, height: 32)
            }
        }
    }

    private var modelCompareInstrument: some View {
        let sorted = alternateMode
            ? data.models.sorted { $0.speedTokensPerSec > $1.speedTokensPerSec }
            : data.models.sorted { $0.callCount > $1.callCount }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                PreviewPill("主力模型成功率近 14 天全线 ▲", tint: .green)
                Spacer()
                Button(alternateMode ? "按速度最快 ↑" : "按调用次数 ↓") { alternateMode.toggle() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ForEach(sorted) { model in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Text("调用 \(model.callCount) 次 · \(Int(model.speedTokensPerSec)) tok/s")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 138, alignment: .leading)
                    PreviewMetricBar(
                        label: "一次成功率",
                        value: model.firstPassRate,
                        valueText: "\(Int(model.firstPassRate * 100))% \(model.successDeltaText)",
                        tint: .green
                    )
                    PreviewSparkline(values: model.trend14d, tint: .green, height: 22)
                        .frame(width: 72)
                }
            }
        }
    }

    private var roleWorkloadInstrument: some View {
        let activeRole = data.roles[selectedIndex % max(data.roles.count, 1)]
        return VStack(alignment: .leading, spacing: 9) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(data.roles.enumerated()), id: \.element.id) { index, role in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(role.plainRoleTitle) (\(role.name))").font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text(role.durationDeltaText).font(.caption2.monospacedDigit()).foregroundStyle(.green)
                        }
                        Text("完成 \(role.completedCount) 次 · 一次成功 \(Int(role.firstPassRate * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("平均耗时 \(String(format: "%.1f", role.avgMinutes)) 分钟")
                            .font(.caption2.monospacedDigit())
                    }
                    .padding(8)
                    .background(
                        index == selectedIndex ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture { selectedIndex = index }
                }
            }
            HStack {
                Text("\(activeRole.plainRoleTitle) 平均耗时下降曲线").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                PreviewPill("\(activeRole.durationDeltaText) 提速", tint: .green)
            }
            PreviewSparkline(values: activeRole.durationTrend, tint: .blue, height: 24)
        }
    }

    private var autoInspectionsInstrument: some View {
        let visible = Array(data.inspections.prefix(6))
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                PreviewPill("近 14 天运行 112 次 · 自动修好 40/42 项 (▲ 95%)", tint: .green)
                Spacer()
            }
            ForEach(visible) { item in
                HStack(spacing: 8) {
                    Text(item.title).font(.caption.weight(.medium)).lineLimit(1).frame(width: 158, alignment: .leading)
                    Text("跑 \(item.runs14d) 次 · 修好 \(item.autoFixed)/\(item.issuesFound)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    PreviewSparkline(values: item.trend14d, tint: .green, height: 18)
                        .frame(width: 58)
                    PreviewPill(item.deltaText, tint: .green)
                }
            }
        }
    }

    private var interruptDropInstrument: some View {
        let dailyInterrupts: [(String, Double)] = [
            ("D1", 9.5), ("D3", 7.8), ("D5", 6.1), ("D7", 4.4), ("D9", 2.9), ("D11", 1.8), ("D14", 1.2)
        ]
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                PreviewPill("日均卡壳等待：9.5 次 → 1.2 次 ▼ -87%", tint: .green)
                PreviewPill("自动放行率 93.6% ▲", tint: .blue)
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(dailyInterrupts, id: \.0) { label, count in
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f", count)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(count <= 2.5 ? Color.green.opacity(0.8) : Color.orange.opacity(0.8))
                            .frame(height: CGFloat(max(10, count * 6.2)))
                        Text(label).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 86)
        }
    }

    private var repoTrendsInstrument: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PreviewPill("4 大主力仓库 30 天共完成 128 个任务 ▲", tint: .blue)
                Spacer()
            }
            ForEach(Array(data.repos.enumerated()), id: \.element.id) { index, repo in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(repo.repoName).font(.caption.weight(.semibold))
                        Text("30天 \(repo.completedTasks30d) 任务 · 调用 \(repo.totalCalls30d) 次")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 160, alignment: .leading)
                    PreviewMetricBar(
                        label: "一次成功率",
                        value: repo.firstPassRate,
                        valueText: "\(Int(repo.firstPassRate * 100))% \(repo.deltaText)",
                        tint: .green
                    )
                    PreviewSparkline(values: repo.activityTrend14d, tint: .blue, height: 22)
                        .frame(width: 64)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture { selectedIndex = index }
            }
        }
    }

    private func kpiTile(_ label: String, _ value: String, _ delta: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(delta).font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(.green)
            }
            Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(tint).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var drawer: some View {
        PreviewSurface {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(drawerTitle).font(.subheadline.weight(.semibold))
                    Spacer()
                    PreviewPill("随时间演进明细", tint: .secondary)
                }
                ForEach(Array(drawerRows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.0).font(.caption)
                        Spacer()
                        Text(row.1).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
        }
    }

    private var drawerTitle: String {
        switch mode {
        case .baseOverview: return "按周演进对比表（第 1 周 → 第 4 周）"
        case .dailyRework: return "近 7 天返工重试原因归类（自动统计）"
        case .cliQuotas: return "各工具近 7 天额度消耗走势与登录状态"
        case .tokenSavings: return "各工具缓存省钱排行榜"
        case .durationDrop: return "历次提速关键节点前后对比"
        case .modelCompare: return "各主力模型擅长任务与表现明细"
        case .roleWorkload: return "四大角色 Token 占比与协作流转耗时"
        case .autoInspections: return "全部 7 大定时巡检自动修复记录"
        case .interruptDrop: return "剩余少量人工确认原因分布"
        case .repoTrends: return "各项目仓库单任务平均耗时对比"
        }
    }

    private var drawerRows: [(String, String)] {
        switch mode {
        case .baseOverview:
            return [
                ("第 1 周 → 第 4 周一次成功率", "79.5% → 88.4% ▲ +8.9%"),
                ("第 1 周 → 第 4 周单任务耗时", "9.8 分钟 → 6.4 分钟 ▼ -35%"),
                ("第 1 周 → 第 4 周单任务均摊 Token", "182K → 142K ▼ -22%")
            ]
        case .dailyRework:
            return [
                ("界面边距与字号细节微调", "4 次（较上周 ▼ -50%）"),
                ("测试用例同步补齐", "3 次（较上周 ▼ -40%）"),
                ("需求口径微调补充", "2 次（较上周 ▼ -33%）")
            ]
        case .cliQuotas:
            return data.quotas.map { ($0.name, "\($0.auth) · \($0.reset) · \($0.deltaText)") }
        case .tokenSavings:
            return data.quotas.map { ($0.name, "缓存命中 \(Int($0.cacheHit * 100))% ▲ · 今日 \(DashboardTokenFormatter.compact($0.tokens))") }
        case .durationDrop:
            return [
                ("编译产物迁入 /tmp 独立目录", "本地门禁 95s → 14s ▼ -85%"),
                ("iCloud 镜像本地化改造", "主线程卡顿 4.2s → 0ms ▼ -100%"),
                ("子任务同分支连续推进", "单任务耗时 11.2m → 6.4m ▼ -43%")
            ]
        case .modelCompare:
            return data.models.map { ($0.name, "调用 \($0.callCount) 次 · 成功率 \(Int($0.firstPassRate * 100))% \($0.successDeltaText)") }
        case .roleWorkload:
            return data.roles.map { ("\($0.plainRoleTitle) (\($0.name))", "占比 \(Int($0.tokenShare * 100))% · 均耗 \(String(format: "%.1f", $0.avgMinutes))m \($0.durationDeltaText)") }
        case .autoInspections:
            return data.inspections.map { ($0.title, "14天跑 \($0.runs14d) 次 · 自动修好 \($0.autoFixed)/\($0.issuesFound) \($0.deltaText)") }
        case .interruptDrop:
            return [
                ("首次安装独立桌面应用确认", "本周 3 次（安全必选）"),
                ("重大产品方向二选一拍板", "本周 4 次（较上月 ▼ -72%）"),
                ("其余常规研发与巡检流程", "93.6% 全程自动放行 ▲")
            ]
        case .repoTrends:
            return data.repos.map { ($0.repoName, "30天 \($0.completedTasks30d) 任务 · 均耗 \(String(format: "%.1f", $0.avgTaskMinutes))m · \($0.deltaText)") }
        }
    }
}
#endif
