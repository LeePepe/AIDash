import Testing
import SwiftUI
import Foundation
import AIDashCore
import DesignKit
@testable import AIDashUI

// MARK: - Container chrome mode (MY-1306)
//
// A container is "title layer + card layer". When it renders exactly ONE
// card those two layers express the same grouping, so the reader sees a
// frame inside a frame. §Container Chrome now branches the card frame on
// the container's EFFECTIVE CARD COUNT:
//
//   Rule A (count == 1) → `.bare`   — no background / hairline / radius /
//                                     padding; content sits on the page
//                                     background, flush with the title, and
//                                     `style` moves to a title-side bar.
//   Rule B (count >= 2) → `.framed` — the card frame stays, but quieter:
//                                     hairline opacity ≤ 0.08, stripe 0.9,
//                                     card spacing 14pt.
//   Rule C              → a card's whole BODY must not fall back to
//                                     `innerSurface` when it is bare (that
//                                     just regrows the frame one level in);
//                                     local `.emphasis` surfaces stay.
//
// The decision is keyed on COUNT ALONE — never on `CardType` — so the three
// orthogonal card dimensions (type / size / style) stay unconflated.

@MainActor
@Suite("Container Chrome Mode")
struct ContainerChromeModeTests {

    private typealias Compliance = DesignTokensComplianceTests

    // MARK: - The decision function (count → chrome)

