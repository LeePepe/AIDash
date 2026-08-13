import Testing
import SwiftUI
import Foundation
import AIDashCore
import DesignKit
@testable import AIDashUI

// Stage-3 integration evidence (MY-1396).
//
// Renders ONE shaped-data briefing — small metrics + a medium ranking + a wide
// relationship — through the production render path (ContainerView → CardRouter
// → the real card views) and writes the light/dark PNGs the design gate scores.
//
// Why this is a separate case from `SnapshotRenderTests`: that suite writes
// throwaway shots to /tmp for eyeballing. These two PNGs are committed evidence
// with fixed paths, so they get their own case and their own composition —
// the page chrome BriefingView actually ships (terminal masthead, 1200pt max
// width, theme.neutrals.bg backing) rather than a bare VStack. Scoring a shot
// that omits the production chrome would score a view the user never sees.
//
// BriefingView itself is @Query-bound to SwiftData and cannot be instantiated
// off a store, so the chrome is reproduced here from the same tokens it reads.
// The CARDS are the real thing — no stand-ins.
//
// Gated behind AIDASH_SNAPSHOT=1 exactly like the sibling suite, so the normal
// test gate never pays for it. The commit that adds it inherits that variable
// from the pre-commit hook environment, which is what actually produces the
// artifacts — the renderer is never invoked by hand.
@MainActor
@Suite("Data-driven briefing evidence (MY-1396)")
struct DataDrivenBriefingEvidenceTests {

