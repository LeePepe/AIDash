import Testing
import Foundation
@testable import AIDashCore

@Suite("UserEventModel")
struct UserEventModelTests {
    @Test func initSetsAllProperties() {
        let id = UUID().uuidString
        let now = Date.now
        let event = UserEventModel(
            id: id,
            timestamp: now,
            device: "iPhone [12345678]",
            cardId: "card-abc",
            action: .done
        )

        #expect(event.id == id)
        #expect(event.timestamp == now)
        #expect(event.device == "iPhone [12345678]")
        #expect(event.cardId == "card-abc")
        #expect(event.actionRaw == "done")
    }

    @Test func actionReturnsTypedEnum() {
        let event = UserEventModel(
            id: UUID().uuidString,
            timestamp: .now,
            device: "iPhone [12345678]",
            cardId: "card-123",
            action: .done
        )
        #expect(event.action == .done)

        let starEvent = UserEventModel(
            id: UUID().uuidString,
            timestamp: .now,
            device: "iPad [AABBCCDD]",
            cardId: "card-456",
            action: .star
        )
        #expect(starEvent.action == .star)
    }

    @Test func actionReturnsNilForUnknownRawValue() {
        let event = UserEventModel(
            id: UUID().uuidString,
            timestamp: .now,
            device: "iPhone [12345678]",
            cardId: "card-789",
            action: .done
        )
        // Simulate a future/malformed value from CloudKit
        event.actionRaw = "unknownFutureAction"
        #expect(event.action == nil)
    }

    // MARK: - itemRef (spec 002 D1 / T001)

    @Test func itemRefDefaultsToNil() {
        let event = UserEventModel(
            id: UUID().uuidString,
            timestamp: .now,
            device: "Mac [ABCDEF]",
            cardId: "card-plain",
            action: .done
        )
        #expect(event.itemRef == nil)
    }

    @Test func itemRefIsPersistedWhenProvided() {
        let event = UserEventModel(
            id: UUID().uuidString,
            timestamp: .now,
            device: "Mac [ABCDEF]",
            cardId: "radar-card-1",
            action: .star,
            itemRef: "https://github.com/vapor/vapor"
        )
        #expect(event.itemRef == "https://github.com/vapor/vapor")
        #expect(event.actionRaw == "star")
    }

    // MARK: - UserEvent.star factory (T001)

    @Test func starFactoryProducesItemLevelStarEvent() {
        let before = Date()
        let event = UserEvent.star(
            cardId: "radar-card-1",
            itemRef: "https://github.com/apple/swift",
            device: "Mac [12345678]"
        )
        let after = Date()

        #expect(event.action == .star)
        #expect(event.cardId == "radar-card-1")
        #expect(event.itemRef == "https://github.com/apple/swift")
        #expect(event.device == "Mac [12345678]")
        #expect(!event.id.isEmpty)
        #expect(UUID(uuidString: event.id) != nil)
        #expect(event.timestamp >= before && event.timestamp <= after)
    }

    @Test func starFactoryMintsUniqueIDs() {
        let a = UserEvent.star(cardId: "c", itemRef: "https://x", device: "d")
        let b = UserEvent.star(cardId: "c", itemRef: "https://x", device: "d")
        #expect(a.id != b.id)
    }
}
