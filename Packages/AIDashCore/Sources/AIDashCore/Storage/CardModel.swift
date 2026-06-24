import SwiftData
import Foundation

@Model
public final class CardModel {
    @Attribute(.unique) public var id: String
    public var typeRaw: String
    public var sizeRaw: String
    public var styleRaw: String
    public var payloadJSON: Data

    public init(id: String, type: CardType, size: CardSize,
                style: CardStyle, payloadJSON: Data) {
        self.id = id
        self.typeRaw = type.rawValue
        self.sizeRaw = size.rawValue
        self.styleRaw = style.rawValue
        self.payloadJSON = payloadJSON
    }

    public var type: CardType { CardType(rawValue: typeRaw)! }
    public var size: CardSize { CardSize(rawValue: sizeRaw)! }
    public var style: CardStyle { CardStyle(rawValue: styleRaw)! }
}
