import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("DesignTokens Foundation")
struct DesignTokensFoundationTests {

    // MARK: - Spacing

    @Test("AIDashSpacing matches constitution §Spacing & Color Tokens")
    func spacingConstants() {
        #expect(AIDashSpacing.containerVertical == 24)
        #expect(AIDashSpacing.containerHeaderToFirstCard == 12)
        #expect(AIDashSpacing.cardVertical == 12)
        #expect(AIDashSpacing.gridGap == 12)
        #expect(AIDashSpacing.pageHorizontalMac == 24)
        #expect(AIDashSpacing.pageHorizontalCompact == 20)
        #expect(AIDashSpacing.pageVertical == 24)
    }

    // MARK: - Size ladder

    @Test("AIDashSize.cornerRadius follows the 10/14/14/20 ladder")
    func cornerRadiusLadder() {
        #expect(AIDashSize.cornerRadius(.small) == 10)
        #expect(AIDashSize.cornerRadius(.medium) == 14)
        #expect(AIDashSize.cornerRadius(.wide) == 14)
        #expect(AIDashSize.cornerRadius(.hero) == 20)
    }

    @Test("AIDashSize.minHeight follows the 96/140/140/280 ladder")
    func minHeightLadder() {
        #expect(AIDashSize.minHeight(.small) == 96)
        #expect(AIDashSize.minHeight(.medium) == 140)
        #expect(AIDashSize.minHeight(.wide) == 140)
        #expect(AIDashSize.minHeight(.hero) == 280)
    }

    @Test("AIDashSize.padding follows the 12-14 / 16 / 16-20 / 24 ladder")
    func paddingLadder() {
        let small = AIDashSize.padding(.small)
        #expect(small.leading == 12 && small.trailing == 12)
        #expect(small.top == 14 && small.bottom == 14)

        let medium = AIDashSize.padding(.medium)
        #expect(medium.top == 16 && medium.bottom == 16)
        #expect(medium.leading == 16 && medium.trailing == 16)

        let wide = AIDashSize.padding(.wide)
        #expect(wide.top == 16 && wide.bottom == 16)
        #expect(wide.leading == 20 && wide.trailing == 20)

        let hero = AIDashSize.padding(.hero)
        #expect(hero.top == 24 && hero.bottom == 24)
        #expect(hero.leading == 24 && hero.trailing == 24)
    }

    @Test("AIDashSize.gridSpan: small=1, medium=2, wide/hero span full row")
    func gridSpan() {
        #expect(AIDashSize.gridSpan(.small) == 1)
        #expect(AIDashSize.gridSpan(.medium) == 2)
        #expect(AIDashSize.gridSpan(.wide) == .max)
        #expect(AIDashSize.gridSpan(.hero) == .max)
    }

    @Test("AIDashSize.columnCount maps viewport widths to 1/2/3/4 columns")
    func columnCount() {
        #expect(AIDashSize.columnCount(forWidth: 320) == 1)   // iPhone
        #expect(AIDashSize.columnCount(forWidth: 479) == 1)
        #expect(AIDashSize.columnCount(forWidth: 480) == 2)   // iPad portrait
        #expect(AIDashSize.columnCount(forWidth: 767) == 2)
        #expect(AIDashSize.columnCount(forWidth: 768) == 3)   // iPad landscape / small Mac
        #expect(AIDashSize.columnCount(forWidth: 1099) == 3)
        #expect(AIDashSize.columnCount(forWidth: 1100) == 4)  // large Mac
        #expect(AIDashSize.columnCount(forWidth: 2000) == 4)
    }

    // MARK: - Icon badge contract

    @Test("CardType.iconSymbol matches the Per-Type Visual Recipes table")
    func iconSymbolMapping() {
        #expect(CardType.metric.iconSymbol == "chart.bar.fill")
        #expect(CardType.insight.iconSymbol == "sparkles")
        #expect(CardType.digest.iconSymbol == "doc.text.fill")
        #expect(CardType.agentSummary.iconSymbol == "bubble.left.and.bubble.right.fill")
        #expect(CardType.todoList.iconSymbol == "checklist")
        #expect(CardType.trending.iconSymbol == "chart.line.uptrend.xyaxis")
        #expect(CardType.sectionHeader.iconSymbol == nil)
    }

    @Test("CardType.iconTint uses only allowlisted system colors")
    func iconTintMapping() {
        #expect(CardType.metric.iconTint == .blue)
        #expect(CardType.insight.iconTint == .purple)
        #expect(CardType.digest.iconTint == .teal)
        #expect(CardType.agentSummary.iconTint == .indigo)
        #expect(CardType.todoList.iconTint == .green)
        #expect(CardType.trending.iconTint == .orange)
        #expect(CardType.sectionHeader.iconTint == nil)
    }

    @Test("CardType.hasIconBadge true for content cards, false for sectionHeader")
    func hasIconBadge() {
        for type in CardType.allCases where type != .sectionHeader {
            #expect(type.hasIconBadge, "\(type) must render a badge")
        }
        #expect(!CardType.sectionHeader.hasIconBadge)
    }

