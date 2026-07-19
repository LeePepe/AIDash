import Testing
import SwiftUI
import Foundation
import AIDashCore
@testable import AIDashUI
@testable import DesignKit

// Off-screen snapshot renderer. Uses SwiftUI's ImageRenderer (no screen-
// recording permission needed) to rasterize the modernized cards with the
// sample-briefing data, so the rendered result can be inspected directly.
// Gated behind AIDASH_SNAPSHOT=1 so it never runs in the normal test gate.
@MainActor
@Suite("Snapshot render (manual)")
struct SnapshotRenderTests {

    private func render(_ view: some View, width: CGFloat, to name: String) {
        for (suffix, scheme) in [("", ColorScheme.light), ("-dark", ColorScheme.dark)] {
            let host = view
                .frame(width: width)
                .designTheme(seed: .lime, neutral: .slate)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: host)
            renderer.scale = 2
            #if canImport(AppKit)
            guard let nsImage = renderer.nsImage,
                  let tiff = nsImage.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                Issue.record("ImageRenderer produced no image for \(name)\(suffix)")
                continue
            }
            let url = URL(fileURLWithPath: "/tmp/aidash-shots/\(name)\(suffix).png")
            try? png.write(to: url)
            #endif
        }
    }

    @Test("render OVERVIEW KPI grid + prose cards to /tmp/aidash-shots")
    func renderSample() {
        guard ProcessInfo.processInfo.environment["AIDASH_SNAPSHOT"] == "1" else { return }

        let overview = container("Overview", .grid, [
            card(.metric, .small, .neutral, #"{"items":[{"label":"PRs merged","value":12,"trend":"up","higherIsBetter":true,"context":"Sapphire · this week","series":[4,6,5,8,7,10,9,12]}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"Build time","value":124,"unit":"s","trend":"down","higherIsBetter":false,"context":"CI median · 7d","series":[180,170,165,150,148,140,132,124]}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"Coverage","value":87,"unit":"%","ratio":0.87,"context":"Sapphire"}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"Open incidents","value":3,"trend":"up","higherIsBetter":false,"context":"all repos · today","series":[0,1,1,2,1,2,2,3]}]}"#),
        ])

        let today = container("Today", .grid, [
            card(.digest, .wide, .neutral, #"{"title":"A strong, incident-light day","subtitle":"All repos · yesterday","body":"Twelve PRs merged across Sapphire and Basalt, with the v9-blocking crash finally resolved. The design-system migration crossed 70%. Build times are trending down.","sections":[{"heading":"Shipped","paragraphs":["SAP-301 crash fix (unblocks v9).","Cache rework cut CI 30%."]},{"heading":"Blocking today","paragraphs":["Perf review feedback due 5pm."]}]}"#),
            card(.insight, .medium, .accent, #"{"title":"Build-cache rework is paying off","subtitle":"Sapphire CI · this week","body":"Median CI dropped 180s to 124s over the week — the single biggest developer-time win this sprint."}"#),
            card(.agentSummary, .medium, .success, #"{"agentName":"Multica","completed":[{"title":"Merged 3 Sapphire PRs"},{"title":"Regenerated changelog"}],"stats":[{"label":"PRs","value":3},{"label":"Reviews","value":9},{"label":"Hours","value":6.5}]}"#),
            card(.todoList, .medium, .warning, #"{"items":[{"title":"Reply to perf review","priority":"high"},{"title":"Decide Q3 priorities","priority":"high"},{"title":"Review changelog","priority":"medium"},{"title":"Archive branches","priority":"low"}]}"#),
        ])

        render(
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("2026-07-08").font(.largeTitle.bold())
                    Text("Published just now").font(.caption).foregroundStyle(.secondary)
                }
                ContainerView(container: overview)
                ContainerView(container: today)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading),
            width: 1000,
            to: "render"
        )

        // Variant: EVERYTHING in one grid container, mixed sizes only. Proves
        // TokenGrid packs 4 small KPIs + a wide digest + medium prose into a
        // single greedy-packed grid without separate containers.
        let unified = container("Today", .grid, [
            card(.metric, .small, .neutral, #"{"items":[{"label":"PRs merged","value":12,"trend":"up","higherIsBetter":true,"context":"Sapphire","series":[4,6,5,8,7,10,9,12]}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"Build time","value":124,"unit":"s","trend":"down","higherIsBetter":false,"context":"CI · 7d","series":[180,170,165,150,148,140,132,124]}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"Coverage","value":87,"unit":"%","ratio":0.87,"context":"Sapphire"}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"Open incidents","value":3,"trend":"up","higherIsBetter":false,"context":"today","series":[0,1,1,2,1,2,2,3]}]}"#),
            card(.digest, .wide, .neutral, #"{"title":"A strong, incident-light day","subtitle":"All repos · yesterday","body":"Twelve PRs merged across Sapphire and Basalt, with the v9-blocking crash finally resolved. Build times are trending down.","sections":[{"heading":"Shipped","paragraphs":["SAP-301 crash fix.","Cache rework cut CI 30%."]},{"heading":"Blocking","paragraphs":["Perf review due 5pm."]}]}"#),
            card(.insight, .medium, .accent, #"{"title":"Build-cache rework is paying off","subtitle":"Sapphire CI","body":"Median CI dropped 180s to 124s — the biggest developer-time win this sprint."}"#),
            card(.todoList, .medium, .warning, #"{"items":[{"title":"Reply to perf review","priority":"high"},{"title":"Decide Q3 priorities","priority":"high"},{"title":"Review changelog","priority":"medium"}]}"#),
        ])
        render(
            VStack(alignment: .leading, spacing: 16) {
                Text("2026-07-08").font(.largeTitle.bold())
                ContainerView(container: unified)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading),
            width: 1000,
            to: "render-unified"
        )

        // Variant: REAL agent data (large magnitudes + a 9-item wide metric +
        // sparse hero/list cards) — the case that broke on live data. Proves
        // formattedValue abbreviates (217836228 → 218M) and nothing overflows.
        let trends = container("趋势指标", .auto, [
            // A single 9-item metric payload is one irreducible JSON literal;
            // it can't wrap, so exempt just this line from line_length.
            // swiftlint:disable:next line_length
            card(.metric, .wide, .neutral, #"{"items":[{"label":"成本","value":1013.79,"unit":"$","trend":"down","higherIsBetter":false,"series":[1408.19,728.46,1063.87,833.82,491.59,1837.16,698.83,2493.94,4523.19,2180.19,2854.52,2717.9,2013.81,1013.79]},{"label":"Token","value":217836228,"trend":"down","series":[325255254,142186521,209118076,175099598,106793163,405750768,176161328,685800284,1236175928,498605887,720861036,767046007,511537245,217836228]},{"label":"请求数","value":1301,"trend":"down","series":[6136,4440,2240,2232,1459,3883,2439,7066,12657,4595,8604,6990,4428,1301]},{"label":"浪费额","value":112.3,"unit":"$","trend":"down","higherIsBetter":false,"series":[228.16,187.96,147.7,113.22,50.05,185.56,90.72,104.87,123.18,55.67,286.45,312.23,267.49,112.3]},{"label":"完成任务","value":0,"trend":"down","higherIsBetter":true,"series":[49,6,2,13,14,75,45,247,394,37,143,92,26,0]},{"label":"会话数","value":4,"trend":"down","higherIsBetter":true,"series":[24,9,23,18,7,26,13,78,121,19,78,19,12,4]},{"label":"完成 issue","value":1,"trend":"down","higherIsBetter":true,"series":[10,1,1,5,2,5,11,49,72,5,26,9,7,1]},{"label":"开 PR","value":1,"trend":"flat","higherIsBetter":true,"series":[2,2,2,1,2,2,3,0,0,2,0,7,1,1]},{"label":"自动化占比","value":100,"unit":"%","ratio":1.0,"trend":"flat","higherIsBetter":true}]}"#),
        ])
        render(
            VStack(alignment: .leading, spacing: 16) {
                Text("2026-07-12").font(.largeTitle.bold())
                ContainerView(container: trends)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading),
            width: 1000,
            to: "render-realdata"
        )

        // Variant: SPARSE / EMPTY cards mixed into a grid — a valid-but-empty
        // metric payload (a quiet day) must render the neutral empty state, not
        // a bare-badge box. Sits beside a populated small KPI for contrast.
        let sparse = container("Sparse", .grid, [
            card(.metric, .small, .neutral, #"{"items":[{"label":"完成任务","value":0,"trend":"flat","higherIsBetter":true}]}"#),
            card(.metric, .small, .neutral, #"{"items":[]}"#),
            card(.metric, .medium, .neutral, #"{"items":[]}"#),
            card(.metric, .wide, .neutral, #"{"items":[]}"#),
        ])
        render(
            VStack(alignment: .leading, spacing: 16) {
                Text("2026-07-12").font(.largeTitle.bold())
                ContainerView(container: sparse)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading),
            width: 1000,
            to: "render-sparse"
        )

        // Variant: GitHub 工具雷达 — the redesigned trending card. Each row is a
        // recommendation block: clickable repo link, star + Δ pill, a one-line
        // reason, and a category tag. No score sparkline. Renders the real radar
        // container so the redesign can be inspected directly.
        // swiftlint:disable line_length
        let radar = container("GitHub 工具雷达", .auto, [
            card(.trending, .hero, .accent, #"{"topic":"值得现在看 · 多关联 Financial","items":[{"title":"VoltAgent/awesome-design-md","url":"https://github.com/VoltAgent/awesome-design-md","score":102743,"delta":12,"category":"设计系统/AI编码","reason":"DESIGN.md 让 AI agents 生成匹配 UI，直接加速 AIDashUI 的设计系统建设"},{"title":"TauricResearch/TradingAgents","url":"https://github.com/TauricResearch/TradingAgents","score":93459,"delta":412,"category":"AI-agent/交易投资","reason":"多 Agent LLM 金融交易框架，与 Financial 项目直接相关，可用于交易策略开发"},{"title":"ZhuLinsen/daily_stock_analysis","url":"https://github.com/ZhuLinsen/daily_stock_analysis","score":57689,"delta":-8,"category":"AI-agent/交易投资","reason":"LLM 驱动的量化交易系统，与 Financial 的交易分析需求高度契合"},{"title":"emilkowalski/skills","url":"https://github.com/emilkowalski/skills","score":16785,"delta":16,"category":"设计工具","reason":"与你的 Skills 项目同名，直接相关，值得深入了解其设计理念和实现"},{"title":"HKUDS/OpenHarness","url":"https://github.com/HKUDS/OpenHarness","score":14887,"category":"AI-agent 框架","reason":"开源 Agent 框架，与 AIDash 的智能助手系统直接相关，可参考其架构设计"},{"title":"oh-my-mermaid/oh-my-mermaid","url":"https://github.com/oh-my-mermaid/oh-my-mermaid","score":1793,"delta":3,"category":"开发工具","reason":"用 Claude Code 自动生成架构图，适合理解复杂系统"},{"title":"simonlin1212/investment-news","url":"https://github.com/simonlin1212/investment-news","score":289,"delta":5,"category":"交易投资","reason":"A股投资资讯聚合工具，覆盖 12 大赛道，本地 LLM 提炼要点"}]}"#),
            card(.trending, .hero, .neutral, #"{"topic":"拓展视野","items":[{"title":"byoungd/up","url":"https://github.com/byoungd/up","score":55918,"delta":1,"category":"学习","reason":"英语学习指南，与技术项目无直接关系，但作为开发者的通用技能提升有参考价值"},{"title":"bleedline/aimoneyhunter","url":"https://github.com/bleedline/aimoneyhunter","score":17808,"category":"AI-agent/交易投资","reason":"AI 副业赚钱指南，与 Financial 项目理念相关，但更偏实践案例而非核心技术"},{"title":"tw93/Kami","url":"https://github.com/tw93/Kami","score":9944,"category":"工具","reason":"内容展示工具，可作为知识管理参考，但与现有项目关联不大"},{"title":"zkbys/whiteboard","url":"https://github.com/zkbys/whiteboard","score":15,"category":"工具","reason":"Python 白板工具，可能涉及可视化或协作功能，拓展工具库"}]}"#),
        ])
        // swiftlint:enable line_length
        render(
            VStack(alignment: .leading, spacing: 16) {
                Text("2026-07-17").font(.largeTitle.bold())
                ContainerView(container: radar)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading),
            width: 1960,   // real dashboard width — where the row goes "too empty"
            to: "render-radar"
        )
    }

    // MARK: - In-memory model builders

    private func container(_ title: String, _ layout: ContainerLayout, _ cards: [CardModel]) -> ContainerModel {
        let c = ContainerModel(
            id: UUID().uuidString, title: title, subtitle: nil,
            order: 10, layout: layout, style: .neutral
        )
        c.cards = cards
        return c
    }

    private func card(_ type: CardType, _ size: CardSize, _ style: CardStyle, _ json: String) -> CardModel {
        CardModel(
            id: UUID().uuidString, type: type, size: size,
            style: style, payloadJSON: Data(json.utf8)
        )
    }
}
