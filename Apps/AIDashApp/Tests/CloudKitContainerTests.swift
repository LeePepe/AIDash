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
@Test func storeURLResolvesIdenticallyInBothSandboxPostures() throws {
    // SwiftData's default store path is resolved relative to the running
    // process's container, so it MOVES when the same app runs sandboxed
    // (Xcode/dev) vs unsandboxed (ad-hoc fixed install). That split-brain
    // orphaned a real append-only star event on 2026-08-03: `events pull`
    // answered ok:true/count:0 against a freshly created store while the
    // event sat in the abandoned one. Pinning to one absolute path that BOTH
    // postures can reach makes store identity independent of packaging.
    #if os(macOS)
    // storeURL() is now a PURE path derivation — calling it must not create
    // directories or move files. (It previously did both, and running this very
    // test relocated the developer's real store and left an empty one behind,
    // which would have permanently suppressed the real migration.)
    let url = try #require(CloudKitContainer.storeURL())
    let bundleID = Bundle.main.bundleIdentifier ?? "com.tianpli.aidash"
    // The container path spelled ABSOLUTELY from the real home is the one
    // location both sandbox postures resolve to the same bytes: a sandboxed
    // process sees it as its own container, an unsandboxed one opens it as a
    // plain path. Pinning to ~/Library/Application Support instead would be
    // unreachable from a sandboxed build and would leave the split-brain unfixed.
    #expect(url.path.hasSuffix(
        "Library/Containers/\(bundleID)/Data/Library/Application Support/AIDash/AIDash.store"))
    #expect(url.path.hasPrefix(CloudKitContainer.realHomeDirectory().path))
    // Derived from the REAL home, never from a container-relative home — that
    // is what keeps the answer identical in both postures.
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
    // Migration is all-or-nothing. A partial result would be UNRECOVERABLE:
    // adoption is skipped forever once `pinned` exists, so a store published
    // without its -wal would permanently strand every committed-but-not-
    // checkpointed row. On failure nothing may be published and the legacy set
    // must survive untouched so the next launch can retry.
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let legacy = tmp.appendingPathComponent("default.store")
    try Data("store".utf8).write(to: legacy)
    try Data("wal".utf8).write(to: URL(fileURLWithPath: legacy.path + "-wal"))

    // A FILE where the store's parent directory should be: staging cannot be
    // created underneath it, so the migration genuinely fails.
    let blocker = tmp.appendingPathComponent("blocker")
    try Data("not a directory".utf8).write(to: blocker)
    let pinned = blocker.appendingPathComponent("AIDash.store")
    CloudKitContainer.adoptLegacyStore(from: [legacy], to: pinned)

    // Legacy survives in full…
    #expect(fm.fileExists(atPath: legacy.path))
    #expect(fm.fileExists(atPath: legacy.path + "-wal"))
    // …and nothing was published, so the next launch retries rather than
    // seeing a pinned store and skipping forever.
    #expect(!fm.fileExists(atPath: pinned.path))
    #expect(!fm.fileExists(atPath: pinned.path + "-wal"))
    #endif
}

@MainActor
@Test func adoptSkipsEntirelyWhenSomethingAlreadyOccupiesThePinnedPath() throws {
    #if os(macOS)
    // The `fileExists(pinned)` guard is what makes migration run exactly once.
    // It must also hold for a non-file occupant: if anything sits at the pinned
    // path, adopt does nothing at all — no sidecar published beside it, legacy
    // untouched. (An orphan `pinned-wal` would be worse than doing nothing: a
    // later successful adopt would publish a store next to a STALE wal from a
    // different database.)
    //
    // NOTE on coverage: the `catch`-branch rollback inside adoptLegacyStore is
    // NOT exercised here. Reaching it needs a publish that fails partway, which
    // requires filesystem permissions this test cannot arrange portably. The
    // rollback is written defensively but is currently unproven by test.
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let legacy = tmp.appendingPathComponent("default.store")
    try Data("store".utf8).write(to: legacy)
    try Data("wal".utf8).write(to: URL(fileURLWithPath: legacy.path + "-wal"))

    let dest = tmp.appendingPathComponent("dest", isDirectory: true)
    try fm.createDirectory(at: dest, withIntermediateDirectories: true)
    let pinned = dest.appendingPathComponent("AIDash.store")
    try fm.createDirectory(at: pinned, withIntermediateDirectories: true)

    CloudKitContainer.adoptLegacyStore(from: [legacy], to: pinned)

    #expect(!fm.fileExists(atPath: pinned.path + "-wal"))
    #expect(fm.fileExists(atPath: legacy.path))
    #expect(fm.fileExists(atPath: legacy.path + "-wal"))
    #endif
}

