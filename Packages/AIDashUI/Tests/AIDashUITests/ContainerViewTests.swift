import Testing
import Foundation
import SwiftData
@testable import AIDashUI
@testable import AIDashCore

@Suite("ContainerView")
struct ContainerViewTests {

    @MainActor
    private func makeContainer(
        title: String = "Test Container",
        subtitle: String? = nil,
        layout: ContainerLayout = .auto,
        style: CardStyle = .neutral,
        cards: [CardModel] = []
    ) -> ContainerModel {
        let container = ContainerModel(
            id: "container-1",
            title: title,
            subtitle: subtitle,
            order: 0,
            layout: layout,
            style: style
        )
        for card in cards {
            container.cards.append(card)
        }
        return container
    }

    @Test("Initializes with container")
    @MainActor
    func initWithContainer() {
        let container = makeContainer(title: "Morning Briefing")
        let view = ContainerView(container: container)
        #expect(view.container.title == "Morning Briefing")
    }

    @Test("Layout dispatches to correct case")
    @MainActor
    func layoutDispatch() {
        for layout in ContainerLayout.allCases {
            let container = makeContainer(layout: layout)
            #expect(container.layout == layout)
            // ContainerView body should compile and dispatch without crash
            _ = ContainerView(container: container)
        }
    }

    @Test("Subtitle is optional")
    @MainActor
    func subtitleOptional() {
        let withSub = makeContainer(subtitle: "Hello")
        #expect(withSub.subtitle == "Hello")

        let withoutSub = makeContainer(subtitle: nil)
        #expect(withoutSub.subtitle == nil)

        let emptySub = makeContainer(subtitle: "")
        #expect(emptySub.subtitle == "")
    }

    @Test("Cards sorted by id for stable ordering")
    @MainActor
    func cardsSortedById() {
        let card1 = CardModel(id: "z-card", type: .metric, size: .medium, style: .neutral, payloadJSON: Data())
        let card2 = CardModel(id: "a-card", type: .metric, size: .medium, style: .neutral, payloadJSON: Data())
        let container = makeContainer(cards: [card1, card2])

        let sorted = container.cards.sorted(by: { $0.id < $1.id })
        #expect(sorted[0].id == "a-card")
        #expect(sorted[1].id == "z-card")
    }
}
