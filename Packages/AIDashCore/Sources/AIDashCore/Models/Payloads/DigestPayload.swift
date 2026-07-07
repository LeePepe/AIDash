public struct DigestPayload: CardPayloadProtocol {
    public struct Section: Codable, Sendable {
        public let heading: String
        public let paragraphs: [String]

        public init(heading: String, paragraphs: [String]) {
            self.heading = heading
            self.paragraphs = paragraphs
        }
    }

    public let title: String
    /// Optional context sub-label under the title (project / scope / time
    /// range, e.g. "Sapphire · yesterday"). Content only; absent → none.
    public let subtitle: String?
    public let body: String
    public let sections: [Section]?

    public init(title: String, subtitle: String? = nil, body: String, sections: [Section]? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.sections = sections
    }

    public func validateInvariants() throws {
        if title.isEmpty {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "DigestPayload requires non-empty title",
                field: "title"
            )
        }
        if body.isEmpty {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "DigestPayload requires non-empty body",
                field: "body"
            )
        }
    }
}
