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

    /// The bar-list header anchor must be reachable from outside the module:
    /// AIDashUI builds the card's header band from `headerTitle`, and the
    /// `title:` argument must stay defaulted so existing call sites that pass
    /// only `items:` keep compiling.
    @Test func barListPayloadPublicHeaderAnchor() {
        let untitled = BarListPayload(items: [.init(label: "AIDash", value: 48)])
        #expect(untitled.title == nil)
        #expect(untitled.headerTitle == nil)

        let titled = BarListPayload(
            items: [.init(label: "AIDash", value: 48)],
            title: "提交排行"
        )
        #expect(titled.headerTitle == "提交排行")
    }
}
