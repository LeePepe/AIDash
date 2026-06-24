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
}
