public struct SectionHeaderPayload: CardPayloadProtocol {
    public let title: String
    public let subtitle: String?

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public func validateInvariants() throws {
        if title.isEmpty {
            throw XPCError(
                code: "schema.payload_decode_failed",
                message: "SectionHeaderPayload requires non-empty title",
                field: "title"
            )
        }
    }
}
