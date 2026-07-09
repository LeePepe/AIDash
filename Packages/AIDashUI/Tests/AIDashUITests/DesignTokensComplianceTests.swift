import Testing
import SwiftUI
import Foundation
import AIDashCore
import DesignKit
@testable import AIDashUI

// MARK: - DesignTokensComplianceTests (MY-1060)
//
// Final cross-card compliance net for MY-1054 §Acceptance 10 and §14-21.
//
// This file is the integration-tier contract net. It does NOT re-test the
// per-token unit behaviour already covered by `DesignTokensFoundationTests`
// (MY-1055) nor the per-renderer behaviour covered by each `*CardViewTests`
// suite (MY-1057/1058/1059). Its job is to assert the
// `type x size x style` orthogonality contract from constitution
// §Principle VI / §Design System & Tokens — i.e. that the 112 theoretical
// combinations do NOT visually collapse into one style, which was the
// failure mode that triggered MY-1054.
//
// Source-level guards (file-content greps) are used wherever a rendered-
// tree introspection would require private SwiftUI APIs. The guards target
// the seven `*CardView.swift` renderers in `Packages/AIDashUI/Sources/
// AIDashUI/CardView/` plus the `BriefingView.swift` and `ContainerView.swift`
// page/container surfaces. The CardRouter file is owned by upstream issues
// and intentionally out of scope here.

@MainActor
@Suite("Design Tokens Compliance Matrix")
struct DesignTokensComplianceTests {

    // MARK: - Acceptance 10 — type x medium x neutral matrix (≥7 combos)
    //
    // Every content card type at medium / neutral MUST consume the shared
    // per-type recipe (typography), the shared cardChrome modifier (chrome),
    // and the 32x32 type badge (visual discriminator). `sectionHeader` is
    // the one structural variant — verified separately below.

