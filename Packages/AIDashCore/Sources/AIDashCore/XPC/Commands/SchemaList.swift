import Foundation

public struct SchemaListParams: Codable, Sendable {
    public init() {}
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
