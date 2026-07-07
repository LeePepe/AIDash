public struct MetricPayload: CardPayloadProtocol {
    public struct Item: Codable, Sendable {
        public let label: String
        public let value: Double
        public let unit: String?
        public let trend: Trend?
        /// Optional time-series for a sparkline next to the value. Agents
        /// supply the recent history; the renderer draws a mini line/area
        /// chart. Absent → no sparkline. See north-star §6/§7.
        public let series: [Double]?
        /// Optional 0…1 completion ratio for a ring gauge (replaces the
        /// sparkline for ratio-type metrics per north-star §6). Absent →
        /// no gauge. Validated to `0...1` in `validateInvariants()`.
        public let ratio: Double?

        public enum Trend: String, Codable, Sendable {
            case up, down, flat
        }

        public init(
            label: String,
            value: Double,
            unit: String? = nil,
            trend: Trend? = nil,
            series: [Double]? = nil,
            ratio: Double? = nil
        ) {
            self.label = label
            self.value = value
            self.unit = unit
            self.trend = trend
            self.series = series
            self.ratio = ratio
        }
    }

    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    public func validateInvariants() throws {
        guard !items.isEmpty else {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "MetricPayload requires at least one item",
                field: "items"
            )
        }
        for item in items {
            if let ratio = item.ratio, !(0...1).contains(ratio) {
                throw XPCError(
                    code: "schema.payload_decode_failed",
                    message: "MetricPayload.Item.ratio must be within 0...1",
                    field: "ratio"
                )
            }
        }
    }
}
