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
}
#endif
