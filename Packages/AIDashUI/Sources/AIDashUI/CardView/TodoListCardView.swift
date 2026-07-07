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
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome(size: size, style: style)
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

    // MARK: - Small: count + highest-priority item title

    @ViewBuilder
    private var smallContent: some View {
        let highestPriority = itemsSortedByPriority.first
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(payload.items.count)")
                .font(Self.recipe.primary)
                .fontWeight(.semibold)
            Text("items")
                .font(Self.recipe.secondary)
                .foregroundStyle(Self.recipe.secondaryColor)
        }
        .accessibilityElement(children: .combine)
        if let item = highestPriority {
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
    let item: TodoListPayload.Item
    let showDue: Bool

    var body: some View {
        HStack(spacing: 8) {
            priorityPill
            Text(item.title)
                .font(TodoListCardView.recipe.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if showDue, let due = item.due {
                Text(due, style: .date)
                    .font(TodoListCardView.recipe.secondary)
                    .foregroundStyle(TodoListCardView.recipe.secondaryColor)
            }
        }
        .accessibilityElement(children: .combine)
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
            .init(title: "Review Sapphire PRs", priority: .high),
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
            .init(title: "Review Sapphire PRs", priority: .high),
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
            .init(title: "Review Sapphire PRs from overnight", priority: .high),
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
            .init(title: "Review Sapphire PRs", priority: .high, ref: "https://github.com/example/pr/4521"),
            .init(title: "Reply to performance review", priority: .medium, due: Date()),
            .init(title: "Update VitalStride changelog", priority: .low, ref: "https://github.com/example/issues/42"),
        ]),
        size: .hero,
        style: .warning
    )
    .padding()
}