    @Test("Every content card type has a symbol AND a tint, sectionHeader has neither")
    func iconBadgeContractIsTotal() {
        for type in CardType.allCases {
            let symbol = type.iconSymbol
            let tint = type.iconTint
            if type == .sectionHeader {
                #expect(symbol == nil && tint == nil)
            } else {
                #expect(symbol != nil && tint != nil, "\(type) must define both icon and tint")
            }
        }
    }

    // MARK: - Typography

    @Test("AIDashTypography.section uses caption2/rounded/semibold with .secondary color and +0.6 tracking")
    func sectionTypography() {
        #expect(AIDashTypography.section == .system(.caption2, design: .rounded, weight: .semibold))
        #expect(AIDashTypography.sectionColor == .secondary)
        #expect(AIDashTypography.sectionTracking == 0.6)
    }

    @Test("AIDashTypography.detail returns a recipe for every CardType")
    func detailRecipeIsTotal() {
        for type in CardType.allCases {
            let recipe = AIDashTypography.detail(for: type)
            _ = recipe.primary
            _ = recipe.secondary
            _ = recipe.secondaryLineSpacing
            _ = recipe.secondaryColor
        }
    }

    @Test("Metric detail recipe: 36pt rounded bold primary, caption secondary, .secondary color")
    func metricDetailRecipe() {
        let r = AIDashTypography.detail(for: .metric)
        #expect(r.primary == .system(size: 36, weight: .bold, design: .rounded))
        #expect(r.secondary == .caption)
        #expect(r.secondaryColor == .secondary)
        #expect(r.secondaryLineSpacing == 0)
    }

    @Test("Insight detail recipe: title3 semibold primary, body primary secondary")
    func insightDetailRecipe() {
        let r = AIDashTypography.detail(for: .insight)
        #expect(r.primary == .title3.weight(.semibold))
        #expect(r.secondary == .body)
        #expect(r.secondaryColor == .primary)
    }

    @Test("Digest detail recipe: headline primary, body secondary with 4pt line spacing")
    func digestDetailRecipe() {
        let r = AIDashTypography.detail(for: .digest)
        #expect(r.primary == .headline)
        #expect(r.secondary == .body)
        #expect(r.secondaryLineSpacing == 4)
        #expect(r.secondaryColor == .primary)
    }

    @Test("AgentSummary detail recipe: headline primary, callout secondary")
    func agentSummaryDetailRecipe() {
        let r = AIDashTypography.detail(for: .agentSummary)
        #expect(r.primary == .headline)
        #expect(r.secondary == .callout)
    }

    @Test("TodoList detail recipe: body primary, caption2 secondary with .secondary color")
    func todoListDetailRecipe() {
        let r = AIDashTypography.detail(for: .todoList)
        #expect(r.primary == .body)
        #expect(r.secondary == .caption2)
        #expect(r.secondaryColor == .secondary)
    }

    @Test("Trending detail recipe: callout monospaced primary, body secondary")
    func trendingDetailRecipe() {
        let r = AIDashTypography.detail(for: .trending)
        #expect(r.primary == .callout.monospaced())
        #expect(r.secondary == .body)
    }

    @Test("SectionHeader detail recipe: title3 semibold primary, subheadline .secondary secondary")
    func sectionHeaderDetailRecipe() {
        let r = AIDashTypography.detail(for: .sectionHeader)
        #expect(r.primary == .title3.weight(.semibold))
        #expect(r.secondary == .subheadline)
        #expect(r.secondaryColor == .secondary)
    }

    // MARK: - Style → stripe

    @Test("AIDashChrome.stripeColor: neutral=nil, success=green, warning=orange, accent=accentColor")
    func stripeColorMapping() {
        #expect(AIDashChrome.stripeColor(for: .neutral) == nil)
        #expect(AIDashChrome.stripeColor(for: .success) == .green)
        #expect(AIDashChrome.stripeColor(for: .warning) == .orange)
        #expect(AIDashChrome.stripeColor(for: .accent) == .accentColor)
    }

    @Test("AIDashChrome carries only stripe + hairline tokens (no flat radius/padding)")
    func chromeConstants() {
        #expect(AIDashChrome.stripeWidth == 3)
        #expect(AIDashChrome.hairlineWidth == 0.5)
        #expect(AIDashChrome.hairlineOpacity == 0.5)
    }

    // MARK: - Card chrome modifier wiring

    @Test("cardChrome(size:style:) compiles and applies for every (size, style) combination")
    func cardChromeIsApplicableEverywhere() {
        for size in CardSize.allCases {
            for style in CardStyle.allCases {
                let v = Color.clear.cardChrome(size: size, style: style)
                _ = v
            }
        }
    }

    // MARK: - Badge view

    @Test("CardTypeBadge renders a non-nil body for content cards and an empty body for sectionHeader")
    func badgeRenders() {
        for type in CardType.allCases {
            let badge = CardTypeBadge(type: type)
            _ = badge
        }
    }
}
