import Testing
import SwiftUI
import AIDashCore
import DesignKit
@testable import AIDashUI

@MainActor
@Suite("AgentSummaryCardView Tests")
struct AgentSummaryCardViewTests {
    private let samplePayload = AgentSummaryPayload(
        agentName: "multica/atlas",
        completed: [
            .init(title: "Fixed PROJ-301 crash on launch", ref: "https://example.com/pr/4521"),
            .init(title: "Migrated Activity Tabs", ref: "https://example.com/pr/4522"),
        ],
        stats: [
            .init(label: "PRs", value: 3),
            .init(label: "Hours active", value: 6.5),
        ]
    )

    @Test("initializes with payload, size, and style")
    func initializesCorrectly() {
        let view = AgentSummaryCardView(
            payload: samplePayload,
            size: .medium,
            style: .neutral
        )

        #expect(view.payload.agentName == "multica/atlas")
        #expect(view.size == .medium)
        #expect(view.style == .neutral)
    }

    @Test("renders across all card sizes", arguments: CardSize.allCases)
    func acceptsAllSizes(size: CardSize) {
        let view = AgentSummaryCardView(
            payload: samplePayload,
            size: size,
            style: .neutral
        )
        _ = view.body
        #expect(view.size == size)
    }

    @Test("renders across all card styles", arguments: CardStyle.allCases)
    func acceptsAllStyles(style: CardStyle) {
        let view = AgentSummaryCardView(
            payload: samplePayload,
            size: .medium,
            style: style
        )
        _ = view.body
        #expect(view.style == style)
    }

    @Test("renders rows with and without valid link refs")
    func rendersLinkedAndUnlinkedRows() {
        let payload = AgentSummaryPayload(
            agentName: "bot",
            completed: [
                .init(title: "Linked", ref: "https://example.com/pr/1"),
                .init(title: "Unlinked"),
                .init(title: "Blocked scheme", ref: "javascript:alert(1)"),
            ]
        )
        let view = AgentSummaryCardView(payload: payload, size: .wide, style: .neutral)
        _ = view.body
        #expect(view.payload.completed.count == 3)
    }

    @Test("enforces single P0 focal stat with condensed secondary stats line instead of competing stat chips")
    func singleFocalStatHierarchy() throws {
        let view = AgentSummaryCardView(payload: samplePayload, size: .wide, style: .neutral)
        #expect(view.primaryStatDisplay.value == "3")
        #expect(view.primaryStatDisplay.label == "PRs")
        #expect(view.secondaryStatsSummary == "Hours active 6.5")

        let source = try DesignTokensComplianceTests.rendererSource(for: .agentSummary)
        #expect(!source.contains("statChips("),
                "AgentSummaryCardView must not render 4 equal-weight stat chips competing with primary P0")
        #expect(!source.contains("theme.success"),
                "AgentSummaryCardView routine checkmarks must stay monochrome neutral")
    }

    // MARK: - Token compliance contract

    @Test("declares CardType.agentSummary so it carries the constitution badge + tint")
    func badgeIsAgentSummary() {
        #expect(CardType.agentSummary.iconSymbol == "bubble.left.and.bubble.right.fill")
        #expect(CardType.agentSummary.classification == .agentSummary)
        #expect(CardType.agentSummary.hasIconBadge)
    }

    @Test("uses the AgentSummary detail recipe (headline + callout) from DesignTokens")
    func consumesDetailRecipe() {
        let recipe = AIDashTypography.detail(for: .agentSummary)
        #expect(recipe.primary == .headline)
        #expect(recipe.secondary == .callout)
    }
}
