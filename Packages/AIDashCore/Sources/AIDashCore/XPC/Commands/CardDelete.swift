import Foundation

public struct CardDeleteParams: Codable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct CardDeleteResult: Codable, Sendable {
    public init() {}
}
