public struct TrendingPayload: CardPayloadProtocol {
    public struct Item: Codable, Sendable {
        public let title: String
        public let url: String
        public let score: Double?

        public init(title: String, url: String, score: Double? = nil) {
            self.title = title
            self.url = url
            self.score = score
        }
    }

    public let topic: String
    public let items: [Item]

    public init(topic: String, items: [Item]) {
        self.topic = topic
        self.items = items
    }

    public func validateInvariants() throws {
        if topic.isEmpty {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "TrendingPayload requires non-empty topic",
                field: "topic"
            )
        }
        guard !items.isEmpty else {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "TrendingPayload requires at least one item",
                field: "items"
            )
        }
    }
}
