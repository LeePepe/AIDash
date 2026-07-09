import Foundation
import Testing
import AIDashCore

/// Coverage for `AppLauncher.resolveAppURL(env:fileExists:derivedDataCandidates:)`.
///
/// The lookup order (env override → /Applications → DerivedData latest) is a
/// small state machine; each branch gets its own test so regressions surface
/// on the specific rule they broke instead of a single fat "resolve" test.
@Suite("AppLauncher.resolveAppURL")
struct AppLauncherResolveTests {

    private static let installedPath = "/Applications/AIDash.app"
    private static let derivedCandidate = URL(fileURLWithPath: "/tmp/DD/AIDash-abc/Build/Products/Debug/AIDash.app")
    private static let derivedCandidate2 = URL(fileURLWithPath: "/tmp/DD/AIDash-def/Build/Products/Debug/AIDash.app")

    // MARK: - Env override

    @Test("env AIDASH_APP_PATH wins when the file exists")
    func envOverrideWinsWhenPresent() throws {
        let override = "/tmp/custom/AIDash.app"
        let url = try AppLauncher.resolveAppURL(
            env: { $0 == AppLauncher.appPathEnvVar ? override : nil },
            fileExists: { $0.path == override },
            derivedDataCandidates: { [] }
        )
        #expect(url.path == override)
    }

    @Test("env override falls through when the file is missing")
    func envOverrideFallsThroughWhenMissing() throws {
        // env set to a non-existent path → installed exists → returns installed.
        let url = try AppLauncher.resolveAppURL(
            env: { $0 == AppLauncher.appPathEnvVar ? "/tmp/does-not-exist/AIDash.app" : nil },
            fileExists: { $0.path == Self.installedPath },
            derivedDataCandidates: { [] }
        )
        #expect(url.path == Self.installedPath)
    }

    @Test("empty env override is ignored (treated as unset)")
    func emptyEnvOverrideIgnored() throws {
        let url = try AppLauncher.resolveAppURL(
            env: { $0 == AppLauncher.appPathEnvVar ? "" : nil },
            fileExists: { $0.path == Self.installedPath },
            derivedDataCandidates: { [] }
        )
        #expect(url.path == Self.installedPath)
    }

    // MARK: - Installed path

    @Test("/Applications/AIDash.app wins over DerivedData")
    func installedWinsOverDerivedData() throws {
        let url = try AppLauncher.resolveAppURL(
            env: { _ in nil },
            fileExists: { $0.path == Self.installedPath || $0 == Self.derivedCandidate },
            derivedDataCandidates: { [Self.derivedCandidate] }
        )
        #expect(url.path == Self.installedPath)
    }

    // MARK: - DerivedData fallback

    @Test("first existing DerivedData candidate is picked when /Applications is empty")
    func derivedDataFallback() throws {
        let url = try AppLauncher.resolveAppURL(
            env: { _ in nil },
            fileExists: { $0 == Self.derivedCandidate2 },
            derivedDataCandidates: { [Self.derivedCandidate, Self.derivedCandidate2] }
        )
        #expect(url == Self.derivedCandidate2)
    }

    // MARK: - Not found

    @Test("throws xpc.app_launch_failed with searched-path list when nothing exists")
    func notFoundListsSearchedPaths() {
        do {
            _ = try AppLauncher.resolveAppURL(
                env: { $0 == AppLauncher.appPathEnvVar ? "/tmp/nope/AIDash.app" : nil },
                fileExists: { _ in false },
                derivedDataCandidates: { [Self.derivedCandidate] }
            )
            Issue.record("Expected XPCError but resolveAppURL returned")
        } catch let error as XPCError {
            #expect(error.code == "xpc.app_launch_failed")
            #expect(error.message.contains(AppLauncher.appPathEnvVar))
            #expect(error.message.contains(Self.installedPath))
            #expect(error.message.contains(Self.derivedCandidate.path))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - DerivedData enumeration (integration-ish, no mocks)

    @Test("defaultDerivedDataCandidates returns URLs ending in the debug AIDash.app path")
    func derivedDataCandidatesShape() {
        // Purely structural — we don't assume any specific build exists on the
        // machine running the test. The suffix pattern is what other code
        // relies on, so pin it.
        let candidates = AppLauncher.defaultDerivedDataCandidates()
        for candidate in candidates {
            #expect(candidate.path.hasSuffix("/Build/Products/Debug/AIDash.app"))
            #expect(candidate.path.contains("/DerivedData/AIDash-"))
        }
    }
}
