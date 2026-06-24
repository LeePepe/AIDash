import Foundation

public struct EventsPullParams: Codable, Sendable {
    public let since: Date
    public let until: Date?
    public let cardId: String?
    public let action: UserEventAction?

    public init(since: Date, until: Date?, cardId: String?, action: UserEventAction?) {
        self.since = since
        self.until = until
        self.cardId = cardId
        self.action = action
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
