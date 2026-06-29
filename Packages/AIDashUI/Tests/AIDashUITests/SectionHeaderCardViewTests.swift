import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("SectionHeaderCardView Tests")
struct SectionHeaderCardViewTests {
    @Test("initializes with payload, size, and style")
    func initializesCorrectly() {
        let payload = SectionHeaderPayload(title: "Engineering", subtitle: "Backend, infra")
        let view = SectionHeaderCardView(payload: payload, size: .medium, style: .neutral)

        #expect(view.payload.title == "Engineering")
        #expect(view.payload.subtitle == "Backend, infra")
        #expect(view.size == .medium)
        #expect(view.style == .neutral)
    }

    @Test("accepts nil subtitle")
    func nilSubtitle() {
        let payload = SectionHeaderPayload(title: "Header only")
        let view = SectionHeaderCardView(payload: payload, size: .small, style: .accent)

        #expect(view.payload.subtitle == nil)
        #expect(view.payload.title == "Header only")
    }

    @Test("body materializes for every size+style combination without error")
    func bodyMaterializes() {
        let payload = SectionHeaderPayload(title: "Title", subtitle: "Subtitle")
        for size in CardSize.allCases {
            for style in CardStyle.allCases {
                let view = SectionHeaderCardView(payload: payload, size: size, style: style)
                _ = view.body
            }
        }
    }

    @Test("empty subtitle string is tolerated by initializer")
    func emptySubtitleString() {
        let payload = SectionHeaderPayload(title: "Title", subtitle: "")
        let view = SectionHeaderCardView(payload: payload, size: .hero, style: .warning)
        #expect(view.payload.subtitle == "")
        _ = view.body
    }

    @Test("init signature matches CardRouter expectation")
    func initSignatureMatches() {
        let payload = SectionHeaderPayload(title: "T")
        let _: SectionHeaderCardView = SectionHeaderCardView(
            payload: payload,
            size: .wide,
            style: .success
        )
    }

    // MARK: - Typography contract (MY-1059)
    //
    // contracts/cardtype-payloads.md §sectionHeader:
    //   "all sizes show the same header layout. Size hint affects vertical
    //   spacing only (small = compact, hero = generous)."
    //
    // Typography (title font, subtitle font, secondary color) comes from
    // the shared per-type recipe and MUST NOT depend on size. Only
    // vertical paddings and the subtitle gap may vary, and they must
    // scale monotonically from .small → .hero (small = compact,
    // hero = generous).

    @Test("uses the shared sectionHeader typography recipe")
    func usesSharedTypographyRecipe() {
        let expected = AIDashTypography.detail(for: .sectionHeader)
        #expect(SectionHeaderCardView.recipe.primary == expected.primary)
        #expect(SectionHeaderCardView.recipe.secondary == expected.secondary)
        #expect(SectionHeaderCardView.recipe.secondaryColor == expected.secondaryColor)
    }

    @Test("title font is invariant across sizes (typography contract)")
    func titleFontInvariant() {
        #expect(SectionHeaderCardView.recipe.primary == .title3.weight(.semibold))
    }

    @Test("subtitle font is invariant across sizes (typography contract)")
    func subtitleFontInvariant() {
        #expect(SectionHeaderCardView.recipe.secondary == .subheadline)
    }

    @Test("vertical padding scales monotonically: small ≤ medium ≤ wide ≤ hero")
    func verticalPaddingMonotonic() {
        let payload = SectionHeaderPayload(title: "Title")
        let small  = SectionHeaderCardView(payload: payload, size: .small,  style: .neutral)
        let medium = SectionHeaderCardView(payload: payload, size: .medium, style: .neutral)
        let wide   = SectionHeaderCardView(payload: payload, size: .wide,   style: .neutral)
        let hero   = SectionHeaderCardView(payload: payload, size: .hero,   style: .neutral)

        #expect(small.verticalPadding < medium.verticalPadding)
        #expect(medium.verticalPadding <= wide.verticalPadding)
        #expect(wide.verticalPadding < hero.verticalPadding)
        // Compact for .small, generous for .hero — contract wording.
        #expect(small.verticalPadding < hero.verticalPadding)
    }

    @Test("subtitle spacing scales monotonically: small ≤ medium ≤ wide ≤ hero")
    func subtitleSpacingMonotonic() {
        let payload = SectionHeaderPayload(title: "Title", subtitle: "Sub")
        let small  = SectionHeaderCardView(payload: payload, size: .small,  style: .neutral)
        let medium = SectionHeaderCardView(payload: payload, size: .medium, style: .neutral)
        let wide   = SectionHeaderCardView(payload: payload, size: .wide,   style: .neutral)
        let hero   = SectionHeaderCardView(payload: payload, size: .hero,   style: .neutral)

        #expect(small.subtitleSpacing < medium.subtitleSpacing)
        #expect(medium.subtitleSpacing < wide.subtitleSpacing)
        #expect(wide.subtitleSpacing < hero.subtitleSpacing)
    }

    @Test("vertical padding values do not depend on style")
    func verticalPaddingIndependentOfStyle() {
        let payload = SectionHeaderPayload(title: "Title")
        for size in CardSize.allCases {
            let neutral = SectionHeaderCardView(payload: payload, size: size, style: .neutral).verticalPadding
            for style in CardStyle.allCases {
                let other = SectionHeaderCardView(payload: payload, size: size, style: style).verticalPadding
                #expect(neutral == other)
            }
        }
    }

    // MARK: - No-badge / no-chrome contract (MY-1059)
    //
    // §Card Chrome — sectionHeader is the single allowed structural
    // variant that renders NO badge, NO shared card chrome, NO
    // background, NO border, NO card padding wrapper.

    @Test("sectionHeader CardType declares no icon badge")
    func noIconBadge() {
        #expect(!CardType.sectionHeader.hasIconBadge)
        #expect(CardType.sectionHeader.iconSymbol == nil)
        #expect(CardType.sectionHeader.iconTint == nil)
    }

    @Test("renderer source applies no shared card chrome and no local background")
    func sourceHasNoChrome() throws {
        let source = try loadRendererSource(named: "SectionHeaderCardView")
        #expect(!source.contains(".cardChrome("), "SectionHeaderCardView must NOT use shared cardChrome")
        #expect(!source.contains("CardTypeBadge("), "SectionHeaderCardView must NOT render a type badge")
        #expect(!source.contains("RoundedRectangle(cornerRadius:"), "SectionHeaderCardView must NOT draw a rounded background")
        #expect(!source.contains("backgroundTint"), "SectionHeaderCardView must NOT declare a backgroundTint")
        #expect(!source.contains(".background(Color"), "SectionHeaderCardView must NOT apply a Color background")
        #expect(!source.contains(".background(.background"), "SectionHeaderCardView must NOT apply a hierarchical background")
        #expect(!source.contains(".strokeBorder("), "SectionHeaderCardView must NOT draw a border")
    }
}
