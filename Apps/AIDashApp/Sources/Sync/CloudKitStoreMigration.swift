import Foundation
import os

// Store location + legacy-store adoption for `CloudKitContainer`.
//
// Split out of CloudKitContainer.swift purely for size (the file crossed the
// 600-line limit). This half is one coherent concern: WHERE the SwiftData store
// lives and how a store left behind by a differently-packaged build is adopted
// without losing data.
extension CloudKitContainer {
    #if os(macOS)
    /// The user's REAL home directory, even inside the App Sandbox.
    ///
    /// `FileManager.homeDirectoryForCurrentUser` / `NSHomeDirectory()` are
    /// container-relative: in a sandboxed process they return
    /// `~/Library/Containers/<bundleID>/Data`, NOT `/Users/<name>`. Deriving the
    /// pinned path from either would make it mean a DIFFERENT directory in each
    /// sandbox posture — the exact fork this is meant to close. `getpwuid_r`
    /// reads the passwd database directly and is the documented
    /// sandbox-independent answer, so the absolute container path it builds
    /// names the same bytes to a sandboxed and an unsandboxed process alike.
    nonisolated internal static func realHomeDirectory() -> URL {
        // `pw.pw_dir` points INTO `buffer`, so the string must be copied out
        // while the buffer pointer is still guaranteed valid. Swift only
        // guarantees an `&array` pointer for the duration of the call it is
        // passed to, so reading pw_dir after the call returns would be UB.
        // withUnsafeMutableBufferPointer keeps the lifetime explicit.
        var buffer = [CChar](repeating: 0, count: 4096)
        let home: String? = buffer.withUnsafeMutableBufferPointer { buf in
            var pw = passwd()
            var result: UnsafeMutablePointer<passwd>?
            guard getpwuid_r(getuid(), &pw, buf.baseAddress, buf.count, &result) == 0,
                  result != nil, let dir = pw.pw_dir else { return nil }
            return String(cString: dir)
        }
        if let home, !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        // Fall back rather than trap; a container-relative home is still a
        // usable location, just not sandbox-independent.
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Legacy SwiftData default store locations, newest-usable first.
    ///
    /// `default.store` is what SwiftData creates when no `url:` is given. It
    /// resolves differently depending on the running process's sandbox state,
    /// which is exactly how the app ended up with two divergent stores.
    nonisolated internal static func legacyStoreURLs() -> [URL] {
        legacyStoreURLs(under: realHomeDirectory())
    }

    /// Same layout, rooted at an arbitrary directory. Tests pass a temp root so
    /// legacy discovery — the half that MOVES and DELETES files — can never
    /// reach the real home. Production passes the real home.
    nonisolated internal static func legacyStoreURLs(under root: URL) -> [URL] {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tianpli.aidash"
        return [
            // Unsandboxed (ad-hoc fixed install) — the most recently active one.
            root.appendingPathComponent("Library/Application Support/default.store"),
            // Sandboxed (Xcode/dev build).
            root.appendingPathComponent(
                "Library/Containers/\(bundleID)/Data/Library/Application Support/default.store"
            ),
        ]
    }

    /// Move an existing legacy store into the pinned location, ONCE.
    ///
    /// Without this, pinning the path would itself orphan data: on the first
    /// launch after the change the pinned file does not exist, SwiftData would
    /// happily create a fresh empty store, and every row already on disk —
    /// including append-only events that may never have synced — would become
    /// invisible. That is the very failure this whole change exists to stop,
    /// just relocated one directory over.
    ///
    /// Picks the legacy candidate with the most recent modification time (the
    /// store the app actually used last) and moves it plus its `-wal`/`-shm`
    /// sidecars, which carry committed-but-not-checkpointed rows. Copying only
    /// the main file would silently drop whatever is still in the WAL.
    ///
    /// Deliberately a MOVE, not a copy: leaving the original behind invites a
    /// future build resolving the old path and resurrecting stale data as a
    /// third divergent store. Best-effort throughout — a failure here must
    /// never block launch (§D); worst case the app starts on the pinned store
    /// and the legacy file stays untouched for manual recovery.
    ///
    /// Newest activity across a store's WHOLE file set, not just the `.store`.
    ///
    /// SQLite in WAL mode appends commits to `-wal` and only folds them into
    /// the main file at a checkpoint, so the `.store` mtime can lag its own
    /// live data by hours. Ranking candidates by the main file alone would
    /// therefore pick the STALER database whenever the busier one simply had
    /// not checkpointed yet — and the newest append-only events would stay
    /// orphaned, which is the precise failure this migration exists to end.
    /// (Measured on a real machine: the `-wal` was 14 hours newer than its
    /// own `.store`.)
    nonisolated internal static func lastActivity(of store: URL) -> Date {
        let fm = FileManager.default
        return ["", "-wal", "-shm"].compactMap { suffix -> Date? in
            let path = store.path + suffix
            guard let attrs = try? fm.attributesOfItem(atPath: path) else { return nil }
            return attrs[.modificationDate] as? Date
        }.max() ?? .distantPast
    }

    /// MainActor entry point: delegates to the nonisolated overload, passing
    /// the current test sandbox root. Tests call this via `withStoreSandbox`.
    internal static func adoptLegacyStore(from candidates: [URL], to pinned: URL) {
        adoptLegacyStore(from: candidates, to: pinned, confinedTo: Self.sandboxRoot)
    }

    /// Testable core of the migration: `candidates` is injected so the behavior
    /// can be exercised against a temp directory instead of the real home.
    /// `confinedTo` replaces the MainActor `sandboxRoot` read — callers pass
    /// the sandbox root explicitly so this function needs no actor-isolated state.
    ///
    /// COPY-then-publish, never move-in-place. The destination is only put in
    /// its final position once the WHOLE file set (store + `-wal` + `-shm`) has
    /// landed. A partial migration is unrecoverable: `adopt` is skipped forever
    /// once `pinned` exists, so a store published without its `-wal` would
    /// permanently strand every committed-but-not-checkpointed row.
    ///
    /// Staging into a sibling directory and publishing at the end makes the
    /// visible outcome all-or-nothing. On any failure everything published so
    /// far is rolled back and the legacy set is left exactly as it was, so the
    /// next launch simply retries.
    nonisolated internal static func adoptLegacyStore(
        from candidates: [URL], to pinned: URL, confinedTo sandboxRoot: URL?
    ) {
        let fm = FileManager.default

        // LAST LINE OF DEFENSE. This function MOVES and DELETES files, and a
        // test that hands it a real-home path would destroy the developer's
        // data — the caller-side guards above are the primary protection, but
        // they have already been got wrong once, in a way that only surfaced
        // after the damage was done. Refuse outright rather than trust callers.
        if isRunningTests {
            let root = sandboxRoot?.standardizedFileURL.path
            let confined = { (u: URL) in
                root.map { u.standardizedFileURL.path.hasPrefix($0) } ?? false
            }
            guard confined(pinned), candidates.allSatisfy(confined) else {
                // Log, don't trap. An assertionFailure here would abort the
                // whole test run, which makes the safety net itself untestable
                // — and a net nobody can exercise is a net nobody trusts.
                // Returning without touching anything IS the safe behavior.
                logger.error("Refusing legacy-store adoption outside the test sandbox.")
                return
            }
        }

        guard !fm.fileExists(atPath: pinned.path) else { return }

        let existing = candidates.filter { fm.fileExists(atPath: $0.path) }
        guard let legacy = existing.max(by: {
            lastActivity(of: $0) < lastActivity(of: $1)
        }) else { return }

        // More than one legacy store means the split-brain left data on BOTH
        // sides. Only the most recently used one is adopted — SwiftData stores
        // cannot be merged file-wise, and adopting one is strictly better than
        // adopting none. Say so loudly: the other store still holds rows this
        // migration does NOT recover, and only a human can decide what to do
        // with them.
        if existing.count > 1 {
            let others = existing.filter { $0 != legacy }.map(\.path).joined(separator: ", ")
            logger.warning("Multiple legacy stores found; adopting the one with the newest activity across store/-wal/-shm. NOT migrated: \(others, privacy: .public)")
        }

        let staging = pinned.deletingLastPathComponent()
            .appendingPathComponent(".adopt-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }

        var published: [String] = []
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            // Copy the whole set first — the legacy files stay intact until the
            // publish step, so any failure here costs nothing.
            for suffix in ["", "-wal", "-shm"] {
                let from = URL(fileURLWithPath: legacy.path + suffix)
                guard fm.fileExists(atPath: from.path) else { continue }
                try fm.copyItem(
                    at: from,
                    to: staging.appendingPathComponent(pinned.lastPathComponent + suffix)
                )
            }
            // Publish sidecars first and the main store LAST, so `pinned` never
            // exists while its sidecars are missing — that ordering is what
            // makes the "skip if pinned exists" guard safe.
            //
            // Clear the destination first. The guard only checks `pinned`
            // itself, so an ORPHAN `pinned-wal` (left by an interrupted run on
            // an older build) would make every future moveItem throw and the
            // migration would fail-and-roll-back forever. Removing a sidecar
            // that has no store to belong to is safe — it is unreadable on its
            // own — and it is the difference between self-healing and a
            // permanent deadlock.
            for suffix in ["-shm", "-wal", ""] {
                let staged = staging.appendingPathComponent(pinned.lastPathComponent + suffix)
                guard fm.fileExists(atPath: staged.path) else { continue }
                let dest = URL(fileURLWithPath: pinned.path + suffix)
                try? fm.removeItem(at: dest)
                try fm.moveItem(at: staged, to: dest)
                published.append(suffix)
            }
        } catch {
            // Roll back whatever was already published: a half-written pinned
            // set would block the retry on every future launch.
            for suffix in published {
                try? fm.removeItem(at: URL(fileURLWithPath: pinned.path + suffix))
            }
            logger.error("Legacy store adopt failed; legacy left intact, will retry: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Only now retire the originals. Leaving them behind invites a future
        // build resolving the old path and reviving stale data as a third
        // divergent store; failing to delete is harmless, so it is best-effort.
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: legacy.path + suffix))
        }
        logger.notice("Adopted legacy SwiftData store into the pinned location.")
    }
    #endif
}
