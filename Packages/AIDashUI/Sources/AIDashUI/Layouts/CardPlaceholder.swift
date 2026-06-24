import SwiftUI
import AIDashCore

/// Placeholder for card rendering — replaced by CardRouter in T096.
struct CardPlaceholder: View {
    let card: CardModel

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .frame(minHeight: 60)
            .overlay {
                Text(card.type.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }
}
