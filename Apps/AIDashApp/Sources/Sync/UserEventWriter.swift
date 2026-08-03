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

    /// Appends a whole-card star event (spec 005 D1/D2/D3) unless an identical
    /// one already exists. Distinct from `star(cardId:itemRef:)`: this targets
    /// the *card itself* (`itemRef == nil`), tagged with `cardType` so
    /// downstream aggregation can group star counts by card type without
    /// joining through the date-scoped `cardId`. The two star axes (whole-card
    /// vs per-item) coexist independently — starring a card does not star its
    /// items and vice versa.
    ///
    /// `itemRef` is accepted (rather than dropped) to keep this call symmetric
    /// with `star(cardId:itemRef:)` at call sites, but the whole-card path is
    /// only meaningful when it is nil; a non-nil value is routed to the
    /// existing per-item `star(cardId:itemRef:)` instead of silently
    /// discarding the caller's intent.
    ///
    /// Same dedup/best-effort contract as `star(cardId:itemRef:)`: idempotent
    /// per `(cardId, cardType)` (repeated taps do not append duplicate rows),
    /// and a failed fetch/save is swallowed — the filled state re-derives from
    /// persisted events on the next render.
    func star(cardId: String, itemRef: String?, cardType: String) {
        guard let itemRef else {
            starCard(cardId: cardId, cardType: cardType)
            return
        }
        star(cardId: cardId, itemRef: itemRef)
    }

    /// Whole-card star write (see `star(cardId:itemRef:cardType:)` above for
    /// the full contract). Split out as its own method so the dedup fetch
    /// only ever queries `itemRef == nil` rows.
    private func starCard(cardId: String, cardType: String) {
        let context = ModelContext(container)
        let starRaw = UserEventAction.star.rawValue
        let descriptor = FetchDescriptor<UserEventModel>(
            predicate: #Predicate { event in
                event.cardId == cardId &&
                event.itemRef == nil &&
                event.actionRaw == starRaw &&
                event.cardType == cardType
            }
        )
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else { return }

        let event = UserEvent.starCard(
            cardId: cardId,
            cardType: cardType,
            device: DeviceIdentifier.current()
        )
        context.insert(UserEventModel(
            id: event.id,
            timestamp: event.timestamp,
            device: event.device,
            cardId: event.cardId,
            action: event.action,
            itemRef: event.itemRef,
            cardType: event.cardType
        ))
        try? context.save()
    }
    /// the caller's target state (`done: true` → `.done`, `false` → `.undone`).
    ///
    /// Semantics (parent MY-1307, spec 003 §8 — **latest-wins**, replacing the
    /// legacy count-parity model):
    /// - This method never dedups. Every tap appends exactly one row. Two
    ///   consecutive taps of the same state on the same `(cardId, itemRef)`
    ///   are allowed (e.g. cross-device races land two `.done` rows for the
    ///   same item — that's fine, both are `.done` and the item stays done).
    /// - The current checked flag for `(cardId, itemRef)` is derived from the
    ///   most recent event in that pair's timeline via `doneRefs(from:)`.
    /// - Best-effort: `try? save()` swallows storage failures so a dropped
    ///   write degrades to "tap did not stick", never a crash. Higher layers
    ///   re-derive checked state from persisted events on the next render.
    ///
    /// Star events remain governed by `star(...)`; this API only handles the
    /// `.done` / `.undone` axis.
    func setDone(cardId: String, itemRef: String, done: Bool) {
        let context = ModelContext(container)
        let event: UserEvent = done
            ? UserEvent.done(
                cardId: cardId,
                itemRef: itemRef,
                device: DeviceIdentifier.current()
            )
            : UserEvent.undone(
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

// MARK: - Done latest-wins inference (MY-1372 / T102, spec 003 §8)

extension UserEventWriter {
    /// Reduce a sequence of persisted `UserEventModel` rows to the set of
    /// itemRefs currently in the "done" state under **latest-wins** semantics
    /// (parent MY-1307, spec 003 §8): for each `itemRef` group, keep only the
    /// event with the most recent `timestamp`; if that winning event's
    /// `action` is `.done`, the ref is in the resulting set; if it is
    /// `.undone`, the ref is not. Events whose `action` is neither `.done`
    /// nor `.undone`, or whose `itemRef` is nil, are ignored.
    ///
    /// This is a pure function — callers are expected to pre-scope the input
    /// to a single card via an `@Query` predicate (the legacy `cardId`
    /// argument was removed together with the count-parity model in T102).
    /// Passing rows from multiple cards will conflate items with colliding
    /// refs across cards.
    ///
    /// Deterministic tiebreak: when two rows for the same ref share an exact
    /// timestamp (e.g. two devices raced), the event with the lexicographic
    /// larger `id` wins — this keeps latest-wins stable across replays and
    /// avoids relying on SwiftData fetch order.
    static func doneRefs<Events: Sequence>(
        from events: Events
    ) -> Set<String> where Events.Element == UserEventModel {
        var winners: [String: UserEventModel] = [:]
        for event in events {
            guard let ref = event.itemRef,
                  let action = event.action,
                  action == .done || action == .undone else { continue }
            if let current = winners[ref] {
                if event.timestamp > current.timestamp {
                    winners[ref] = event
                } else if event.timestamp == current.timestamp,
                          event.id > current.id {
                    winners[ref] = event
                }
            } else {
                winners[ref] = event
            }
        }
        var result: Set<String> = []
        for (ref, winner) in winners where winner.action == .done {
            result.insert(ref)
        }
        return result
    }
}
