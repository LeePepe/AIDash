public struct Container: Codable, Sendable {
    public let id: String             // caller-supplied UUID
    public let title: String
    public let subtitle: String?
    public let order: Int             // sparse: 10, 20, 30 ...
    public let layout: ContainerLayout
    public let style: CardStyle       // reused
    public let cards: [Card]

    public init(
        id: String,
        title: String,
        subtitle: String?,
        order: Int,
        layout: ContainerLayout,
        style: CardStyle,
        cards: [Card]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.order = order
        self.layout = layout
        self.style = style
        self.cards = cards
    }
}
