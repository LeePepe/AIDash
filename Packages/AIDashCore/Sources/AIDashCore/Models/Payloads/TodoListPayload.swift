import Foundation

public struct TodoListPayload: CardPayloadProtocol {
    public struct Item: Codable, Sendable {
        public let title: String
        public let priority: Priority?
        public let due: Date?
        public let ref: String?

        public enum Priority: String, Codable, Sendable {
            case low, medium, high
        }

        public init(title: String, priority: Priority? = nil, due: Date? = nil, ref: String? = nil) {
            self.title = title
            self.priority = priority
            self.due = due
            self.ref = ref
        }
    }

    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }
}