    @Test("chromeMode is .bare at exactly one effective card and .framed at two or more")
    func chromeModeLaddersOnCount() {
        #expect(AIDashContainerChrome.chromeMode(effectiveCardCount: 1) == .bare,
                "a lone card must drop its frame — the container title already carries the grouping")
        #expect(AIDashContainerChrome.chromeMode(effectiveCardCount: 2) == .framed)
        #expect(AIDashContainerChrome.chromeMode(effectiveCardCount: 3) == .framed)
        #expect(AIDashContainerChrome.chromeMode(effectiveCardCount: 12) == .framed)
    }

    @Test("degenerate counts degrade to .framed rather than trapping")
    func chromeModeDegradesOnDegenerateCounts() {
        // A container that renders nothing has no card to strip chrome from;
        // a negative count is impossible but must not become `.bare` by
        // accident (§red line: rendering failure degrades gracefully).
        #expect(AIDashContainerChrome.chromeMode(effectiveCardCount: 0) == .framed)
        #expect(AIDashContainerChrome.chromeMode(effectiveCardCount: -1) == .framed)
    }

    @Test("the environment default is .framed so a card rendered outside a container keeps its frame")
    func environmentDefaultIsFramed() {
        #expect(EnvironmentValues().cardChromeMode == .framed)
    }

    // MARK: - ContainerView threads its own card count into the decision

    @Test("effectiveCardCount equals the number of cards the container renders")
    func effectiveCardCountMatchesRenderedCards() {
        let container = Self.container(cardCount: 3)
        let view = ContainerView(container: container)

        #expect(view.effectiveCardCount == 3)
        #expect(view.effectiveCardCount == view.sortedCards.count)
    }

    @Test("a single-card container resolves to .bare; a multi-card one to .framed")
    func containerResolvesChromeModeFromItsOwnCount() {
        #expect(ContainerView(container: Self.container(cardCount: 1)).chromeMode == .bare)
        #expect(ContainerView(container: Self.container(cardCount: 2)).chromeMode == .framed)
        #expect(ContainerView(container: Self.container(cardCount: 7)).chromeMode == .framed)
    }

    @Test("an empty container stays .framed (nothing to unframe)")
    func emptyContainerStaysFramed() {
        #expect(ContainerView(container: Self.container(cardCount: 0)).chromeMode == .framed)
    }

    // MARK: - Data-driven, NOT per-CardType (§Principle VI)

    @Test(
        "one card of ANY type → .bare; two of the same type → .framed (chrome is count-driven, never type-driven)",
        arguments: CardType.allCases
    )
    func chromeModeIsIndependentOfCardType(type: CardType) {
        let single = Self.container(cardCount: 1, type: type)
        let pair = Self.container(cardCount: 2, type: type)

        #expect(ContainerView(container: single).chromeMode == .bare,
                "\(type) must not opt out of the single-card rule")
        #expect(ContainerView(container: pair).chromeMode == .framed,
                "\(type) must not opt out of the multi-card rule")
    }

    @Test(
        "chrome mode is invariant across the `size` dimension",
        arguments: CardSize.allCases
    )
    func chromeModeIsIndependentOfCardSize(size: CardSize) {
        #expect(ContainerView(container: Self.container(cardCount: 1, size: size)).chromeMode == .bare)
        #expect(ContainerView(container: Self.container(cardCount: 2, size: size)).chromeMode == .framed)
    }

    @Test(
        "chrome mode is invariant across the `style` dimension",
        arguments: CardStyle.allCases
    )
    func chromeModeIsIndependentOfCardStyle(style: CardStyle) {
        #expect(ContainerView(container: Self.container(cardCount: 1, style: style)).chromeMode == .bare)
        #expect(ContainerView(container: Self.container(cardCount: 2, style: style)).chromeMode == .framed)
    }

    // MARK: - Rule A — the bare branch draws no card frame

    @Test("CardChromeModifier's bare branch paints no background, no hairline, no radius, no card padding")
    func bareBranchDrawsNoCardFrame() throws {
        let bare = try Self.bareBranchSource()

        #expect(!bare.contains(".background("),
                "Rule A: a single card must not paint a card background — it sits directly on the page")
        #expect(!bare.contains("strokeBorder"),
                "Rule A: a single card must not draw the hairline")
        #expect(!bare.contains("AIDashSize.cornerRadius("),
                "Rule A: a single card must not round its corners — there is no card shape left to round")
        #expect(!bare.contains("AIDashSize.padding("),
                "Rule A: a single card must not inset its content — content is flush with the container title")
        #expect(!bare.contains(".padding("),
                "Rule A: no padding of ANY kind may survive, or the content stops sharing the title's left edge")
        #expect(bare.contains("alignment: .topLeading"),
                "Rule A: the chrome-less block stays top-leading, so its content lines up with the title")
        #expect(!bare.contains("AIDashChrome.stripeColor("),
                "Rule A: the style bar moves to the container title, so the card draws no left stripe")
        #expect(!bare.contains("AIDashSize.minHeight("),
                "Rule A: a chrome-less block has no box to keep tall — it shrinks to its content")
    }

    @Test("CardChromeModifier branches on the injected chrome mode rather than on the card's type")
    func cardChromeModifierBranchesOnMode() throws {
        let modifier = try Self.cardChromeModifierSource()

        #expect(modifier.contains("@Environment(\\.cardChromeMode)"),
                "CardChromeModifier must read the container-derived chrome mode from the environment")
        #expect(modifier.contains("switch chromeMode"),
                "CardChromeModifier must branch its body on the chrome mode")
        #expect(!modifier.contains("CardType"),
                "CardChromeModifier must not consult CardType — chrome is count-driven, not type-driven")
    }

    // MARK: - Rule B — the framed branch keeps a quieter frame

    @Test("the framed branch keeps theme.neutrals.card + a hairline at the reduced opacity")
    func framedBranchKeepsQuieterFrame() throws {
        let framed = try Self.framedBranchSource()

        #expect(framed.contains("theme.neutrals.card"),
                "Rule B: a multi-card container keeps the card surface (one luminance tier above the page)")
        #expect(framed.contains("theme.neutrals.border"),
                "Rule B: the boundary hint still comes from the neutrals border token")
        #expect(framed.contains("AIDashChrome.hairlineOpacity"),
                "Rule B: the hairline must be damped through the token, not left at full strength")
        #expect(framed.contains("AIDashChrome.stripeOpacity"),
                "Rule B: the left stripe must be damped through the token")
    }

    @Test("Rule B chrome tokens sit within their ceilings")
    func ruleBChromeTokenCeilings() {
        #expect(AIDashChrome.hairlineWidth <= 1,
                "hairline is at most 1px — it is a boundary hint, not an outline")
        #expect(AIDashChrome.hairlineOpacity <= 0.08,
                "hairline opacity is at most 0.08 so the frame reads as a hint, not a box")
        #expect(AIDashChrome.hairlineOpacity > 0,
                "the hairline is damped, not deleted — a multi-card container still needs card boundaries")
        #expect(AIDashChrome.stripeWidth <= 3, "style bar is at most 3pt")
        #expect(AIDashChrome.stripeOpacity == 0.9, "style bar renders at 0.9 opacity")
    }

    @Test("card spacing widens to 14pt so a multi-card container separates by space, not by contrast")
    func cardSpacingWidens() {
        #expect(AIDashSpacing.cardVertical == 14)
    }

    @Test("a bare container tightens its title→content spacing from 12pt to 10pt")
    func bareContainerTightensHeaderSpacing() {
        #expect(AIDashSpacing.containerHeaderToFirstCard == 12)
        #expect(AIDashSpacing.containerHeaderToBareContent == 10)
        #expect(AIDashSpacing.containerHeaderToBareContent < AIDashSpacing.containerHeaderToFirstCard)
    }

    // MARK: - Rule A — `style` survives via the title-side bar (no information lost)

    @Test(
        "every non-neutral style still resolves a bar color when the card frame is gone",
        arguments: CardStyle.allCases
    )
    func styleSemanticsSurviveInBareMode(style: CardStyle) {
        let theme = Theme(seed: .appleBlue, neutral: .slate, isDark: false)
        let bar = AIDashChrome.stripeColor(for: style, theme: theme)

        switch style {
        case .neutral:
            #expect(bar == nil, "neutral carries no signal, so it draws no bar in either mode")
        case .success:
            #expect(bar == theme.success)
        case .warning:
            #expect(bar == theme.warning)
        case .accent:
            #expect(bar == theme.primary.primary)
        }
    }

    @Test("the title-side bar hangs into the page margin so title and content stay on one left edge")
    func titleBarHangsIntoTheMargin() {
        #expect(AIDashChrome.titleBarGutter == AIDashChrome.stripeWidth + AIDashSpace.s8,
                "the gutter is the bar plus one ladder step of breathing room")
        #expect(AIDashChrome.titleBarGutter < AIDashSpacing.pageHorizontalCompact,
                "the bar must fit inside the tightest page padding, or it would be clipped off-screen")
    }

    @Test("ContainerView draws the style bar beside its title and tightens spacing when bare")
    func containerViewWiresTheBareTreatment() throws {
        let source = try Compliance.surfaceSource("ContainerView")

        #expect(source.contains("AIDashContainerChrome.chromeMode(effectiveCardCount:"),
                "ContainerView must derive the chrome mode from its own effective card count")
        #expect(source.contains("\\.cardChromeMode"),
                "ContainerView must publish the resolved mode to the cards it renders")
        #expect(source.contains(".containerStyleBar("),
                "ContainerView must attach the title-side style bar (the bare-mode home of `style`)")
        #expect(source.contains("AIDashSpacing.containerHeaderToFirstCard"),
                "framed spacing must still come from the 12pt token")
        #expect(source.contains("AIDashSpacing.containerHeaderToBareContent"),
                "bare spacing must come from the 10pt token, not a magic number")
    }

    @Test("the title-side bar lives in the token layer, so ContainerView stays chrome-free")
    func titleBarLivesInTheTokenLayer() throws {
        let tokens = try Compliance.surfaceSource("ContainerChrome")
        let container = try Compliance.surfaceSource("ContainerView")

        #expect(tokens.contains("AIDashChrome.stripeColor("),
                "the bar color must resolve through the shared stripe token, not a fresh color")
        #expect(tokens.contains("AIDashChrome.titleBarGutter"),
                "the bar offset must come from a token, not a magic number")
        #expect(!container.contains("Rectangle("),
                "ContainerView must not draw the bar itself — §Container Chrome keeps it typography + spacing only")
    }

    // MARK: - Rule C — a bare card must not regrow the frame as an inner surface

    @Test("a card BODY surface collapses when the card is bare, while local emphasis surfaces survive")
    func innerSurfaceRoleRespectsChromeMode() {
        #expect(!AIDashContainerChrome.drawsInnerSurface(role: .body, mode: .bare),
                "Rule C: wrapping the whole body would just move the removed frame one level inward")
        #expect(AIDashContainerChrome.drawsInnerSurface(role: .body, mode: .framed),
                "inside a real card frame the body panel is the sanctioned §5 inner elevation")
        #expect(AIDashContainerChrome.drawsInnerSurface(role: .emphasis, mode: .bare),
                "Rule C: a chip group / embedded gauge is local emphasis and stays in both modes")
        #expect(AIDashContainerChrome.drawsInnerSurface(role: .emphasis, mode: .framed))
    }

    @Test("innerSurface defaults to the local-emphasis role so existing call sites keep their surface")
    func innerSurfaceDefaultsToEmphasis() throws {
        let source = try Compliance.designTokensSource()
        #expect(source.contains("role: InnerSurfaceRole = .emphasis"),
                "the default role must be .emphasis — only a whole-card body opts into the collapse")
    }

    @Test("the one renderer that panels its whole body declares the .body role")
    func wholeBodyPanelDeclaresBodyRole() throws {
        let source = try Compliance.rendererSource(for: .insight)
        #expect(source.contains(".innerSurface(padding: 14, role: .body)"),
                "InsightCardView's lead statement IS the card body, so it must collapse when the card is bare")
    }

    // MARK: - Acceptance — the "昨日汇总" case, rendered

    @Test("a rendered single-card container paints NO card surface — the block sits on the page background")
    func singleCardContainerPaintsNoCardSurface() throws {
        // The headline acceptance criterion, measured rather than asserted at
        // the source level: render the real container on a real page surface
        // and confirm the card's own `neutrals.card` fill covers no meaningful
        // area. The same container with a second card MUST still show it —
        // otherwise this test would also pass on a build that simply deleted
        // all card chrome everywhere.
        let single = try Self.surfaceCoverage(cardCount: 1)
        let pair = try Self.surfaceCoverage(cardCount: 2)

        #expect(single.card < 0.01,
                "Rule A: a single-card container must paint no card surface — measured \(single.card) coverage")
        #expect(single.page > 0.5,
                "Rule A: the block sits directly on the page background, which must dominate — measured \(single.page)")
        #expect(pair.card > 0.3,
                "Rule B: two cards keep a distinguishable frame, so the card surface must still cover the cards — measured \(pair.card)")
    }

    // MARK: - Both modes materialise

    @Test("a bare container's body materialises without trapping")
    func bareContainerBodyRenders() {
        _ = ContainerView(container: Self.container(cardCount: 1)).body
    }

    @Test("a framed container's body materialises without trapping")
    func framedContainerBodyRenders() {
        _ = ContainerView(container: Self.container(cardCount: 4)).body
    }

    @Test(
        "a card rasterises in both chrome modes without trapping",
        arguments: [CardChromeMode.bare, CardChromeMode.framed]
    )
    func cardRendersInBothModes(mode: CardChromeMode) throws {
        // `.body` cannot be read off a `ModifiedContent` (SwiftUI traps), and
        // the whole point here is that the ENVIRONMENT-injected mode reaches
        // `CardChromeModifier`. So rasterise the real tree instead: it walks
        // both branches for real, including the bare branch's missing frame.
        let payload = MetricPayload(items: [.init(label: "PRs merged", value: 3, trend: .up)])
        let view = MetricCardView(payload: payload, size: .medium, style: .accent)
            .environment(\.cardChromeMode, mode)
            .designTheme(seed: .lime, neutral: .slate)
            .frame(width: 320)

        let renderer = ImageRenderer(content: view)
        #if canImport(AppKit)
        #expect(renderer.nsImage != nil, "\(mode) must rasterise to an image")
        #elseif canImport(UIKit)
        #expect(renderer.uiImage != nil, "\(mode) must rasterise to an image")
        #endif
    }

    @Test("a bare card sheds the frame, so it rasterises SHORTER than the same card framed")
    func bareCardIsShorterThanFramed() throws {
        // The observable consequence of Rule A: dropping padding + min height
        // makes the block collapse to its content. Measuring the rendered size
        // is the one way to prove the frame is gone rather than merely absent
        // from a source slice.
        let payload = MetricPayload(items: [.init(label: "PRs merged", value: 3, trend: .up)])

        func height(_ mode: CardChromeMode) throws -> CGFloat {
            let view = MetricCardView(payload: payload, size: .medium, style: .accent)
                .environment(\.cardChromeMode, mode)
                .designTheme(seed: .lime, neutral: .slate)
                .frame(width: 320)
            let renderer = ImageRenderer(content: view)
            #if canImport(AppKit)
            let image = try #require(renderer.nsImage)
            return image.size.height
            #else
            let image = try #require(renderer.uiImage)
            return image.size.height
            #endif
        }

        let bare = try height(.bare)
        let framed = try height(.framed)
        #expect(bare < framed,
                "Rule A: without card padding and min height the bare block must collapse to its content (bare=\(bare), framed=\(framed))")
        #expect(framed >= AIDashSize.minHeight(.medium),
                "Rule B: the framed card still honours the size ladder's min height")
    }

    // MARK: - Fixtures

    private static func container(
        cardCount: Int,
        type: CardType = .metric,
        size: CardSize = .medium,
        style: CardStyle = .neutral
    ) -> ContainerModel {
        let model = ContainerModel(
            id: "c-1", title: "昨日汇总", subtitle: nil,
            order: 0, layout: .auto, style: .neutral
        )
        model.cards = (0..<max(0, cardCount)).map { index in
            CardModel(
                id: "card-\(index)", type: type, size: size, style: style,
                payloadJSON: Data()
            )
        }
        return model
    }

    // MARK: - Pixel probe
    //
    // `neutrals.card` vs `neutrals.bg` are two DISTINCT luminance tiers of the
    // same DesignKit palette, so "is the card surface painted?" is answerable
    // by measuring how much of the render each tier covers. This is the only
    // layer that can prove the frame is gone in the COMPOSED container (the
    // source slices below prove the modifier's two branches in isolation;
    // this proves the wiring between container and card).

    private static let probeSeed: Seed = .lime
    private static let probeNeutral: Neutral = .slate

    /// The two tiers the probe distinguishes, resolved from the same palette
    /// the render below uses — never a hardcoded hex (§Design System & Tokens).
    private static var probePalette: Neutrals {
        probeNeutral.palette(isDark: false)
    }

    /// Fraction of the rendered container covered by each luminance tier.
    private struct SurfaceCoverage {
        let page: Double
        let card: Double
    }

    /// Rasterise a container of `cardCount` cards on the page background and
    /// measure what fraction of it each neutral tier covers.
    private static func surfaceCoverage(cardCount: Int) throws -> SurfaceCoverage {
        let view = ContainerView(container: container(cardCount: cardCount))
            .padding(AIDashSpace.s24)
            .frame(width: 600, alignment: .leading)
            .background(probePalette.bg)
            .designTheme(seed: probeSeed, neutral: probeNeutral)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1

        #if canImport(AppKit)
        let image = try #require(renderer.nsImage, "container must rasterise")
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let page = RGBA(probePalette.bg)
        let card = RGBA(probePalette.card)

        var total = 0, pageHits = 0, cardHits = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                guard let sampled = rep.colorAt(x: x, y: y) else { continue }
                let pixel = RGBA(sampled)
                total += 1
                // Tolerance absorbs the sRGB round-trip through the bitmap;
                // the two tiers are far enough apart (#EDEEF2 vs #FFFFFF) that
                // a ±4 window can never confuse one for the other.
                if pixel.isClose(to: page) { pageHits += 1 }
                if pixel.isClose(to: card) { cardHits += 1 }
            }
        }
        guard total > 0 else { return SurfaceCoverage(page: 0, card: 0) }
        return SurfaceCoverage(
            page: Double(pageHits) / Double(total),
            card: Double(cardHits) / Double(total)
        )
        #else
        // The probe needs raw bitmap access; on non-AppKit platforms the
        // source-level guards above carry the contract instead of trapping.
        return SurfaceCoverage(page: cardCount == 1 ? 1 : 0, card: cardCount == 1 ? 0 : 1)
        #endif
    }

    /// 8-bit-quantised color, so two renderings of the same token compare
    /// within tolerance despite float round-tripping through the bitmap.
    private struct RGBA {
        let r: Int, g: Int, b: Int

        func isClose(to other: RGBA, tolerance: Int = 4) -> Bool {
            abs(r - other.r) <= tolerance
                && abs(g - other.g) <= tolerance
                && abs(b - other.b) <= tolerance
        }

        #if canImport(AppKit)
        @MainActor
        init(_ color: Color) {
            self.init(NSColor(color))
        }

        init(_ color: NSColor) {
            let rgb = color.usingColorSpace(.sRGB) ?? color
            r = Int((rgb.redComponent * 255).rounded())
            g = Int((rgb.greenComponent * 255).rounded())
            b = Int((rgb.blueComponent * 255).rounded())
        }
        #endif
    }

    // MARK: - Source slicing
    //
    // The two `CardChromeModifier` branches are named helpers, so a branch's
    // body can be sliced by name. Code-level inspection is the only layer
    // that can prove the ABSENCE of a chrome modifier — SwiftUI's view graph
    // is opaque (same rationale as the §Container Chrome guards).

    private static func bareBranchSource() throws -> String {
        try slice(designTokens(), from: "private func bare(", to: "private func framed(")
    }

    private static func framedBranchSource() throws -> String {
        try slice(designTokens(), from: "private func framed(", to: "\n}")
    }

    private static func cardChromeModifierSource() throws -> String {
        try slice(designTokens(), from: "public struct CardChromeModifier", to: "\nextension View {")
    }

    private static func designTokens() throws -> String {
        try DesignTokensComplianceTests.designTokensSource()
    }

    private static func slice(_ source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw SliceError.markerNotFound(start)
        }
        let tail = source[startRange.upperBound...]
        guard let endRange = tail.range(of: end) else {
            throw SliceError.markerNotFound(end)
        }
        return String(tail[..<endRange.lowerBound])
    }

    private enum SliceError: Error {
        case markerNotFound(String)
    }
}
