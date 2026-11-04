import Testing
import Foundation
@testable import AIDashCore

@Suite("Enum Codable roundtrip")
struct EnumRoundtripTests {
    @Test(arguments: CardType.allCases)
    func cardTypeRoundtrip(_ value: CardType) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(CardType.self, from: data)
        #expect(decoded == value)
        #expect(decoded.rawValue == value.rawValue)
    }

    @Test(arguments: CardSize.allCases)
    func cardSizeRoundtrip(_ value: CardSize) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(CardSize.self, from: data)
        #expect(decoded == value)
        #expect(decoded.rawValue == value.rawValue)
    }

    @Test(arguments: CardStyle.allCases)
    func cardStyleRoundtrip(_ value: CardStyle) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(CardStyle.self, from: data)
        #expect(decoded == value)
        #expect(decoded.rawValue == value.rawValue)
    }

    @Test(arguments: ContainerLayout.allCases)
    func containerLayoutRoundtrip(_ value: ContainerLayout) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(ContainerLayout.self, from: data)
        #expect(decoded == value)
        #expect(decoded.rawValue == value.rawValue)
    }

    @Test(arguments: UserEventAction.allCases)
    func userEventActionRoundtrip(_ value: UserEventAction) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(UserEventAction.self, from: data)
        #expect(decoded == value)
        #expect(decoded.rawValue == value.rawValue)
    }

    @Test func userEventActionRawValuesRemainStable() {
        #expect(UserEventAction.allCases.map(\.rawValue) == [
            "done",
            "star",
            "undone",
            "hide",
            "unhide",
            "acknowledgeFinding",
            "approveRemediation"
        ])
    }

    @Test func cardTypeCount() {
        // Deliberate tripwire: adding a CardType obliges the downstream layers
        // (DesignKit classification, AIDashUI badge + router, XPC schema ad) to
        // follow. Bump this only alongside those.
        #expect(CardType.allCases.count == 10)
    }

    @Test func relationshipVisualizationRoundtrip() throws {
        for value in RelationshipVisualization.allCases {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(RelationshipVisualization.self, from: data)
            #expect(decoded == value)
            #expect(decoded.rawValue == value.rawValue)
        }
        #expect(RelationshipVisualization.allCases.count == 3)
    }

}
