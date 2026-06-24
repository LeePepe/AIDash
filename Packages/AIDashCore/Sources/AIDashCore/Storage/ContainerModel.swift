import SwiftData
import Foundation

@Model
public final class ContainerModel {
    @Attribute(.unique) public var id: String                // UUID from agent
    public var title: String
    public var subtitle: String?
    public var order: Int
    public var layoutRaw: String                             // ContainerLayout.rawValue
    public var styleRaw: String                              // CardStyle.rawValue
    @Relationship(deleteRule: .cascade, inverse: \CardModel.container)
    public var cards: [CardModel]
    public var briefing: BriefingModel?                      // inverse for cascade

    public init(id: String, title: String, subtitle: String?, order: Int,
                layout: ContainerLayout, style: CardStyle) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.order = order
        self.layoutRaw = layout.rawValue
        self.styleRaw = style.rawValue
        self.cards = []
    }

    public var layout: ContainerLayout {
        get { ContainerLayout(rawValue: layoutRaw) ?? .auto }
        set { layoutRaw = newValue.rawValue }
    }

    public var style: CardStyle {
        get { CardStyle(rawValue: styleRaw) ?? .neutral }
        set { styleRaw = newValue.rawValue }
    }
}
