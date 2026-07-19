public struct TrendingPayload: CardPayloadProtocol {
    public struct Item: Codable, Sendable {
        public let title: String
        public let url: String
        public let score: Double?
        /// Optional change in `score` since the previous snapshot (e.g. daily
        /// star delta). Rendered as a ▲/▼ pill; absent (nil) on a first
        /// snapshot. Optional for forward-compat: older records decode as nil.
        public let delta: Double?
        /// Optional short classification tag (e.g. "AI-agent", "设计"). Rendered
        /// as a small tag beside the item. Optional for forward-compat.
        public let category: String?
        /// Optional one-line rationale ("why this is worth a look"). Rendered as
        /// a secondary line under the title. Optional for forward-compat.
        public let reason: String?

        public init(title: String, url: String, score: Double? = nil,
                    delta: Double? = nil, category: String? = nil,
                    reason: String? = nil) {
            self.title = title
            self.url = url
            self.score = score
            self.delta = delta
            self.category = category
            self.reason = reason
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
