import Foundation

public struct ContainerPutParams: Codable, Sendable {
    public let briefingDate: String
    public let id: String
    public let title: String
    public let subtitle: String?
    public let order: Int
    public let layout: ContainerLayout
    public let style: CardStyle

    public init(
        briefingDate: String,
        id: String,
        title: String,
        subtitle: String?,
        order: Int,
        layout: ContainerLayout,
        style: CardStyle
    ) {
        self.briefingDate = briefingDate
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.order = order
        self.layout = layout
        self.style = style
    }
}

public struct ContainerPutResult: Codable, Sendable {
    public let id: String
    public let updatedAt: Date
    public let wasCreated: Bool

    public init(id: String, updatedAt: Date, wasCreated: Bool) {
        self.id = id
        self.updatedAt = updatedAt
        self.wasCreated = wasCreated
    }
}