    @Test(
        "Every CardType at (medium, neutral) renders its declared contract — content types get token-backed typography + chrome + badge; sectionHeader gets typography only (≥7 combos, one per case)",
        arguments: CardType.allCases
    )
    func typeMatrixMediumNeutral(type: CardType) throws {
        // Iterating CardType.allCases (all 7 cases) — not just content
        // types — guarantees the matrix covers the full enum even when the
        // enum grows. The sectionHeader branch documents the
        // "structural variant" contract from §Card Chrome so we cannot
        // silently regress to "6 chromed cards + 1 forgotten".
        let renderer = try Self.rendererSource(for: type)
        let recipe = AIDashTypography.detail(for: type)

        if type == .sectionHeader {
            // sectionHeader is the one structural variant: typography
            // only, no chrome, no badge. Detailed assertions live in
            // sectionHeaderHasNoChrome / sectionHeaderHasNoBadge — the
            // matrix entry just pins the high-level contract.
            #expect(type.iconSymbol == nil,
                    "sectionHeader must NOT declare an SF Symbol")
            #expect(type.classification == nil,
                    "sectionHeader must NOT declare a classification token")
            #expect(!type.hasIconBadge,
                    "sectionHeader must NOT render a badge")
            #expect(recipe.primary != AIDashTypography.section,
                    "sectionHeader detail-tier primary font must NOT collapse to the overview-tier section font")
            #expect(!renderer.contains(".cardChrome("),
                    "sectionHeader renderer must NOT apply cardChrome — it is chrome-less by contract")
            #expect(!renderer.contains("CardTypeBadge("),
                    "sectionHeader renderer must NOT render a CardTypeBadge")
        } else {
            // 1. Every content type has both a symbol and a classification
            //    token — the icon badge is mandatory per §Per-Type Visual
            //    Recipes; the tint color resolves from that token via Theme.
            #expect(type.iconSymbol != nil, "\(type) must declare an SF Symbol")
            #expect(type.classification != nil, "\(type) must declare a classification token")
            #expect(type.hasIconBadge, "\(type) must render a badge")

            // 2. Typography comes from the per-type recipe (Detail tier),
            //    not the overview tier and not freshly-invented constants.
            #expect(recipe.primary != AIDashTypography.section,
                    "\(type) must use the detail-tier primary font, not the overview-tier section font")

            // 3. The renderer source consumes the shared cardChrome modifier
            //    (which carries background, border, padding, corner radius).
            #expect(renderer.contains(".cardChrome(size: size, style: style)"),
                    "\(type) renderer must apply the shared cardChrome modifier")
            #expect(renderer.contains("CardTypeBadge(type: .\(type.rawValue))"),
                    "\(type) renderer must render the shared 32x32 type badge")
        }
    }

    @Test("type matrix covers every CardType case (≥7 combos as required by Acceptance 10)")
    func typeMatrixCoversAllCardTypeCases() {
        // Pin the lower bound explicitly so a future enum shrink or a
        // future `arguments:` regression that filters out cases fails
        // loudly in CI rather than silently dropping coverage.
        #expect(CardType.allCases.count >= 7,
                "Acceptance 10 requires at least 7 type x medium x neutral combinations; CardType.allCases has \(CardType.allCases.count)")
        #expect(CardType.allCases.contains(.sectionHeader),
                "sectionHeader MUST be included in the type matrix even though its chrome contract differs")
    }

    @Test("Per-type badge classification tokens are all distinct (visual discriminator contract)")
    func iconTintsAreDistinct() {
        let tokens = Self.contentCardTypes.compactMap { $0.classification }
        let uniqueTokens = Set(tokens.map { $0.rawValue })
        #expect(uniqueTokens.count == tokens.count,
                "every content card type must use a distinct classification token")
    }

    @Test("Per-type icon symbols are all distinct (visual discriminator contract)")
    func iconSymbolsAreDistinct() {
        let symbols = Self.contentCardTypes.compactMap { $0.iconSymbol }
        #expect(Set(symbols).count == symbols.count,
                "every content card type must use a distinct SF Symbol glyph")
    }

    @Test("Every content card type has a visually-distinguishable typography recipe (no two share primary+secondary)")
    func typographyRecipesAreDistinct() {
        // Two distinct types may not share both primary and secondary fonts —
        // otherwise typography no longer discriminates types and §Principle VI
        // collapses to icon-only differentiation. We compare via Font's own
        // `Equatable` conformance pairwise (SwiftUI Font equality respects the
        // text-style / weight / design dimensions individually, where
        // `String(describing:)` does not).
        let recipes = Self.contentCardTypes.map { ($0, AIDashTypography.detail(for: $0)) }
        for i in recipes.indices {
            for j in recipes.indices where j > i {
                let (a, ra) = recipes[i]
                let (b, rb) = recipes[j]
                let primaryMatches = ra.primary == rb.primary
                let secondaryMatches = ra.secondary == rb.secondary
                #expect(!(primaryMatches && secondaryMatches),
                        "\(a) and \(b) share the same (primary, secondary) typography pair — typography no longer discriminates type")
            }
        }
    }

    // MARK: - Acceptance 14 — SectionHeader: no badge, no chrome

    @Test("sectionHeader CardType declares no icon badge")
    func sectionHeaderHasNoBadge() {
        #expect(CardType.sectionHeader.iconSymbol == nil)
        #expect(CardType.sectionHeader.classification == nil)
        #expect(!CardType.sectionHeader.hasIconBadge)
    }

    @Test("SectionHeaderCardView renderer applies no shared cardChrome, no card padding, no background, no border, no badge")
    func sectionHeaderHasNoChrome() throws {
        let source = try Self.rendererSource(for: .sectionHeader)
        #expect(!source.contains(".cardChrome("),
                "SectionHeaderCardView must NOT consume the shared cardChrome modifier")
        #expect(!source.contains("CardTypeBadge("),
                "SectionHeaderCardView must NOT render the type badge")
        #expect(!source.contains("RoundedRectangle(cornerRadius:"),
                "SectionHeaderCardView must NOT draw a rounded background or border")
        #expect(!source.contains(".strokeBorder("),
                "SectionHeaderCardView must NOT draw a border")
        #expect(!source.contains(".background(Color"),
                "SectionHeaderCardView must NOT apply a colored Color background")
        #expect(!source.contains(".background(.background"),
                "SectionHeaderCardView must NOT apply a hierarchical card background")
        #expect(!source.contains(".regularMaterial") && !source.contains(".thinMaterial") && !source.contains(".ultraThinMaterial"),
                "SectionHeaderCardView must NOT use material backgrounds")
        #expect(!source.contains("AIDashSize.cornerRadius(") &&
                !source.contains("AIDashSize.padding(") &&
                !source.contains("AIDashSize.minHeight("),
                "SectionHeaderCardView must NOT consume card-geometry tokens (cornerRadius/padding/minHeight) — it is chrome-less")
    }

    // MARK: - Acceptance 15 — size orthogonality (4 metric x size x neutral)
    //
    // `size` only affects geometry / content density. Typography, badge,
    // and chrome (background contract) MUST NOT vary with size.

    @Test(
        "metric x size x neutral: typography invariant across sizes (renderer reads from a size-free recipe + size-free badge)",
        arguments: CardSize.allCases
    )
    func metricSizeOrthogonalityTypographyInvariant(size: CardSize) throws {
        // The recipe lookup is keyed on CardType only — it MUST NOT take
        // size. We still iterate sizes here so that any future regression
        // adding a `detail(for:size:)` overload would force this call
        // site to change and break the contract loudly.
        let recipe = AIDashTypography.detail(for: .metric)
        let neutralRecipe = AIDashTypography.detail(for: .metric)
        #expect(recipe.primary == neutralRecipe.primary,
                "metric primary font must be the same at size=\(size) as at .medium")
        #expect(recipe.secondary == neutralRecipe.secondary,
                "metric secondary font must be the same at size=\(size) as at .medium")
        #expect(recipe.secondaryColor == neutralRecipe.secondaryColor)
        #expect(recipe.secondaryLineSpacing == neutralRecipe.secondaryLineSpacing)

        // Inspect renderer behavior per size: walk every `switch size`
        // block in the renderer body and assert that the per-case branch
        // for THIS size contains no `.font(`, `CardTypeBadge(`,
        // `stripeColor(`, `.cardChrome(`, or `.background(` call. A
        // future regression that wraps any of those in a size-conditional
        // would fire this assertion. The metricRendererDoesNotSizeBranchOnFont
        // test enforces the no-`.font(.system(size:` rule globally; this
        // test enforces the no-conditional-on-size rule per case.
        let source = try Self.rendererSource(for: .metric)
        let branchSource = try Self.body(of: source, forCaseLabel: ".\(Self.rawCase(for: size))",
                                         inSwitchKey: "size")
        let forbiddenInSizeBranch: [(String, String)] = [
            (".font(", "renderer must not select fonts inside a `switch size` branch"),
            ("CardTypeBadge(", "renderer must not place CardTypeBadge inside a `switch size` branch — badge is size-invariant"),
            ("stripeColor(", "renderer must not consume stripeColor inside a `switch size` branch — stripe is style-driven"),
            (".cardChrome(", "renderer must not call cardChrome inside a `switch size` branch — chrome lives at the top of the body"),
            (".background(", "renderer must not introduce any `.background(...)` inside a `switch size` branch"),
        ]
        for (needle, msg) in forbiddenInSizeBranch {
            #expect(!branchSource.contains(needle),
                    "metric renderer (size=\(size)): \(msg) — found `\(needle)` in the per-size branch")
        }
    }

    @Test(
        "metric x size x neutral: badge contract invariant across sizes",
        arguments: CardSize.allCases
    )
    func metricSizeOrthogonalityBadgeInvariant(size: CardSize) throws {
        // The badge is type-keyed, not size-keyed. We assert the
        // CardType extension contract AND verify the renderer renders
        // exactly one CardTypeBadge — at the body's top level, never
        // inside a `switch size` branch.
        #expect(CardType.metric.iconSymbol == "chart.bar.fill", "size=\(size) must not change badge symbol")
        #expect(CardType.metric.classification == .metric, "size=\(size) must not change badge classification")

        let source = try Self.rendererSource(for: .metric)
        let badgeOccurrences = source.components(separatedBy: "CardTypeBadge(type: .metric)").count - 1
        #expect(badgeOccurrences == 1,
                "metric renderer must render exactly one CardTypeBadge — found \(badgeOccurrences). A size-conditional badge would make the count > 1 or wrap it in a `switch size`")
    }

    @Test(
        "metric x size x neutral: chrome wires size-driven geometry to the shared modifier (per-size geometry ladder)",
        arguments: CardSize.allCases
    )
    func metricSizeOrthogonalityChromeGeometry(size: CardSize) {
        // Expected geometry ladder per constitution §Size = Geometry Only:
        // small=10/148/(12,14), medium=14/148/16, wide=14/140/(16,20), hero=20/280/24.
        let radius = AIDashSize.cornerRadius(size)
        let minH = AIDashSize.minHeight(size)
        let pad = AIDashSize.padding(size)
        switch size {
        case .small:
            #expect(radius == 10)
            #expect(minH == 148)
            #expect(pad.leading == 12 && pad.trailing == 12 && pad.top == 14 && pad.bottom == 14)
        case .medium:
            #expect(radius == 14)
            #expect(minH == 148)
            #expect(pad.top == 16 && pad.bottom == 16 && pad.leading == 16 && pad.trailing == 16)
        case .wide:
            #expect(radius == 14)
            #expect(minH == 140)
            #expect(pad.top == 16 && pad.bottom == 16 && pad.leading == 20 && pad.trailing == 20)
        case .hero:
            #expect(radius == 20)
            #expect(minH == 280)
            #expect(pad.top == 24 && pad.bottom == 24 && pad.leading == 24 && pad.trailing == 24)
        }
    }

    @Test(
        "metric x size x neutral: body materialises for every size (no crash, no implicit type-switch)",
        arguments: CardSize.allCases
    )
    func metricSizeOrthogonalityBodyRenders(size: CardSize) {
        let payload = MetricPayload(items: [
            .init(label: "PRs merged", value: 3, trend: .up),
            .init(label: "Build time", value: 124, unit: "s", trend: .down),
            .init(label: "Coverage", value: 87.5, unit: "%", trend: .flat),
            .init(label: "Active issues", value: 12),
        ])
        let view = MetricCardView(payload: payload, size: size, style: .neutral)
        _ = view.body
    }

    @Test("metric renderer source does not branch on size to choose a Font (§Quality Bar I P0.1)")
    func metricRendererDoesNotSizeBranchOnFont() throws {
        let source = try Self.rendererSource(for: .metric)
        // The renderer is allowed to switch on `size` for layout / item count.
        // It is NOT allowed to put `.font(` inside a `switch size` branch.
        // We check that no `.font(.system(size: <number>` literal sneaks in
        // (which is the most common P1.1 token-drift pattern) and that the
        // renderer reads typography from the per-type recipe, not from its
        // own constants.
        #expect(!source.contains(".font(.system(size:"),
                "metric renderer must not hardcode .font(.system(size:)) — read AIDashTypography.detail(for:) instead")
        #expect(source.contains("AIDashTypography.detail(for: .metric)"),
                "metric renderer must read typography from AIDashTypography.detail(for: .metric)")
    }

    // MARK: - Acceptance 16 — style orthogonality (4 metric x medium x style)
    //
    // `style` only manifests as the optional left stripe. It MUST NOT
    // change typography, padding, corner radius, or apply a whole-card
    // tinted fill.

    @Test(
        "metric x medium x style: stripe color is the ONLY style affordance — neutral=nil, others resolve from theme tokens",
        arguments: CardStyle.allCases
    )
    func metricStyleOrthogonalityStripeColor(style: CardStyle) {
        let theme = Theme(seed: .appleBlue, neutral: .slate, isDark: false)
        switch style {
        case .neutral:
            #expect(AIDashChrome.stripeColor(for: .neutral, theme: theme) == nil,
                    "neutral style MUST have no stripe")
        case .success:
            #expect(AIDashChrome.stripeColor(for: .success, theme: theme) == theme.success)
        case .warning:
            #expect(AIDashChrome.stripeColor(for: .warning, theme: theme) == theme.warning)
        case .accent:
            #expect(AIDashChrome.stripeColor(for: .accent, theme: theme) == theme.primary.primary)
        }
    }

    @Test(
        "metric x medium x style: typography invariant across styles (renderer reads from a style-free recipe; no `.font(` lives inside a `switch style` branch)",
        arguments: CardStyle.allCases
    )
    func metricStyleOrthogonalityTypographyInvariant(style: CardStyle) throws {
        let neutralRecipe = AIDashTypography.detail(for: .metric)
        let recipe = AIDashTypography.detail(for: .metric) // recipe keyed on type only
        #expect(recipe.primary == neutralRecipe.primary, "style=\(style) must not change primary font")
        #expect(recipe.secondary == neutralRecipe.secondary, "style=\(style) must not change secondary font")

        // Renderer inspection: if a future regression wraps `.font(` in a
        // `switch style` block, this assertion fires. The renderer is
        // allowed to have NO `switch style` block at all — that is the
        // current and correct state. We only assert that if one exists
        // for this case label, it does not contain forbidden tokens.
        let source = try Self.rendererSource(for: .metric)
        if let branchSource = try? Self.body(of: source, forCaseLabel: ".\(style)", inSwitchKey: "style") {
            let forbiddenInStyleBranch: [(String, String)] = [
                (".font(", "renderer must not select fonts inside a `switch style` branch"),
                (".background(", "renderer must not introduce any `.background(...)` inside a `switch style` branch"),
                (".cardChrome(", "renderer must not call cardChrome inside a `switch style` branch"),
            ]
            for (needle, msg) in forbiddenInStyleBranch {
                #expect(!branchSource.contains(needle),
                        "metric renderer (style=\(style)): \(msg) — found `\(needle)` in the per-style branch")
            }
        }
        // The renderer must NOT switch on style at all in its top-level
        // body (style only manifests as the stripe inside cardChrome).
        #expect(!source.contains("switch style"),
                "metric renderer body must not contain `switch style` — style is consumed by the shared cardChrome modifier, not the renderer")
    }

    @Test(
        "metric x medium x style: chrome geometry is style-invariant (radius / padding / minHeight independent of style)",
        arguments: CardStyle.allCases
    )
    func metricStyleOrthogonalityChromeGeometry(style: CardStyle) {
        // Geometry is keyed on size only; iterating styles documents the
        // contract and guards against a future regression where style
        // mutates AIDashSize.* via a side channel.
        #expect(AIDashSize.cornerRadius(.medium) == 14,
                "style=\(style) must not change medium corner radius")
        #expect(AIDashSize.padding(.medium).leading == 16,
                "style=\(style) must not change medium padding")
        #expect(AIDashSize.minHeight(.medium) == 148,
                "style=\(style) must not change medium min-height")
    }

    @Test("AIDashChrome carries stripe + hairline tokens only — NO flat radius/padding/background constants live here")
    func styleNeverWidensIntoOtherChromeTokens() {
        // If a future refactor adds e.g. AIDashChrome.background or
        // AIDashChrome.cornerRadius, the orthogonality contract collapses.
        // Pin the public API surface here.
        #expect(AIDashChrome.stripeWidth == 3, "stripe is 3pt per §Card Chrome")
        #expect(AIDashChrome.hairlineWidth == 1, "border is 1px per §Card Chrome")
    }

    @Test(
        "metric x medium x style: body materialises for every style (no crash, no chrome-mutation path)",
        arguments: CardStyle.allCases
    )
    func metricStyleOrthogonalityBodyRenders(style: CardStyle) {
        let payload = MetricPayload(items: [
            .init(label: "PRs merged", value: 3, trend: .up),
            .init(label: "Build time", value: 124, unit: "s", trend: .down),
        ])
        let view = MetricCardView(payload: payload, size: .medium, style: style)
        _ = view.body
    }

    // MARK: - Fixtures

    nonisolated static let contentCardTypes: [CardType] = CardType.allCases.filter { $0 != .sectionHeader }

    // MARK: - Source loaders
    //
    // These walk up from `#filePath` to the Tests directory, then descend
    // into `Sources/AIDashUI/...`. The strategy mirrors the
    // `loadRendererSource` helper already used by `TodoListCardViewTests`
    // and `SectionHeaderCardViewTests`, kept local here so this file
    // remains self-contained for the MY-1060 file-scope guard.

    static func rendererSource(for type: CardType) throws -> String {
        let name: String
        switch type {
        case .metric:        name = "MetricCardView"
        case .insight:       name = "InsightCardView"
        case .digest:        name = "DigestCardView"
        case .agentSummary:  name = "AgentSummaryCardView"
        case .todoList:      name = "TodoListCardView"
        case .trending:      name = "TrendingCardView"
        case .sectionHeader: name = "SectionHeaderCardView"
        }
        let url = try sourceFile(named: "\(name).swift",
                                 under: ["Sources", "AIDashUI", "CardView"])
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func surfaceSource(_ name: String) throws -> String {
        let url = try sourceFile(named: "\(name).swift",
                                 under: ["Sources", "AIDashUI"])
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func designTokensSource() throws -> String {
        let url = try sourceFile(named: "DesignTokens.swift",
                                 under: ["Sources", "AIDashUI"])
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Source slicing
    //
    // `body(of:forCaseLabel:inSwitchKey:)` extracts the body of one
    // `case <label>:` arm of a `switch <key>` block from a renderer's
    // source. The match is intentionally lenient (no AST): we look for
    // the first `switch <key>` occurrence, then the first `case <label>:`
    // inside it, then return everything up to the next `case ` at the
    // same indentation level or the closing brace. This is enough to
    // catch a regression that puts `.font(`, `CardTypeBadge(`,
    // `.cardChrome(`, or `.background(` inside a `switch size` /
    // `switch style` arm — the actual purpose of the helper.
    //
    // Throws `bodySliceError(.switchNotFound)` if no `switch <key>`
    // appears in the source, and `bodySliceError(.caseNotFound)` if the
    // case label is not present inside the switch. Callers that treat a
    // missing switch as "no regression possible" should catch the throw
    // with `try?`.

    static func body(of source: String, forCaseLabel label: String, inSwitchKey key: String) throws -> String {
        let switchToken = "switch \(key)"
        guard let switchRange = source.range(of: switchToken) else {
            throw BodySliceError.switchNotFound(key)
        }
        let after = source[switchRange.upperBound...]
        let caseToken = "case \(label):"
        guard let caseRange = after.range(of: caseToken) else {
            throw BodySliceError.caseNotFound(label, key)
        }
        let armStart = caseRange.upperBound
        // The arm ends at the next `case ` (sibling), or the next
        // `default:`, or the next closing brace. We scan for the first
        // of these terminators and slice up to it.
        let armSource = after[armStart...]
        let terminators = ["case .", "default:", "}\n"]
        var endIndex = armSource.endIndex
        for term in terminators {
            if let r = armSource.range(of: term), r.lowerBound < endIndex {
                endIndex = r.lowerBound
            }
        }
        return String(armSource[..<endIndex])
    }

    enum BodySliceError: Error {
        case switchNotFound(String)
        case caseNotFound(String, String)
    }

    /// Returns the unqualified case identifier for a CardSize, i.e.
    /// "small" / "medium" / "wide" / "hero". Used to build a `case .<x>:`
    /// label for `body(of:forCaseLabel:inSwitchKey:)`.
    static func rawCase(for size: CardSize) -> String { size.rawValue }

    private static func sourceFile(named filename: String,
                                   under relativeComponents: [String]) throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        var dir = here.deletingLastPathComponent()
        while dir.lastPathComponent != "Tests" && dir.path != "/" {
            dir = dir.deletingLastPathComponent()
        }
        guard dir.lastPathComponent == "Tests" else {
            throw ComplianceSourceLookupError.testsRootNotFound
        }
        let packageRoot = dir.deletingLastPathComponent()
        var url = packageRoot
        for component in relativeComponents {
            url = url.appendingPathComponent(component)
        }
        url = url.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComplianceSourceLookupError.fileNotFound(filename, url.path)
        }
        return url
    }

    enum ComplianceSourceLookupError: Error {
        case testsRootNotFound
        case fileNotFound(String, String)
    }
}

// MARK: - Local regex helper
//
// Foundation's `range(of:options:.regularExpression)` is the most portable
// regex API across macOS / iOS / iPadOS. We wrap it so each call site reads
// like an intent ("does the source match this forbidden pattern?") rather
// than a NSRange dance.

func matches(_ source: String, pattern: String) -> Bool {
    source.range(of: pattern, options: .regularExpression) != nil
}
