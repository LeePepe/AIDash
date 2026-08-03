import Foundation
import CryptoKit

public struct UserEvent: Codable, Sendable {
    public let id: String
    public let timestamp: Date
    public let device: String
    public let cardId: String
    public let action: UserEventAction
    /// Optional stable identifier of the specific item within the card that the
    /// event targets (e.g. for a `trending` radar card, the GitHub repo URL of
    /// the starred item). Absent (nil) for whole-card events. Optional for
    /// forward-compat: older records / older JSON without this key decode as
    /// nil (same pattern as TrendingPayload.Item's delta/category/reason).
    public let itemRef: String?
    /// Optional `CardType.rawValue` of the card the event was emitted from
    /// (e.g. "trending", "todoList"). Added spec 005 D2 (2026-08-03): the L5
    /// `cardId` is date-scoped and does not encode card type, so aggregating
    /// "star counts per card type" needs the type carried on the event itself.
    /// Optional and forward-compat, same pattern as `itemRef`: older records /
    /// older JSON without this key decode as nil.
    public let cardType: String?

    public init(
        id: String,
        timestamp: Date,
        device: String,
        cardId: String,
        action: UserEventAction,
        itemRef: String? = nil,
        cardType: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.device = device
        self.cardId = cardId
        self.action = action
        self.itemRef = itemRef
        self.cardType = cardType
    }
}

extension UserEvent {
    /// Core-layer factory for a star event targeting a specific item within a
    /// card (e.g. a repo URL inside a trending/radar card). Generates a fresh
    /// UUID and current timestamp; caller only supplies stable identifiers.
    ///
    /// Per spec 002 D2 (2026-07-20): star is append-only and toggle state is
    /// inferred from emitted events; there is no `.unstar` action in v1.
    public static func star(cardId: String, itemRef: String, device: String) -> UserEvent {
        UserEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            device: device,
            cardId: cardId,
            action: .star,
            itemRef: itemRef
        )
    }

    /// Core-layer factory for a `done` event targeting a specific item within a
    /// TodoList card. Generates a fresh UUID and current timestamp; caller only
    /// supplies stable identifiers.
    ///
    /// Per parent MY-1307 / spec 003 §8: append-only with **latest-wins**
    /// semantics. Toggle state for `(cardId, itemRef)` is derived from the
    /// most recent event in that pair's history — a `.done` marks the item
    /// complete, and a subsequent `.undone` (see `UserEvent.undone(...)`)
    /// clears the completion. Events are never mutated or deleted.
    public static func done(cardId: String, itemRef: String, device: String) -> UserEvent {
        UserEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            device: device,
            cardId: cardId,
            action: .done,
            itemRef: itemRef
        )
    }

    /// Core-layer factory for an `undone` event targeting a specific item
    /// within a TodoList card, emitted when the user clears a previously
    /// marked-done item. Generates a fresh UUID and current timestamp;
    /// caller only supplies stable identifiers.
    ///
    /// Per parent MY-1307 / spec 003 §8: append-only with **latest-wins**
    /// semantics — an `.undone` appended after a `.done` clears the item's
    /// completed state; a subsequent `.done` re-completes it. Events are
    /// never mutated or deleted (constitution §I).
    public static func undone(cardId: String, itemRef: String, device: String) -> UserEvent {
        UserEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            device: device,
            cardId: cardId,
            action: .undone,
            itemRef: itemRef
        )
    }

    /// Core-layer factory for a whole-card star event (spec 005 D1/D2,
    /// 2026-08-03): `itemRef` is always nil (the "whole card" sentinel
    /// established by spec 002 D1), and `cardType` carries the
    /// `CardType.rawValue` of the starred card so downstream aggregation can
    /// group by card type without needing to decode/join the card itself.
    /// Generates a fresh UUID and current timestamp; caller only supplies
    /// stable identifiers.
    ///
    /// `cardType` must be non-empty — callers should pass
    /// `card.type.rawValue`, which is never empty for any `CardType` case.
    public static func starCard(cardId: String, cardType: String, device: String) -> UserEvent {
        UserEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            device: device,
            cardId: cardId,
            action: .star,
            itemRef: nil,
            cardType: cardType
        )
    }
}

// MARK: - Stable itemRef derivation (MY-1308 / T001)

extension UserEvent {
    /// Derive a stable `itemRef` for a `TodoListPayload.Item`, so `done`
    /// events emitted on the same logical task on different days collapse to
    /// the same `itemRef` and toggle state can be recovered cross-day.
    ///
    /// Strategy (per parent MY-1307):
    /// - If `item.ref` is non-empty (trimmed), use it verbatim — refs are
    ///   already stable global identifiers (issue/PR URLs).
    /// - Otherwise, derive `"title:" + SHA256(normalizedTitle)` where
    ///   `normalizedTitle` is the item title lowercased, whitespace-folded,
    ///   and trimmed. Same-title tasks across days collapse; different-title
    ///   tasks separate. (Changing the title = new task, accepted per spec.)
    ///
    /// The `"title:"` prefix keeps derived refs disambiguated from real URL
    /// refs; the SHA256 keeps the identifier bounded, opaque, and free of
    /// Unicode surprises.
    public static func stableItemRef(for item: TodoListPayload.Item) -> String {
        let trimmedRef = item.ref?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedRef.isEmpty {
            return trimmedRef
        }
        return "title:" + normalizedTitleHash(item.title)
    }

    /// Normalize a title (lowercase, fold internal whitespace runs to a single
    /// space, trim) and return the lowercase hex SHA256 of its UTF-8 bytes.
    /// Empty / whitespace-only titles hash the empty string, yielding a
    /// deterministic sentinel value.
    private static func normalizedTitleHash(_ title: String) -> String {
        let lower = title.lowercased()
        let folded = lower.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        let digest = SHA256.hash(data: Data(folded.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
