import Foundation

public struct Card: Codable, Sendable {
    public let id: String             // UUID
    public let type: CardType
    public let size: CardSize
    public let style: CardStyle
    public let payload: Data          // JSON-encoded per-type payload

    public init(
        id: String,
        type: CardType,
        size: CardSize,
        style: CardStyle,
        payload: Data
    ) {
        self.id = id
        self.type = type
        self.size = size
        self.style = style
        self.payload = payload
    }
}
