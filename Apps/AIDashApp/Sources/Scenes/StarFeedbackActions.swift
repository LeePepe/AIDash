import SwiftUI
import AIDashUI

/// The exact set of environment intent-closures the briefing UI needs wired to
/// the append-only `UserEventWriter` (spec 002 star, spec 005 whole-card star +
/// TODO done toggle).
///
/// Extracted from `StarFeedbackScope.body` so the *same* closures the scene
/// injects can be exercised directly by the spec 005 §6 wiring-verification
/// test (`StarFeedbackWiringTests`). The test drives these closures through a
/// real writer over an in-memory `ModelContainer` and asserts the resulting
/// `UserEventModel` rows — proving "UI action → writer → SwiftData" end to end,
/// not merely that `UserEventWriter`'s methods have unit tests.
///
/// Each closure is a thin adapter over one `UserEventWriter` call; the writer
/// owns all persistence + dedup + latest-wins semantics (spec 002 D2 /
/// spec 003 §8). `@MainActor` because taps and the writer are main-actor bound.
@MainActor
struct StarFeedbackActions {
    let onStarItem: StarItemAction
    let onStarCard: StarCardAction
    let onToggleDone: ToggleDoneAction

    /// Build the intent closures over `writer`. This is the single definition
    /// used by both `StarFeedbackScope` (production injection) and the wiring
    /// test — there is no second, test-only reimplementation to drift from.
    init(writer: UserEventWriter) {
        onStarItem = { cardId, itemRef in
            writer.star(cardId: cardId, itemRef: itemRef)
        }
        onStarCard = { cardId, cardType in
            writer.star(cardId: cardId, itemRef: nil, cardType: cardType)
        }
        onToggleDone = { cardId, itemRef, done in
            writer.setDone(cardId: cardId, itemRef: itemRef, done: done)
        }
    }
}

extension View {
    /// Inject the star/done intent closures produced by `actions`. Mirrors the
    /// per-item `onStarItem` injection already used for spec 002; the filled/
    /// checked state sets (`starredItemRefs` etc.) are injected separately by
    /// the caller since they come from `@Query`, not from the writer.
    func starFeedbackActions(_ actions: StarFeedbackActions) -> some View {
        self
            .environment(\.onStarItem, actions.onStarItem)
            .environment(\.onStarCard, actions.onStarCard)
            .environment(\.onToggleDone, actions.onToggleDone)
    }
}
