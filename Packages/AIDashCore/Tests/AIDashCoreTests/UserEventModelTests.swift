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

    // MARK: - UserEvent.done factory (MY-1308 / T001)

    @Test func doneFactoryProducesItemLevelDoneEvent() {
        let before = Date()
        let event = UserEvent.done(
            cardId: "todo-card-today",
            itemRef: "https://github.com/foo/bar/issues/42",
            device: "Mac [12345678]"
        )
        let after = Date()

        #expect(event.action == .done)
        #expect(event.cardId == "todo-card-today")
        #expect(event.itemRef == "https://github.com/foo/bar/issues/42")
        #expect(event.device == "Mac [12345678]")
        #expect(!event.id.isEmpty)
        #expect(UUID(uuidString: event.id) != nil)
        #expect(event.timestamp >= before && event.timestamp <= after)
    }

    @Test func doneFactoryMintsUniqueIDs() {
        let a = UserEvent.done(cardId: "c", itemRef: "x", device: "d")
        let b = UserEvent.done(cardId: "c", itemRef: "x", device: "d")
        #expect(a.id != b.id)
    }

    // MARK: - UserEvent.stableItemRef helper (MY-1308 / T001)

    @Test func stableItemRefPrefersExplicitRef() {
        let item = TodoListPayload.Item(
            title: "Review PR #42",
            ref: "https://github.com/foo/bar/pull/42"
        )
        #expect(
            UserEvent.stableItemRef(for: item)
                == "https://github.com/foo/bar/pull/42"
        )
    }

    @Test func stableItemRefTrimsExplicitRefWhitespace() {
        let item = TodoListPayload.Item(
            title: "anything",
            ref: "  https://example.com/x  "
        )
        #expect(UserEvent.stableItemRef(for: item) == "https://example.com/x")
    }

    @Test func stableItemRefFallsBackToTitleHashWhenRefIsNil() {
        let item = TodoListPayload.Item(title: "Ship the release notes")
        let ref = UserEvent.stableItemRef(for: item)
        #expect(ref.hasPrefix("title:"))
        // SHA256 hex = 64 chars → total prefix + hex = 70
        #expect(ref.count == "title:".count + 64)
    }

    @Test func stableItemRefFallsBackToTitleHashWhenRefIsEmpty() {
        let item = TodoListPayload.Item(title: "Ship the release notes", ref: "")
        let ref = UserEvent.stableItemRef(for: item)
        #expect(ref.hasPrefix("title:"))
    }

    @Test func stableItemRefFallsBackToTitleHashWhenRefIsWhitespaceOnly() {
        let item = TodoListPayload.Item(title: "Ship the release notes", ref: "   ")
        let ref = UserEvent.stableItemRef(for: item)
        #expect(ref.hasPrefix("title:"))
    }

    @Test func stableItemRefIsStableAcrossIdenticalTitles() {
        let a = TodoListPayload.Item(title: "Review PR #42")
        let b = TodoListPayload.Item(title: "Review PR #42")
        #expect(UserEvent.stableItemRef(for: a) == UserEvent.stableItemRef(for: b))
    }

    @Test func stableItemRefNormalizesWhitespaceAndCase() {
        // Different casing, leading/trailing whitespace, and collapsed internal
        // whitespace must all collapse to the same itemRef.
        let a = TodoListPayload.Item(title: "Review PR #42")
        let b = TodoListPayload.Item(title: "  review   pr #42  ")
        let c = TodoListPayload.Item(title: "REVIEW\tPR\n#42")
        #expect(UserEvent.stableItemRef(for: a) == UserEvent.stableItemRef(for: b))
        #expect(UserEvent.stableItemRef(for: a) == UserEvent.stableItemRef(for: c))
    }

    @Test func stableItemRefDiffersForDifferentTitles() {
        let a = TodoListPayload.Item(title: "Review PR #42")
        let b = TodoListPayload.Item(title: "Review PR #43")
        #expect(UserEvent.stableItemRef(for: a) != UserEvent.stableItemRef(for: b))
    }

    @Test func stableItemRefPrefersRefEvenWhenBothPresent() {
        let item = TodoListPayload.Item(
            title: "Review PR #42",
            ref: "https://github.com/foo/bar/pull/42"
        )
        // Explicit ref wins over title-derived hash.
        #expect(UserEvent.stableItemRef(for: item).hasPrefix("title:") == false)
        #expect(
            UserEvent.stableItemRef(for: item)
                == "https://github.com/foo/bar/pull/42"
        )
    }

    @Test func stableItemRefHandlesEmptyTitleDeterministically() {
        let a = TodoListPayload.Item(title: "")
        let b = TodoListPayload.Item(title: "   \t\n  ")
        // Both normalize to empty; hashes match.
        #expect(UserEvent.stableItemRef(for: a) == UserEvent.stableItemRef(for: b))
        #expect(UserEvent.stableItemRef(for: a).hasPrefix("title:"))
    }
}
