import Foundation

/// A horizontal bar ranking (card type `barList`) — a descending list of
/// labeled magnitudes drawn as horizontal bars. Covers "failure root cause",
/// "app focus time", "commits by repo", and similar rank-by-value views.
///
/// Items are expected in descending `value` order (the publisher sorts; the
/// renderer draws them as given and scales each bar against the first/largest).
/// An optional `semantic` flags a row that warrants a status color + icon
/// (e.g. an infrastructure `runtime-offline` root cause) so a single hot row
/// pops out of an otherwise neutral ranking.
///
/// An optional `title` gives the card a header band. It is optional and
/// additive: payloads written before the field existed keep decoding, and a
/// payload that omits it renders exactly as it did.
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
    /// Optional header title for the ranking (e.g. "失败根因"). Absent → the
    /// card draws no header band and the rows start at the top edge, exactly
    /// as every payload published before this field existed.
    ///
    /// Present → the renderer owes the ranking a header band. That band is the
    /// anchor for card-level affordances (the star / pin control), which
    /// otherwise have nowhere to sit but on top of the first row's trailing
    /// value read-out. Mirrors `StackedBarPayload.title`; the two bar forms
    /// carry the same header contract so a publisher writes one shape.
    public let title: String?

    public init(items: [Item], title: String? = nil) {
        self.items = items
        self.title = title
    }

    /// The header title once normalized: `nil` when absent **or** blank, the
    /// trimmed string otherwise. Consumers branch on this rather than on
    /// `title` directly, so "is there a header band?" is decided in one place
    /// instead of each renderer re-deriving it (and drifting on whitespace).
    public var headerTitle: String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    public func validateInvariants() throws {
        guard !items.isEmpty else {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "BarListPayload requires at least one item",
                field: "items"
            )
        }
        // A present-but-blank title is rejected rather than silently ignored:
        // it would reserve a header band with nothing in it, which reads as a
        // rendering bug. Omit the key instead to get the headerless card.
        if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "BarListPayload title must be non-empty when present",
                field: "title"
            )
        }
    }
}
