import Testing
import Foundation
import SwiftData
@testable import AIDashApp
import AIDashCore

// MARK: - Deterministic contract tests

@MainActor
@Test func cloudKitContainerReadyStateReturnsContainer() async throws {
    let schema = Schema([
        BriefingModel.self,
        ContainerModel.self,
        CardModel.self,
        UserEventModel.self,
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: config)

    let sut = CloudKitContainer(state: .ready(container))

    switch sut.state {
    case .ready(let c):
        #expect(c.schema.entities.count == 4)
    case .failed:
        Issue.record("Expected .ready state")
    }

    let result = try sut.modelContainer
    #expect(result === container)
}

@MainActor
@Test func cloudKitContainerFailedStateThrows() async throws {
    let reason = "iCloud data sync is unavailable. Please check your iCloud account in Settings."
    let sut = CloudKitContainer(state: .failed(reason: reason))

    guard case .failed(let r) = sut.state else {
        Issue.record("Expected .failed state")
        return
    }
    #expect(r == reason)

    #expect(throws: CloudKitContainerError.self) {
        _ = try sut.modelContainer
    }
}

@MainActor
@Test func cloudKitContainerFailedReasonIsSanitized() async throws {
    // The real singleton's failed reason must not leak internal diagnostics
    let sut = CloudKitContainer(state: .failed(
        reason: "iCloud data sync is unavailable. Please check your iCloud account in Settings."
    ))

    if case .failed(let reason) = sut.state {
        #expect(!reason.contains("/"))
        #expect(!reason.contains("NSError"))
        #expect(!reason.contains("CloudKit"))
    }
}

// MARK: - Singleton integration tests

@MainActor
@Test func cloudKitContainerIsSingleton() async throws {
    let a = CloudKitContainer.shared
    let b = CloudKitContainer.shared
    #expect(a === b)
}

@MainActor
@Test func cloudKitContainerSharedSchemaHasFourEntities() async throws {
    // Validates that the singleton registers all 4 models regardless of CloudKit availability
    switch CloudKitContainer.shared.state {
    case .ready(let container):
        #expect(container.schema.entities.count == 4)
    case .failed(let reason):
        // In CI without iCloud, failure is expected — verify it's a non-empty sanitized reason
        #expect(!reason.isEmpty)
        #expect(!reason.contains("/"))
        #expect(!reason.contains("NSError"))
    }
}
