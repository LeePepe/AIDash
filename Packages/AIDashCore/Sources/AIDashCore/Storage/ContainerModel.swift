import SwiftData
import Foundation

/// Stub for T021. Full implementation will add all properties
/// and the @Relationship to CardModel.
@Model
public final class ContainerModel {
    @Attribute(.unique) public var id: String
    public var title: String
    @Relationship(deleteRule: .cascade, inverse: \CardModel.container)
    public var cards: [CardModel]

    public init(id: String, title: String) {
        self.id = id
        self.title = title
        self.cards = []
    }
}
