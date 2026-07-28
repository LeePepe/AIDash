/// A horizontal bar ranking (card type `barList`) — a descending list of
/// labeled magnitudes drawn as horizontal bars. Covers "failure root cause",
/// "app focus time", "commits by repo", and similar rank-by-value views.
///
/// Items are expected in descending `value` order (the publisher sorts; the
/// renderer draws them as given and scales each bar against the first/largest).
/// An optional `semantic` flags a row that warrants a status color + icon
/// (e.g. an infrastructure `runtime-offline` root cause) so a single hot row
/// pops out of an otherwise neutral ranking.
public struct BarListPayload: CardPayloadProtocol {
    public struct Item: Codable, Sendable {
        /// Row label (e.g. `runtime-offline`, `cmux`, `AIDash`).
        public let label: String
        /// Magnitude driving the bar width (bar width ∝ value / max value).
        public let value: Double
        /// Optional pre-formatted value text shown at the row's trailing edge
        /// (e.g. "39%", "4.4min", "144"). Absent → the renderer formats `value`
        /// itself. Content only; the app never derives units.
        public let valueText: String?
        /// Optional semantic marker for a row that deserves a status color +
        /// icon rather than the neutral bar tone — e.g. "warning" for an
        /// infrastructure root cause. Absent → the row renders neutral.
        public let semantic: String?

        public init(
            label: String,
            value: Double,
            valueText: String? = nil,
            semantic: String? = nil
        ) {
            self.label = label
            self.value = value
            self.valueText = valueText
            self.semantic = semantic
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
                message: "BarListPayload requires at least one item",
                field: "items"
            )
        }
    }
}
