import SwiftData
import Foundation

@Model
public final class UserEventModel {
    @Attribute(.unique) public var id: String
    public var timestamp: Date
    public var device: String
    public var cardId: String
    public var actionRaw: String

    public init(id: String, timestamp: Date, device: String,
                cardId: String, action: UserEventAction) {
        self.id = id
        self.timestamp = timestamp
        self.device = device
        self.cardId = cardId
        self.actionRaw = action.rawValue
    }

    /// Typed accessor for the stored action.
    /// Returns `nil` if `actionRaw` contains an unknown value
    /// (forward-compatibility with future enum cases or malformed CloudKit records).
    public var action: UserEventAction? { UserEventAction(rawValue: actionRaw) }
}
