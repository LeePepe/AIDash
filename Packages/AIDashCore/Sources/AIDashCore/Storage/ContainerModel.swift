import SwiftData
import Foundation

// CloudKit compatibility: scalars optional or default-valued; no `@Attribute(.unique)`;
// to-many relationships optional. Public `cards` API stays non-optional via a
// computed wrapper. Logical uniqueness is enforced in the XPC business layer
// by fetching by id and updating in place. See data-model.md.
@Model
public final class ContainerModel {
    public var id: String = ""                                // UUID from agent
    public var title: String = ""
    public var subtitle: String?
    public var order: Int = 0
    public var layoutRaw: String = ContainerLayout.auto.rawValue
    public var styleRaw: String = CardStyle.neutral.rawValue
    @Relationship(deleteRule: .cascade, inverse: \CardModel.container)
    var rawCards: [CardModel]?
    public var briefing: BriefingModel?                       // inverse for cascade

    public init(id: String, title: String, subtitle: String?, order: Int,
                layout: ContainerLayout, style: CardStyle) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.order = order
        self.layoutRaw = layout.rawValue
        self.styleRaw = style.rawValue
        self.rawCards = []
    }

    public var layout: ContainerLayout {
        get { ContainerLayout(rawValue: layoutRaw) ?? .auto }
        set { layoutRaw = newValue.rawValue }
    }

    public var style: CardStyle {
        get { CardStyle(rawValue: styleRaw) ?? .neutral }
        set { styleRaw = newValue.rawValue }
    }

    /// Non-optional business-layer view of the to-many relationship.
    /// CloudKit may surface the underlying store value as nil; callers always
    /// see an array (possibly empty).
    public var cards: [CardModel] {
        get { rawCards ?? [] }
        set { rawCards = newValue }
    }
}
