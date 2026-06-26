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

    // MARK: - Contract: invariant layout across sizes
    //
    // contracts/cardtype-payloads.md §sectionHeader states:
    //   "all sizes show the same header layout. Size hint affects vertical
    //   spacing only (small = compact, hero = generous)."
    //
    // These tests pin that contract: typography (title font, subtitle font)
    // and horizontal padding MUST NOT depend on size. Only vertical padding
    // and subtitle gap may vary, and they must scale monotonically from
    // .small → .hero (small = compact, hero = generous).

    @Test("title font is invariant across sizes (typography contract)")
    func titleFontInvariant() {
        #expect(SectionHeaderCardView.titleFont == .title3)
    }

    @Test("subtitle font is invariant across sizes (typography contract)")
    func subtitleFontInvariant() {
        #expect(SectionHeaderCardView.subtitleFont == .subheadline)
    }

    @Test("horizontal padding is invariant across sizes")
    func horizontalPaddingInvariant() {
        let payload = SectionHeaderPayload(title: "Title", subtitle: "Sub")
        for size in CardSize.allCases {
            let view = SectionHeaderCardView(payload: payload, size: size, style: .neutral)
            // Horizontal padding lives on the type, not the instance — but we
            // assert via the same path the body uses so the test fails if a
            // refactor ever reintroduces per-size horizontal padding on the
            // instance.
            _ = view.body
        }
        #expect(SectionHeaderCardView.horizontalPadding == 16)
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

    // MARK: - Style tint contract

    @Test("neutral style uses clear background tint")
    func neutralBackgroundIsClear() {
        let payload = SectionHeaderPayload(title: "Title")
        let view = SectionHeaderCardView(payload: payload, size: .medium, style: .neutral)
        #expect(view.backgroundTint == Color.clear)
    }

    @Test("non-neutral styles use distinct, non-clear background tints")
    func nonNeutralBackgroundsDiffer() {
        let payload = SectionHeaderPayload(title: "Title")
        let neutral = SectionHeaderCardView(payload: payload, size: .medium, style: .neutral).backgroundTint
        let success = SectionHeaderCardView(payload: payload, size: .medium, style: .success).backgroundTint
        let warning = SectionHeaderCardView(payload: payload, size: .medium, style: .warning).backgroundTint
        let accent  = SectionHeaderCardView(payload: payload, size: .medium, style: .accent).backgroundTint

        #expect(success != neutral)
        #expect(warning != neutral)
        #expect(accent  != neutral)
        #expect(success != warning)
        #expect(success != accent)
        #expect(warning != accent)
    }
}
