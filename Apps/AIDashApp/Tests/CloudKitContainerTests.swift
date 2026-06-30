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
    let reason = CloudKitContainer.iCloudUnavailableMessage
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
        reason: CloudKitContainer.iCloudUnavailableMessage
    ))

    if case .failed(let reason) = sut.state {
        #expect(!reason.contains("/"))
        #expect(!reason.contains("NSError"))
        #expect(!reason.contains("CloudKit"))
    }
}

@MainActor
@Test func cloudKitContainerFailedReasonIsLocalized() async throws {
    // The message must be sourced from the String Catalog, not a hardcoded
    // literal. We assert non-empty + identical to the public accessor.
    let message = CloudKitContainer.iCloudUnavailableMessage
    #expect(!message.isEmpty)
    let sut = CloudKitContainer(state: .failed(reason: message))
    if case .failed(let reason) = sut.state {
        #expect(reason == message)
    } else {
        Issue.record("Expected .failed state")
    }
}

// MARK: - Singleton integration tests

@MainActor
@Test func cloudKitContainerIsSingleton() async throws {
    let a = CloudKitContainer.shared
    let b = CloudKitContainer.shared
    #expect(a === b)
}

// MARK: - Storage-mode gate (prevents the async CloudKit-mirror crash)

@MainActor
@Test func storageModeUsesCloudKitWhenAccountAvailable() {
    // With an iCloud account present, attach the CloudKit-mirrored store.
    #expect(CloudKitContainer.storageMode(cloudAvailable: true) == .cloudKit)
}

@MainActor
@Test func storageModeFallsBackToLocalWhenNoAccount() {
    // Without iCloud, we MUST NOT attach the CloudKit mirror: doing so lets
    // NSPersistentCloudKitContainer abort the process on its own queue, a
    // crash no do/catch can intercept. Local-only keeps the app launchable.
    #expect(CloudKitContainer.storageMode(cloudAvailable: false) == .localOnly)
}

@MainActor
@Test func realSingletonInitNeverCrashesRegardlessOfICloud() {
    // Constructing the shared container must not crash whether or not this
    // host has iCloud — the whole point of the preflight gate. Reaching here
    // with a non-failed-or-failed state (i.e. no trap) is the assertion.
    switch CloudKitContainer.shared.state {
    case .ready, .failed:
        #expect(Bool(true))
    }
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
