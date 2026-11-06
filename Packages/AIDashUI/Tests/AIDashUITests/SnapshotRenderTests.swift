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
    @Test("exports four states for the two-container page in light and dark")
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

        let states: [(String, BriefingViewState)] = [
            ("populated", .populated(
                date: "2026-11-02", containers: Self.sampleContainers, isFallback: true,
                publishedAt: Date(timeIntervalSinceNow: -3600))),
            ("loading", .loading),
            ("empty", .empty),
            ("error", .error),
        ]

        for (name, state) in states {
            try render(state: state, name: name, width: 1200, padding: 24, output: output,
                       archiveDates: ["2026-11-01", "2026-11-02"],
                       hiddenCardIds: name == "populated" ? ["metric-b"] : [])
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
            id: "overview", title: "总览", subtitle: nil,
            order: 10, layout: .grid, style: .neutral
        )
        overview.cards = [
            card("metric-a", .metric, #"{"items":[{"label":"成本","value":1013.79,"unit":"$","trend":"down","higherIsBetter":false,"series":[2180.19,1500.4,1013.79]}]}"#),
            card("metric-b", .metric, #"{"items":[{"label":"请求数","value":1284,"trend":"up","higherIsBetter":true,"series":[820,940,1284]}]}"#),
            card("metric-c", .metric, #"{"items":[{"label":"会话数","value":341,"trend":"up","higherIsBetter":true,"series":[220,290,341]}]}"#),
            card("digest", .digest, #"{"title":"今日摘要","body":"十二个 PR 已合并，构建时间持续下降。今日优先完成性能复核。"}"#, style: .accent),
        ]
        let plan = ContainerModel(
            id: "plan", title: "今日规划", subtitle: nil,
            order: 30, layout: .list, style: .neutral
        )
        plan.cards = [
            card("todos", .todoList, #"{"title":"近期行动","items":[{"title":"回复性能复核","priority":"high","ref":"PR #4521"},{"title":"归档分支","priority":"medium","category":"工程"},{"title":"更新日报","priority":"low"}]}"#)
        ]
        return [overview, plan]
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
