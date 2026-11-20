#if os(macOS)
import SwiftUI

private enum Tab2InstrumentMode: String, CaseIterable {
    case inventoryOverview, callLeaderboard, categoryDaily, successEvolution, scriptErrorDrop
    case scriptSpeedTrend, autoOptReport, weeklyMovers, docUsage, fullMatrix
}

private struct CategoryDailyRow: Identifiable {
    let id: String
    let calls: Int
    let deltaText: String
    let tint: Color
}

private struct ScriptSpeedRow: Identifiable {
    let id: String
    let avgSeconds: Double
    let valueText: String
    let tint: Color
}

@MainActor
public enum Tab2SkillsArsenalInspectorSections {
    public static let descriptors: [PreviewVariantDescriptor] = [
        PreviewVariantDescriptor(id: "tab2-v01", tab: .agentEfficiency, badgeCode: "V01", title: "Skills 家底总览与核心趋势卡", metricTags: ["24 个：活跃 21 / 闲置 3", "近 30 天调用 2,840 次 ▲", "一次成功率 89.2% ▲"], symbolName: "sparkles.rectangle.stack", topologySignature: "tab2-v01:5kpi-base-inventory+30d-call-trend+active-idle-drawer"),
        PreviewVariantDescriptor(id: "tab2-v02", tab: .agentEfficiency, badgeCode: "V02", title: "每个 Skill 的调用次数排行榜与 14 天趋势线", metricTags: ["调用次数排行 ▲", "最近使用时间", "展开看全量 24 个 Skill"], symbolName: "list.number", topologySignature: "tab2-v02:top7-call-leaderboard+14d-sparkline+full24-drawer"),
        PreviewVariantDescriptor(id: "tab2-v03", tab: .agentEfficiency, badgeCode: "V03", title: "Skills 每日调用总次数趋势图（按四大用途分类堆叠）", metricTags: ["总控 · 设计 · 工程 · 数据", "每日调用量 ▲ +31%", "分类占比演进"], symbolName: "chart.bar.doc.horizontal", topologySignature: "tab2-v03:4category-stacked-daily-bars+filter-pill+category-summary-drawer"),
        PreviewVariantDescriptor(id: "tab2-v04", tab: .agentEfficiency, badgeCode: "V04", title: "各 Skill 任务成功率 vs 返工次数随时间变化", metricTags: ["首周 → 本周成功率 ▲", "返工次数 ▼ -38%", "主力 Skill 演进"], symbolName: "chart.line.uptrend.xyaxis", topologySignature: "tab2-v04:week1-to-week4-uplift-bars+rework-drop+all-active-drawer"),
        PreviewVariantDescriptor(id: "tab2-v05", tab: .agentEfficiency, badgeCode: "V05", title: "Skill 脚本调用次数与报错率下降趋势", metricTags: ["脚本调用 5,420 次 ▲", "自身报错率 8.4% → 1.1% ▼", "主力脚本排行"], symbolName: "terminal", topologySignature: "tab2-v05:script-calls-up-error-down-curve+top6-scripts+intercept-drawer"),
        PreviewVariantDescriptor(id: "tab2-v06", tab: .agentEfficiency, badgeCode: "V06", title: "Skill 脚本执行耗时趋势（快慢排行与提速曲线）", metricTags: ["整体均耗 ▼ -41%", "最快 vs 最慢排行", "提速前后对比"], symbolName: "speedometer", topologySignature: "tab2-v06:script-latency-drop-sparkline+fast-slow-bars+speedup-drawer"),
        PreviewVariantDescriptor(id: "tab2-v07", tab: .agentEfficiency, badgeCode: "V07", title: "自动进化成绩单：Skill 自动优化前 vs 优化后效果对比", metricTags: ["成功率 73% → 92% ▲", "耗时 8.2m → 4.6m ▼", "后台自动升级"], symbolName: "wand.and.stars", topologySignature: "tab2-v07:before-after-auto-upgrade-bars+delta-pills+upgrade-notes-drawer"),
        PreviewVariantDescriptor(id: "tab2-v08", tab: .agentEfficiency, badgeCode: "V08", title: "近 7 天进步最快 ▲ vs 表现波动 ▼ 的 Skill 排行", metricTags: ["本周进步 Top 4 ▲", "波动关注 ▼ 自动排期", "周环比对比"], symbolName: "arrow.up.arrow.down.circle", topologySignature: "tab2-v08:dual-column-gainers-watchers+wow-delta-drawer"),
        PreviewVariantDescriptor(id: "tab2-v09", tab: .agentEfficiency, badgeCode: "V09", title: "Skill 内部参考文档实际使用率（常用 vs 救急用 vs 从未用过）", metricTags: ["常用 48 篇 · 救急 24 篇", "0 次阅读 9 篇", "自动精简省 Token ▼"], symbolName: "book.pages", topologySignature: "tab2-v09:3tier-doc-usage-bars+token-saved-sparkline+skill-doc-drawer"),
        PreviewVariantDescriptor(id: "tab2-v10", tab: .agentEfficiency, badgeCode: "V10", title: "全部 24 个 Skill 全景小卡片矩阵（调用次数 + 成功率 + 趋势线）", metricTags: ["默认 Top 8 主力卡", "展开看齐 24 个 Skill", "14 天微折线 ▲"], symbolName: "square.grid.3x3.topleft.filled", topologySignature: "tab2-v10:compact-top8-bento-cards+14d-sparklines+all24-matrix-drawer")
    ]

