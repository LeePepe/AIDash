import SwiftData
import Foundation

// CloudKit-backed SwiftData requires every scalar attribute to be optional or
// have a default value, every to-many relationship to be optional, and no
// `@Attribute(.unique)` constraints. The public `containers` surface stays
// non-optional via a computed wrapper so callers see business semantics
// (empty array when nil). See specs/001-core-briefing-cli/data-model.md.
@Model
public final class BriefingModel {
    public var date: String = ""                              // "2026-06-23"
    public var generatedAt: Date = Date.distantPast
    public var generatedBy: String = ""
    public var publishedAt: Date?                             // nil until briefing.publish
    @Relationship(deleteRule: .cascade, inverse: \ContainerModel.briefing)
    var rawContainers: [ContainerModel]?

    public init(date: String, generatedAt: Date, generatedBy: String, publishedAt: Date? = nil) {
        self.date = date
        self.generatedAt = generatedAt
        self.generatedBy = generatedBy
        self.publishedAt = publishedAt
        self.rawContainers = []
    }

    /// Non-optional business-layer view of the to-many relationship.
    /// CloudKit may surface the underlying store value as nil; callers always
    /// see an array (possibly empty).
    public var containers: [ContainerModel] {
        get { rawContainers ?? [] }
        set { rawContainers = newValue }
    }
}
