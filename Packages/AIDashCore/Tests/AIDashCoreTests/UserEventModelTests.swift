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
}
