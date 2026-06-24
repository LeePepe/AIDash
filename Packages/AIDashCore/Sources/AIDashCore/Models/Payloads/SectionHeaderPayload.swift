public struct SectionHeaderPayload: CardPayloadProtocol {
    public let title: String
    public let subtitle: String?

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
}
