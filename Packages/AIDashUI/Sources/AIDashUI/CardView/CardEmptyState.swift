import SwiftUI
import DesignKit

/// The sanctioned "no data" state for a content card whose payload decoded
/// cleanly but carries no items to show (e.g. a metric card with an empty
/// `items` array on a quiet day). Without this, such a card renders as a bare
/// chrome box — just the icon badge over dead space — which reads as a broken
/// card rather than an intentional empty state (the failure seen on real,
/// sparse agent data).
///
/// This is NOT the decode-failure fallback (`CardRouter.fallbackView`): that
/// signals an error with a warning glyph. This signals a valid-but-empty
/// dataset with a quiet, neutral dash — no alarm, just "nothing to report".
struct CardEmptyState: View {
    /// Short caption describing what is absent, e.g. "无指标数据". Callers pass
    /// an already-localized string so each card type can name its own content.
    let message: String
    @Environment(\.theme) private var theme
    @Environment(\.cardChromeMode) private var chromeMode

    var body: some View {
        HStack(spacing: AIDashSpace.s8) {
            ZStack {
                Circle()
                    .fill(theme.neutrals.inner)
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutrals.text2)
                    .accessibilityHidden(true)
            }
            .frame(width: AIDashSpace.s24, height: AIDashSpace.s24)
            Text(message)
                .font(AIDashTypography.section)
                .tracking(AIDashTypography.sectionTracking)
                .foregroundStyle(theme.neutrals.text2)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AIDashSpace.s12)
        .padding(.vertical, AIDashSpace.s8)
        .background {
            if chromeMode == .framed {
                RoundedRectangle(cornerRadius: AIDashSpace.s8)
                    .fill(theme.neutrals.card)
                    .overlay {
                        RoundedRectangle(cornerRadius: AIDashSpace.s8)
                            .stroke(theme.neutrals.border, lineWidth: AIDashChrome.hairlineWidth)
                    }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
