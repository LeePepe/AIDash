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
    }

    @Test(arguments: CardStyle.allCases)
    func cardStyleRoundtrip(_ value: CardStyle) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(CardStyle.self, from: data)
        #expect(decoded == value)
    }

    @Test(arguments: ContainerLayout.allCases)
    func containerLayoutRoundtrip(_ value: ContainerLayout) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(ContainerLayout.self, from: data)
        #expect(decoded == value)
    }

    @Test(arguments: UserEventAction.allCases)
    func userEventActionRoundtrip(_ value: UserEventAction) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(UserEventAction.self, from: data)
        #expect(decoded == value)
    }

    @Test func cardTypeCount() {
        #expect(CardType.allCases.count == 7)
    }

    @Test func userEventActionExcludesHide() {
        #expect(!UserEventAction.allCases.map { $0.rawValue }.contains("hide"),
                "hide was cut for v1 per spec D17")
    }
}
