import Foundation

public struct SchemaListParams: Codable, Sendable {
    /// Optional CardType filter. When set, the app responds with only that
    /// type's payload schema in the `payloads` map (other enum fields are
    /// still emitted for self-documentation).
    public let type: String?

    public init(type: String? = nil) {
        self.type = type
    }
}

public struct SchemaListResult: Codable, Sendable {
    public let cliVersion: String
    public let schemaVersion: String
    public let cardTypes: [String]
    public let cardSizes: [String]
    public let cardStyles: [String]
    public let containerLayouts: [String]
    public let userEventActions: [String]
    /// Per-CardType JSON Schema document (key = card type rawValue, value = JSON Schema string).
    public let payloads: [String: String]

    public init(
        cliVersion: String,
        schemaVersion: String,
        cardTypes: [String],
        cardSizes: [String],
        cardStyles: [String],
        containerLayouts: [String],
        userEventActions: [String],
        payloads: [String: String]
    ) {
        self.cliVersion = cliVersion
        self.schemaVersion = schemaVersion
        self.cardTypes = cardTypes
        self.cardSizes = cardSizes
        self.cardStyles = cardStyles
        self.containerLayouts = containerLayouts
        self.userEventActions = userEventActions
        self.payloads = payloads
    }
}
