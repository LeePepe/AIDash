#if os(macOS)
import Testing
import Foundation
import SwiftData
@testable import AIDashApp
import AIDashCore

/// Regression tests for the events.pull handler (spec 002, star feedback
/// loop). The handler maps persisted `UserEventModel` rows back to the
/// `UserEvent` contract — it once dropped `itemRef`, which would have
/// silently broken the star signal's repo-URL identity for `aidash events
/// pull` consumers. See ``XPCTestSupport`` for the shared fixture.
@MainActor
@Suite("XPCHandlers events.pull")
struct XPCHandlersEventsPullTests {

    @Test("events.pull maps itemRef back into UserEvent (regression)")
    func itemRefSurvivesRoundTrip() async throws {
        let (handlers, container) = try XPCTestSupport.makeHandlersWithContainer()
        let repoURL = "https://github.com/VoltAgent/awesome-design-md"
        let context = ModelContext(container)
        context.insert(UserEventModel(
            id: UUID().uuidString,
            timestamp: Date(),
            device: "test-device",
            cardId: "radar-card-1",
            action: .star,
            itemRef: repoURL
        ))
        try context.save()

        let response = try await XPCTestSupport.send(
            handlers,
            command: "events.pull",
            params: EventsPullParams(since: .distantPast, until: nil, cardId: nil, action: nil)
        )

        #expect(response.ok == true)
        let result = try XPCTestSupport.decodeResult(EventsPullResult.self, from: response)
        let event = try #require(result.events.first)
        #expect(result.events.count == 1)
        #expect(event.action == .star)
        #expect(event.cardId == "radar-card-1")
        #expect(event.itemRef == repoURL)
    }

    @Test("events.pull filters by itemRef when provided")
    func filtersByItemRef() async throws {
        let (handlers, container) = try XPCTestSupport.makeHandlersWithContainer()
        let target = "https://github.com/a/b"
        let context = ModelContext(container)
        for ref in [target, "https://github.com/c/d"] {
            context.insert(UserEventModel(
                id: UUID().uuidString,
                timestamp: Date(),
                device: "test-device",
                cardId: "radar-card-1",
                action: .star,
                itemRef: ref
            ))
        }
        try context.save()

        let response = try await XPCTestSupport.send(
            handlers,
            command: "events.pull",
            params: EventsPullParams(
                since: .distantPast, until: nil, cardId: nil,
                action: .star, itemRef: target
            )
        )

        #expect(response.ok == true)
        let result = try XPCTestSupport.decodeResult(EventsPullResult.self, from: response)
        #expect(result.events.count == 1)
        #expect(result.events.first?.itemRef == target)
    }

    @Test("events.pull keeps itemRef nil for whole-card events")
    func wholeCardEventKeepsNilItemRef() async throws {
        let (handlers, container) = try XPCTestSupport.makeHandlersWithContainer()
        let context = ModelContext(container)
        context.insert(UserEventModel(
            id: UUID().uuidString,
            timestamp: Date(),
            device: "test-device",
            cardId: "digest-card-1",
            action: .done
        ))
        try context.save()

        let response = try await XPCTestSupport.send(
            handlers,
            command: "events.pull",
            params: EventsPullParams(since: .distantPast, until: nil, cardId: nil, action: nil)
        )

        #expect(response.ok == true)
        let result = try XPCTestSupport.decodeResult(EventsPullResult.self, from: response)
        let event = try #require(result.events.first)
        #expect(event.itemRef == nil)
    }
}
#endif
