import Testing
import SwiftUI
import Foundation
import AIDashCore
import DesignKit
#if canImport(AppKit)
import AppKit
#endif
@testable import AIDashUI

// Two-container integration evidence for the simplified daily briefing.
//
// Renders the default contract — overview metrics + one digest and a focused
// three-row plan — through the production render path.
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
@Suite("Data-driven two-container briefing evidence")
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

    @Test("render the two-container briefing to design/prototype-shots (light + dark)")
    func renderEvidenceShots() throws {
        // The payloads are asserted unconditionally: even in the normal gate
        // (no AIDASH_SNAPSHOT) this case still proves the fixture is the shape
        // the issue requires, so a later edit that guts it fails loudly here
        // instead of silently producing a weaker screenshot.
        let containers = Self.briefingContainers()

        #expect(containers.count == 2)
        #expect(containers.map(\.title) == ["总览", "今日规划"])
        #expect(containers[0].cards.filter { $0.type == .metric }.count <= 4)
        #expect(containers[0].cards.filter { $0.type == .digest }.count == 1)
        #expect(containers[1].cards.filter { $0.type == .todoList }.count == 1)

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
                    StatusPill("SYNCED", tone: .success)
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

    // MARK: - Two-container fixture

    private static func briefingContainers() -> [ContainerModel] {
        let overview = container("总览", .grid, order: 10, [
            // swiftlint:disable line_length
            card(.metric, .small, .neutral, #"{"items":[{"label":"成本","value":1013.79,"unit":"$","trend":"down","higherIsBetter":false,"context":"今日","series":[2180.19,1500.4,1013.79]}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"请求数","value":1284,"trend":"up","higherIsBetter":true,"context":"今日","series":[820,940,1284]}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"会话数","value":341,"trend":"up","higherIsBetter":true,"context":"今日","series":[220,290,341]}]}"#),
            card(.metric, .small, .neutral, #"{"items":[{"label":"自动化占比","value":63,"unit":"%","ratio":0.63,"context":"今日"}]}"#),
            card(.digest, .wide, .accent, #"{"title":"今日摘要","body":"十二个 PR 已合并，构建时间持续下降。今日优先完成性能复核。"}"#)
            // swiftlint:enable line_length
        ])

        let plan = container("今日规划", .list, order: 30, [
            // swiftlint:disable:next line_length
            card(.todoList, .wide, .neutral, #"{"title":"近期行动","items":[{"title":"回复性能复核","priority":"high","ref":"PR #4521"},{"title":"归档分支","priority":"medium","category":"工程"},{"title":"更新日报","priority":"low"}]}"#)
        ])

        return [overview, plan]
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
