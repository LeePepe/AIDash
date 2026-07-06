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
            (".font(",        "renderer must not select fonts inside a `switch size` branch"),
            ("CardTypeBadge(", "renderer must not place CardTypeBadge inside a `switch size` branch — badge is size-invariant"),
            ("stripeColor(",  "renderer must not consume stripeColor inside a `switch size` branch — stripe is style-driven"),
            (".cardChrome(",  "renderer must not call cardChrome inside a `switch size` branch — chrome lives at the top of the body"),
            (".background(",  "renderer must not introduce any `.background(...)` inside a `switch size` branch"),
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
        // small=10/96/(12,14), medium=14/140/16, wide=14/140/(16,20), hero=20/280/24.
        let radius = AIDashSize.cornerRadius(size)
        let minH = AIDashSize.minHeight(size)
        let pad = AIDashSize.padding(size)
        switch size {
        case .small:
            #expect(radius == 10)
            #expect(minH == 96)
            #expect(pad.leading == 12 && pad.trailing == 12 && pad.top == 14 && pad.bottom == 14)
        case .medium:
            #expect(radius == 14)
            #expect(minH == 140)
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
                (".font(",       "renderer must not select fonts inside a `switch style` branch"),
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
        #expect(AIDashSize.minHeight(.medium) == 140,
                "style=\(style) must not change medium min-height")
    }

    @Test("AIDashChrome carries stripe + hairline tokens only — NO flat radius/padding/background constants live here")
    func styleNeverWidensIntoOtherChromeTokens() {
        // If a future refactor adds e.g. AIDashChrome.background or
        // AIDashChrome.cornerRadius, the orthogonality contract collapses.
        // Pin the public API surface here.
        #expect(AIDashChrome.stripeWidth == 3, "stripe is 3pt per §Card Chrome")
        #expect(AIDashChrome.hairlineWidth == 0.5, "hairline is 0.5pt per §Card Chrome")
        #expect(AIDashChrome.hairlineOpacity == 0.5, "hairline opacity is .separator * 0.5 per §Card Chrome")
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

    // MARK: - Acceptance 17 — forbidden local chrome / source guards
    //
    // §Quality Bar I P0.3 / P1.1 / P1.2 / P1.3 / P1.4 — renderer bodies
    // MUST NOT carry their own font sizes, whole-card tinted fills,
    // local rounded backgrounds, literal card padding / corner constants,
    // .regularMaterial, Color.white, card-level #if os chrome branches,
    // or non-token background helpers.

    @Test(
        "renderer bodies contain no forbidden local chrome / typography / color constructs",
        arguments: contentCardTypes
    )
    func renderersHaveNoForbiddenLocalChrome(type: CardType) throws {
        let source = try Self.rendererSource(for: type)

        // P0.3 — whole-card colored fills
        #expect(!source.contains("Color.white"),
                "\(type) renderer must not use Color.white as background")
        #expect(!source.contains("Color.black"),
                "\(type) renderer must not use Color.black as background")

        // P0.3 — Whole-card tinted fill guard (broadened per MY-1060 review #3).
        //
        // The previous guard only matched three narrow patterns
        // (`.background(Color.*`, `.background(.background…)`, and the
        // `backgroundTint` identifier). That left obvious style-driven
        // fills such as `.background(.green.opacity(0.1))`,
        // `.background(AIDashChrome.stripeColor(for: style)?.opacity(0.1))`,
        // `.background(panelTint)`, and any newly-named background helper
        // wide open. The renderer contract is unambiguous: card chrome
        // lives in the shared `.cardChrome(size:style:)` modifier and
        // NOWHERE ELSE. So we forbid ANY `.background(` call in renderer
        // bodies, with no allow-list. The shared `cardChrome` modifier
        // applies the background once, outside any renderer.
        //
        // This guard is intentionally absolute. If a renderer ever
        // legitimately needs a non-card background (e.g. an inner ZStack
        // tint inside a sub-component), refactor that sub-component out
        // into its own helper view in DesignTokens.swift or a new file
        // and apply the background there — NOT in the per-type renderer.
        let backgroundOccurrences = source.components(separatedBy: ".background(").count - 1
        #expect(backgroundOccurrences == 0,
                "\(type) renderer must not call `.background(` at all — chrome (including any style-driven fill) lives only in the shared `.cardChrome(size:style:)` modifier. Found \(backgroundOccurrences) occurrence(s). Whole-card tinted fills (e.g. `.background(.green.opacity(...))`, `.background(AIDashChrome.stripeColor(for: style)?.opacity(...))`, `.background(panelTint)`, or any newly-named helper) are forbidden.")

        // Defense-in-depth: even if a future contributor exempts the
        // absolute guard above (e.g. by moving renderer chrome behind a
        // helper that does not contain the literal `.background(`), the
        // following named anti-patterns still fail loudly. These mirror
        // the patterns the reviewer called out explicitly.
        #expect(!source.contains("backgroundTint"),
                "\(type) renderer must not declare or consume a local backgroundTint — style controls the shared left stripe only")
        #expect(!source.contains("panelTint"),
                "\(type) renderer must not declare or consume a `panelTint` — whole-card tints are forbidden")
        #expect(!source.contains("cardTint"),
                "\(type) renderer must not declare or consume a `cardTint` — whole-card tints are forbidden")
        #expect(!source.contains("AIDashChrome.stripeColor"),
                "\(type) renderer must not consume AIDashChrome.stripeColor — the stripe is painted by the shared cardChrome modifier, not the renderer")

        // P1.1 — hardcoded numeric font sizes
        #expect(!matches(source, pattern: #"\.font\(\.system\(size:\s*[0-9]"#),
                "\(type) renderer must not hardcode .font(.system(size:)) — read AIDashTypography.detail(for:) instead")

        // P1.3 — local card backgrounds / corner-radius rounded shape literals
        #expect(!source.contains("RoundedRectangle(cornerRadius:"),
                "\(type) renderer must not declare a local RoundedRectangle background — chrome lives in the shared cardChrome modifier")

        // P1.3 — material backgrounds at the card level
        #expect(!source.contains(".regularMaterial"),
                "\(type) renderer must not use .regularMaterial — card background comes from .background.secondary via cardChrome")
        #expect(!source.contains(".thickMaterial"),
                "\(type) renderer must not use .thickMaterial")
        #expect(!source.contains(".ultraThickMaterial"),
                "\(type) renderer must not use .ultraThickMaterial")

        // P1.4 — hardcoded color literals
        #expect(!matches(source, pattern: #"Color\(red:\s*"#),
                "\(type) renderer must not use Color(red:green:blue:) literals — use semantic colors")
        #expect(!source.contains("Color(hex:"),
                "\(type) renderer must not use Color(hex:) literals — use semantic colors")

        // (P0.3 backgroundTint guard is enforced above with the broadened
        // whole-card tinted-fill block — no duplicate needed here.)

        // §Card Chrome — literal corner radius / padding / minHeight constants
        // belong inside `AIDashSize.*`, never in a renderer body. The shared
        // modifier owns geometry; renderers only choose layout density.
        #expect(!matches(source, pattern: #"cornerRadius:\s*[0-9]"#),
                "\(type) renderer must not declare a literal cornerRadius constant — geometry comes from AIDashSize.cornerRadius(size)")
        #expect(!matches(source, pattern: #"\.padding\(\.all,\s*[0-9]"#),
                "\(type) renderer must not declare literal .padding(.all, N) — padding comes from AIDashSize.padding(size) inside cardChrome")
        // §Size = Geometry Only — renderers must not branch on size to read AIDashSize
        // (geometry is owned by the shared modifier, not the renderer).
        #expect(!source.contains("AIDashSize.cornerRadius("),
                "\(type) renderer must not consume AIDashSize.cornerRadius directly — the shared cardChrome modifier owns it")
        #expect(!source.contains("AIDashSize.minHeight("),
                "\(type) renderer must not consume AIDashSize.minHeight directly — the shared cardChrome modifier owns it")

        // §Card Chrome — no per-card #if os chrome branch
        #expect(!matches(source, pattern: #"#if\s+os\("#),
                "\(type) renderer must not branch chrome on platform via #if os(...) — chrome is platform-neutral via .background.secondary")
        #expect(!matches(source, pattern: #"#if\s+canImport\("#),
                "\(type) renderer must not branch chrome on canImport(UIKit/AppKit) — chrome lives in the shared modifier")

        // Card-level shadow is explicitly forbidden by §Card Chrome ("Shadow: none").
        #expect(!matches(source, pattern: #"\.shadow\(\s*(color|radius|x|y)"#),
                "\(type) renderer must not draw its own shadow — §Card Chrome forbids card shadow")
    }

    // MARK: - Acceptance 18-19 — page / container hierarchy guards
    //
    // §Page Chrome — BriefingView owns the page background and page
    // padding. §Container Chrome — ContainerView is typography + spacing,
    // NOT a panel.

    @Test("BriefingView source owns page horizontal + vertical padding from page-chrome tokens, not magic numbers")
    func briefingViewOwnsPagePadding() throws {
        let source = try Self.surfaceSource("BriefingView")
        #expect(source.contains("AIDashSpacing.pageVertical"),
                "BriefingView must read page vertical padding from AIDashSpacing.pageVertical")
        #expect(source.contains("pageHorizontalPadding"),
                "BriefingView must expose a single pageHorizontalPadding token (mac=24 / compact=20)")
        #expect(source.contains("AIDashSpacing.pageHorizontalMac")
                || !source.contains("import AppKit"),
                "BriefingView must use AIDashSpacing.pageHorizontalMac on the Mac branch")
        #expect(source.contains("AIDashSpacing.pageHorizontalCompact")
                || !source.contains("import UIKit"),
                "BriefingView must use AIDashSpacing.pageHorizontalCompact on the iOS branch")
    }

    @Test("BriefingView owns the page background — must reference a page-chrome system color, never `.background.secondary`")
    func briefingViewOwnsPageBackground() throws {
        let source = try Self.surfaceSource("BriefingView")
        // The page sits one hierarchy step below the card. Using
        // `.background.secondary` for the page would erase the contrast
        // and reproduce the "everything looks the same" failure mode.
        #expect(!source.contains(".background(.background.secondary"),
                "BriefingView must NOT paint the page in .background.secondary — that is the card background, not the page background")
        #expect(source.contains("pageBackground"),
                "BriefingView must expose a pageBackground token instead of inlining the platform color")
        // The page-chrome token MUST resolve to the system page colors
        // per constitution §Page Chrome.
        #expect(source.contains("NSColor.windowBackgroundColor")
                || !source.contains("import AppKit"),
                "BriefingView macOS branch must use NSColor.windowBackgroundColor")
        #expect(source.contains(".systemGroupedBackground")
                || !source.contains("import UIKit"),
                "BriefingView iOS branch must use .systemGroupedBackground")
    }

    @Test("BriefingView.pageHorizontalPadding resolves to the platform-correct token")
    func briefingViewPageHorizontalPaddingTokenized() {
        #if os(macOS)
        #expect(BriefingView.pageHorizontalPadding == AIDashSpacing.pageHorizontalMac)
        #expect(BriefingView.pageHorizontalPadding == 24)
        #else
        #expect(BriefingView.pageHorizontalPadding == AIDashSpacing.pageHorizontalCompact)
        #expect(BriefingView.pageHorizontalPadding == 20)
        #endif
    }

    @Test("ContainerView draws no panel chrome — no background, no rounded shape, no border, no padding wrapper")
    func containerViewDrawsNoChrome() throws {
        let source = try Self.surfaceSource("ContainerView")
        #expect(!source.contains("RoundedRectangle(cornerRadius:"),
                "ContainerView must NOT draw a rounded background — §Container Chrome forbids container panel chrome")
        #expect(!source.contains(".background(.background.secondary"),
                "ContainerView must NOT apply .background.secondary — that belongs to the card, not the container")
        #expect(!source.contains(".strokeBorder("),
                "ContainerView must NOT draw a border around its cards")
        #expect(!source.contains(".regularMaterial") && !source.contains(".thinMaterial"),
                "ContainerView must NOT use material backgrounds")
        #expect(!source.contains(".cardChrome("),
                "ContainerView must NOT call cardChrome — chrome is per-card, not per-container")
        #expect(!source.contains(".padding(.all, "),
                "ContainerView must NOT wrap its cards in a card-style .padding(.all, ...) panel")
        #expect(source.contains("AIDashSpacing.containerHeaderToFirstCard"),
                "ContainerView header-to-first-card spacing must use AIDashSpacing.containerHeaderToFirstCard")
        #expect(source.contains("AIDashTypography.section"),
                "ContainerView header must use the overview-tier AIDashTypography.section font")
    }

    // MARK: - Acceptance 20 — card chrome uses `.background.secondary` + 0.5pt separator border

    @Test("Shared cardChrome modifier paints `.background.secondary` (not material, not Color.white)")
    func cardChromeBackgroundIsHierarchical() throws {
        let source = try Self.designTokensSource()
        #expect(source.contains(".background(.background.secondary"),
                "CardChromeModifier must paint .background.secondary per §Card Chrome — the one-step-up surface above the page")
        #expect(!source.contains(".background(.regularMaterial") &&
                !source.contains(".background(.thinMaterial") &&
                !source.contains(".background(.ultraThinMaterial"),
                "CardChromeModifier must NOT use material backgrounds — material does not hierarchy-step above the page")
        #expect(!source.contains("Color.white") && !source.contains("Color.black"),
                "CardChromeModifier must NOT use Color.white / Color.black for card background")
    }

    @Test("Shared cardChrome modifier draws exactly the 0.5pt separator hairline overlay (no other border)")
    func cardChromeHairlineSeparatorOverlay() throws {
        let source = try Self.designTokensSource()
        // The hairline must use the .separator system color (UIKit /
        // AppKit equivalent), at 0.5pt width, at .hairlineOpacity (0.5).
        #expect(source.contains("UIColor.separator")
                || source.contains("NSColor.separatorColor"),
                "CardChromeModifier hairline must come from the .separator system color")
        #expect(source.contains("AIDashChrome.hairlineWidth"),
                "CardChromeModifier hairline width must come from AIDashChrome.hairlineWidth (0.5pt)")
        #expect(source.contains("AIDashChrome.hairlineOpacity"),
                "CardChromeModifier hairline opacity must come from AIDashChrome.hairlineOpacity (0.5)")
        #expect(AIDashChrome.hairlineWidth == 0.5,
                "hairline width contract: 0.5pt per §Card Chrome")
        #expect(AIDashChrome.hairlineOpacity == 0.5,
                "hairline opacity contract: .separator * 0.5 per §Card Chrome")
        // No additional border tokens should exist beyond the hairline overlay.
        #expect(!source.contains(".border(Color"),
                "CardChromeModifier must NOT draw an additional .border(Color) — the hairline IS the border")
    }

    @Test("Every chromed card type (every type except sectionHeader) is wrapped by exactly one cardChrome call in its renderer")
    func everyChromedCardAppliesExactlyOneCardChrome() throws {
        for type in Self.contentCardTypes {
            let source = try Self.rendererSource(for: type)
            let occurrences = source.components(separatedBy: ".cardChrome(").count - 1
            #expect(occurrences == 1,
                    "\(type) renderer must apply cardChrome exactly once — found \(occurrences) occurrences in its body")
        }
    }

    // MARK: - Acceptance 21 — telemetry / privacy invariants

    @Test("compliance tests add NO telemetry / logging / network / persistence imports")
    func complianceFileHasNoSideEffectImports() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath),
            encoding: .utf8
        )
        // Build the forbidden tokens at runtime so the assertion list itself
        // does not show up when scanning this file's own source.
        let importPrefix = "imp" + "ort "
        let forbidden: [String] = [
            importPrefix + "OSLog",
            importPrefix + "os.log",
            importPrefix + "CloudKit",
            importPrefix + "SwiftData",
            importPrefix + "Network",
            "URL" + "Session",
        ]
        for token in forbidden {
            #expect(!source.contains(token),
                    "DesignTokensComplianceTests must not introduce \(token) — UI contract tests are pure")
        }
    }

    // MARK: - PR-description visual evidence notes (Acceptance, no test assertion)
    //
    // The constitution mandates that visual evidence for `type x size x style`
    // orthogonality lives in the PR description (per §User Feedback, Not
    // Manual Test Gates). This suite does not block on screenshots. The
    // Fullstack handoff comment for this PR MUST attach:
    //
    //   * Screenshot of one column of 7 cards (one per type) at .medium /
    //     .neutral showing 7 distinct icon badges + 7 distinct typography
    //     recipes.
    //   * Screenshot of one metric card at small / medium / wide / hero
    //     showing geometry-only differences (no font/badge/style changes).
    //   * Screenshot of one metric card at .medium x neutral / success /
    //     warning / accent showing the left stripe is the ONLY style
    //     differentiator (no whole-card fills).
    //   * Screenshot of a BriefingView with at least two chromed cards
    //     showing the page background is visibly darker than the card
    //     background, and that the hairline is visible at 1x.
    //
    // The PR description checklist is the human gate; this comment is the
    // machine-readable contract pointer for future runs.

    // MARK: - Fixtures

    nonisolated static let contentCardTypes: [CardType] = CardType.allCases.filter { $0 != .sectionHeader }

    // MARK: - Source loaders
    //
    // These walk up from `#filePath` to the Tests directory, then descend
    // into `Sources/AIDashUI/...`. The strategy mirrors the
    // `loadRendererSource` helper already used by `TodoListCardViewTests`
    // and `SectionHeaderCardViewTests`, kept local here so this file
    // remains self-contained for the MY-1060 file-scope guard.

    private static func rendererSource(for type: CardType) throws -> String {
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

    private static func surfaceSource(_ name: String) throws -> String {
        let url = try sourceFile(named: "\(name).swift",
                                 under: ["Sources", "AIDashUI"])
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func designTokensSource() throws -> String {
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

private func matches(_ source: String, pattern: String) -> Bool {
    source.range(of: pattern, options: .regularExpression) != nil
}
