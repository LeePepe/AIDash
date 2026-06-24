import Foundation

public struct ContainerDeleteParams: Codable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct ContainerDeleteResult: Codable, Sendable {
    public init() {}
}
