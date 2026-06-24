import Foundation

public struct UserEvent: Codable, Sendable {
    public let id: String
    public let timestamp: Date
    public let device: String
    public let cardId: String
    public let action: UserEventAction

    public init(
        id: String,
        timestamp: Date,
        device: String,
        cardId: String,
        action: UserEventAction
    ) {
        self.id = id
        self.timestamp = timestamp
        self.device = device
        self.cardId = cardId
        self.action = action
    }
}
