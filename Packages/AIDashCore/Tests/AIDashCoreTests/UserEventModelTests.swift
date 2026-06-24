import Testing
import Foundation
@testable import AIDashCore

@Suite("UserEventModel")
struct UserEventModelTests {

    @Test("init stores fields correctly")
    func initStoresFields() {
        let id = UUID().uuidString
        let now = Date.now
        let event = UserEventModel(
            id: id, timestamp: now, device: "iPhone [12345678]",
            cardId: "card-1", action: .done
        )

        #expect(event.id == id)
        #expect(event.timestamp == now)
        #expect(event.device == "iPhone [12345678]")
        #expect(event.cardId == "card-1")
        #expect(event.actionRaw == "done")
    }

    @Test("action computed property returns typed enum")
    func actionRoundTrip() {
        let event = UserEventModel(
            id: UUID().uuidString, timestamp: .now,
            device: "iPhone [12345678]", cardId: "card-1", action: .done
        )
        #expect(event.action == .done)

        let starEvent = UserEventModel(
            id: UUID().uuidString, timestamp: .now,
            device: "iPad [ABCDEF01]", cardId: "card-2", action: .star
        )
        #expect(starEvent.action == .star)
    }

    @Test("action returns nil for unknown raw value")
    func actionUnknownRawValue() {
        let event = UserEventModel(
            id: UUID().uuidString, timestamp: .now,
            device: "iPhone [12345678]", cardId: "card-1", action: .done
        )
        // Simulate a future/malformed value written by CloudKit sync
        event.actionRaw = "unknown_future_action"
        #expect(event.action == nil)
    }
}
