import SwiftUI
import AIDashCore
import DesignKit

public struct TodoListCardView: View {
    let payload: TodoListPayload
    let size: CardSize
    let style: CardStyle

    public init(payload: TodoListPayload, size: CardSize, style: CardStyle) {
        self.payload = payload
        self.size = size
        self.style = style
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CardTypeBadge(type: .todoList)
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider()
                content
            }
            .frame(maxWidth: 560, alignment: .leading)
            Spacer(minLength: 0)
        }
        .cardChrome(size: size, style: style)
    }

    // MARK: - Checklist header (title + count) — gives the card a distinct
    // "to-do list" identity vs the other prose cards.

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Self.titleLabel)
                .font(AIDashTypography.section)
                .tracking(AIDashTypography.sectionTracking)
                .foregroundStyle(AIDashTypography.sectionColor)
                .textCase(.uppercase)
            Text("\(payload.items.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Size-driven content selection (geometry/density only)

    @ViewBuilder
    private var content: some View {
        switch size {
        case .small:
            smallContent
        case .medium:
            mediumContent
        case .wide:
            wideContent
        case .hero:
            heroContent
        }
    }

    // MARK: - Small: highest-priority item only

    @ViewBuilder
    private var smallContent: some View {
        if let item = itemsSortedByPriority.first {
            TodoItemRow(item: item, showDue: false)
        }
    }

    // MARK: - Medium: top 3 by priority

    @ViewBuilder
    private var mediumContent: some View {
        let top3 = Array(itemsSortedByPriority.prefix(3))
        ForEach(Array(top3.enumerated()), id: \.offset) { _, item in
            TodoItemRow(item: item, showDue: false)
        }
        if payload.items.count > 3 {
            Text("+\(payload.items.count - 3) more")
                .font(Self.recipe.secondary)
                .foregroundStyle(Self.recipe.secondaryColor)
        }
    }

    // MARK: - Wide: all items (payload order preserved)

    @ViewBuilder
    private var wideContent: some View {
        ForEach(Array(payload.items.enumerated()), id: \.offset) { _, item in
            TodoItemRow(item: item, showDue: true)
        }
    }

    // MARK: - Hero: all items with expanded due-date / ref panel (payload order preserved)

    @ViewBuilder
    private var heroContent: some View {
        ForEach(Array(payload.items.enumerated()), id: \.offset) { _, item in
            VStack(alignment: .leading, spacing: 4) {
                TodoItemRow(item: item, showDue: true)
                if let ref = item.ref {
                    Text(ref)
                        .font(Self.recipe.secondary)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Helpers

    static let recipe = AIDashTypography.detail(for: .todoList)

    private static let titleLabel = String(
        localized: "todo_list.title",
        defaultValue: "Tasks",
        bundle: .module,
        comment: "Header label at the top of a to-do list card, followed by the item count."
    )

    private var itemsSortedByPriority: [TodoListPayload.Item] {
        payload.items.sorted { lhs, rhs in
            priorityWeight(lhs.priority) > priorityWeight(rhs.priority)
        }
    }

    private func priorityWeight(_ priority: TodoListPayload.Item.Priority?) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case nil: return 0
        }
    }
}

// MARK: - TodoItemRow

private struct TodoItemRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.onToggleDone) private var onToggleDone
    @Environment(\.doneItemRefs) private var doneItemRefs
    @Environment(\.currentCardId) private var currentCardId
    let item: TodoListPayload.Item
    let showDue: Bool

    /// Optimistic toggle: the persisted done/undone event only flows back
    /// through `doneItemRefs` on the next SwiftData refresh, so the tap flips
    /// the glyph immediately (spec 005 US4: checked within 100ms).
    @State private var optimisticDone: Bool?

    private var itemRef: String { UserEvent.stableItemRef(for: item) }

    private var isDone: Bool {
        optimisticDone ?? doneItemRefs.contains(itemRef)
    }

    var body: some View {
        // The done toggle sits outside the combined accessibility element so
        // VoiceOver keeps it as its own actionable control (mirrors
        // `TrendingItemRow`'s star button in TrendingCardView.swift).
        HStack(spacing: 10) {
            doneToggle
            HStack(spacing: 10) {
                Text(item.title)
                    .font(TodoListCardView.recipe.primary)
                    .lineLimit(2)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                priorityPill
                Spacer(minLength: 8)
                if showDue, let due = item.due {
                    Text(due, style: .date)
                        .font(TodoListCardView.recipe.secondary)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // The completion circle: a real Button (not a static decoration) so a
    // tap toggles done state via the injected `onToggleDone` closure. Spec
    // 005 D3/D4 fixes what spec 003 shipped without wiring — the writer
    // method and latest-wins semantics already existed, but no view called
    // it. Degrades to a visual no-op when `onToggleDone` isn't injected
    // (previews, snapshots, tests), per constitution §D graceful degrade.
    private var doneToggle: some View {
        Button {
            let target = !isDone
            withAnimation(.snappy(duration: 0.2)) { optimisticDone = target }
            onToggleDone?(currentCardId, itemRef, target)
        } label: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.subheadline)
                .foregroundStyle(isDone ? theme.primary.primary : theme.neutrals.text3)
                .contentTransition(.symbolEffect(.replace))
                .frame(minWidth: AIDashSpacing.starButtonHitTarget,
                       minHeight: AIDashSpacing.starButtonHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? Self.doneLabel(item.title) : Self.notDoneLabel(item.title))
    }

    private static func doneLabel(_ title: String) -> String {
        String(
            localized: "todo_list.done_toggle.label.done \(title)",
            bundle: .module,
            comment: "VoiceOver label for a TodoList item's completion toggle when the item is marked done. The parameter is the item title."
        )
    }

    private static func notDoneLabel(_ title: String) -> String {
        String(
            localized: "todo_list.done_toggle.label.not_done \(title)",
            bundle: .module,
            comment: "VoiceOver label for a TodoList item's completion toggle when the item is not yet done. The parameter is the item title."
        )
    }

    /// Priority as a content-level status pill (§Content-Level Status Pills):
    /// high=danger, medium=warning, low=primary. A row with no priority
    /// renders no pill (pills reflect a payload value).
    @ViewBuilder
    private var priorityPill: some View {
        if let tone = priorityTone {
            StatusPill(priorityText, tone: tone)
                .accessibilityLabel(priorityLabel)
        }
    }

    private var priorityText: String {
        switch item.priority {
        case .high: return "High"
        case .medium: return "Med"
        case .low: return "Low"
        case nil: return ""
        }
    }

    private var priorityTone: PillTone? {
        switch item.priority {
        case .high: return .danger
        case .medium: return .warning
        case .low: return .primary
        case nil: return nil
        }
    }

    private var priorityLabel: String {
        switch item.priority {
        case .high: return "High priority"
        case .medium: return "Medium priority"
        case .low: return "Low priority"
        case nil: return "No priority"
        }
    }
}

// MARK: - Previews

#Preview("Small") {
    TodoListCardView(
        payload: TodoListPayload(items: [
            .init(title: "Review Atlas PRs", priority: .high),
            .init(title: "Update changelog", priority: .low),
            .init(title: "Reply to feedback", priority: .medium),
        ]),
        size: .small,
        style: .neutral
    )
    .padding()
}

#Preview("Medium") {
    TodoListCardView(
        payload: TodoListPayload(items: [
            .init(title: "Review Atlas PRs", priority: .high),
            .init(title: "Reply to performance review", priority: .medium, due: Date()),
            .init(title: "Update changelog", priority: .low),
            .init(title: "Plan Q3 priorities", priority: .medium),
        ]),
        size: .medium,
        style: .accent
    )
    .padding()
}

#Preview("Wide") {
    TodoListCardView(
        payload: TodoListPayload(items: [
            .init(title: "Review Atlas PRs from overnight", priority: .high),
            .init(title: "Reply to performance review feedback", priority: .medium, due: Date()),
            .init(title: "Update VitalStride changelog", priority: .low),
        ]),
        size: .wide,
        style: .success
    )
    .padding()
}

