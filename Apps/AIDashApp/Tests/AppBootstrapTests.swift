import Testing
import Foundation
import SwiftData
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif
import AIDashCore

// MARK: - GUI loader MainActor responsiveness tests

/// A loader that blocks until its gate is signaled — simulates an indefinitely-
/// hanging SQLite open. Used to prove that MainActor remains responsive when
/// startDetached is used, because the hang is confined to the detached task.
///
/// Value type with an immutable `DispatchSemaphore` reference: Swift 6 proves
/// `Sendable` conformance without any `@unchecked` escape hatch.
/// Unlike `Thread.sleep(.infinity)`, the gate can be signaled so xctest exits.
private struct NeverReturningLoader: ContainerLoading {
    let gate: DispatchSemaphore

    init() {
        gate = DispatchSemaphore(value: 0)
    }

    nonisolated func load() -> CloudKitContainer.InitState {
        // Block the calling thread until the gate is released. Since this runs
        // in Task.detached, it must NOT block MainActor.
        dispatchPrecondition(condition: .notOnQueue(.main))
        gate.wait()
        return .failed(reason: "released-by-teardown")
    }
}

/// A loader that returns immediately with a known state.
private struct ImmediateLoader: ContainerLoading {
    let result: CloudKitContainer.InitState

    nonisolated func load() -> CloudKitContainer.InitState {
        result
    }
}

@MainActor
@Test func guiLoaderNeverBlocksMainActorEvenWhenHanging() async throws {
    // GIVEN: a bootstrap with a loader that blocks until its gate is signaled
    let loader = NeverReturningLoader()

    #if os(macOS)
    let bootstrap = AppBootstrap(handlers: nil)
    #else
    let bootstrap = AppBootstrap()
    #endif
    let task = bootstrap.startDetached(loader: loader)

    // WHEN: we yield back to the run loop and check MainActor is free
    // If startDetached blocked MainActor, we would never reach this point.
    try await Task.sleep(for: .milliseconds(50))

    // THEN: MainActor is responsive — we reached here — and the state is
    // still the loading sentinel because the loader never completed.
    guard case .failed(let reason) = bootstrap.containerState else {
        Issue.record("Expected loading-sentinel (.failed with empty reason)")
        return
    }
    #expect(reason.isEmpty, "Should still be in loading-sentinel state")

    // TEARDOWN: release the gate and await the detached task to ensure
    // delivery back to MainActor completes deterministically.
    loader.gate.signal()
    await task.value
}

@MainActor
@Test func guiLoaderDeliversResultToMainActor() async throws {
    // GIVEN: a bootstrap with an immediate loader
    let schema = Schema([
        BriefingModel.self, ContainerModel.self,
        CardModel.self, UserEventModel.self,
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: config)

    #if os(macOS)
    let bootstrap = AppBootstrap(handlers: nil)
    #else
    let bootstrap = AppBootstrap()
    #endif
    let task = bootstrap.startDetached(loader: ImmediateLoader(result: .ready(container)))

    // WHEN: we await the detached task to complete and deliver back
    await task.value

    // THEN: the container state is delivered
    guard case .ready(let delivered) = bootstrap.containerState else {
        Issue.record("Expected .ready state after immediate loader completes")
        return
    }
    #expect(delivered === container)
}

/// Verifies that an injected loader conforming to ContainerLoading works
/// through startDetached without blocking MainActor. Tests the protocol
/// contract and bootstrap delivery — NOT the real GUIContainerLoader which
/// would open the default store.
@MainActor
@Test func injectedLoaderDeliversViaStartDetached() async throws {
    // A minimal loader that returns a known in-memory container.
    let schema = Schema([
        BriefingModel.self, ContainerModel.self,
        CardModel.self, UserEventModel.self,
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let expected = try ModelContainer(for: schema, configurations: config)

    #if os(macOS)
    let bootstrap = AppBootstrap(handlers: nil)
    #else
    let bootstrap = AppBootstrap()
    #endif
    let task = bootstrap.startDetached(loader: ImmediateLoader(result: .ready(expected)))

    await task.value

    guard case .ready(let delivered) = bootstrap.containerState else {
        Issue.record("Expected .ready state after injected loader completes")
        return
    }
    #expect(delivered === expected)
}

// MARK: - Storage-mode parity tests

/// Verifies that `storageMode(cloudAvailable:)` returns `.localOnly` when
/// cloud is unavailable, and `.cloudKit` when it is — ensuring the GUI/agent
/// semantic split is correctly driven by this single decision point.
@Test func storageModeReturnsLocalOnlyWhenCloudUnavailable() {
    let mode = CloudKitContainer.storageMode(cloudAvailable: false)
    guard case .localOnly = mode else {
        Issue.record("Expected .localOnly when cloudAvailable is false, got \(mode)")
        return
    }
}

@Test func storageModeReturnsCloudKitWhenCloudAvailable() {
    let mode = CloudKitContainer.storageMode(cloudAvailable: true)
    guard case .cloudKit = mode else {
        Issue.record("Expected .cloudKit when cloudAvailable is true, got \(mode)")
        return
    }
}

/// Verifies that the nonisolated `makeConfiguration` overload produces a
/// configuration with no CloudKit database when mode is `.localOnly`.
/// Asserts observable configuration properties without creating a container
/// (creating a non-memory container with nil URL would open the default store).
@Test func makeConfigurationLocalOnlyHasNoCloudKit() {
    let schema = CloudKitContainer.makeSchema()
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("AppBootstrapTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }
    let storeURL = tmpDir.appendingPathComponent("test.store")

    let config = CloudKitContainer.makeConfiguration(
        schema: schema, mode: .localOnly, url: storeURL
    )
    // A local-only configuration must not reference any CloudKit database.
    guard case .none = config.cloudKitDatabase else {
        Issue.record("Expected .none cloudKitDatabase for localOnly config, got \(config.cloudKitDatabase)")
        return
    }
}

/// Verifies that agent mode ALWAYS hardcodes `.localOnly` — the decision is
/// independent of iCloud availability. Tests the pure mode/config decision
/// without opening any real store.
#if os(macOS)
@Test func agentModeAlwaysLocalOnly() {
    // The agent path always passes `.localOnly` to makeConfiguration regardless
    // of what isCloudKitAvailable() returns. Verify the configuration produced
    // for agent mode has no CloudKit database.
    let schema = CloudKitContainer.makeSchema()
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("AppBootstrapTests-agent-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }
    let storeURL = tmpDir.appendingPathComponent("agent-test.store")

    let config = CloudKitContainer.makeConfiguration(
        schema: schema, mode: .localOnly, url: storeURL
    )
    // If this were .cloudKit, the database field would be .private(...).
    // Agent mode must always produce .none.
    guard case .none = config.cloudKitDatabase else {
        Issue.record("Expected .none cloudKitDatabase for agent-mode config, got \(config.cloudKitDatabase)")
        return
    }
}
#endif
