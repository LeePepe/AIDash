import Testing
import SwiftUI
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
}
