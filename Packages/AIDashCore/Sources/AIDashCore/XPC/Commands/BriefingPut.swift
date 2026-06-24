import Foundation

public struct BriefingPutParams: Codable, Sendable {
    public let date: String
    public let generatedBy: String
    public let published: Bool

    public init(date: String, generatedBy: String, published: Bool) {
        self.date = date
        self.generatedBy = generatedBy
        self.published = published
    }
}

public struct BriefingPutResult: Codable, Sendable {
    public let date: String
    public let generatedAt: Date
    public let publishedAt: Date?

    public init(date: String, generatedAt: Date, publishedAt: Date?) {
        self.date = date
        self.generatedAt = generatedAt
        self.publishedAt = publishedAt
    }
}
