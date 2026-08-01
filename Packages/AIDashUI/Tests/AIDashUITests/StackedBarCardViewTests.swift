import Testing
import SwiftUI
import AIDashCore
import DesignKit
@testable import AIDashUI

@MainActor
@Suite("StackedBarCardView Tests")
struct StackedBarCardViewTests {

    private func view(
        segments: [StackedBarPayload.Segment] = [
            .init(label: "end_turn", value: 70, semantic: "success"),
            .init(label: "tool_use", value: 25),
            .init(label: "max_tokens", value: 5, semantic: "warning"),
        ],
        title: String? = "会话质量",
        size: CardSize = .medium,
        style: CardStyle = .neutral
    ) -> StackedBarCardView {
        StackedBarCardView(
            payload: StackedBarPayload(segments: segments, title: title),
            size: size,
            style: style
        )
    }

    // MARK: - Rendering

    @Test("body materialises for every size", arguments: CardSize.allCases)
    func bodyRendersEverySize(size: CardSize) {
        _ = view(size: size).body
    }

    @Test("body materialises for every style", arguments: CardStyle.allCases)
    func bodyRendersEveryStyle(style: CardStyle) {
        _ = view(style: style).body
    }

    @Test("empty payload materialises the empty state without crashing")
    func emptyRenders() {
        _ = view(segments: []).body
    }

    @Test("model-tier (pure categorical, no semantics) payload renders")
    func categoricalRenders() {
        _ = view(
            segments: [
                .init(label: "opus-4.6-1m", value: 73.5),
                .init(label: "opus-4.7", value: 18),
                .init(label: "gpt-5.4", value: 8.5),
            ],
            title: "模型分层"
        ).body
    }

    @Test("no-title payload renders")
    func noTitleRenders() {
        _ = view(title: nil).body
    }

    // MARK: - Slice coloring: semantic vs categorical

    @Test("quality-gradient bar: semantic segments take status colors, in-between segments go quiet neutral grey")
    func sliceColoringQualityGradient() {
        let theme = Theme(seed: .lime, neutral: .slate, isDark: true)
        // good / neutral / bad — the session-quality shape (has semantics).
        let segments = [
            StackedBarPayload.Segment(label: "end_turn", value: 70, semantic: "success"),
            StackedBarPayload.Segment(label: "tool_use", value: 25),
            StackedBarPayload.Segment(label: "max_tokens", value: 5, semantic: "warning"),
        ]
        let slices = StackedBarSliceResolver.resolve(segments: segments, theme: theme)
        #expect(slices.count == 3)
        #expect(slices[0].color == theme.success)
        #expect(slices[0].tone == .success)
        #expect(slices[2].color == theme.warning)
        #expect(slices[2].tone == .warning)
        // The neutral middle segment goes quiet grey (NOT categorical) because
        // the bar already carries semantics — good/neutral/bad in three tiers.
        #expect(slices[1].color == theme.neutrals.text2)
        #expect(slices[1].tone == nil)
    }

    @Test("pure-category bar (no semantics): every segment takes a distinct chartCategorical color")
    func sliceColoringCategorical() {
        let theme = Theme(seed: .lime, neutral: .slate, isDark: true)
        let segments = [
            StackedBarPayload.Segment(label: "opus-4.6-1m", value: 73.5),
            StackedBarPayload.Segment(label: "opus-4.7", value: 18),
            StackedBarPayload.Segment(label: "gpt-5.4", value: 8.5),
        ]
        let slices = StackedBarSliceResolver.resolve(segments: segments, theme: theme)
        #expect(slices[0].color == theme.chartCategorical(0))
        #expect(slices[1].color == theme.chartCategorical(1))
        #expect(slices[2].color == theme.chartCategorical(2))
        #expect(slices[0].color != slices[1].color)
        #expect(slices[1].color != slices[2].color)
        #expect(slices.allSatisfy { $0.tone == nil })
    }

    @Test("fractions sum to 1 for a positive-total payload and are 0 for an all-zero payload")
    func fractions() {
        let theme = Theme(seed: .lime, neutral: .slate, isDark: false)
        let slices = StackedBarSliceResolver.resolve(
            segments: [.init(label: "a", value: 3), .init(label: "b", value: 1)],
            theme: theme
        )
        #expect(abs(slices.map(\.fraction).reduce(0, +) - 1.0) < 0.0001)
        #expect(abs(slices[0].fraction - 0.75) < 0.0001)

        let zero = StackedBarSliceResolver.resolve(
            segments: [.init(label: "a", value: 0), .init(label: "b", value: 0)],
            theme: theme
        )
        #expect(zero.allSatisfy { $0.fraction == 0 })
    }

    // MARK: - Renderer chrome contract

    @Test("renderer applies the shared cardChrome and the stackedBar badge exactly once")
    func rendererChromeContract() throws {
        let source = try DesignTokensComplianceTests.rendererSource(for: .stackedBar)
        #expect(source.contains(".cardChrome(size: size, style: style"),
                "stackedBar renderer must apply the shared cardChrome modifier")
        #expect(source.contains("CardTypeBadge(type: .stackedBar)"),
                "stackedBar renderer must render the shared type badge")
        let chromeCount = source.components(separatedBy: ".cardChrome(").count - 1
        #expect(chromeCount == 1, "stackedBar renderer must apply cardChrome exactly once")
        #expect(!source.contains("Color(hex:"),
                "stackedBar renderer must not inline hex colors — use theme tokens")
    }
}
