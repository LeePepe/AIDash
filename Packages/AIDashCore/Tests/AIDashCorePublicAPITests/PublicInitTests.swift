import Foundation
import Testing
import AIDashCore

@Suite("Public API — Memberwise Init Accessibility")
struct PublicInitTests {

    @Test func cardPublicInit() {
        let card = Card(
            id: "x",
            type: .metric,
            size: .small,
            style: .neutral,
            payload: Data()
        )
        #expect(card.id == "x")
    }

    @Test func containerPublicInit() {
        let container = Container(
            id: "x",
            title: "t",
            subtitle: nil,
            order: 0,
            layout: .auto,
            style: .neutral,
            cards: []
        )
        #expect(container.id == "x")
    }

    @Test func briefingPublicInit() {
        let briefing = Briefing(
            date: "2026-01-01",
            generatedAt: Date(),
            generatedBy: "test",
            containers: []
        )
        #expect(briefing.date == "2026-01-01")
    }

    @Test func userEventPublicInit() {
        let event = UserEvent(
            id: "x",
            timestamp: Date(),
            device: "d",
            cardId: "c",
            action: .done
        )
        #expect(event.id == "x")
    }
}
