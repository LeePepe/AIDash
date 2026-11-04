import Foundation
import SwiftUI
import Testing
import AIDashCore
import DesignKit
@testable import AIDashUI
#if canImport(AppKit)
import AppKit
#endif

@MainActor
@Suite("Main page snapshots")
struct SnapshotRenderTests {
    @Test("exports the locked desktop and compact state matrix")
    func exportsStateMatrix() throws {
        #if canImport(AppKit)
        let customDir = ProcessInfo.processInfo.environment["AIDASH_SNAPSHOT_DIR"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        let output = customDir ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("aidash-ui-snapshots-\(UUID().uuidString)", isDirectory: true)
        defer {
            if customDir == nil {
                try? FileManager.default.removeItem(at: output)
            }
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let desktop: [(String, BriefingViewState)] = [
            ("desktop-populated", .populated(
                date: "2026-11-02", containers: Self.sampleContainers, isFallback: true,
                publishedAt: Date(timeIntervalSinceNow: -3600))),
            ("desktop-loading", .loading),
            ("desktop-empty", .empty),
            ("desktop-error", .error),
        ]
        let compact: [(String, BriefingViewState)] = [
            ("compact-populated", .populated(
                date: "2026-11-02", containers: Self.sampleContainers, isFallback: false,
                publishedAt: Date(timeIntervalSinceNow: -120))),
            ("compact-empty", .empty),
        ]

        for (name, state) in desktop {
            try render(state: state, name: name, width: 1200, padding: 24, output: output,
                       archiveDates: ["2026-11-01", "2026-11-02"],
                       hiddenCardIds: name == "desktop-populated" ? ["metric-b"] : [])
        }
        for (name, state) in compact {
            try render(state: state, name: name, width: 390, padding: 20, output: output,
                       archiveDates: ["2026-11-01", "2026-11-02"])
        }
        #else
        Issue.record("Snapshots require AppKit's ImageRenderer on macOS.")
        #endif
    }

    #if canImport(AppKit)
    private func render(
        state: BriefingViewState,
        name: String,
        width: CGFloat,
        padding: CGFloat,
        output: URL,
        archiveDates: [String] = [],
        hiddenCardIds: Set<String> = []
    ) throws {
        for (suffix, scheme) in [("-light", ColorScheme.light), ("-dark", ColorScheme.dark)] {
            let theme = Theme(seed: .lime, neutral: .slate, isDark: scheme == .dark)
            let host = BriefingView(state: state, archiveDates: archiveDates)
                .padding(.horizontal, padding)
                .padding(.vertical, AIDashSpacing.pageVertical)
                .frame(width: width, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .background(theme.neutrals.bg)
                .environment(\.theme, theme)
                .environment(\.colorScheme, scheme)
                .environment(\.hiddenCardIds, hiddenCardIds)
            let renderer = ImageRenderer(content: host)
            renderer.scale = 2
            let nsImage = try #require(renderer.nsImage)
            let tiff = try #require(nsImage.tiffRepresentation)
            let rep = try #require(NSBitmapImageRep(data: tiff))
            let png = try #require(rep.representation(using: .png, properties: [:]))
            #expect(rep.pixelsWide == Int(width * 2))
            let uniqueColors = Set((0..<rep.pixelsHigh).flatMap { y in
                (0..<rep.pixelsWide).map { x in
                    rep.colorAt(x: x, y: y)?.cgColor.components?.prefix(3).map { Int($0 * 255) } ?? []
                }
            })
            #expect(uniqueColors.count > 20)
            let url = output.appendingPathComponent("\(name)\(suffix).png")
            try png.write(to: url)
        }
    }

    private static var sampleContainers: [ContainerModel] {
        let overview = ContainerModel(
            id: "overview", title: "运行状态与交付信号", subtitle: "今日 · 多工作区",
            order: 0, layout: .grid, style: .accent
        )
        overview.cards = [
            card("metric-a", .metric, #"{"items":[{"label":"已合并 PR","value":1284,"trend":"up","series":[820,940,1100,1180,1284],"higherIsBetter":true,"context":"本周"}]}"#),
            card("metric-b", .metric, #"{"items":[{"label":"构建时间","value":124,"unit":"s","trend":"down","ratio":0.76,"higherIsBetter":false,"context":"CI 中位数"}]}"#),
            card("todos", .todoList, #"{"items":[{"title":"回复性能复核","priority":"high"},{"title":"归档分支","priority":"low"}]}"#),
        ]
        let evidence = ContainerModel(
            id: "evidence", title: "本日证据与待处理事项", subtitle: "Agent authored briefing",
            order: 1, layout: .grid, style: .neutral
        )
        evidence.cards = [
            card("digest", .digest, #"{"title":"系统保持稳定","subtitle":"过去 24 小时","body":"十二个 PR 已合并，构建时间持续下降。","sections":[{"heading":"下一步","paragraphs":["完成性能复核。"]}]}"#, style: .accent),
            card("agent-summary", .agentSummary, AgentSummaryPayload(
                agentName: "bot_tl",
                completed: [.init(title: "完成主线复核"), .init(title: "发布日报")],
                stats: [.init(label: "PRs", value: 12), .init(label: "小时", value: 4.5)]
            )),
            card("section-header", .sectionHeader, SectionHeaderPayload(
                title: "证据分组", subtitle: "关系与趋势"
            )),
            card("relationship-slope", .relationship, RelationshipPayload(
                title: "交付成本变化",
                visualization: .slope,
                xAxis: .init(label: "之前", unit: "min"),
                yAxis: .init(label: "之后", unit: "min"),
                slopes: [.init(label: "AIDash", before: 21, after: 18)],
                sampleSize: 12,
                timeWindow: "7d",
                metricDefinition: "Observed cycle time",
                summary: "Observed cycle time declined."
            )),
            card("relationship-scatter", .relationship, RelationshipPayload(
                title: "投入与交付",
                visualization: .scatter,
                xAxis: .init(label: "投入", unit: "h"),
                yAxis: .init(label: "交付", unit: "PR"),
                points: [
                    .init(label: "A", x: 2, y: 3),
                    .init(label: "B", x: 4, y: 6),
                ],
                sampleSize: 8,
                timeWindow: "7d",
                metricDefinition: "Observed work and delivery",
                summary: "Observed association only."
            ))
        ]
        return [overview, evidence]
    }

    private static func card(_ id: String, _ type: CardType, _ json: String,
                             style: CardStyle = .neutral) -> CardModel {
        CardModel(
            id: id, type: type, size: .medium, style: style,
            payloadJSON: Data(json.utf8)
        )
    }

    private static func card<T: Encodable>(_ id: String, _ type: CardType, _ payload: T,
                                           style: CardStyle = .neutral) -> CardModel {
        let data = try! JSONEncoder().encode(payload)
        return CardModel(id: id, type: type, size: .medium, style: style, payloadJSON: data)
    }
    #endif
}