    @ViewBuilder
    public static func view(
        for descriptor: PreviewVariantDescriptor,
        data: AIDashPreviewSampleData,
        globalExpandAll: Bool,
        speed: PreviewSpeedMultiplier
    ) -> some View {
        PreviewSkillsInventorySection(
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

    private static func mode(for descriptor: PreviewVariantDescriptor) -> Tab2InstrumentMode {
        switch descriptor.id {
        case "tab2-v01": return .inventoryOverview
        case "tab2-v02": return .callLeaderboard
        case "tab2-v03": return .categoryDaily
        case "tab2-v04": return .successEvolution
        case "tab2-v05": return .scriptErrorDrop
        case "tab2-v06": return .scriptSpeedTrend
        case "tab2-v07": return .autoOptReport
        case "tab2-v08": return .weeklyMovers
        case "tab2-v09": return .docUsage
        default: return .fullMatrix
        }
    }
}

private struct PreviewSkillsInventorySection: View {
    let descriptor: PreviewVariantDescriptor
    let mode: Tab2InstrumentMode
    let data: AIDashPreviewSampleData
    let globalExpandAll: Bool
    let speed: PreviewSpeedMultiplier
    @State private var drawerExpanded = false
    @State private var filterMode = 0
    @State private var windowIndex = 2

    private var expanded: Bool { globalExpandAll || drawerExpanded }
    private var totalCalls: Int { max(1, data.skills.map(\.calls30d).reduce(0, +)) }

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
                PreviewSurface { drawer }
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
        case .inventoryOverview: inventoryOverview
        case .callLeaderboard: callLeaderboard
        case .categoryDaily: categoryDaily
        case .successEvolution: successEvolution
        case .scriptErrorDrop: scriptErrorDrop
        case .scriptSpeedTrend: scriptSpeedTrend
        case .autoOptReport: autoOptReport
        case .weeklyMovers: weeklyMovers
        case .docUsage: docUsage
        case .fullMatrix: fullMatrix
        }
    }

