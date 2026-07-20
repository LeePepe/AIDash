import SwiftData
import Foundation

// CloudKit compatibility: scalars optional or default-valued; no `@Attribute(.unique)`.
// UserEvent id uniqueness is enforced by the device/agent generating the UUID; the
// XPC layer fetches by id where dedupe matters. See data-model.md.
@Model
public final class UserEventModel {
    public var id: String = ""
    public var timestamp: Date = Date.distantPast
    public var device: String = ""
    public var cardId: String = ""
    public var actionRaw: String = UserEventAction.done.rawValue
    /// Optional stable identifier of the specific item within the card that
    /// the event targets (e.g. GitHub repo URL for a starred radar item).
    /// Nil for whole-card events; nil for records written before this field
    /// existed. CloudKit-compatible: optional scalar with default value.
    public var itemRef: String? = nil

    public init(id: String, timestamp: Date, device: String,
                cardId: String, action: UserEventAction, itemRef: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.device = device
        self.cardId = cardId
        self.actionRaw = action.rawValue
        self.itemRef = itemRef
    }

    public var action: UserEventAction? { UserEventAction(rawValue: actionRaw) }
}
