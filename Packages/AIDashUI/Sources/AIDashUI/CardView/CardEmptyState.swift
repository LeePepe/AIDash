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

    var body: some View {
        HStack(spacing: AIDashSpace.s8) {
            Image(systemName: "minus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(message)
                .font(AIDashTypography.section)
                .tracking(AIDashTypography.sectionTracking)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
