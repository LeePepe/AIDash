import Foundation

public struct BriefingGetParams: Codable, Sendable {
    public let date: String
    public let includeDrafts: Bool

    public init(date: String, includeDrafts: Bool = false) {
        self.date = date
        self.includeDrafts = includeDrafts
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case includeDrafts
    }

    /// Backward-compatible decoding: payloads from older CLI/app versions
    /// that predate the `includeDrafts` flag continue to decode successfully,
    /// defaulting to `false`. This follows the XPC contract's additive-change
    /// guidance for new optional fields.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.date = try container.decode(String.self, forKey: .date)
        self.includeDrafts = try container.decodeIfPresent(Bool.self, forKey: .includeDrafts) ?? false
    }
}

public struct BriefingGetResult: Codable, Sendable {
    public let briefing: Briefing

    public init(briefing: Briefing) {
        self.briefing = briefing
    }
}