    private var inventoryOverview: some View {
        let activeCount = data.skills.filter { !$0.isIdle }.count
        let idleCount = data.skills.count - activeCount
        let windows = ["近 7 天", "近 14 天", "近 30 天"]
        let callSeries: [Double] = [62, 68, 74, 81, 89, 95, 104, 118]
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                PreviewPill("Skill 总数 \(data.skills.count) 个（活跃 \(activeCount) / 闲置 \(idleCount)）", tint: .blue)
                Spacer()
                Button(windows[windowIndex % 3]) { windowIndex = (windowIndex + 1) % 3 }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                statTile("近 30 天总调用", "2,840 次", "▲ +31%", .blue)
                statTile("内置脚本总调用", "5,420 次", "▲ +45%", .teal)
                statTile("平均一次成功率", "89.2%", "▲ +7.4%", .green)
                statTile("平均报错与返工率", "6.8%", "▼ -5.3%", .purple)
            }
            HStack {
                Text("30 天每日调用热度爬升线").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                PreviewPill("▲ 活跃度稳步提升", tint: .green)
            }
            PreviewSparkline(values: callSeries, tint: .green, height: 26)
        }
    }

    private var callLeaderboard: some View {
        let boardTitles = ["🔥 高频主力榜 Top 7", "💤 低频/闲置榜", "📈 增长最快榜"]
        let sorted: [PreviewSkillMetric] = {
            switch filterMode % 3 {
            case 1: return Array(data.skills.sorted { $0.calls30d < $1.calls30d }.prefix(7))
            case 2: return Array(data.skills.sorted { $0.weeklyDeltaPct > $1.weeklyDeltaPct }.prefix(7))
            default: return Array(data.skills.sorted { $0.calls30d > $1.calls30d }.prefix(7))
            }
        }()
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                PreviewPill(boardTitles[filterMode % 3], tint: .blue)
                Spacer()
                Button("切换榜单") { filterMode = (filterMode + 1) % 3 }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            ForEach(sorted) { skill in
                let share = Double(skill.calls30d) / Double(totalCalls)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(skill.plainSummary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(width: 158, alignment: .leading)
                    PreviewMetricBar(
                        label: skill.lastUsedText,
                        value: min(share * 3.8, 1),
                        valueText: "\(skill.calls30d) 次 (\(Int(share * 100))%)",
                        tint: skill.calls30d == 0 ? .orange : .blue
                    )
                    PreviewSparkline(values: skill.trend14d, tint: skill.calls30d == 0 ? .orange : .green, height: 20)
                        .frame(width: 54)
                }
            }
        }
    }

    private var categoryDaily: some View {
        let categories: [CategoryDailyRow] = [
            CategoryDailyRow(id: "总控与编排", calls: 1_130, deltaText: "▲ +28%", tint: .blue),
            CategoryDailyRow(id: "工程与构建", calls: 749, deltaText: "▲ +24%", tint: .teal),
            CategoryDailyRow(id: "界面与设计", calls: 576, deltaText: "▲ +39%", tint: .purple),
            CategoryDailyRow(id: "数据与复盘", calls: 385, deltaText: "▲ +33%", tint: .green)
        ]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                PreviewPill("近 30 天合计 2,840 次调用 ▲ +31%", tint: .green)
                Spacer()
                Button(filterMode == 0 ? "看全部类别" : categories[(filterMode - 1) % categories.count].id) {
                    filterMode = (filterMode + 1) % (categories.count + 1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(categories) { cat in
                PreviewMetricBar(
                    label: cat.id,
                    value: Double(cat.calls) / 1_200.0,
                    valueText: "\(cat.calls) 次 · \(cat.deltaText)",
                    tint: cat.tint
                )
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<10, id: \.self) { day in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.8)).frame(height: CGFloat(6 + day))
                        RoundedRectangle(cornerRadius: 2).fill(Color.purple.opacity(0.8)).frame(height: CGFloat(8 + (day % 4) * 2))
                        RoundedRectangle(cornerRadius: 2).fill(Color.teal.opacity(0.8)).frame(height: CGFloat(10 + day))
                        RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.85)).frame(height: CGFloat(14 + day * 2))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 58)
        }
    }

    private var successEvolution: some View {
        let top6 = Array(data.skills.prefix(6))
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                PreviewPill("最近 4 周：一次成功率连涨 ▲ · 返工次数 ▼ -38%", tint: .green)
                Spacer()
            }
            ForEach(top6) { skill in
                HStack(spacing: 8) {
                    Text(skill.name).font(.caption.weight(.semibold)).frame(width: 112, alignment: .leading).lineLimit(1)
                    PreviewMetricBar(
                        label: "首周 \(Int(skill.week1SuccessRate * 100))% → 本周 \(Int(skill.firstPassRate * 100))%",
                        value: skill.firstPassRate,
                        valueText: "▲ +\(Int((skill.firstPassRate - skill.week1SuccessRate) * 100))%",
                        tint: .green
                    )
                    Text("返工 \(skill.reworkCount) 次 ▼")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                }
            }
        }
    }

    private var scriptErrorDrop: some View {
        let errSeries: [Double] = [8.4, 6.9, 5.5, 4.1, 2.9, 2.1, 1.5, 1.1]
        let scripts: [(String, Int, String)] = [
            ("goal-queue.py · 任务队列与状态同步", 1_420, "报错 0.4% ▼"),
            ("ci-monitor.py · 后台零消耗盯 CI", 1_180, "报错 0.6% ▼"),
            ("verify_design_cases.py · 界面合规检查", 960, "报错 0.9% ▼"),
            ("herdr-dispatch.sh · 独立窗口派单", 840, "报错 1.2% ▼"),
            ("feedback_guard.py · 提审前防呆检查", 610, "报错 0.5% ▼"),
            ("design_catalog.py · 预览选择回执管理", 410, "报错 0.3% ▼")
        ]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                PreviewPill("脚本自身报错率：8.4% → 1.1% ▼ -87%", tint: .green)
                Spacer()
            }
            PreviewSparkline(values: errSeries, tint: .teal, height: 24)
            ForEach(scripts, id: \.0) { item in
                HStack {
                    Text(item.0).font(.caption).lineLimit(1)
                    Spacer()
                    Text("调用 \(item.1) 次 · \(item.2)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var scriptSpeedTrend: some View {
        let speedCurve: [Double] = [4.8, 4.1, 3.5, 2.9, 2.4, 2.0, 1.7, 1.5]
        let rows: [ScriptSpeedRow] = [
            ScriptSpeedRow(id: "design_catalog.py（最快）", avgSeconds: 0.3, valueText: "平均 0.3s ▼", tint: .green),
            ScriptSpeedRow(id: "goal-queue.py", avgSeconds: 0.5, valueText: "平均 0.5s ▼", tint: .green),
            ScriptSpeedRow(id: "feedback_guard.py", avgSeconds: 0.8, valueText: "平均 0.8s ▼", tint: .teal),
            ScriptSpeedRow(id: "verify_design_cases.py", avgSeconds: 1.4, valueText: "平均 1.4s ▼ -52%", tint: .blue),
            ScriptSpeedRow(id: "inspect_aidata_pipeline.py", avgSeconds: 2.1, valueText: "平均 2.1s ▼ -38%", tint: .blue),
            ScriptSpeedRow(id: "goal-supervisor.py（最慢关注）", avgSeconds: 3.2, valueText: "平均 3.2s ▼ -44%", tint: .orange)
        ]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                PreviewPill("全部脚本平均耗时：4.8s → 1.5s ▼ -69%", tint: .green)
                Spacer()
            }
            PreviewSparkline(values: speedCurve, tint: .blue, height: 24)
            ForEach(rows) { row in
                PreviewMetricBar(label: row.id, value: min(row.avgSeconds / 4.0, 1), valueText: row.valueText, tint: row.tint)
            }
        }
    }

    private var autoOptReport: some View {
        let upgraded = data.skills.filter { $0.beforeOptSuccessRate != nil }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                PreviewPill("后台自动复盘近期已升级 \(upgraded.count) 个主力 Skill ▲", tint: .green)
                Spacer()
            }
            ForEach(upgraded) { skill in
                let before = Int((skill.beforeOptSuccessRate ?? 0.72) * 100)
                let after = Int((skill.afterOptSuccessRate ?? skill.firstPassRate) * 100)
                let minBefore = skill.beforeOptMinutes ?? 8.5
                let minAfter = skill.afterOptMinutes ?? 4.8
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(skill.name).font(.caption.weight(.semibold))
                        Spacer()
                        Text("成功率 \(before)% → \(after)% ▲ · 耗时 \(String(format: "%.1f", minBefore))m → \(String(format: "%.1f", minAfter))m ▼")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    PreviewMetricBar(label: skill.optSummary ?? "自动优化完成", value: Double(after) / 100.0, valueText: "提升 +\(after - before)%", tint: .green)
                }
            }
        }
    }

    private var weeklyMovers: some View {
        let gainers = Array(data.skills.sorted { $0.weeklyDeltaPct > $1.weeklyDeltaPct }.prefix(4))
        let watchers = Array(data.skills.filter { $0.weeklyDeltaPct < 0 }.prefix(3))
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                PreviewPill("本周进步最快 Top 4 ▲", tint: .green)
                ForEach(gainers) { skill in
                    HStack {
                        Text(skill.name).font(.caption.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text(skill.deltaText).font(.caption2.monospacedDigit()).foregroundStyle(.green)
                    }
                    .padding(6)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                PreviewPill("本周有波动需关注 ▼", tint: .orange)
                ForEach(watchers) { skill in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(skill.name).font(.caption.weight(.medium)).lineLimit(1)
                            Spacer()
                            Text(skill.deltaText).font(.caption2.monospacedDigit()).foregroundStyle(.orange)
                        }
                        Text("后台已排期自动优化").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var docUsage: some View {
        let savedSeries: [Double] = [12, 18, 25, 31, 38, 44, 49, 54]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                PreviewPill("共 81 篇参考文档 · 自动精简后每次省 54% Token ▼", tint: .green)
                Spacer()
            }
            PreviewMetricBar(label: "经常用到（高频主力文档）", value: 48.0 / 81.0, valueText: "48 篇 (59%)", tint: .green)
            PreviewMetricBar(label: "修问题时救急用到（低频刚需）", value: 24.0 / 81.0, valueText: "24 篇 (30%)", tint: .blue)
            PreviewMetricBar(label: "长期 0 次阅读（后台自动精简对象）", value: 9.0 / 81.0, valueText: "9 篇 (11%) ▼", tint: .orange)
            HStack {
                Text("单次加载节省 Token 比例爬升趋势").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("▲ 省下 54%").font(.caption2.monospacedDigit()).foregroundStyle(.green)
            }
            PreviewSparkline(values: savedSeries, tint: .green, height: 22)
        }
    }

    private var fullMatrix: some View {
        let sorted: [PreviewSkillMetric] = {
            switch filterMode % 3 {
            case 1: return data.skills.sorted { $0.firstPassRate > $1.firstPassRate }
            case 2: return data.skills.sorted { $0.name < $1.name }
            default: return data.skills.sorted { $0.calls30d > $1.calls30d }
            }
        }()
        let top8 = Array(sorted.prefix(8))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                PreviewPill("默认展示前 8 个主力 Skill · 展开抽屉看齐全部 \(data.skills.count) 个", tint: .blue)
                Spacer()
                Button(["按调用量 ↓", "按成功率 ↓", "按名称 A-Z"][filterMode % 3]) { filterMode = (filterMode + 1) % 3 }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(top8) { skill in
                    skillMiniCard(skill)
                }
            }
        }
    }

    private func skillMiniCard(_ skill: PreviewSkillMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(skill.name).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer()
                Text("\(Int(skill.firstPassRate * 100))%").font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(.green)
            }
            Text(skill.plainSummary).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                Text("\(skill.calls30d) 次").font(.caption2.monospacedDigit())
                Text(skill.deltaText).font(.caption2.monospacedDigit()).foregroundStyle(skill.weeklyDeltaPct >= 0 ? .green : .orange)
                Spacer()
                PreviewSparkline(values: skill.trend14d, tint: skill.calls30d == 0 ? .orange : .green, height: 14)
                    .frame(width: 46)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func statTile(_ label: String, _ value: String, _ delta: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(delta).font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(.green)
            }
            Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var drawer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(drawerTitle).font(.subheadline.weight(.semibold))
                Spacer()
                PreviewPill("共 \(data.skills.count) 个受管 Skill", tint: .blue)
            }
            if mode == .fullMatrix {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(data.skills) { skill in
                        skillMiniCard(skill)
                    }
                }
            } else {
                ForEach(Array(drawerRows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.0).font(.caption).lineLimit(1)
                        Spacer()
                        Text(row.1).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Divider()
                }
            }
        }
    }

    private var drawerTitle: String {
        switch mode {
        case .inventoryOverview: return "活跃主力 vs 3 个闲置 Skill 快速清单"
        case .callLeaderboard: return "全部 24 个 Skill 完整调用次数排名表"
        case .categoryDaily: return "四大用途类别调用量、平均成功率与环比增幅"
        case .successEvolution: return "全部活跃 Skill 成功率与返工次数对照表"
        case .scriptErrorDrop: return "自动化脚本拦截问题数与近期自愈记录"
        case .scriptSpeedTrend: return "各脚本提速优化前后耗时对比"
        case .autoOptReport: return "后台自动升级具体改动一句话说明"
        case .weeklyMovers: return "全部 24 个 Skill 近 7 天周环比明细"
        case .docUsage: return "各 Skill 参考文档实际阅读次数分布"
        case .fullMatrix: return "全部 24 个 Skill 全景卡片矩阵（含闲置标记）"
        }
    }

    private var drawerRows: [(String, String)] {
        switch mode {
        case .inventoryOverview:
            let idleNames = data.skills.filter(\.isIdle).map(\.name).joined(separator: "、")
            return [
                ("活跃使用中（21 个）", "team-lead、my-designer、m2-dispatcher 等"),
                ("30 天 0 次调用闲置（3 个）", idleNames),
                ("近 30 天环比表现", "总调用 ▲ +31% · 返工率 ▼ -5.3%")
            ]
        case .callLeaderboard:
            return data.skills.enumerated().map { idx, skill in
                ("#\(idx + 1) \(skill.name) · \(skill.plainSummary)", "\(skill.calls30d) 次 · \(skill.lastUsedText) · \(skill.deltaText)")
            }
        case .categoryDaily:
            return [
                ("总控与编排（6 个 Skill）", "1,130 次 · 平均成功率 91.5% · ▲ +28%"),
                ("工程与构建（8 个 Skill）", "749 次 · 平均成功率 89.0% · ▲ +24%"),
                ("界面与设计（3 个 Skill）", "576 次 · 平均成功率 91.3% · ▲ +39%"),
                ("数据与复盘（7 个 Skill）", "385 次 · 平均成功率 87.8% · ▲ +33%")
            ]
        case .successEvolution:
            return data.skills.filter { !$0.isIdle }.map { skill in
                (skill.name, "首周 \(Int(skill.week1SuccessRate * 100))% → 本周 \(Int(skill.firstPassRate * 100))% ▲ · 返工 \(skill.reworkCount) 次")
            }
        case .scriptErrorDrop:
            return [
                ("累计提前拦截潜在问题", "146 次（避免线上返工 ▲）"),
                ("脚本参数与路径防呆自愈", "报错率从 8.4% 降至 1.1% ▼"),
                ("后台静默监控覆盖率", "100% 零人工盯盘 ▲")
            ]
        case .scriptSpeedTrend:
            return [
                ("verify_design_cases.py", "优化前 2.9s → 优化后 1.4s ▼ -52%"),
                ("goal-supervisor.py", "优化前 5.7s → 优化后 3.2s ▼ -44%"),
                ("design_catalog.py", "优化前 0.7s → 优化后 0.3s ▼ -57%")
            ]
        case .autoOptReport:
            return data.skills.compactMap { skill in
                guard let summary = skill.optSummary else { return nil }
                return (skill.name, summary)
            }
        case .weeklyMovers:
            return data.skills.map { ($0.name, "近7天 \($0.calls7d) 次 · 成功率 \(Int($0.firstPassRate * 100))% · \($0.deltaText)") }
        case .docUsage:
            return data.skills.prefix(12).map { skill in
                (skill.name, "常用 \(skill.frequentDocsCount) 篇 · 救急 \(skill.rescueDocsCount) 篇 · 0阅读 \(skill.zeroReadDocsCount) 篇")
            }
        case .fullMatrix:
            return []
        }
    }
}
#endif
