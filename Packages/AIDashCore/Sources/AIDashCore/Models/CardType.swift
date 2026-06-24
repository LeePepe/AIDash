import Foundation

public enum CardType: String, Codable, Sendable, CaseIterable {
    case metric
    case insight
    case agentSummary
    case todoList
    case trending
    case digest
    case sectionHeader
}

extension CardType {
    public func decode(_ data: Data) throws -> any CardPayloadProtocol {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        switch self {
        case .metric:        return try decoder.decode(MetricPayload.self, from: data)
        case .insight:       return try decoder.decode(InsightPayload.self, from: data)
        case .agentSummary:  return try decoder.decode(AgentSummaryPayload.self, from: data)
        case .todoList:      return try decoder.decode(TodoListPayload.self, from: data)
        case .trending:      return try decoder.decode(TrendingPayload.self, from: data)
        case .digest:        return try decoder.decode(DigestPayload.self, from: data)
        case .sectionHeader: return try decoder.decode(SectionHeaderPayload.self, from: data)
        }
    }

    public func validate(_ data: Data) throws {
        let payload = try decode(data)
        try payload.validateInvariants()
    }
}
