public struct InsightPayload: CardPayloadProtocol {
    public struct Citation: Codable, Sendable {
        public let label: String
        public let url: String

        public init(label: String, url: String) {
            self.label = label
            self.url = url
        }
    }

    public let title: String
    public let body: String
    public let citations: [Citation]?

    public init(title: String, body: String, citations: [Citation]? = nil) {
        self.title = title
        self.body = body
        self.citations = citations
    }

    public func validateInvariants() throws {
        if title.isEmpty {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "InsightPayload requires non-empty title",
                field: "title"
            )
        }
        if body.isEmpty {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "InsightPayload requires non-empty body",
                field: "body"
            )
        }
    }
}
