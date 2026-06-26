import SwiftData
import Foundation

// CloudKit compatibility: scalars optional or default-valued; no `@Attribute(.unique)`.
// Logical uniqueness is enforced in the XPC business layer. See data-model.md.
@Model
public final class CardModel {
    public var id: String = ""                                // UUID from agent
    public var typeRaw: String = CardType.metric.rawValue
    public var sizeRaw: String = CardSize.medium.rawValue
    public var styleRaw: String = CardStyle.neutral.rawValue
    public var payloadJSON: Data = Data()
    public var container: ContainerModel?                     // inverse for cascade

    public init(id: String, type: CardType, size: CardSize,
                style: CardStyle, payloadJSON: Data) {
        self.id = id
        self.typeRaw = type.rawValue
        self.sizeRaw = size.rawValue
        self.styleRaw = style.rawValue
        self.payloadJSON = payloadJSON
    }

    public var type: CardType {
        get { CardType(rawValue: typeRaw) ?? .metric }
        set { typeRaw = newValue.rawValue }
    }

    public var size: CardSize {
        get { CardSize(rawValue: sizeRaw) ?? .medium }
        set { sizeRaw = newValue.rawValue }
    }

    public var style: CardStyle {
        get { CardStyle(rawValue: styleRaw) ?? .neutral }
        set { styleRaw = newValue.rawValue }
    }
}
