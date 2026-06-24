import Foundation

public struct CardPutParams: Codable, Sendable {
    public let containerId: String
    public let id: String
    public let type: CardType
    public let size: CardSize
    public let style: CardStyle
    public let payload: Data

    public init(
        containerId: String,
        id: String,
        type: CardType,
        size: CardSize,
        style: CardStyle,
        payload: Data
    ) {
        self.containerId = containerId
        self.id = id
        self.type = type
        self.size = size
        self.style = style
        self.payload = payload
    }
}

public struct CardPutResult: Codable, Sendable {
    public let id: String
    public let updatedAt: Date
    public let wasCreated: Bool

    public init(id: String, updatedAt: Date, wasCreated: Bool) {
        self.id = id
        self.updatedAt = updatedAt
        self.wasCreated = wasCreated
    }
}
