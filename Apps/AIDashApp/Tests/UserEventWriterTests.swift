#if os(macOS)
import Testing
import Foundation
import SwiftData
@testable import AIDashApp
import AIDashCore

/// Tests for the App layer's star write path (spec 002, US1/D2): each star
/// tap appends exactly one `UserEventModel`, repeated stars are idempotent,
/// and nothing ever mutates existing rows.
@MainActor
@Suite("UserEventWriter (spec 002 star write path)")
struct UserEventWriterTests {

    private func makeWriter() throws -> (UserEventWriter, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: BriefingModel.self,
            ContainerModel.self,
            CardModel.self,
            UserEventModel.self,
            configurations: config
        )
        return (UserEventWriter(container: container), container)
    }

    private func fetchEvents(_ container: ModelContainer) throws -> [UserEventModel] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<UserEventModel>())
    }

    @Test("star appends one UserEventModel with action=star, itemRef, device")
    func starAppendsEvent() async throws {
        let (writer, container) = try makeWriter()
        let repoURL = "https://github.com/TauricResearch/TradingAgents"

        writer.star(cardId: "radar-card-1", itemRef: repoURL)

        let events = try fetchEvents(container)
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.action == .star)
        #expect(event.cardId == "radar-card-1")
        #expect(event.itemRef == repoURL)
        #expect(!event.id.isEmpty)
        #expect(!event.device.isEmpty)
    }

    @Test("repeated star for the same cardId+itemRef is idempotent (D2)")
    func repeatedStarIsIdempotent() async throws {
        let (writer, container) = try makeWriter()
        let repoURL = "https://github.com/a/b"

        writer.star(cardId: "radar-card-1", itemRef: repoURL)
        writer.star(cardId: "radar-card-1", itemRef: repoURL)

        #expect(try fetchEvents(container).count == 1)
    }

    @Test("same itemRef under a different card still appends")
    func sameItemDifferentCardAppends() async throws {
        let (writer, container) = try makeWriter()
        let repoURL = "https://github.com/a/b"

        writer.star(cardId: "radar-card-1", itemRef: repoURL)
        writer.star(cardId: "radar-card-2", itemRef: repoURL)

        #expect(try fetchEvents(container).count == 2)
    }

    // MARK: - Done write path (MY-1309 / T002)

    @Test("done appends one UserEventModel with action=done, itemRef, device")
    func doneAppendsEvent() async throws {
        let (writer, container) = try makeWriter()
        let ref = "title:abc123"

        writer.done(cardId: "todo-card-1", itemRef: ref)

        let events = try fetchEvents(container)
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.action == .done)
        #expect(event.cardId == "todo-card-1")
        #expect(event.itemRef == ref)
        #expect(!event.id.isEmpty)
        #expect(!event.device.isEmpty)
    }

    @Test("done is a toggle — repeated taps append additional rows (not idempotent)")
    func doneToggleAppendsEachTap() async throws {
        let (writer, container) = try makeWriter()
        let ref = "title:abc123"

        writer.done(cardId: "todo-card-1", itemRef: ref)
        writer.done(cardId: "todo-card-1", itemRef: ref)

        #expect(try fetchEvents(container).count == 2)
    }

    // MARK: - Done inference (doneItemRefs)

    @Test("doneItemRefs infers checked set from odd-count of .done events per itemRef")
    func doneItemRefsInfersOddCounts() async throws {
        let (writer, container) = try makeWriter()

        // Item A: 1x done -> checked
        writer.done(cardId: "todo-card-1", itemRef: "title:a")
        // Item B: 2x done -> unchecked (toggled back off)
        writer.done(cardId: "todo-card-1", itemRef: "title:b")
        writer.done(cardId: "todo-card-1", itemRef: "title:b")
        // Item C: 3x done -> checked again
        writer.done(cardId: "todo-card-1", itemRef: "title:c")
        writer.done(cardId: "todo-card-1", itemRef: "title:c")
        writer.done(cardId: "todo-card-1", itemRef: "title:c")

        let events = try fetchEvents(container)
        let checked = UserEventWriter.doneItemRefs(cardId: "todo-card-1", in: events)

        #expect(checked == ["title:a", "title:c"])
    }

    @Test("doneItemRefs is scoped by cardId — other cards' events are ignored")
    func doneItemRefsScopedByCardId() async throws {
        let (writer, container) = try makeWriter()

        writer.done(cardId: "todo-card-1", itemRef: "title:a")
        writer.done(cardId: "todo-card-2", itemRef: "title:a")

        let events = try fetchEvents(container)
        let checkedCard1 = UserEventWriter.doneItemRefs(cardId: "todo-card-1", in: events)
        let checkedCard2 = UserEventWriter.doneItemRefs(cardId: "todo-card-2", in: events)

        #expect(checkedCard1 == ["title:a"])
        #expect(checkedCard2 == ["title:a"])
    }

    @Test("doneItemRefs ignores non-done actions and nil itemRefs")
    func doneItemRefsIgnoresIrrelevantEvents() async throws {
        let (writer, container) = try makeWriter()

        // A star event on the same card — must be ignored.
        writer.star(cardId: "todo-card-1", itemRef: "title:a")
        // A real done event.
        writer.done(cardId: "todo-card-1", itemRef: "title:b")

        // Inject a nil-itemRef done event directly (whole-card, which no
        // caller emits today but the helper must stay defensive).
        let ctx = ModelContext(container)
        ctx.insert(UserEventModel(
            id: UUID().uuidString,
            timestamp: Date(),
            device: "test-device",
            cardId: "todo-card-1",
            action: .done,
            itemRef: nil
        ))
        try ctx.save()

        let events = try fetchEvents(container)
        let checked = UserEventWriter.doneItemRefs(cardId: "todo-card-1", in: events)

        #expect(checked == ["title:b"])
    }

    @Test("doneItemRefs returns empty when no matching events exist")
    func doneItemRefsEmpty() async throws {
        let (_, container) = try makeWriter()
        let events = try fetchEvents(container)
        let checked = UserEventWriter.doneItemRefs(cardId: "todo-card-1", in: events)
        #expect(checked.isEmpty)
    }
}
#endif
