public enum CardType: String, Codable, Sendable, CaseIterable {
    case metric
    case insight
    case agentSummary
    case todoList
    case trending
    case digest
    case sectionHeader
}
