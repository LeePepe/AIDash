public enum UserEventAction: String, Codable, Sendable, CaseIterable {
    case done
    case star
    case undone
    // `hide` deferred to v2 per spec D17
}