#Preview("Hero") {
    TodoListCardView(
        payload: TodoListPayload(items: [
            .init(title: "Review Atlas PRs", priority: .high, ref: "https://github.com/example/pr/4521"),
            .init(title: "Reply to performance review", priority: .medium, due: Date()),
            .init(title: "Update VitalStride changelog", priority: .low, ref: "https://github.com/example/issues/42"),
        ]),
        size: .hero,
        style: .warning
    )
    .padding()
}

// MARK: - Previews: done-toggle states (spec 005 D3/D4)

#Preview("Done toggle — not done (outline)") {
    let items = [TodoListPayload.Item(title: "Review Atlas PRs", priority: .high)]
    TodoListCardView(payload: TodoListPayload(items: items), size: .small, style: .neutral)
        .environment(\.onToggleDone) { _, _, _ in }
        .environment(\.doneItemRefs, [])
        .padding()
}

#Preview("Done toggle — done (checked)") {
    let items = [TodoListPayload.Item(title: "Review Atlas PRs", priority: .high)]
    TodoListCardView(payload: TodoListPayload(items: items), size: .small, style: .neutral)
        .environment(\.onToggleDone) { _, _, _ in }
        .environment(\.doneItemRefs, [UserEvent.stableItemRef(for: items[0])])
        .padding()
}
