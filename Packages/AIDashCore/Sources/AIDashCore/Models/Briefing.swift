import Foundation

public struct Briefing: Codable, Sendable {
    public let date: String           // "YYYY-MM-DD"
    public let generatedAt: Date
    public let generatedBy: String
    public let containers: [Container]

    public init(
        date: String,
        generatedAt: Date,
        generatedBy: String,
        containers: [Container]
    ) {
        self.date = date
        self.generatedAt = generatedAt
        self.generatedBy = generatedBy
        self.containers = containers
    }
}
