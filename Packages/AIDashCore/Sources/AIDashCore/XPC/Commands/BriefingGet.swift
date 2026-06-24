import Foundation

public struct BriefingGetParams: Codable, Sendable {
    public let date: String

    public init(date: String) {
        self.date = date
    }
}

public struct BriefingGetResult: Codable, Sendable {
    public let briefing: Briefing

    public init(briefing: Briefing) {
        self.briefing = briefing
    }
}