    /// Where the committed artifacts land, relative to the repo root.
    /// `#filePath` walks up out of Packages/AIDashUI/Tests/AIDashUITests/.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AIDashUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // AIDashUI
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repo root
    }

    private static let shotsDir = "design/prototype-shots"
    private static let artifactStem = "data-driven-briefing"

    @Test("render the shaped-data briefing to design/prototype-shots (light + dark)")
    func renderEvidenceShots() throws {
        // The payloads are asserted unconditionally: even in the normal gate
        // (no AIDASH_SNAPSHOT) this case still proves the fixture is the shape
        // the issue requires, so a later edit that guts it fails loudly here
        // instead of silently producing a weaker screenshot.
        let containers = Self.briefingContainers()

        let cards = containers.flatMap(\.cards)
        #expect(cards.contains { $0.type == .metric && $0.size == .small },
                "evidence fixture must carry small metric cards")
        #expect(cards.contains { $0.type == .barList && $0.size == .medium },
                "evidence fixture must carry a medium ranking card")
        #expect(cards.contains { $0.type == .relationship && $0.size == .wide },
                "evidence fixture must carry a wide relationship card")

        // A wide relationship card is only honestly wide if its payload earns
        // that size — EffectiveCardSize downgrades a sparse scatter, which would
        // silently render the evidence at the wrong geometry.
        let wideRelationship = try #require(
            cards.first { $0.type == .relationship && $0.size == .wide }
        )
        #expect(
            EffectiveCardSize.resolve(
                type: .relationship,
                authored: .wide,
                payloadJSON: wideRelationship.payloadJSON
            ) == .wide,
            "the relationship payload must justify `wide`, not be downgraded"
        )

        guard ProcessInfo.processInfo.environment["AIDASH_SNAPSHOT"] == "1" else { return }

        #if canImport(AppKit)
        for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let page = Self.page(containers: containers)
                .frame(width: Space.contentMaxWidth)
                .designTheme(seed: .lime, neutral: .slate)
                .environment(\.colorScheme, scheme)

            let renderer = ImageRenderer(content: page)
            renderer.scale = 2

            let nsImage = try #require(renderer.nsImage, "ImageRenderer produced no image (\(suffix))")
            let tiff = try #require(nsImage.tiffRepresentation)
            let rep = try #require(NSBitmapImageRep(data: tiff))
            let png = try #require(rep.representation(using: .png, properties: [:]))

            let dir = Self.repoRoot.appending(path: Self.shotsDir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appending(path: "\(Self.artifactStem)-\(suffix).png")
            try png.write(to: url)

            #expect(FileManager.default.fileExists(atPath: url.path))
        }
        #endif
    }

    // MARK: - Production page chrome
    //
    // Mirrors BriefingView.scrollBody/header: terminal masthead (product mark,
    // sync dot, monospaced date, hairline rule), page padding, content max
    // width, and the bg-tier backing that makes cards read as elevated.

    @ViewBuilder
    private static func page(containers: [ContainerModel]) -> some View {
        ThemedPage(containers: containers)
    }

    private struct ThemedPage: View {
        @Environment(\.theme) private var theme
        let containers: [ContainerModel]

        var body: some View {
            VStack(alignment: .leading, spacing: AIDashSpacing.containerVertical) {
                masthead
                ForEach(containers.sorted(by: { $0.order < $1.order }), id: \.id) { container in
                    ContainerView(container: container)
                }
            }
            .padding(.horizontal, AIDashSpacing.pageHorizontalMac)
            .padding(.vertical, AIDashSpacing.pageVertical)
            .frame(maxWidth: Space.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .background(theme.neutrals.bg)
        }

        private var masthead: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: "AIDASH")
                        .font(AIDashTypography.mastheadStatus)
                        .tracking(2)
                        .foregroundStyle(theme.primary.primary)
                    Text(verbatim: "// DAILY BRIEFING")
                        .font(AIDashTypography.mastheadStatus)
                        .tracking(1.4)
                        .foregroundStyle(theme.neutrals.text3)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(theme.success).frame(width: 7, height: 7)
                        Text(verbatim: "PUBLISHED · SYNCED")
                            .font(AIDashTypography.mastheadStatus)
                            .foregroundStyle(theme.neutrals.text2)
                    }
                }
                Text(verbatim: "2026-08-12")
                    .font(AIDashTypography.masthead)
                    .foregroundStyle(theme.neutrals.text1)
                Rectangle()
                    .fill(theme.neutrals.border)
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Shaped fixture
    //
    // Magnitudes and labels follow the real token-efficiency briefing this
    // feature was built for. The relationship summary stays correlational on
    // purpose — the y-axis is a pipeline-status proxy, not measured
    // correctness, and the card must never imply causation.

    private static func briefingContainers() -> [ContainerModel] {
        let overview = container("总览 · 今日", .grid, order: 10, [
            // swiftlint:disable line_length
            card(.metric, .small, .neutral, #"{"items":[{"label":"Token 用量","value":217836228,"trend":"down","higherIsBetter":false,"context":"全部工作区 · 今日","series":[498605887,720861036,767046007,511537245,325255254,289114002,217836228]}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"成本","value":1013.79,"unit":"$","trend":"down","higherIsBetter":false,"context":"全部工作区 · 今日","series":[2180.19,2854.52,2717.9,2013.81,1408.19,1190.44,1013.79]}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"完成 issue","value":7,"trend":"up","higherIsBetter":true,"context":"pipeline 状态代理","series":[5,26,9,7,10,4,7]}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"缓存命中率","value":63,"unit":"%","ratio":0.63,"context":"覆盖 ~8k/13k 会话"}]}"#)
            // swiftlint:enable line_length
        ])

        let ranking = container("返工来源 · 排名", .grid, order: 20, [
            // swiftlint:disable:next line_length
            card(.barList, .medium, .neutral, #"{"items":[{"label":"取消后重做","value":41,"valueText":"41%","semantic":"warning"},{"label":"review 往返","value":27,"valueText":"27%"},{"label":"跨层返工","value":19,"valueText":"19%"},{"label":"门禁失败","value":13,"valueText":"13%"}]}"#),
            // swiftlint:disable:next line_length
            card(.stackedBar, .medium, .neutral, #"{"title":"会话结束原因","segments":[{"label":"end_turn","value":68,"semantic":"success"},{"label":"tool_use","value":26},{"label":"max_tokens","value":6,"semantic":"warning"}]}"#)
        ])

        let relationship = container("关联 · 成本 × 产出", .grid, order: 30, [
            // swiftlint:disable:next line_length
            card(.relationship, .wide, .neutral, #"{"title":"Cost × outcome","visualization":"scatter","xAxis":{"label":"Cost per completed task","unit":"USD"},"yAxis":{"label":"First-pass completion proxy","unit":"%"},"points":[{"label":"AIDash","x":2.1,"y":88,"magnitude":34,"category":"project"},{"label":"Financial","x":3.4,"y":81,"magnitude":21,"category":"project"},{"label":"Skills","x":4.8,"y":74,"magnitude":12,"category":"workspace"},{"label":"Multica","x":5.6,"y":69,"magnitude":28,"category":"workspace"},{"label":"aidata","x":6.9,"y":62,"magnitude":9,"category":"project"}],"sampleSize":34,"timeWindow":"7d","metricDefinition":"completed is a pipeline proxy, not objective correctness","summary":"AIDash has the lowest observed cost at the highest completion proxy."}"#)
        ])

        return [overview, ranking, relationship]
    }

    // MARK: - In-memory model builders

    private static func container(
        _ title: String,
        _ layout: ContainerLayout,
        order: Int,
        _ cards: [CardModel]
    ) -> ContainerModel {
        let c = ContainerModel(
            id: UUID().uuidString, title: title, subtitle: nil,
            order: order, layout: layout, style: .neutral
        )
        c.cards = cards
        return c
    }

    private static func card(
        _ type: CardType,
        _ size: CardSize,
        _ style: CardStyle,
        _ json: String
    ) -> CardModel {
        CardModel(
            id: UUID().uuidString, type: type, size: size,
            style: style, payloadJSON: Data(json.utf8)
        )
    }
}
