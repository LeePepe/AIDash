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
    public let body: String
    public let sections: [Section]?

    public init(title: String, body: String, sections: [Section]? = nil) {
        self.title = title
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
