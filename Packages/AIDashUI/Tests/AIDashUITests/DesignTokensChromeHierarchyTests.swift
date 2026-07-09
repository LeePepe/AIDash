import Testing
import SwiftUI
import Foundation
import AIDashCore
@testable import AIDashUI

// MARK: - Page / Container / Chrome hierarchy guards (Acceptance 18-21)
//
// Split out of DesignTokensComplianceTests to keep each file within the
// file-length budget. These guards enforce §Page Chrome, §Container Chrome,
// and §Card Chrome from the constitution: the page owns the lowest luminance
// tier and a 1200pt content cap, containers draw no panel chrome, and the
// shared cardChrome modifier paints theme.neutrals.card + a 1px neutrals
// border. Uses the source-loader helpers on `DesignTokensComplianceTests`.

@MainActor
@Suite("Design Tokens — Page/Chrome Hierarchy")
struct DesignTokensChromeHierarchyTests {

    private typealias Compliance = DesignTokensComplianceTests

    // MARK: - Acceptance 18-19 — page / container hierarchy guards

    @Test("BriefingView source owns page horizontal + vertical padding from page-chrome tokens, not magic numbers")
    func briefingViewOwnsPagePadding() throws {
        let source = try Compliance.surfaceSource("BriefingView")
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

    @Test("BriefingView owns the page background — must use the lowest luminance tier theme.neutrals.bg, never the card background")
    func briefingViewOwnsPageBackground() throws {
        let source = try Compliance.surfaceSource("BriefingView")
        // The page sits one luminance tier below the card. Using the card
        // background for the page would erase the contrast and reproduce the
        // "everything looks the same" failure mode.
        #expect(!source.contains(".background(.background.secondary"),
                "BriefingView must NOT paint the page in the card background — that is the card surface, not the page")
        #expect(!source.contains("theme.neutrals.card"),
                "BriefingView must NOT paint the page in theme.neutrals.card — the page is one tier below (theme.neutrals.bg)")
        // The page background MUST be the lowest luminance tier per §Page Chrome.
        #expect(source.contains("theme.neutrals.bg"),
                "BriefingView must paint the page in theme.neutrals.bg per §Page Chrome")
        // Content is capped and centered per §Page Chrome.
        #expect(source.contains("Space.contentMaxWidth"),
                "BriefingView must cap content at Space.contentMaxWidth (1200pt) per §Page Chrome")
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
        let source = try Compliance.surfaceSource("ContainerView")
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

    // MARK: - Acceptance 20 — card chrome uses `theme.neutrals.card` + 1px neutrals border

    @Test("Shared cardChrome modifier paints `theme.neutrals.card` (not material, not Color.white)")
    func cardChromeBackgroundIsHierarchical() throws {
        let source = try Compliance.designTokensSource()
        #expect(source.contains("theme.neutrals.card"),
                "CardChromeModifier must paint theme.neutrals.card per §Card Chrome — the middle luminance tier above the page")
        #expect(!source.contains(".background(.regularMaterial") &&
                !source.contains(".background(.thinMaterial") &&
                !source.contains(".background(.ultraThinMaterial"),
                "CardChromeModifier must NOT use material backgrounds — material does not luminance-step above the page")
        #expect(!source.contains("Color.white") && !source.contains("Color.black"),
                "CardChromeModifier must NOT use Color.white / Color.black for card background")
    }

    @Test("Shared cardChrome modifier draws exactly the 1px neutrals.border overlay (no other border)")
    func cardChromeBorderOverlay() throws {
        let source = try Compliance.designTokensSource()
        // The border must use the DesignKit neutral border token, at 1px width.
        #expect(source.contains("theme.neutrals.border"),
                "CardChromeModifier border must come from the theme.neutrals.border token")
        #expect(source.contains("AIDashChrome.hairlineWidth"),
                "CardChromeModifier border width must come from AIDashChrome.hairlineWidth (1px)")
        #expect(AIDashChrome.hairlineWidth == 1,
                "border width contract: 1px per §Card Chrome")
        // No additional border tokens should exist beyond the overlay.
        #expect(!source.contains(".border(Color"),
                "CardChromeModifier must NOT draw an additional .border(Color) — the hairline IS the border")
    }

    @Test("Every chromed card type (every type except sectionHeader) is wrapped by exactly one cardChrome call in its renderer")
    func everyChromedCardAppliesExactlyOneCardChrome() throws {
        for type in Compliance.contentCardTypes {
            let source = try Compliance.rendererSource(for: type)
            let occurrences = source.components(separatedBy: ".cardChrome(").count - 1
            #expect(occurrences == 1,
                    "\(type) renderer must apply cardChrome exactly once — found \(occurrences) occurrences in its body")
        }
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
        arguments: DesignTokensComplianceTests.contentCardTypes
    )
    func renderersHaveNoForbiddenLocalChrome(type: CardType) throws {
        let source = try Compliance.rendererSource(for: type)

        // P0.3 — whole-card colored fills
        #expect(!source.contains("Color.white"),
                "\(type) renderer must not use Color.white as background")
        #expect(!source.contains("Color.black"),
                "\(type) renderer must not use Color.black as background")

        // P0.3 — Whole-card tinted fill guard. Card chrome lives in the
        // shared `.cardChrome(size:style:)` modifier and NOWHERE ELSE, so
        // any `.background(` call in a renderer body is forbidden (no
        // allow-list). A sub-component needing its own background must be
        // factored out into its own helper view, not inlined in the renderer.
        let backgroundOccurrences = source.components(separatedBy: ".background(").count - 1
        #expect(backgroundOccurrences == 0,
                "\(type) renderer must not call `.background(` at all — chrome (including any style-driven fill) lives only in the shared `.cardChrome(size:style:)` modifier. Found \(backgroundOccurrences) occurrence(s).")

        // Defense-in-depth: named anti-patterns still fail loudly even if a
        // future contributor routes chrome behind a helper without `.background(`.
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
                "\(type) renderer must not use .regularMaterial — card background comes from theme.neutrals.card via cardChrome")
        #expect(!source.contains(".thickMaterial"),
                "\(type) renderer must not use .thickMaterial")
        #expect(!source.contains(".ultraThickMaterial"),
                "\(type) renderer must not use .ultraThickMaterial")

        // P1.4 — hardcoded color literals
        #expect(!matches(source, pattern: #"Color\(red:\s*"#),
                "\(type) renderer must not use Color(red:green:blue:) literals — use semantic colors")
        #expect(!source.contains("Color(hex:"),
                "\(type) renderer must not use Color(hex:) literals — use semantic colors")

        // §Card Chrome — literal corner radius / padding / minHeight constants
        // belong inside `AIDashSize.*`, never in a renderer body.
        #expect(!matches(source, pattern: #"cornerRadius:\s*[0-9]"#),
                "\(type) renderer must not declare a literal cornerRadius constant — geometry comes from AIDashSize.cornerRadius(size)")
        #expect(!matches(source, pattern: #"\.padding\(\.all,\s*[0-9]"#),
                "\(type) renderer must not declare literal .padding(.all, N) — padding comes from AIDashSize.padding(size) inside cardChrome")
        #expect(!source.contains("AIDashSize.cornerRadius("),
                "\(type) renderer must not consume AIDashSize.cornerRadius directly — the shared cardChrome modifier owns it")
        #expect(!source.contains("AIDashSize.minHeight("),
                "\(type) renderer must not consume AIDashSize.minHeight directly — the shared cardChrome modifier owns it")

        // §Card Chrome — no per-card #if os chrome branch
        #expect(!matches(source, pattern: #"#if\s+os\("#),
                "\(type) renderer must not branch chrome on platform via #if os(...) — chrome is platform-neutral via theme.neutrals.card")
        #expect(!matches(source, pattern: #"#if\s+canImport\("#),
                "\(type) renderer must not branch chrome on canImport(UIKit/AppKit) — chrome lives in the shared modifier")

        // Card-level shadow is explicitly forbidden by §Card Chrome ("Shadow: none").
        #expect(!matches(source, pattern: #"\.shadow\(\s*(color|radius|x|y)"#),
                "\(type) renderer must not draw its own shadow — §Card Chrome forbids card shadow")
    }
}
