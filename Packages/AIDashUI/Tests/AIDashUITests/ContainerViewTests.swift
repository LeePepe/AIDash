import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("ContainerView Tests")
struct ContainerViewTests {

    // MARK: - Initialization

    @Test("initializes with container model and exposes it")
    func initializesWithContainer() {
        let container = ContainerModel(
            id: "c-1", title: "Morning Brief", subtitle: "Your daily digest",
            order: 10, layout: .auto, style: .neutral
        )
        let view = ContainerView(container: container)

        #expect(view.container.id == "c-1")
        #expect(view.container.title == "Morning Brief")
        #expect(view.container.subtitle == "Your daily digest")
        #expect(view.container.layout == .auto)
        #expect(view.container.style == .neutral)
    }

    // MARK: - Card sorting

    @Test("sortedCards returns cards ordered by id ascending")
    func sortedCardsByIdAscending() {
        let container = ContainerModel(
            id: "c-1", title: "Test", subtitle: nil,
            order: 0, layout: .list, style: .neutral
        )
        let cardZ = CardModel(id: "z-card", type: .metric, size: .medium, style: .neutral, payloadJSON: Data())
        let cardA = CardModel(id: "a-card", type: .insight, size: .small, style: .accent, payloadJSON: Data())
        let cardM = CardModel(id: "m-card", type: .todoList, size: .wide, style: .success, payloadJSON: Data())
        container.cards = [cardZ, cardA, cardM]

        let view = ContainerView(container: container)
        let sorted = view.sortedCards

        #expect(sorted.count == 3)
        #expect(sorted[0].id == "a-card")
        #expect(sorted[1].id == "m-card")
        #expect(sorted[2].id == "z-card")
    }

    @Test("sortedCards handles empty cards array")
    func sortedCardsEmpty() {
        let container = ContainerModel(
            id: "c-1", title: "Empty", subtitle: nil,
            order: 0, layout: .auto, style: .neutral
        )
        let view = ContainerView(container: container)

        #expect(view.sortedCards.isEmpty)
    }

    @Test("sortedCards handles single card")
    func sortedCardsSingle() {
        let container = ContainerModel(
            id: "c-1", title: "Single", subtitle: nil,
            order: 0, layout: .auto, style: .neutral
        )
        let card = CardModel(id: "only", type: .metric, size: .medium, style: .neutral, payloadJSON: Data())
        container.cards = [card]

        let view = ContainerView(container: container)

        #expect(view.sortedCards.count == 1)
        #expect(view.sortedCards[0].id == "only")
    }

    // MARK: - Subtitle handling

    @Test("container with nil subtitle does not expose subtitle")
    func nilSubtitle() {
        let container = ContainerModel(
            id: "c-1", title: "No Sub", subtitle: nil,
            order: 0, layout: .list, style: .neutral
        )
        let view = ContainerView(container: container)

        #expect(view.container.subtitle == nil)
    }

    @Test("container with empty subtitle is treated as no subtitle")
    func emptySubtitle() {
        let container = ContainerModel(
            id: "c-1", title: "Empty Sub", subtitle: "",
            order: 0, layout: .list, style: .neutral
        )
        let view = ContainerView(container: container)

        // ContainerView body skips rendering when subtitle is nil or empty
        #expect(view.container.subtitle?.isEmpty == true)
    }

    // MARK: - Layout dispatch

    @Test("accepts all layout variants without error", arguments: ContainerLayout.allCases)
    func acceptsAllLayouts(layout: ContainerLayout) {
        let container = ContainerModel(
            id: "c-1", title: "Layout Test", subtitle: nil,
            order: 0, layout: layout, style: .neutral
        )
        let view = ContainerView(container: container)

        #expect(view.container.layout == layout)
    }

    @Test("accepts all style variants", arguments: CardStyle.allCases)
    func acceptsAllStyles(style: CardStyle) {
        let container = ContainerModel(
            id: "c-1", title: "Style Test", subtitle: nil,
            order: 0, layout: .auto, style: style
        )
        let view = ContainerView(container: container)

        #expect(view.container.style == style)
    }

    // MARK: - Container Chrome contract
    //
    // Constitution §Container Chrome: the container view MUST NOT wrap
    // its cards in a `RoundedRectangle`, `.background(...)`, material
    // panel, or colored fill. These tests pin the contract by reading
    // the source — code-level inspection is the only test layer that
    // can prove the absence of chrome modifiers since SwiftUI's view
    // graph is opaque.

    @Test("ContainerView source contains no container-level background or panel chrome")
    func containerHasNoPanelChrome() throws {
        let source = try Self.containerViewSource()

        #expect(!source.contains(".background("),
                "ContainerView must not call .background — containers carry typography + spacing only")
        #expect(!source.contains("RoundedRectangle("),
                "ContainerView must not draw a RoundedRectangle around its cards")
        #expect(!source.contains(".thinMaterial") && !source.contains(".regularMaterial"),
                "ContainerView must not use a material panel")
        #expect(!source.contains(".fill("),
                "ContainerView must not paint a colored fill")
    }

    @Test("ContainerView header uses overview-tier typography token")
    func headerUsesOverviewTypography() throws {
        let source = try Self.containerViewSource()

        #expect(source.contains("AIDashTypography.section"),
                "Header must use AIDashTypography.section font")
        #expect(source.contains("AIDashTypography.sectionTracking"),
                "Header must apply the +0.6pt tracking token")
        #expect(source.contains("AIDashTypography.sectionColor"),
                "Header must use the overview-tier color token")
    }

    @Test("ContainerView header-to-first-card spacing uses AIDashSpacing token")
    func headerToFirstCardSpacingUsesToken() throws {
        let source = try Self.containerViewSource()

        #expect(source.contains("AIDashSpacing.containerHeaderToFirstCard"),
                "Header-to-card spacing must come from the 12pt token, not a magic number")
    }

    // MARK: - Source helper

    private static func containerViewSource() throws -> String {
        let url = try sourceFile(named: "ContainerView.swift",
                                 under: "Sources/AIDashUI")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func sourceFile(named filename: String,
                                   under relativePath: String) throws -> URL {
        // Walk up from this test file until we find the AIDashUI package root,
        // then descend into the requested subdirectory.
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir
                .appendingPathComponent(relativePath)
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        throw SourceLookupError.notFound(filename)
    }

    private enum SourceLookupError: Error {
        case notFound(String)
    }
}
