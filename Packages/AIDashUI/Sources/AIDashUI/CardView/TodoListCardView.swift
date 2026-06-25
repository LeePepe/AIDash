import SwiftUI
import AIDashCore

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
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundTint, in: RoundedRectangle(cornerRadius: 12))
    }

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
        HStack {
            Text("\(payload.items.count)")
                .font(.title2)
                .fontWeight(.bold)
            Text("items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                .font(.caption)
                .foregroundStyle(.secondary)
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
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Helpers

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

    private var backgroundTint: Color {
        switch style {
        case .neutral: return Color.clear
        case .success: return Color.green.opacity(0.08)
        case .warning: return Color.orange.opacity(0.08)
        case .accent: return Color.accentColor.opacity(0.10)
        }
    }
}

// MARK: - TodoItemRow

private struct TodoItemRow: View {
    let item: TodoListPayload.Item
    let showDue: Bool

    var body: some View {
        HStack(spacing: 8) {
            priorityIndicator
            Text(item.title)
                .font(.subheadline)
                .lineLimit(2)
            Spacer()
            if showDue, let due = item.due {
                Text(due, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var priorityIndicator: some View {
        Circle()
            .fill(priorityColor)
            .frame(width: 8, height: 8)
            .accessibilityLabel(priorityLabel)
    }

    private var priorityLabel: String {
        switch item.priority {
        case .high: return "High priority"
        case .medium: return "Medium priority"
        case .low: return "Low priority"
        case nil: return "No priority"
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        case nil: return .gray
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
