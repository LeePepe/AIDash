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

    // MARK: - Spec 005 D2/D5: cardType round-trip

    @Test("events.pull maps cardType back into UserEvent for a whole-card star event")
    func cardTypeSurvivesRoundTrip() async throws {
        // Regression guard for the gap this task closed: handleEventsPull's
        // UserEvent(...) construction previously omitted `cardType`, so it
        // was persisted (UserEventModel.cardType) but never reached the wire
        // format `aidash events pull` consumers read — the whole-card star
        // event would have been indistinguishable from a per-item one with a
        // dropped itemRef. See XPCHandlers.swift `handleEventsPull`.
        let (handlers, container) = try XPCTestSupport.makeHandlersWithContainer()
        let context = ModelContext(container)
        context.insert(UserEventModel(
            id: UUID().uuidString,
            timestamp: Date(),
            device: "test-device",
            cardId: "trending-card-1",
            action: .star,
            itemRef: nil,
            cardType: "trending"
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
        #expect(event.itemRef == nil)
        #expect(event.cardType == "trending")
    }

    @Test("events.pull keeps cardType nil for events written before the field existed")
    func legacyEventKeepsNilCardType() async throws {
        let (handlers, container) = try XPCTestSupport.makeHandlersWithContainer()
        let context = ModelContext(container)
        context.insert(UserEventModel(
            id: UUID().uuidString,
            timestamp: Date(),
            device: "test-device",
            cardId: "radar-card-1",
            action: .star,
            itemRef: "https://github.com/a/b"
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
        #expect(event.cardType == nil)
    }
}
#endif
