#if os(macOS)
import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import AIDashApp
import AIDashCore
import AIDashUI

/// Spec 005 §6 — the **hard constraint** this feature exists to satisfy.
///
/// `done` shipped in spec 003 as a "hollow" feature: the writer method existed
/// and had unit tests, but no scene wired the UI to it, so tapping produced no
/// event. This suite proves the wiring is real by exercising the exact intent
/// closures the scene injects (`StarFeedbackActions`, built over a real
/// `UserEventWriter`) against an in-memory `ModelContainer`, then asserting the
/// persisted `UserEventModel` rows.
///
/// It deliberately does NOT re-test `UserEventWriter` in isolation (that's
/// `UserEventWriterTests`). The point is the *path*: closure the button calls →
/// writer → SwiftData. The closures under test are the same values
/// `StarFeedbackScope.body` injects into the environment via
/// `.starFeedbackActions(_:)`, so a regression that unwires the UI (e.g. an
/// `onStarCard` that no longer reaches the writer) fails here.
@MainActor
@Suite("Star/done UI→writer wiring (spec 005 §6)")
struct StarFeedbackWiringTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: BriefingModel.self,
            ContainerModel.self,
            CardModel.self,
            UserEventModel.self,
            configurations: config
        )
    }

    private func fetchEvents(_ container: ModelContainer) throws -> [UserEventModel] {
        try ModelContext(container).fetch(FetchDescriptor<UserEventModel>())
    }

    // MARK: - star whole-card

    @Test("whole-card star intent → one row action=star, itemRef=nil, cardType set")
    func wholeCardStarWiresToStore() throws {
        let container = try makeContainer()
        let actions = StarFeedbackActions(writer: UserEventWriter(container: container))

        // Exactly what `WholeCardStarButton` hands to the injected closure on
        // tap: (currentCardId, card.type.rawValue).
        actions.onStarCard("digest-card-1", CardType.trending.rawValue)

        let events = try fetchEvents(container)
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.action == .star)
        #expect(event.cardId == "digest-card-1")
        #expect(event.itemRef == nil)
        #expect(event.cardType == CardType.trending.rawValue)
    }

    @Test("whole-card star coexists with per-item star (two distinct rows, D1)")
    func wholeCardAndItemStarCoexist() throws {
        let container = try makeContainer()
        let actions = StarFeedbackActions(writer: UserEventWriter(container: container))

        actions.onStarItem("radar-card-1", "https://github.com/a/b")
        actions.onStarCard("radar-card-1", CardType.trending.rawValue)

        let events = try fetchEvents(container)
        #expect(events.count == 2)
        #expect(events.contains { $0.itemRef == "https://github.com/a/b" && $0.cardType == nil })
        #expect(events.contains { $0.itemRef == nil && $0.cardType == CardType.trending.rawValue })
    }

    // MARK: - done TODO (latest-wins, spec 003 §8)

    @Test("done toggle → done row, then re-toggle → undone row (latest-wins)")
    func doneToggleWiresToStore() throws {
        let container = try makeContainer()
        let actions = StarFeedbackActions(writer: UserEventWriter(container: container))
        let ref = "title:abc123"

        // First tap: not-done → done.
        actions.onToggleDone("todo-card-1", ref, true)
        var events = try fetchEvents(container)
        #expect(events.count == 1)
        #expect(events.first?.action == .done)
        #expect(events.first?.itemRef == ref)

        // Second tap on the now-done item: done → undone (append, not mutate).
        actions.onToggleDone("todo-card-1", ref, false)
        events = try fetchEvents(container)
        #expect(events.count == 2)
        #expect(events.contains { $0.action == .done })
        #expect(events.contains { $0.action == .undone })

        // The derived latest-wins state clears the ref (spec 003 §8).
        #expect(!UserEventWriter.doneRefs(from: events).contains(ref))
    }

    // MARK: - reverse sentinel (UI purity: no injection = no-op, no crash)

    @Test("with no actions injected the UI buttons are inert — nothing is written")
    func noInjectionIsNoOp() throws {
        // `WholeCardStarButton` / `TodoItemRow` read the intent closures from
        // the environment as optionals and call them with `?.`; the default
        // `EnvironmentValues` value is nil (asserted in
        // StarActionEnvironmentTests). So without a StarFeedbackActions
        // injection, a tap resolves to `nil?(...)` — a no-op. Model that here:
        // no closures built, no writer touched.
        let container = try makeContainer()

        let onStarCard: StarCardAction? = EnvironmentValues().onStarCard
        let onToggleDone: ToggleDoneAction? = EnvironmentValues().onToggleDone
        #expect(onStarCard == nil)
        #expect(onToggleDone == nil)

        // Simulating the taps: optional-chained calls against the (nil) defaults.
        onStarCard?("digest-card-1", CardType.trending.rawValue)
        onToggleDone?("todo-card-1", "title:abc123", true)

        #expect(try fetchEvents(container).isEmpty)
    }
}
#endif
