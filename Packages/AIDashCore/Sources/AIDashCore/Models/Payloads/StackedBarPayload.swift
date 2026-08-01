/// A single stacked horizontal bar (card type `stackedBar`) — one bar split
/// into proportional segments with a legend below. Covers "session quality"
/// (end_turn / tool_use / max_tokens) and "model-tier usage" (opus / gpt …):
/// a composition-of-a-whole view where the mix is the point.
///
/// Segments render in order, each sized by its share of the total `value`. An
/// optional `semantic` flags a segment that warrants a status color (e.g.
/// "warning" for a `max_tokens` truncation) so a quality alert stands out; a
/// segment without `semantic` takes a distinct categorical chart color.
public struct StackedBarPayload: CardPayloadProtocol {
    public struct Segment: Codable, Sendable {
        /// Segment label shown in the legend (e.g. `end_turn`, `opus-4.6`).
        public let label: String
        /// Magnitude driving the segment's share of the bar
        /// (segment width ∝ value / Σ values).
        public let value: Double
        /// Optional semantic marker for a segment that deserves a status color
        /// rather than a neutral categorical tone — e.g. "success" for a good
        /// outcome, "warning" for a truncation. Absent → categorical color.
        public let semantic: String?

        public init(label: String, value: Double, semantic: String? = nil) {
            self.label = label
            self.value = value
            self.semantic = semantic
        }
    }

    public let segments: [Segment]
    /// Optional title shown above the bar (e.g. "会话质量"). Absent → no title.
    public let title: String?

    public init(segments: [Segment], title: String? = nil) {
        self.segments = segments
        self.title = title
    }

    public func validateInvariants() throws {
        guard !segments.isEmpty else {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "StackedBarPayload requires at least one segment",
                field: "segments"
            )
        }
    }
}
