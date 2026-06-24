import SwiftData
import Foundation

// Minimal stub so BriefingModel's @Relationship compiles.
// T021 will replace this with the full implementation.
@Model
public final class ContainerModel {
    @Attribute(.unique) public var id: String
    public var briefing: BriefingModel?

    public init(id: String) {
        self.id = id
    }
}
