import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("TodoListCardView Tests")
struct TodoListCardViewTests {
    private let sampleItems: [TodoListPayload.Item] = [
        .init(title: "High priority task", priority: .high),
        .init(title: "Medium priority task", priority: .medium, due: Date()),
        .init(title: "Low priority task", priority: .low),
        .init(title: "No priority task"),
    ]

    @Test("initializes with correct payload, size, and style")
    func initializesCorrectly() {
        let payload = TodoListPayload(items: sampleItems)
        let view = TodoListCardView(payload: payload, size: .medium, style: .accent)

        #expect(view.payload.items.count == 4)
        #expect(view.size == .medium)
        #expect(view.style == .accent)
    }

    @Test("accepts all card sizes", arguments: CardSize.allCases)
    func acceptsAllSizes(size: CardSize) {
        let payload = TodoListPayload(items: [.init(title: "Task", priority: .high)])
        let view = TodoListCardView(payload: payload, size: size, style: .neutral)

        #expect(view.size == size)
    }

    @Test("accepts all card styles", arguments: CardStyle.allCases)
    func acceptsAllStyles(style: CardStyle) {
        let payload = TodoListPayload(items: [.init(title: "Task", priority: .low)])
        let view = TodoListCardView(payload: payload, size: .wide, style: style)

        #expect(view.style == style)
    }

    @Test("preserves payload items")
    func preservesPayloadItems() {
        let payload = TodoListPayload(items: sampleItems)
        let view = TodoListCardView(payload: payload, size: .hero, style: .success)

        #expect(view.payload.items.count == 4)
        #expect(view.payload.items[0].title == "High priority task")
        #expect(view.payload.items[0].priority == .high)
        #expect(view.payload.items[2].priority == .low)
    }
}
