import SwiftData
import Foundation

@Model
public final class BriefingModel {
    @Attribute(.unique) public var date: String              // "2026-06-23"
    public var generatedAt: Date
    public var generatedBy: String
    public var publishedAt: Date?                            // nil until briefing.publish
    @Relationship(deleteRule: .cascade, inverse: \ContainerModel.briefing)
    public var containers: [ContainerModel]

    public init(date: String, generatedAt: Date, generatedBy: String, publishedAt: Date? = nil) {
        self.date = date
        self.generatedAt = generatedAt
        self.generatedBy = generatedBy
        self.publishedAt = publishedAt
        self.containers = []
    }
}
