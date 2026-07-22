import Foundation

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

    public init(
        id: String,
        timestamp: Date,
        device: String,
        cardId: String,
        action: UserEventAction,
        itemRef: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.device = device
        self.cardId = cardId
        self.action = action
        self.itemRef = itemRef
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
}
