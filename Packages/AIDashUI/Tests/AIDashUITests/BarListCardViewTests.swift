import Testing
import SwiftUI
import AIDashCore
import DesignKit
@testable import AIDashUI

@MainActor
@Suite("BarListCardView Tests")
struct BarListCardViewTests {

    private func view(
        items: [BarListPayload.Item] = [.init(label: "runtime-offline", value: 39, valueText: "39%", semantic: "warning")],
        size: CardSize = .medium,
        style: CardStyle = .neutral
    ) -> BarListCardView {
        BarListCardView(payload: BarListPayload(items: items), size: size, style: style)
    }

    // MARK: - Rendering: materialises at every size / style

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
        _ = view(items: []).body
    }

    // MARK: - Value formatting fallback

    @Test("BarListFormat renders whole numbers without decimals and fractions with one place")
    func valueFormatting() {
        #expect(BarListFormat.value(39) == "39")
        #expect(BarListFormat.value(0) == "0")
        #expect(BarListFormat.value(4.4) == "4.4")
        #expect(BarListFormat.value(1.25) == "1.2")
    }

    // MARK: - "+N more" overflow

    @Test("moreItemsLabel embeds the overflow count in its fallback")
    func moreItemsLabelHasCount() {
        #expect(BarListCardView.moreItemsLabel(overflow: 3).contains("3"))
    }

    @Test("small size folds a long list into an overflow line")
    func longListRendersAtSmall() {
        let items = (0..<10).map { BarListPayload.Item(label: "row-\($0)", value: Double(10 - $0)) }
        _ = view(items: items, size: .small).body
    }

    // MARK: - Semantic tone mapping

    @Test("SemanticTone maps known strings to a status color + icon, nil otherwise")
    func semanticToneMapping() {
        let theme = Theme(seed: .lime, neutral: .slate, isDark: true)
        #expect(SemanticTone(rawValue: "warning")?.color(theme) == theme.warning)
        #expect(SemanticTone(rawValue: "success")?.color(theme) == theme.success)
        #expect(SemanticTone(rawValue: "danger")?.color(theme) == theme.danger)
        #expect(SemanticTone(rawValue: "warning")?.iconName == "exclamationmark.triangle.fill")
        // Unknown / nil → no tone (renders neutral).
        #expect(SemanticTone(rawValue: "bogus") == nil)
        #expect(SemanticTone(rawValue: nil) == nil)
    }

    // MARK: - Renderer chrome contract (source guards)

    @Test("renderer applies the shared cardChrome and the barList badge exactly once")
    func rendererChromeContract() throws {
        let source = try DesignTokensComplianceTests.rendererSource(for: .barList)
        #expect(source.contains(".cardChrome(size: size, style: style"),
                "barList renderer must apply the shared cardChrome modifier")
        #expect(source.contains("CardTypeBadge(type: .barList)"),
                "barList renderer must render the shared type badge")
        let chromeCount = source.components(separatedBy: ".cardChrome(").count - 1
        #expect(chromeCount == 1, "barList renderer must apply cardChrome exactly once")
        // Value text must NOT inherit the bar color — the number stays neutral.
        #expect(!source.contains("Color(hex:"),
                "barList renderer must not inline hex colors — use theme tokens")
    }
}
