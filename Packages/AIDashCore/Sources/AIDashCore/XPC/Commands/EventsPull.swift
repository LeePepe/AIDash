import Foundation

public struct EventsPullParams: Codable, Sendable {
    public let since: Date
    public let until: Date?
    public let cardId: String?
    public let action: UserEventAction?
    /// Optional filter: only return events whose `itemRef` matches. Absent
    /// (nil) returns events regardless of `itemRef`. Added for spec 002
    /// (star radar feedback) so `aidash events pull` can slice by repo URL.
    public let itemRef: String?

    public init(since: Date, until: Date?, cardId: String?, action: UserEventAction?, itemRef: String? = nil) {
        self.since = since
        self.until = until
        self.cardId = cardId
        self.action = action
        self.itemRef = itemRef
    }
}

public struct EventsPullResult: Codable, Sendable {
    public let events: [UserEvent]
    public let count: Int

    public init(events: [UserEvent], count: Int) {
        self.events = events
        self.count = count
    }
}
