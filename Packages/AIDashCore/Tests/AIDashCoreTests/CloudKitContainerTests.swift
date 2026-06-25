import Testing
import Foundation
import SwiftData
@testable import AIDashCore

@Suite("CloudKitContainer")
struct CloudKitContainerTests {

    // Note: CloudKitContainer.shared requires iCloud entitlements (only present in
    // the full app build). Unit tests exercise the in-memory path; the CloudKit
    // persistent path is verified by the xcodebuild integration test.

    @Test @MainActor
    func inMemoryContainerCreatesSuccessfully() {
        let container = CloudKitContainer(inMemoryOnly: true)
        #expect(container.state != nil, "In-memory container should succeed")
        #expect(container.initializationError == nil)
    }

    @Test @MainActor
    func stateAndErrorAreMutuallyExclusive() {
        let container = CloudKitContainer(inMemoryOnly: true)
        let hasState = container.state != nil
        let hasError = container.initializationError != nil
        #expect(hasState != hasError, "state and initializationError should be mutually exclusive")
    }

    @Test @MainActor
    func cloudKitContainerIdentifierMatchesSpec() {
        #expect(CloudKitContainer.cloudKitContainerIdentifier == "iCloud.com.tianpli.aidash")
    }

    @Test @MainActor
    func containerSupportsExpectedModelTypes() throws {
        let container = CloudKitContainer(inMemoryOnly: true)
        let modelContainer = try #require(container.state)
        let context = ModelContext(modelContainer)

        // Verify BriefingModel can be inserted and fetched
        let briefing = BriefingModel(
            date: "2026-06-25",
            generatedAt: Date(),
            generatedBy: "test"
        )
        context.insert(briefing)
        try context.save()

        let descriptor = FetchDescriptor<BriefingModel>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched.first?.date == "2026-06-25")
    }

    @Test @MainActor
    func inMemoryContainerSupportsAllModelCRUD() throws {
        let container = CloudKitContainer(inMemoryOnly: true)
        let modelContainer = try #require(container.state)
        let context = ModelContext(modelContainer)

        // Insert a briefing with a container and card to verify cascade relationships
        let briefing = BriefingModel(
            date: "2026-06-26",
            generatedAt: Date(),
            generatedBy: "test-crud"
        )
        context.insert(briefing)

        let containerModel = ContainerModel(
            id: "c1",
            title: "Test Container",
            subtitle: nil,
            order: 0,
            layout: .list,
            style: .neutral
        )
        containerModel.briefing = briefing
        context.insert(containerModel)

        let card = CardModel(
            id: "card1",
            type: .metric,
            size: .medium,
            style: .neutral,
            payloadJSON: Data("{}".utf8)
        )
        card.container = containerModel
        context.insert(card)

        let event = UserEventModel(
            id: "ev1",
            timestamp: Date(),
            device: "test-device",
            cardId: "card1",
            action: .done
        )
        context.insert(event)

        try context.save()

        // Verify all types can be fetched
        let briefings = try context.fetch(FetchDescriptor<BriefingModel>())
        #expect(briefings.count == 1)

        let containers = try context.fetch(FetchDescriptor<ContainerModel>())
        #expect(containers.count == 1)

        let cards = try context.fetch(FetchDescriptor<CardModel>())
        #expect(cards.count == 1)

        let events = try context.fetch(FetchDescriptor<UserEventModel>())
        #expect(events.count == 1)
    }
}
