import SwiftUI
import SwiftData
import AIDashCore

public struct ContainerView: View {
    let container: ContainerModel

    public init(container: ContainerModel) {
        self.container = container
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(container.title)
                    .font(.title2.bold())
                if let subtitle = container.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            let cards = container.cards.sorted(by: { $0.id < $1.id })

            switch container.layout {
            case .auto: AutoLayout(cards: cards, style: container.style)
            case .list: ListLayout(cards: cards, style: container.style)
            case .grid: GridLayout(cards: cards, style: container.style)
            case .hero: HeroLayout(cards: cards, style: container.style)
            }
        }
        .padding(.vertical, 8)
    }
}
