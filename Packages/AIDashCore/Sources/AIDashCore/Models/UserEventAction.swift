public enum UserEventAction: String, Codable, Sendable, CaseIterable {
    case done
    case star
    case undone
    case hide
    case unhide
    case acknowledgeFinding
    case approveRemediation
}