@MainActor
@Test func adoptRanksCandidatesByWalActivityNotJustTheStoreFile() throws {
    #if os(macOS)
    // SQLite in WAL mode appends commits to -wal and only folds them into the
    // main file at a checkpoint, so a busy store's .store mtime can lag its own
    // live data by hours. Ranking by the main file alone picks the STALER
    // database and leaves the newest append-only events orphaned — exactly the
    // failure this migration exists to end. (Measured on a real machine: the
    // -wal was 14 hours newer than its own .store.)
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let old = Date(timeIntervalSince1970: 1_000_000)
    let new = Date(timeIntervalSince1970: 2_000_000)

    // Candidate A: NEWER .store, but no recent WAL activity.
    let quiet = tmp.appendingPathComponent("quiet.store")
    try Data("quiet".utf8).write(to: quiet)
    try fm.setAttributes([.modificationDate: new], ofItemAtPath: quiet.path)

    // Candidate B: OLDER .store, but its -wal carries the newest commits.
    let busy = tmp.appendingPathComponent("busy.store")
    try Data("busy".utf8).write(to: busy)
    try Data("wal".utf8).write(to: URL(fileURLWithPath: busy.path + "-wal"))
    try fm.setAttributes([.modificationDate: old], ofItemAtPath: busy.path)
    try fm.setAttributes([.modificationDate: new.addingTimeInterval(60)],
                         ofItemAtPath: busy.path + "-wal")

    #expect(CloudKitContainer.lastActivity(of: busy)
            > CloudKitContainer.lastActivity(of: quiet))

    let pinned = tmp.appendingPathComponent("dest/AIDash.store")
    try fm.createDirectory(at: pinned.deletingLastPathComponent(),
                           withIntermediateDirectories: true)
    CloudKitContainer.adoptLegacyStore(from: [quiet, busy], to: pinned)

    // The busy store (newest WAL) must win, not the one with the newer .store.
    #expect(try String(contentsOf: pinned, encoding: .utf8) == "busy")
    #expect(fm.fileExists(atPath: pinned.path + "-wal"))
    #expect(fm.fileExists(atPath: quiet.path))  // the loser is left untouched
    #endif
}

// MARK: - Tests must never touch the real home

@MainActor
@Test func prepareStoreURLRefusesToTouchTheRealHomeUnderTest() throws {
    #if os(macOS)
    // REGRESSION. `prepareStoreURL()` creates a directory and MIGRATES a legacy
    // store. Any test reaching container construction — including one that only
    // reads `CloudKitContainer.shared.state` — used to run that migration
    // against the developer's real home. Repeated `xcodebuild test` runs
    // actually relocated a real store and made macOS prompt for file access on
    // every run.
    //
    // Under XCTest with no explicit override, it must decline entirely (nil →
    // SwiftData's own default) rather than fall through to the real home.
    #expect(CloudKitContainer.storeURLOverride == nil)
    // The real-home path must be untouched. Compare the directory's mtime
    // across the call: creating a file inside it (or creating the directory
    // itself) would move that timestamp. A "does .probe-file exist?" check
    // would be near-tautological — nothing ever creates that name — so it
    // could not have caught the original bug.
    let real = try #require(CloudKitContainer.storeURL())
    let realDir = real.deletingLastPathComponent().path
    let fm = FileManager.default
    let before = (try? fm.attributesOfItem(atPath: realDir)[.modificationDate]) as? Date
    #expect(CloudKitContainer.prepareStoreURL() == nil)
    let after = (try? fm.attributesOfItem(atPath: realDir)[.modificationDate]) as? Date
    #expect(before == after)

    // With an explicit override, the whole prepare path runs — inside temp only.
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let pinned = tmp.appendingPathComponent("AIDash.store")
    let resolved = CloudKitContainer.withStoreLocation(pinned) {
        CloudKitContainer.prepareStoreURL()
    }
    #expect(resolved == pinned)
    #expect(FileManager.default.fileExists(atPath: tmp.path))  // dir created there
    // Override is restored, so no later test inherits it.
    #expect(CloudKitContainer.storeURLOverride == nil)
    #endif
}
