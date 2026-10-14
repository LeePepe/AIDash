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

    @Test func cardTypeCount() {
        // Deliberate tripwire: adding a CardType obliges the downstream layers
        // (DesignKit classification, AIDashUI badge + router, XPC schema ad) to
        // follow. Bump this only alongside those.
        #expect(CardType.allCases.count == 11)
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

    @Test func userEventActionExcludesHide() {
        #expect(!UserEventAction.allCases.map { $0.rawValue }.contains("hide"),
                "hide was cut for v1 per spec D17")
    }

    @Test func teamAuditEnumsRoundtrip() throws {
        for v in TeamAuditSection.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(TeamAuditSection.self, from: data)
            #expect(decoded == v)
        }
        for v in AuditMode.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(AuditMode.self, from: data)
            #expect(decoded == v)
        }
        for v in CoreAuditAxis.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(CoreAuditAxis.self, from: data)
            #expect(decoded == v)
        }
        for v in FindingAxis.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(FindingAxis.self, from: data)
            #expect(decoded == v)
        }
        for v in ConformanceVerdict.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(ConformanceVerdict.self, from: data)
            #expect(decoded == v)
        }
        for v in FitnessVerdict.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(FitnessVerdict.self, from: data)
            #expect(decoded == v)
        }
        for v in OutcomeVerdict.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(OutcomeVerdict.self, from: data)
            #expect(decoded == v)
        }
        for v in FindingPriority.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(FindingPriority.self, from: data)
            #expect(decoded == v)
        }
        for v in FindingState.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(FindingState.self, from: data)
            #expect(decoded == v)
        }
        for v in RemediationOwner.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(RemediationOwner.self, from: data)
            #expect(decoded == v)
        }
        for v in ArtifactKind.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(ArtifactKind.self, from: data)
            #expect(decoded == v)
        }
        for v in ArtifactRequirement.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(ArtifactRequirement.self, from: data)
            #expect(decoded == v)
        }
        for v in ActorRole.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(ActorRole.self, from: data)
            #expect(decoded == v)
        }
        for v in ReleaseChannel.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(ReleaseChannel.self, from: data)
            #expect(decoded == v)
        }
        for v in ImportObservationDisposition.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(ImportObservationDisposition.self, from: data)
            #expect(decoded == v)
        }
        for v in RepeatTriggerCause.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(RepeatTriggerCause.self, from: data)
            #expect(decoded == v)
        }
        for v in TaskEffectivenessState.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(TaskEffectivenessState.self, from: data)
            #expect(decoded == v)
        }
        for v in ExternalizableEntityKind.allCases {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(ExternalizableEntityKind.self, from: data)
            #expect(decoded == v)
        }
    }
}
