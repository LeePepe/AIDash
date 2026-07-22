import Foundation
import SwiftData
import AIDashCore

/// Append-only writer for user events (spec 002 — star feedback loop, and
/// MY-1307 — done feedback loop).
///
/// The App layer is the ONLY writer of events (constitution §II: the CLI
/// never writes events). Each call appends one `UserEventModel` row to the
/// app's SwiftData container, which mirrors to the CloudKit `events` record
/// type; agents later pull them via `aidash events pull`. Nothing here ever
/// updates or deletes an existing event row.
@MainActor
final class UserEventWriter {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    /// Appends a star event for (cardId, itemRef) unless an identical star
    /// event already exists. Spec 002 D2: the toggle only ever emits star
    /// (no unstar event in v1) and repeated stars are idempotent, deduped by
    /// cardId+itemRef.
    ///
    /// Best-effort: a failed fetch/save is swallowed rather than thrown back
    /// across the UI tap — the filled state is re-derived from persisted
    /// events on the next render, so a dropped write degrades to "tap did
    /// not stick", never a crash.
    func star(cardId: String, itemRef: String) {
        let context = ModelContext(container)
        let starRaw = UserEventAction.star.rawValue
        let ref: String? = itemRef
        let descriptor = FetchDescriptor<UserEventModel>(
            predicate: #Predicate { event in
                event.cardId == cardId &&
                event.itemRef == ref &&
                event.actionRaw == starRaw
            }
        )
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else { return }

        let event = UserEvent.star(
            cardId: cardId,
            itemRef: itemRef,
            device: DeviceIdentifier.current()
        )
        context.insert(UserEventModel(
            id: event.id,
            timestamp: event.timestamp,
            device: event.device,
            cardId: event.cardId,
            action: event.action,
            itemRef: event.itemRef
        ))
        try? context.save()
    }

    /// Appends a `done` event for (cardId, itemRef). Unlike `star`, `done` is
    /// a *toggle*: repeated taps append additional `.done` rows and the
    /// current "checked" state is inferred from the parity of the emitted
    /// event count via `doneItemRefs(cardId:in:)` (spec 002 D2 pattern,
    /// applied to `.done` per MY-1307).
    ///
    /// Best-effort: a failed save is swallowed. Higher layers re-derive the
    /// checked set from persisted events on the next render.
    func done(cardId: String, itemRef: String) {
        let context = ModelContext(container)
        let event = UserEvent.done(
            cardId: cardId,
            itemRef: itemRef,
            device: DeviceIdentifier.current()
        )
        context.insert(UserEventModel(
            id: event.id,
            timestamp: event.timestamp,
            device: event.device,
            cardId: event.cardId,
            action: event.action,
            itemRef: event.itemRef
        ))
        try? context.save()
    }
}

// MARK: - Done toggle-from-events inference (MY-1309 / T002)

extension UserEventWriter {
    /// Reduce a sequence of persisted `UserEventModel` rows to the set of
    /// itemRefs currently in the "done" state under the given card.
    ///
    /// Toggle rule (parallels spec 002 D2 for star, applied to `.done` per
    /// MY-1307): each `.done` event for a `(cardId, itemRef)` flips the
    /// checked flag. An itemRef with an **odd** number of `.done` events is
    /// currently done; **even** (including zero) is not. Events whose
    /// `action` is not `.done`, whose `cardId` differs, or whose `itemRef`
    /// is nil are ignored.
    ///
    /// Callers typically pass an @Query-backed collection already filtered
    /// to `actionRaw == "done"` — this function stays defensive and re-checks
    /// so it is safe to use with any `UserEventModel` collection.
    static func doneItemRefs<Events: Sequence>(
        cardId: String,
        in events: Events
    ) -> Set<String> where Events.Element == UserEventModel {
        var counts: [String: Int] = [:]
        for event in events {
            guard event.cardId == cardId,
                  event.action == .done,
                  let ref = event.itemRef else { continue }
            counts[ref, default: 0] += 1
        }
        var result: Set<String> = []
        for (ref, count) in counts where count % 2 == 1 {
            result.insert(ref)
        }
        return result
    }
}
