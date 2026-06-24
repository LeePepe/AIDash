public struct MetricPayload: CardPayloadProtocol {
    public struct Item: Codable, Sendable {
        public let label: String
        public let value: Double
        public let unit: String?
        public let trend: Trend?

        public enum Trend: String, Codable, Sendable {
            case up, down, flat
        }

        public init(label: String, value: Double, unit: String? = nil, trend: Trend? = nil) {
            self.label = label
            self.value = value
            self.unit = unit
            self.trend = trend
        }
    }

    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }
}
