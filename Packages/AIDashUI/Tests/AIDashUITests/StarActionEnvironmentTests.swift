import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

/// Contract tests for the spec 002 D4 star-action environment: the UI layer
/// emits star intents through injected values, and the defaults must keep
/// previews/snapshots safe (no-op action, all-outline stars).
@Suite("Star action environment (spec 002 D4)")
struct StarActionEnvironmentTests {

    @Test("onStarItem defaults to nil → star button degrades to a no-op")
    func onStarItemDefaultsToNil() {
        #expect(EnvironmentValues().onStarItem == nil)
    }

    @Test("starredItemRefs defaults to empty → every item renders outline")
    func starredItemRefsDefaultsToEmpty() {
        #expect(EnvironmentValues().starredItemRefs.isEmpty)
    }

    @Test("currentCardId defaults to empty outside a routed card")
    func currentCardIdDefaultsToEmpty() {
        #expect(EnvironmentValues().currentCardId.isEmpty)
    }

    @Test("injected action receives the cardId + itemRef it was given")
    @MainActor
    func injectedActionRoundTrips() {
        var values = EnvironmentValues()
        var received: (cardId: String, itemRef: String)?
        values.onStarItem = { cardId, itemRef in received = (cardId, itemRef) }
        values.currentCardId = "radar-card-1"
        values.starredItemRefs = ["https://github.com/a/b"]

        values.onStarItem?(values.currentCardId, "https://github.com/a/b")

        #expect(received?.cardId == "radar-card-1")
        #expect(received?.itemRef == "https://github.com/a/b")
        #expect(values.starredItemRefs.contains("https://github.com/a/b"))
    }

    // MARK: - Spec 005 D4: whole-card star + done-toggle environment values

    @Test("onStarCard defaults to nil → whole-card star button degrades to a no-op")
    func onStarCardDefaultsToNil() {
        #expect(EnvironmentValues().onStarCard == nil)
    }

    @Test("starredCardIds defaults to empty → every card renders outline")
    func starredCardIdsDefaultsToEmpty() {
        #expect(EnvironmentValues().starredCardIds.isEmpty)
    }

    @Test("hide action defaults to nil and hidden ids default to empty")
    func hideActionDefaultsAreSafe() {
        #expect(EnvironmentValues().onHideCard == nil)
        #expect(EnvironmentValues().hiddenCardIds.isEmpty)
    }

    @Test("injected hide action round-trips the card identity and target state")
    @MainActor
    func injectedHideActionRoundTrips() {
        var values = EnvironmentValues()
        var received: (id: String, type: CardType, hidden: Bool)?
        values.onHideCard = { id, type, hidden in received = (id, type, hidden) }

        values.onHideCard?("card-1", .agentSummary, true)

        #expect(received?.id == "card-1")
        #expect(received?.type == .agentSummary)
        #expect(received?.hidden == true)
    }

    @Test("onToggleDone defaults to nil → done toggle degrades to a no-op")
    func onToggleDoneDefaultsToNil() {
        #expect(EnvironmentValues().onToggleDone == nil)
    }

    @Test("doneItemRefs defaults to empty → every TODO item renders unchecked")
    func doneItemRefsDefaultsToEmpty() {
        #expect(EnvironmentValues().doneItemRefs.isEmpty)
    }

    @Test("injected onStarCard receives the cardId + cardType it was given")
    @MainActor
    func injectedOnStarCardRoundTrips() {
        var values = EnvironmentValues()
        var received: (cardId: String, cardType: String)?
        values.onStarCard = { cardId, cardType in received = (cardId, cardType) }
        values.starredCardIds = ["digest-card-1"]

        values.onStarCard?("digest-card-1", "trending")

        #expect(received?.cardId == "digest-card-1")
        #expect(received?.cardType == "trending")
        #expect(values.starredCardIds.contains("digest-card-1"))
    }

    @Test("injected onToggleDone receives the cardId + itemRef + done it was given")
    @MainActor
    func injectedOnToggleDoneRoundTrips() {
        var values = EnvironmentValues()
        var received: (cardId: String, itemRef: String, done: Bool)?
        values.onToggleDone = { cardId, itemRef, done in received = (cardId, itemRef, done) }
        values.doneItemRefs = ["title:abc"]

        values.onToggleDone?("todo-card-1", "title:abc", true)

        #expect(received?.cardId == "todo-card-1")
        #expect(received?.itemRef == "title:abc")
        #expect(received?.done == true)
        #expect(values.doneItemRefs.contains("title:abc"))
    }
}
