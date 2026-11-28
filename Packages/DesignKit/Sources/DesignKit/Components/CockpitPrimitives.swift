import SwiftUI

/// Platform minimum for an interactive container without changing its visual
/// styling.
public enum CockpitHitTarget {
    public static var platformMinimum: CGFloat {
        #if os(macOS)
        28
        #else
        44
        #endif
    }
}

private struct ContainerHitTargetModifier: ViewModifier {
    let minSize: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(minWidth: minSize, minHeight: minSize)
            .contentShape(Rectangle())
    }
}

public extension View {
    /// Makes the complete container activate as one rectangular target.
    ///
    /// The caller supplies the visible container; this modifier only
    /// establishes the minimum platform target and interaction shape.
    func containerHitTarget(minSize: CGFloat = CockpitHitTarget.platformMinimum) -> some View {
        modifier(ContainerHitTargetModifier(minSize: max(0, minSize)))
    }
}

/// A compact, token-backed section rail/status chip.
public struct RailChip: View {
    private let theme = Theme.system

    private let title: String
    private let icon: String?
    private let tone: PillTone
    private let isSelected: Bool

    public init(
        _ title: String,
        icon: String? = nil,
        tone: PillTone = .neutral,
        isSelected: Bool = false
    ) {
        self.title = title
        self.icon = icon
        self.tone = tone
        self.isSelected = isSelected
    }

    private var accent: Color {
        switch tone {
        case .primary: theme.primary.primary
        case .success: theme.success
        case .warning: theme.warning
        case .danger: theme.danger
        case .neutral: theme.neutrals.text2
        }
    }

    private var foreground: Color {
        if isSelected || tone != .neutral {
            switch tone {
            case .primary: theme.primary.onPrimarySubtle
            case .success: theme.successOnSubtle
            case .warning: theme.warningOnSubtle
            case .danger: theme.dangerOnSubtle
            case .neutral: theme.text(.body)
            }
        } else {
            theme.text(.body)
        }
    }

    private var fill: Color {
        if isSelected {
            return accent.opacity(0.12)
        }
        if tone == .warning || tone == .danger {
            return accent.opacity(0.10)
        }
        return theme.neutrals.inner
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(TypeScale.meta)
                .fontWeight(isSelected ? .semibold : .medium)
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(fill)
        .clipShape(Capsule())
        .overlay {
            if isSelected {
                Capsule().stroke(accent.opacity(0.35), lineWidth: 1)
            }
        }
        .containerHitTarget()
        .accessibilityElement(children: .combine)
    }
}

/// Monochromatic P0 hero numeral enforcing `UI_COCKPIT_RAINBOW_NUMERAL_NOISE`
/// (`Theme.system.neutrals.text1` by default, monospaced digits).
public struct CockpitPrimaryNumeral: View {
    public static let usesMonochromePrimaryText = true

    private let theme = Theme.system
    private let value: String
    private let unit: String?

    public init(_ value: String, unit: String? = nil) {
        self.value = value
        self.unit = unit
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(TypeScale.display)
                .foregroundStyle(theme.neutrals.text1)
            if let unit, !unit.isEmpty {
                Text(unit)
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.neutrals.text2)
            }
        }
    }
}
