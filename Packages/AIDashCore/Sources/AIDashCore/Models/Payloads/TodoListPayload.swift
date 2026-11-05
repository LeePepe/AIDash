import Foundation

public struct TodoListPayload: CardPayloadProtocol {
    public struct Item: Codable, Sendable {
        public let title: String
        public let priority: Priority?
        public let due: Date?
        public let ref: String?
        public let category: String?
        public let waitingOn: String?
        public let ageText: String?
        public let commandHint: String?

        public enum Priority: String, Codable, Sendable {
            case low, medium, high
        }

        public init(title: String, priority: Priority? = nil, due: Date? = nil, ref: String? = nil, category: String? = nil, waitingOn: String? = nil, ageText: String? = nil, commandHint: String? = nil) {
            self.title = title
            self.priority = priority
            self.due = due
            self.ref = ref
            self.category = category
            self.waitingOn = waitingOn
            self.ageText = ageText
            self.commandHint = commandHint
        }
    }

    public let items: [Item]
    public let title: String?

    public init(items: [Item], title: String? = nil) {
        self.items = items
        self.title = title
    }

    public func validateInvariants() throws {
        guard !items.isEmpty else {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "TodoListPayload requires at least one item",
                field: "items"
            )
        }
    }
}
