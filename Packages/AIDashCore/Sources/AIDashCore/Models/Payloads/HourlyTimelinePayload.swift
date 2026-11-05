import Foundation

public struct HourlyTimelinePayload: CardPayloadProtocol {
    public struct Citation: Codable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let url: String?

        public init(id: String, label: String, url: String? = nil) {
            self.id = id
            self.label = label
            self.url = url
        }
    }

    public struct HourBucket: Codable, Sendable, Identifiable {
        public let hour: Int
        public let summary: String
        public let evidenceIds: [String]
        public let sampled: Bool?
        public var id: String { String(format: "H%02d-%02d", hour, hour) }

        public init(hour: Int, summary: String, evidenceIds: [String] = [], sampled: Bool? = nil) {
            self.hour = hour
            self.summary = summary
            self.evidenceIds = evidenceIds
            self.sampled = sampled
        }
    }

    public static let emptyBucketSummary = "无采集数据。"
    public let title: String
    public let subtitle: String?
    public let overview: String
    public let hours: [HourBucket]
    public let citations: [Citation]
    public let nextSteps: [String]?

    public init(title: String, subtitle: String? = nil, overview: String, hours: [HourBucket], citations: [Citation] = [], nextSteps: [String]? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.overview = overview
        self.hours = hours
        self.citations = citations
        self.nextSteps = nextSteps
    }

    public func validateInvariants() throws {
        guard hours.count == 24 else {
            throw XPCError(code: "schema.payload_decode_failed", message: "HourlyTimelinePayload requires 24 hour buckets", field: "hours")
        }
        for (index, bucket) in hours.enumerated() {
            guard bucket.hour == index else {
                throw XPCError(code: "schema.payload_decode_failed", message: "HourlyTimelinePayload hours must be ordered 00 through 23", field: "hours")
            }
            let expectedPrefix = String(format: "H%02d-", index)
            guard bucket.id.hasPrefix(expectedPrefix) else {
                throw XPCError(code: "schema.payload_decode_failed", message: "HourlyTimelinePayload bucket IDs must use H%02d- prefixes", field: "hours")
            }
            let empty = bucket.summary.trimmingCharacters(in: .whitespacesAndNewlines) == Self.emptyBucketSummary
            if empty && !bucket.evidenceIds.isEmpty {
                throw XPCError(code: "schema.payload_decode_failed", message: "Empty hourly buckets cannot contain evidence", field: "hours")
            }
            if !empty && bucket.evidenceIds.isEmpty {
                throw XPCError(code: "schema.payload_decode_failed", message: "Active hourly buckets require evidence", field: "hours")
            }
        }
    }
}
