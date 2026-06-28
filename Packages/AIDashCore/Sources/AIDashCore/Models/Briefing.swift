import Foundation

public struct Briefing: Codable, Sendable {
    public let date: String           // "YYYY-MM-DD"
    public let generatedAt: Date
    public let generatedBy: String
    public let publishedAt: Date?     // nil until briefing.publish
    public let containers: [Container]

    public init(
        date: String,
        generatedAt: Date,
        generatedBy: String,
        publishedAt: Date? = nil,
        containers: [Container]
    ) {
        self.date = date
        self.generatedAt = generatedAt
        self.generatedBy = generatedBy
        self.publishedAt = publishedAt
        self.containers = containers
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case generatedAt
        case generatedBy
        case publishedAt
        case containers
    }

    // Backward-compatible decoding: payloads emitted by older app versions
    // that predate `publishedAt` continue to decode successfully with
    // `publishedAt == nil`. Per xpc-protocol.md, new optional fields on
    // result structs are additive and must not break older clients.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.date = try container.decode(String.self, forKey: .date)
        self.generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        self.generatedBy = try container.decode(String.self, forKey: .generatedBy)
        self.publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        self.containers = try container.decode([Container].self, forKey: .containers)
    }
}
