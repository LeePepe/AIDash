import Foundation
import SwiftData
import AIDashCore

/// Append-only writer for user events (spec 002 — star feedback loop).
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
}
