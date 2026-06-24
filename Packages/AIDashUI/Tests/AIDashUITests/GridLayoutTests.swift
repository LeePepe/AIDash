import Testing
import SwiftUI
import SwiftData
@testable import AIDashUI
import AIDashCore

@Suite("GridLayout Tests")
struct GridLayoutTests {
    @Test("init sets cards and style")
    @MainActor func initSetsProperties() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: CardModel.self, ContainerModel.self,
            configurations: config
        )
        let context = ModelContext(container)

        let card = CardModel(
            id: "test-1",
            type: .metric,
            size: .medium,
            style: .accent,
            payloadJSON: Data()
        )
        context.insert(card)

        let layout = GridLayout(cards: [card], style: .neutral)
        #expect(layout.cards.count == 1)
        #expect(layout.cards[0].id == "test-1")
        #expect(layout.style == .neutral)
    }

    @Test("init with empty cards array")
    @MainActor func initWithEmptyCards() {
        let layout = GridLayout(cards: [], style: .success)
        #expect(layout.cards.isEmpty)
        #expect(layout.style == .success)
    }
}
