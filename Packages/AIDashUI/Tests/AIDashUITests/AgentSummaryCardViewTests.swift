import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("AgentSummaryCardView Tests")
struct AgentSummaryCardViewTests {
    private let samplePayload = AgentSummaryPayload(
        agentName: "multica/sapphire",
        completed: [
            .init(title: "Fixed SAP-301 crash on launch", ref: "https://example.com/pr/4521"),
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

        #expect(view.payload.agentName == "multica/sapphire")
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

    @Test("renders across all card styles", arguments: [CardStyle.neutral, .success, .warning, .accent])
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
}
