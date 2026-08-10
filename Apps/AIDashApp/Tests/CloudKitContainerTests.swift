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

// MARK: - Pinned store URL (sandbox-independent)

@MainActor
@Test func storeURLIsPinnedOutsideTheSandboxContainerOnMacOS() throws {
    // SwiftData's default store path is resolved relative to the running
    // process's container, so it MOVES when the same app runs sandboxed
    // (Xcode/dev) vs unsandboxed (ad-hoc fixed install). That split-brain
    // orphaned a real append-only star event on 2026-08-03: `events pull`
    // answered ok:true/count:0 against a freshly created store while the
    // event sat in the abandoned one. Pinning makes store identity
    // independent of sandbox posture.
    #if os(macOS)
    // storeURL() is now a PURE path derivation — calling it must not create
    // directories or move files. (It previously did both, and running this very
    // test relocated the developer's real store and left an empty one behind,
    // which would have permanently suppressed the real migration.)
    let url = try #require(CloudKitContainer.storeURL())
    #expect(url.path.hasSuffix("Library/Application Support/AIDash/AIDash.store"))
    // The whole point: the path is derived from the REAL home, so it never
    // lands inside a per-app sandbox container regardless of sandbox posture.
    // (Asserted via realHomeDirectory() rather than the literal string, so this
    // holds whether or not the TEST process itself happens to be sandboxed.)
    #expect(url.path.hasPrefix(CloudKitContainer.realHomeDirectory().path))
    #expect(!CloudKitContainer.realHomeDirectory().path.contains("/Library/Containers/"))
    // Purity: calling it twice yields the same answer and, critically, the
    // second call cannot have been influenced by a directory the first created.
    #expect(CloudKitContainer.storeURL() == url)
    #else
    // iOS is always sandboxed and its container path is already stable, so the
    // SwiftData default is correct there — an absolute home path would be wrong.
    #expect(CloudKitContainer.storeURL() == nil)
    #endif
}

@MainActor
@Test func legacyStoreIsAdoptedRatherThanOrphaned() throws {
    #if os(macOS)
    // Pinning the store path without ADOPTING what is already on disk would
    // re-create the exact bug it fixes, one directory over: on the first
    // launch after the change SwiftData would create a fresh empty store and
    // every existing row — including append-only events that may never have
    // synced — would silently go invisible.
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let legacy = tmp.appendingPathComponent("default.store")
    let pinned = tmp.appendingPathComponent("AIDash/AIDash.store")
    try fm.createDirectory(at: pinned.deletingLastPathComponent(),
                           withIntermediateDirectories: true)
    // The -wal carries committed-but-not-checkpointed rows; losing it loses data.
    try Data("store".utf8).write(to: legacy)
    try Data("wal".utf8).write(to: URL(fileURLWithPath: legacy.path + "-wal"))

    CloudKitContainer.adoptLegacyStore(from: [legacy], to: pinned)

    #expect(fm.fileExists(atPath: pinned.path))
    #expect(fm.fileExists(atPath: pinned.path + "-wal"))
    // A MOVE, not a copy: a leftover original invites a future build resolving
    // the old path and resurrecting stale data as a third divergent store.
    #expect(!fm.fileExists(atPath: legacy.path))
    #endif
}

@MainActor
@Test func adoptDoesNothingWhenPinnedStoreAlreadyExists() throws {
    #if os(macOS)
    // Migration must run exactly once. If the pinned store is already live,
    // overwriting it with an older legacy file would destroy newer data.
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let legacy = tmp.appendingPathComponent("default.store")
    let pinned = tmp.appendingPathComponent("AIDash.store")
    try Data("old".utf8).write(to: legacy)
    try Data("current".utf8).write(to: pinned)

    CloudKitContainer.adoptLegacyStore(from: [legacy], to: pinned)

    #expect(try String(contentsOf: pinned, encoding: .utf8) == "current")
    #expect(fm.fileExists(atPath: legacy.path))  // untouched
    #endif
}

@MainActor
@Test func adoptLeavesLegacySetIntactWhenTheMainStoreCannotMove() throws {
    #if os(macOS)
    // If the main .store move fails, the sidecars must NOT be moved either.
    // A legacy store stripped of its -wal loses every committed-but-not-
    // checkpointed row — the exact loss this migration exists to prevent.
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let legacy = tmp.appendingPathComponent("default.store")
    try Data("store".utf8).write(to: legacy)
    try Data("wal".utf8).write(to: URL(fileURLWithPath: legacy.path + "-wal"))

    // Destination directory does not exist → the main move fails.
    let pinned = tmp.appendingPathComponent("missing-dir/AIDash.store")
    CloudKitContainer.adoptLegacyStore(from: [legacy], to: pinned)

    #expect(fm.fileExists(atPath: legacy.path))
    #expect(fm.fileExists(atPath: legacy.path + "-wal"))  // sidecar stayed put
    #expect(!fm.fileExists(atPath: pinned.path + "-wal"))
    #endif
}
