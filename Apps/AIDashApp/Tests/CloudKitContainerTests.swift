import Testing
import Foundation
import SwiftData
@testable import AIDashApp
import AIDashCore

/// Tests for CloudKitContainer — validates init state handling.
/// In CI/simulator without iCloud sign-in, CloudKit init fails gracefully.
@MainActor
@Test func cloudKitContainerInitState() async throws {
    let state = CloudKitContainer.shared.state

    // In test/CI context (no iCloud account), expect .failed with a reason
    // On a device with iCloud, expect .ready — both paths are valid
    switch state {
    case .ready(let container):
        #expect(container.schema.entities.count == 4)
    case .failed(let reason):
        #expect(!reason.isEmpty)
    }
}

@MainActor
@Test func cloudKitContainerModelContainerThrowsWhenFailed() async throws {
    let state = CloudKitContainer.shared.state

    switch state {
    case .ready:
        // When ready, modelContainer should return successfully
        let container = try CloudKitContainer.shared.modelContainer
        #expect(container.schema.entities.count == 4)
    case .failed:
        // When failed, modelContainer must throw CloudKitContainerError
        #expect(throws: CloudKitContainerError.self) {
            _ = try CloudKitContainer.shared.modelContainer
        }
    }
}

@MainActor
@Test func cloudKitContainerFailedReasonIsSanitized() async throws {
    let state = CloudKitContainer.shared.state

    if case .failed(let reason) = state {
        // Reason must not contain raw system paths or internal diagnostics
        #expect(!reason.contains("/"))
        #expect(!reason.contains("NSError"))
        #expect(!reason.contains("CloudKit"))
    }
}

@MainActor
@Test func cloudKitContainerIsSingleton() async throws {
    let a = CloudKitContainer.shared
    let b = CloudKitContainer.shared
    #expect(a === b)
}
