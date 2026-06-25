import Testing
import Foundation
import SwiftData
@testable import AIDashCore

@Suite("CloudKitContainer")
struct CloudKitContainerTests {

    @Test @MainActor
    func sharedInstanceCreatesContainerSuccessfully() {
        let container = CloudKitContainer.shared
        #expect(container.state != nil, "Shared container should have a valid ModelContainer")
        #expect(container.initializationError == nil, "Shared container should have no initialization error")
    }

    @Test @MainActor
    func inMemoryContainerCreatesSuccessfully() {
        let container = CloudKitContainer(inMemoryOnly: true)
        #expect(container.state != nil, "In-memory container should succeed")
        #expect(container.initializationError == nil)
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
}
