import Foundation

public struct BriefingPublishParams: Codable, Sendable {
    public let date: String

    public init(date: String) {
        self.date = date
    }
}

public struct BriefingPublishResult: Codable, Sendable {
    public let date: String
    public let publishedAt: Date

    public init(date: String, publishedAt: Date) {
        self.date = date
        self.publishedAt = publishedAt
    }
}
