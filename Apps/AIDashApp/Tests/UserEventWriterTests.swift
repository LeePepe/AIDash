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

    // MARK: - Done write path (MY-1372 / T102, latest-wins)

    @Test("setDone(done:true) appends one UserEventModel with action=done, itemRef, device")
    func setDoneTrueAppendsDoneEvent() async throws {
        let (writer, container) = try makeWriter()
        let ref = "title:abc123"

        writer.setDone(cardId: "todo-card-1", itemRef: ref, done: true)

        let events = try fetchEvents(container)
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.action == .done)
        #expect(event.cardId == "todo-card-1")
        #expect(event.itemRef == ref)
        #expect(!event.id.isEmpty)
        #expect(!event.device.isEmpty)
    }

    @Test("setDone(done:false) appends one UserEventModel with action=undone")
    func setDoneFalseAppendsUndoneEvent() async throws {
        let (writer, container) = try makeWriter()
        let ref = "title:abc123"

        writer.setDone(cardId: "todo-card-1", itemRef: ref, done: false)

        let events = try fetchEvents(container)
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.action == .undone)
        #expect(event.cardId == "todo-card-1")
        #expect(event.itemRef == ref)
        #expect(!event.id.isEmpty)
        #expect(!event.device.isEmpty)
    }

    @Test("setDone never dedups — repeated same-state taps append additional rows")
    func setDoneNeverDedups() async throws {
        let (writer, container) = try makeWriter()
        let ref = "title:abc123"

        writer.setDone(cardId: "todo-card-1", itemRef: ref, done: true)
        writer.setDone(cardId: "todo-card-1", itemRef: ref, done: true)
        writer.setDone(cardId: "todo-card-1", itemRef: ref, done: false)

        #expect(try fetchEvents(container).count == 3)
    }

    // MARK: - Done latest-wins inference (doneRefs)

    /// Helper: manually build a `UserEventModel` with an explicit timestamp so
    /// the latest-wins tests can control event ordering deterministically
    /// (the real writer uses `Date()`, which serialises taps too closely to
    /// distinguish reliably in a fast test).
    private func insertEvent(
        _ container: ModelContainer,
        cardId: String,
        itemRef: String?,
        action: UserEventAction,
        timestamp: Date,
        id: String = UUID().uuidString,
        device: String = "test-device"
    ) throws {
        let ctx = ModelContext(container)
        ctx.insert(UserEventModel(
            id: id,
            timestamp: timestamp,
            device: device,
            cardId: cardId,
            action: action,
            itemRef: itemRef
        ))
        try ctx.save()
    }

    @Test("doneRefs latest-wins: done then undone -> ref NOT in set")
    func doneRefsLatestWinsDoneThenUndone() async throws {
        let (_, container) = try makeWriter()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        try insertEvent(container, cardId: "c", itemRef: "title:a",
                        action: .done, timestamp: t0)
        try insertEvent(container, cardId: "c", itemRef: "title:a",
                        action: .undone, timestamp: t0.addingTimeInterval(1))

        let events = try fetchEvents(container)
        let refs = UserEventWriter.doneRefs(from: events)
        #expect(refs.isEmpty)
    }

    @Test("doneRefs latest-wins: undone then done -> ref IN set")
    func doneRefsLatestWinsUndoneThenDone() async throws {
        let (_, container) = try makeWriter()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        try insertEvent(container, cardId: "c", itemRef: "title:a",
                        action: .undone, timestamp: t0)
        try insertEvent(container, cardId: "c", itemRef: "title:a",
                        action: .done, timestamp: t0.addingTimeInterval(1))

        let events = try fetchEvents(container)
        let refs = UserEventWriter.doneRefs(from: events)
        #expect(refs == ["title:a"])
    }

    @Test("doneRefs cross-device: two .done events on same ref stay done (do NOT cancel)")
    func doneRefsCrossDeviceTwoDonesStayDone() async throws {
        let (_, container) = try makeWriter()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        try insertEvent(container, cardId: "c", itemRef: "title:a",
                        action: .done, timestamp: t0,
                        device: "device-A")
        try insertEvent(container, cardId: "c", itemRef: "title:a",
                        action: .done, timestamp: t0.addingTimeInterval(5),
                        device: "device-B")

        let events = try fetchEvents(container)
        let refs = UserEventWriter.doneRefs(from: events)
        #expect(refs == ["title:a"])
    }

    @Test("doneRefs mixes items independently — some done, some undone, some untouched")
    func doneRefsMixedItems() async throws {
        let (_, container) = try makeWriter()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // a: done -> checked
        try insertEvent(container, cardId: "c", itemRef: "title:a",
                        action: .done, timestamp: t0)
        // b: done -> undone -> unchecked
        try insertEvent(container, cardId: "c", itemRef: "title:b",
                        action: .done, timestamp: t0)
        try insertEvent(container, cardId: "c", itemRef: "title:b",
                        action: .undone, timestamp: t0.addingTimeInterval(1))
        // c: undone alone -> unchecked
        try insertEvent(container, cardId: "c", itemRef: "title:c",
                        action: .undone, timestamp: t0)
        // d: done -> undone -> done -> checked
        try insertEvent(container, cardId: "c", itemRef: "title:d",
                        action: .done, timestamp: t0)
        try insertEvent(container, cardId: "c", itemRef: "title:d",
                        action: .undone, timestamp: t0.addingTimeInterval(1))
        try insertEvent(container, cardId: "c", itemRef: "title:d",
                        action: .done, timestamp: t0.addingTimeInterval(2))

        let events = try fetchEvents(container)
        let refs = UserEventWriter.doneRefs(from: events)
        #expect(refs == ["title:a", "title:d"])
    }

    @Test("doneRefs ignores non-done/undone actions and nil itemRefs")
    func doneRefsIgnoresIrrelevantEvents() async throws {
        let (_, container) = try makeWriter()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // A star event — must be ignored.
        try insertEvent(container, cardId: "c", itemRef: "title:a",
                        action: .star, timestamp: t0)
        // A real done event.
        try insertEvent(container, cardId: "c", itemRef: "title:b",
                        action: .done, timestamp: t0)
        // A nil-itemRef done event — must be ignored (whole-card, no caller
        // emits today but the helper must stay defensive).
        try insertEvent(container, cardId: "c", itemRef: nil,
                        action: .done, timestamp: t0)

        let events = try fetchEvents(container)
        let refs = UserEventWriter.doneRefs(from: events)
        #expect(refs == ["title:b"])
    }

    @Test("doneRefs returns empty when no matching events exist")
    func doneRefsEmpty() async throws {
        let (_, container) = try makeWriter()
        let events = try fetchEvents(container)
        let refs = UserEventWriter.doneRefs(from: events)
        #expect(refs.isEmpty)
    }

    @Test("doneRefs same-timestamp tie: larger id wins (deterministic)")
    func doneRefsSameTimestampTiebreak() async throws {
        let (_, container) = try makeWriter()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // Two events at the identical timestamp; the lexicographic-larger id
        // (a `.undone`) must win, so the ref is NOT in the set.
        try insertEvent(container, cardId: "c", itemRef: "title:a",
                        action: .done, timestamp: t0,
                        id: "00000000-0000-0000-0000-000000000001")
        try insertEvent(container, cardId: "c", itemRef: "title:a",
                        action: .undone, timestamp: t0,
                        id: "ffffffff-ffff-ffff-ffff-ffffffffffff")

        let events = try fetchEvents(container)
        let refs = UserEventWriter.doneRefs(from: events)
        #expect(refs.isEmpty)
    }

    // MARK: - Whole-card star write path (spec 005 D1/D2/D3)

    @Test("star(cardId:itemRef:nil:cardType:) appends one row with action=star, itemRef=nil, cardType")
    func wholeCardStarAppendsEvent() async throws {
        let (writer, container) = try makeWriter()

        writer.star(cardId: "trending-card-1", itemRef: nil, cardType: "trending")

        let events = try fetchEvents(container)
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.action == .star)
        #expect(event.cardId == "trending-card-1")
        #expect(event.itemRef == nil)
        #expect(event.cardType == "trending")
        #expect(!event.id.isEmpty)
        #expect(!event.device.isEmpty)
    }

    @Test("repeated whole-card star for the same cardId+cardType is idempotent")
    func repeatedWholeCardStarIsIdempotent() async throws {
        let (writer, container) = try makeWriter()

        writer.star(cardId: "trending-card-1", itemRef: nil, cardType: "trending")
        writer.star(cardId: "trending-card-1", itemRef: nil, cardType: "trending")

        #expect(try fetchEvents(container).count == 1)
    }

    @Test("whole-card star under a different card still appends")
    func wholeCardStarDifferentCardAppends() async throws {
        let (writer, container) = try makeWriter()

        writer.star(cardId: "trending-card-1", itemRef: nil, cardType: "trending")
        writer.star(cardId: "trending-card-2", itemRef: nil, cardType: "trending")

        #expect(try fetchEvents(container).count == 2)
    }

    @Test("whole-card star and per-item star on the same card coexist as separate rows")
    func wholeCardStarAndItemStarCoexist() async throws {
        let (writer, container) = try makeWriter()
        let repoURL = "https://github.com/a/b"

        writer.star(cardId: "trending-card-1", itemRef: repoURL)
        writer.star(cardId: "trending-card-1", itemRef: nil, cardType: "trending")

        let events = try fetchEvents(container)
        #expect(events.count == 2)
        #expect(events.contains { $0.itemRef == repoURL })
        #expect(events.contains { $0.itemRef == nil && $0.cardType == "trending" })
    }

    @Test("star(cardId:itemRef:cardType:) with a non-nil itemRef routes to the existing per-item star path")
    func starWithNonNilItemRefRoutesToPerItemPath() async throws {
        // Confirms the 3-argument overload doesn't silently discard a caller's
        // per-item intent if it's ever invoked with itemRef != nil — it must
        // behave identically to calling `star(cardId:itemRef:)` directly,
        // including the itemRef-scoped dedup (not the cardType-scoped one).
        let (writer, container) = try makeWriter()
        let repoURL = "https://github.com/a/b"

        writer.star(cardId: "radar-card-1", itemRef: repoURL, cardType: "trending")

        let events = try fetchEvents(container)
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.itemRef == repoURL)
        #expect(event.cardType == nil) // per-item star path never sets cardType
    }
}
#endif
