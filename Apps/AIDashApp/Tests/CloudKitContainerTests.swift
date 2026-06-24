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
@Test func cloudKitContainerModelContainerFallback() async throws {
    // Regardless of state, modelContainer always returns a valid container
    let container = CloudKitContainer.shared.modelContainer
    #expect(container.schema.entities.count == 4)
}

@MainActor
@Test func cloudKitContainerIsSingleton() async throws {
    let a = CloudKitContainer.shared
    let b = CloudKitContainer.shared
    #expect(a === b)
}
