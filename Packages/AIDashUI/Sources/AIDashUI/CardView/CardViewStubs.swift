import SwiftUI
import AIDashCore

// MARK: - SectionHeaderCardView stub
//
// Compilation-only stub kept here because no T097–T103 task owns
// `SectionHeaderCardView` yet; CardRouter must still route every CardType.
// Remove this file once a real `SectionHeaderCardView` ships in AIDashUI.

struct SectionHeaderCardView: View {
    let payload: SectionHeaderPayload
    let size: CardSize
    let style: CardStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(payload.title)
                .font(.title3.bold())
            if let subtitle = payload.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
